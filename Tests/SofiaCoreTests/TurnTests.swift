import Testing
import Foundation
@testable import SofiaCore

final class FakeMemory: MemoryStoring, @unchecked Sendable {
    var facts: [String] = []
    func remember(_ fact: String) { facts.append(fact) }
    func forget(matching words: String) -> Int { let n = facts.count; facts.removeAll { $0.lowercased().contains(words.lowercased()) }; return n - facts.count }
}

final class FakePerformer: ActionPerformer, @unchecked Sendable {
    var performed: [MacAction] = []
    var fail = false
    var tasks: [String] = []
    func perform(_ action: MacAction) async -> ActionOutcome { performed.append(action); return fail ? .failed("no app called \(action.target)") : .done("") }
    func computerTask(_ goal: String, progress: @escaping @Sendable (String) -> Void) async -> String { tasks.append(goal); progress("Step 1: click"); return "Filled in the form." }
}

final class ScriptedProvider: ModelProvider, @unchecked Sendable {
    var label = "scripted"
    var supportsVision = true
    var replies: [ChatReply]
    var seen: [[ChatMessage]] = []
    var streamPieces: [String]? = nil
    init(_ replies: [ChatReply]) { self.replies = replies }
    func chat(_ messages: [ChatMessage], tools: [ToolSpec]) async throws -> ChatReply {
        seen.append(messages)
        guard !replies.isEmpty else { throw ProviderError("out of script") }
        return replies.removeFirst()
    }
    func stream(_ messages: [ChatMessage], tools: [ToolSpec], onText: @escaping @Sendable (String) -> Void) async throws -> ChatReply {
        let r = try await chat(messages, tools: tools)
        if let pieces = streamPieces, !r.text.isEmpty { for p in pieces { onText(p) } } else if !r.text.isEmpty { onText(r.text) }
        return r
    }
}

struct AssistantTurnTests {
    @Test func toolCallThenAnswer() async throws {
        let memory = FakeMemory(), performer = FakePerformer()
        let provider = ScriptedProvider([ChatReply(text: "", calls: [ToolCall(id: "c1", name: "mac_control", arguments: #"{"action":"open_app","target":"Safari"}"#)]), ChatReply(text: "Safari is open.")])
        let turn = AssistantTurn(memory: memory, performer: performer)
        let r = try await turn.run("open safari", channel: "mac", provider: provider, ownerName: "Alex", allowComputer: false)
        #expect(r.reply == "Safari is open." && r.performed == ["open Safari"] && r.failed.isEmpty)
        #expect(performer.performed.first?.kind == .openApp)
        #expect(provider.seen.count == 2 && provider.seen[1].last?.role == .tool && provider.seen[1].last?.toolCallID == "c1")
        #expect(provider.seen[0].first?.content.contains("Alex") == true)
    }
    @Test func invalidActionIsRefusedAndFailureReported() async throws {
        let performer = FakePerformer(); performer.fail = true
        let provider = ScriptedProvider([ChatReply(text: "", calls: [ToolCall(id: "a", name: "mac_control", arguments: #"{"action":"rm_rf"}"#), ToolCall(id: "b", name: "mac_control", arguments: #"{"action":"open_app","target":"Nope"}"#)]), ChatReply(text: "That didn't work.")])
        let turn = AssistantTurn(memory: FakeMemory(), performer: performer)
        let r = try await turn.run("x", channel: "mac", provider: provider, ownerName: "", allowComputer: false)
        #expect(performer.performed.count == 1 && r.failed == ["no app called Nope"])
        let results = provider.seen[1].suffix(2).map(\.content)
        #expect(results[0].hasPrefix("Refused") && results[1].hasPrefix("Failed"))
    }
    @Test func memoryToolsAndHistory() async throws {
        let memory = FakeMemory()
        let provider = ScriptedProvider([ChatReply(text: "", calls: [ToolCall(id: "m", name: "remember_fact", arguments: #"{"fact":"Likes tea"}"#)]), ChatReply(text: "Noted."), ChatReply(text: "You like tea.")])
        let turn = AssistantTurn(memory: memory, performer: FakePerformer())
        _ = try await turn.run("remember I like tea", channel: "mac", provider: provider, ownerName: "", allowComputer: false)
        #expect(memory.facts == ["Likes tea"])
        let r2 = try await turn.run("what do I like", channel: "mac", provider: provider, ownerName: "", allowComputer: false)
        #expect(r2.reply == "You like tea." && provider.seen[2].count == 6 && provider.seen[2].first?.content.contains("Likes tea") == true)
        await turn.clear("mac")
        _ = try? await turn.run("hi", channel: "mac", provider: ScriptedProvider([ChatReply(text: "Hi.")]), ownerName: "", allowComputer: false)
    }
    @Test func streamingSpeaksSentencesAndComputerTaskRuns() async throws {
        let performer = FakePerformer()
        let provider = ScriptedProvider([ChatReply(text: "", calls: [ToolCall(id: "t", name: "computer_task", arguments: #"{"goal":"fill in the form"}"#)]), ChatReply(text: "Done, the form is filled. Anything else?")])
        provider.streamPieces = ["Done, the form", " is filled. Anything", " else?"]
        var spoken: [String] = []
        let box = Box()
        let turn = AssistantTurn(memory: FakeMemory(), performer: performer)
        let r = try await turn.run("fill the form", channel: "mac", provider: provider, ownerName: "", allowComputer: true, onSentence: { box.add($0) })
        spoken = box.items
        #expect(performer.tasks == ["fill in the form"] && r.performed == ["a screen task"])
        #expect(spoken == ["Done, the form is filled.", "Anything else?"])
        #expect(provider.seen[1].last?.content == "Filled in the form.")
    }
    @Test func computerToolOnlyWhenAllowed() async throws {
        let provider = ScriptedProvider([ChatReply(text: "ok"), ChatReply(text: "ok")])
        let turn = AssistantTurn(memory: FakeMemory(), performer: FakePerformer())
        _ = try await turn.run("x", channel: "mac", provider: provider, ownerName: "", allowComputer: false)
        _ = try await turn.run("x", channel: "mac", provider: provider, ownerName: "", allowComputer: true)
        #expect(provider.seen[0].first?.content.contains("computer_task") == false && provider.seen[1].first?.content.contains("computer_task") == true)
    }
}

final class Box: @unchecked Sendable {
    private let lock = NSLock(); private var list: [String] = []
    func add(_ s: String) { lock.lock(); list.append(s); lock.unlock() }
    var items: [String] { lock.lock(); defer { lock.unlock() }; return list }
}

struct TelegramRouterTests {
    let update = { (chat: Int, text: String) in TelegramUpdate(updateID: 1, chatID: chat, text: text) }

    @Test func pairingFlowAndLockout() {
        var s = TelegramState(pairedChat: 0, pairingCode: "123456")
        #expect(TelegramRouter.route(update(7, "hello"), state: &s) == .reply("Not paired. Open Sofia's Settings on the Mac and send me the six-digit code shown there."))
        for _ in 0..<3 { _ = TelegramRouter.route(update(7, "000000"), state: &s) }
        let last = TelegramRouter.route(update(7, "000000"), state: &s)
        #expect(last == .reply("Too many wrong codes. Pairing is paused for an hour.") && s.lockedUntil != nil)
        #expect(TelegramRouter.route(update(7, "123456"), state: &s) == .ignore)
        s.lockedUntil = Date(timeIntervalSinceNow: -1)
        #expect(TelegramRouter.route(update(7, "123 456"), state: &s) == .paired(7, "Paired. This chat can now reach the Mac. Send “help” to see what I can do."))
        #expect(s.pairedChat == 7 && s.pairingCode == "")
    }
    @Test func onlyThePairedChatIsAnswered() {
        var s = TelegramState(pairedChat: 7)
        #expect(TelegramRouter.route(update(8, "status"), state: &s) == .ignore)
        #expect(TelegramRouter.route(update(7, "status"), state: &s) == .command(.status))
        #expect(TelegramRouter.route(update(7, "what did I do yesterday"), state: &s) == .freeform("what did I do yesterday"))
        #expect(TelegramRouter.route(update(7, ""), state: &s) == .ignore)
    }
    @Test func remoteSwitch() {
        var s = TelegramState(pairedChat: 7)
        #expect(TelegramRouter.route(update(7, "stop remote"), state: &s) == .setRemote(false, "Remote access is off until you send “start remote”.") && !s.remoteEnabled)
        #expect(TelegramRouter.route(update(7, "send me the thesis"), state: &s) == .reply("Remote access is off. Send “start remote” to turn it on."))
        #expect(TelegramRouter.route(update(7, "start remote"), state: &s) == .setRemote(true, "Remote access is on."))
        #expect(TelegramRouter.route(update(7, "send me the thesis"), state: &s) == .command(.sendFile("thesis")))
    }
    @Test func backoffGrowsWithJitter() {
        #expect(TelegramRouter.backoff(failures: 1, jitter: 0) == 5 && TelegramRouter.backoff(failures: 3, jitter: 0) == 15)
        #expect(TelegramRouter.backoff(failures: 20, jitter: 0) == 60 && TelegramRouter.backoff(failures: 20, jitter: 1) == 78)
    }
}

struct SplitterAndOllamaTests {
    @Test func sentencesComeOutAsTheyComplete() {
        var s = SentenceSplitter()
        var out: [String] = []
        out += s.push("Opening Safari now. It will")
        out += s.push(" take a moment, e.g. a second or two. Done!")
        #expect(out == ["Opening Safari now.", "It will take a moment, e.g. a second or two."])
        #expect(s.flush() == "Done!")
        var short = SentenceSplitter()
        #expect(short.push("Hi. There you go. ") == ["Hi. There you go."])
    }
    @Test func ollamaWireAndStreaming() {
        let body = OllamaWire.body(model: "qwen3:8b", messages: [.system("s"), .user("hi"), .assistant("", calls: [ToolCall(id: "x", name: "mac_control", arguments: #"{"action":"mute"}"#)]), .tool("x", "Done.")], tools: Prompt.tools, stream: true, think: false)
        #expect(body["think"] as? Bool == false && body["stream"] as? Bool == true)
        let msgs = body["messages"] as! [[String: Any]]
        #expect(((msgs[2]["tool_calls"] as? [[String: Any]])?.first?["function"] as? [String: Any])?["arguments"] as? [String: String] == ["action": "mute"])
        let r = OllamaWire.reply(from: ["message": ["role": "assistant", "content": " Muted. ", "tool_calls": [["function": ["name": "mac_control", "arguments": ["action": "mute"]]]]]])!
        #expect(r.text == "Muted." && r.calls[0].input["action"] as? String == "mute")
        var st = OllamaWire.StreamState()
        #expect(st.feed(line: #"{"message":{"role":"assistant","content":"Open"},"done":false}"#) == "Open")
        #expect(st.feed(line: #"{"message":{"role":"assistant","content":"ing."},"done":false}"#) == "ing.")
        #expect(st.feed(line: #"{"message":{"role":"assistant","content":"","tool_calls":[{"function":{"name":"mac_control","arguments":{"action":"lock_screen"}}}]},"done":true}"#) == nil)
        #expect(st.done && st.reply.text == "Opening." && st.reply.calls.count == 1)
        #expect(st.feed(line: "not json") == nil)
    }
    @Test func imagesTravelInWireFormats() {
        let m = ChatMessage(role: .user, content: "look", images: ["AAAA"])
        let o = OpenAIWire.body(model: "m", messages: [m], tools: [])["messages"] as! [[String: Any]]
        #expect((o[0]["content"] as? [[String: Any]])?.count == 2)
        let ol = OllamaWire.body(model: "m", messages: [m], tools: [], stream: false, think: false)["messages"] as! [[String: Any]]
        #expect(ol[0]["images"] as? [String] == ["AAAA"])
    }
}

struct ComputerLoopTests {
    final class FakeHost: ComputerHost, @unchecked Sendable {
        var log: [String] = []
        func screenshot() async throws -> Screenshot { log.append("shot"); return Screenshot(base64: "IMG", width: 1280, height: 800) }
        func click(x: Int, y: Int, double: Bool, right: Bool) async throws { log.append("click \(x),\(y)") }
        func type(_ text: String) async throws { log.append("type \(text)") }
        func key(_ combo: String) async throws { log.append("key \(combo)") }
        func scroll(x: Int, y: Int, direction: String, amount: Int) async throws { log.append("scroll") }
        func findElements(_ query: String) async throws -> String { log.append("find \(query)"); return "e1 button \"Compose\" (120,80)" }
        func pressElement(_ id: String, text: String?) async throws -> String { log.append("press \(id)"); return "Pressed button \"Compose\"." }
    }
    @Test func controlsFirstThenDone() async {
        let host = FakeHost()
        let provider = ScriptedProvider([
            ChatReply(text: "", calls: [ToolCall(id: "1", name: "find_elements", arguments: #"{"query":"compose"}"#)]),
            ChatReply(text: "", calls: [ToolCall(id: "2", name: "press_element", arguments: #"{"id":"e1"}"#)]),
            ChatReply(text: "", calls: [ToolCall(id: "3", name: "done", arguments: #"{"summary":"Compose is open.","success":true}"#)]),
        ])
        let out = await ComputerLoop.run(goal: "open compose", host: host, provider: provider) { _ in }
        #expect(out == "Compose is open." && host.log == ["shot", "find compose", "press e1"])
        #expect(provider.seen[0].first?.content.contains("open compose") == true && provider.seen[0][1].images == ["IMG"])
    }
    @Test func repeatedStepStopsAndNoVisionRefuses() async {
        let host = FakeHost()
        let same = ChatReply(text: "", calls: [ToolCall(id: "k", name: "click", arguments: #"{"x":10,"y":10}"#)])
        let provider = ScriptedProvider([same, same, same, same])
        let out = await ComputerLoop.run(goal: "x", host: host, provider: provider) { _ in }
        #expect(out.hasPrefix("I kept repeating"))
        let blind = ScriptedProvider([]); blind.supportsVision = false
        #expect((await ComputerLoop.run(goal: "x", host: host, provider: blind) { _ in }).contains("no vision"))
    }
}

struct ActionToolTests {
    @Test func actionNamedCallsRun() async throws {
        let performer = FakePerformer()
        let provider = ScriptedProvider([ChatReply(text: "", calls: [
            ToolCall(id: "a", name: "open_app", arguments: #"{"target":"YouTube"}"#),
            ToolCall(id: "b", name: "web_search", arguments: #"{"target":"lofi music","value":"youtube"}"#),
        ]), ChatReply(text: "Searching YouTube for lofi music.")])
        let turn = AssistantTurn(memory: FakeMemory(), performer: performer)
        let r = try await turn.run("find me some calm music to work to", channel: "mac", provider: provider, ownerName: "", allowComputer: false)
        #expect(performer.performed.map(\.kind) == [.openURL, .webSearch])
        #expect(performer.performed.last?.target == "lofi music" && performer.performed.last?.value == "youtube")
        #expect(r.performed.count == 2 && r.reply == "Searching YouTube for lofi music.")
    }

    @Test func everyActionIsItsOwnTool() {
        let names = Set(Prompt.tools.map(\.name))
        for k in MacAction.Kind.allCases { #expect(names.contains(k.rawValue), Comment(rawValue: k.rawValue)) }
        #expect(!names.contains("mac_control"))
        for t in Prompt.tools where MacAction.Kind(rawValue: t.name) != nil {
            #expect(!t.description.isEmpty)
            #expect((t.parameters["properties"] as? [String: Any])?["action"] == nil)
        }
    }

    @Test func unknownToolIsRefused() async throws {
        let performer = FakePerformer()
        let provider = ScriptedProvider([ChatReply(text: "", calls: [ToolCall(id: "x", name: "rm_rf", arguments: "{}")]), ChatReply(text: "I can't do that.")])
        let r = try await AssistantTurn(memory: FakeMemory(), performer: performer).run("x", channel: "mac", provider: provider, ownerName: "", allowComputer: false)
        #expect(performer.performed.isEmpty && provider.seen[1].last?.content == "Unknown tool.")
        #expect(r.reply == "I can't do that.")
    }
}

struct ActionValueTests {
    @Test func numbersAndBooleansFromTheModelAreAccepted() {
        #expect(MacAction(["action": "set_volume", "value": 30])?.value == "30")
        #expect(MacAction(["action": "set_volume", "value": 30.0])?.value == "30")
        #expect(MacAction(["action": "dark_mode", "value": true])?.value == "on")
        #expect(MacAction(["action": "wifi", "value": false])?.value == "off")
        #expect(MacAction(["action": "set_volume", "value": 300]) == nil)
        #expect(MacAction(["action": "set_volume", "value": "down to 30"])?.value == "30")
        #expect(MacAction(["action": "set_volume", "value": "30%"])?.value == "30")
        #expect(MacAction(["action": "set_volume", "value": "a bit louder"])?.value == "up")
        #expect(MacAction(["action": "set_volume", "value": "Down"])?.value == "down")
    }

    @Test func searchResultsAreNotDescribed() async throws {
        let provider = ScriptedProvider([ChatReply(text: "", calls: [ToolCall(id: "s", name: "web_search", arguments: #"{"target":"weather in Lisbon"}"#)]), ChatReply(text: "The results are on screen.")])
        _ = try await AssistantTurn(memory: FakeMemory(), performer: FakePerformer()).run("weather", channel: "mac", provider: provider, ownerName: "", allowComputer: false)
        #expect(provider.seen[1].last?.content.contains("you have not seen it") == true)
    }
}

struct QuickCommandTests {
    @Test func simpleCommandsSkipTheModel() {
        let cases: [(String, MacAction.Kind, String)] = [
            ("mute", .mute, ""), ("Mute.", .mute, ""), ("please mute the sound", .mute, ""), ("unmute", .unmute, ""),
            ("pause", .media, "play_pause"), ("pause the music", .media, "play_pause"), ("next song", .media, "next"), ("skip", .media, "next"),
            ("lock the screen", .lockScreen, ""), ("dark mode on", .darkMode, "on"), ("turn on dark mode", .darkMode, "on"),
            ("turn off dark mode", .darkMode, "off"), ("volume up", .setVolume, "up"), ("quieter", .setVolume, "down"),
            ("set the volume to 30", .setVolume, "30"), ("volume 50 percent", .setVolume, "50"),
        ]
        for (text, kind, value) in cases {
            let m = QuickCommand.match(text)
            #expect(m?.action.kind == kind, Comment(rawValue: text))
            #expect((m?.action.value ?? "") == value, Comment(rawValue: text))
        }
    }

    @Test func anythingMoreGoesToTheModel() {
        for text in ["find me some calm music", "mute Slack notifications", "what's the weather", "next week's meetings", "lock in the plan for tomorrow", "volume 300"] {
            #expect(QuickCommand.match(text) == nil, Comment(rawValue: text))
        }
    }

    @Test func quickCommandRunsWithoutAProvider() async throws {
        let performer = FakePerformer()
        let r = try await AssistantTurn(memory: FakeMemory(), performer: performer).run("mute", channel: "mac", provider: ScriptedProvider([]), ownerName: "", allowComputer: false)
        #expect(performer.performed.map(\.kind) == [.mute] && r.reply == "Muted.")
        let provider = ScriptedProvider([ChatReply(text: "Notion is open.", calls: [])])
        let turn = AssistantTurn(memory: FakeMemory(), performer: performer)
        _ = try await turn.run("mute", channel: "mac", provider: provider, ownerName: "", allowComputer: false)
        _ = try await turn.run("open notion", channel: "mac", provider: provider, ownerName: "", allowComputer: false)
        let history = provider.seen[0]
        #expect(history.contains { $0.role == .assistant && $0.toolCalls.first?.name == "mute" })
        #expect(history.contains { $0.role == .tool && $0.content.hasPrefix("Done") })
    }
}

struct WebsiteTests {
    @Test func websitesOpenAsPages() {
        let a = MacAction(["action": "open_app", "target": "YouTube"])
        #expect(a?.kind == .openURL && a?.target == "https://www.youtube.com")
        #expect(MacAction(["action": "open_app", "target": "gmail.com"])?.target == "https://mail.google.com")
        #expect(MacAction(["action": "open_app", "target": "Safari"])?.kind == .openApp)
        #expect(MacAction(["action": "open_app", "target": "WhatsApp"])?.kind == .openApp)
    }

    @Test func siteSearchesSkipTheModel() {
        let cases: [(String, String, String)] = [
            ("search lofi music on YouTube", "lofi music", "youtube"),
            ("search for Arijit Singh songs on youtube", "arijit singh songs", "youtube"),
            ("open YouTube and search for lofi music", "lofi music", "youtube"),
            ("search YouTube for cooking videos", "cooking videos", "youtube"),
            ("look up the Eiffel Tower on Wikipedia", "the eiffel tower", "wikipedia"),
            ("search Google for weather in Lisbon", "weather in lisbon", "google"),
        ]
        for (text, query, site) in cases {
            let m = QuickCommand.match(text)
            #expect(m?.action.kind == .webSearch && m?.action.target == query && m?.action.value == site, Comment(rawValue: text))
        }
        #expect(QuickCommand.match("open YouTube")?.action.target == "https://www.youtube.com")
        #expect(QuickCommand.match("go to the Netflix website")?.action.target == "https://www.netflix.com")
        #expect(QuickCommand.match("open Safari") == nil)
    }
}

struct AnySiteTests {
    @Test func searchInsideAnySite() {
        #expect(MacAction.searchURL("lofi music", site: "youtube")?.absoluteString == "https://www.youtube.com/results?search_query=lofi%20music")
        #expect(MacAction.searchURL("noise cancelling headphones", site: "amazon")?.absoluteString == "https://duckduckgo.com/?q=%21amazon%20noise%20cancelling%20headphones")
        #expect(MacAction.searchURL("swift testing", site: "github.com")?.absoluteString == "https://duckduckgo.com/?q=%21github%20swift%20testing")
        #expect(MacAction.searchURL("x", site: "bad/site") == nil)
        #expect(MacAction(["action": "web_search", "target": "inception", "value": "IMDb"])?.value == "imdb")
    }

    @Test func openAnySite() {
        #expect(MacAction(["action": "open_app", "target": "booking.com"])?.target == "https://booking.com")
        #expect(MacAction.websiteURL("Netflix")?.absoluteString == "https://www.netflix.com")
        #expect(MacAction.websiteURL("Hacker News")?.absoluteString.hasPrefix("https://duckduckgo.com/?q=%5C") == true)
        #expect(QuickCommand.match("open booking.com")?.action.target == "https://booking.com")
        let m = QuickCommand.match("search noise cancelling headphones on Amazon")
        #expect(m?.action.kind == .webSearch && m?.action.value == "amazon" && m?.action.target == "noise cancelling headphones")
        #expect(QuickCommand.match("search reddit for mechanical keyboards")?.action.value == "reddit")
        #expect(QuickCommand.match("search for files in Downloads") == nil)
        #expect(QuickCommand.match("open Spotify and play some jazz") == nil)
        #expect(QuickCommand.match("open Amazon and search for a desk lamp")?.action.target == "a desk lamp")
        #expect(QuickCommand.match("open booking.com")?.reply == "Opening booking.com.")
    }
}

struct VideoTests {
    @Test func firstVideoIdFromResults() {
        let html = #"..."videoId":"abc"... {"videoRenderer":{"videoId":"dQw4w9WgXcQ","thumbnail":{}} ... "videoId":"zzzzzzzzzzz""#
        #expect(MacAction.firstYouTubeVideo(in: html) == "dQw4w9WgXcQ")
        #expect(MacAction.firstYouTubeVideo(in: "no videos here") == nil)
        let withAd = #"{"adSlotRenderer":{"videoId":"AAAAAAAAAAA"}} {"videoRenderer":{"videoId":"BBBBBBBBBBB","title":{}}}"#
        #expect(MacAction.firstYouTubeVideo(in: withAd) == "BBBBBBBBBBB")
    }

    @Test func playOnYouTubeAndFirstResult() async throws {
        #expect(QuickCommand.match("play Shape of You on YouTube")?.action.kind == .playVideo)
        #expect(QuickCommand.match("watch lofi beats on youtube")?.action.target == "lofi beats")
        for t in ["play the first video", "click on the first video", "open the first one", "play the first result please", "Play the first video."] {
            #expect(QuickCommand.firstResult(t), Comment(rawValue: t))
        }
        #expect(!QuickCommand.firstResult("play the first season of Friends"))
        #expect(QuickCommand.match("play tum hi ho by arijit singh")?.action.target == "tum hi ho by arijit singh")
        #expect(QuickCommand.match("play tum hi ho by arijit singh")?.action.kind == .playVideo)
        #expect(QuickCommand.match("play some jazz on Spotify")?.action.value == "spotify")
        #expect(QuickCommand.match("play")?.action.kind == .media)
        #expect(QuickCommand.match("play the music")?.action.kind == .media)
        #expect(QuickCommand.match("play the first video") == nil)

        let performer = FakePerformer()
        let turn = AssistantTurn(memory: FakeMemory(), performer: performer)
        _ = try await turn.run("search lofi music on YouTube", channel: "mac", provider: ScriptedProvider([]), ownerName: "", allowComputer: false)
        let r = try await turn.run("play the first video", channel: "mac", provider: ScriptedProvider([]), ownerName: "", allowComputer: false)
        #expect(performer.performed.last?.kind == .playResult && performer.performed.last?.target == "lofi music" && performer.performed.last?.value == "1")
        #expect(r.reply == "Playing video 1.")
    }
}

struct ScreenGoalTests {
    @Test func screenRequestsGoToTheScreenTask() async throws {
        for t in ["click the subscribe button", "scroll down", "skip the ad", "what's on my screen", "Can you click on the search bar and type hello", "fill in this form", "what am I looking at"] {
            #expect(QuickCommand.screenGoal(t), Comment(rawValue: t))
        }
        for t in ["open YouTube", "type hello", "close Safari", "what's the weather", "play the first video"] {
            #expect(!QuickCommand.screenGoal(t), Comment(rawValue: t))
        }
        let performer = FakePerformer()
        let r = try await AssistantTurn(memory: FakeMemory(), performer: performer).run("skip the ad", channel: "mac", provider: ScriptedProvider([]), ownerName: "", allowComputer: true)
        #expect(performer.tasks == ["skip the ad"] && r.reply == "Filled in the form.")
        let off = FakePerformer()
        _ = try? await AssistantTurn(memory: FakeMemory(), performer: off).run("skip the ad", channel: "mac", provider: ScriptedProvider([ChatReply(text: "Screen control is off.")]), ownerName: "", allowComputer: false)
        #expect(off.tasks.isEmpty)
    }

    @Test func aVisionModelWithoutToolsIsExplained() async {
        struct NoTools: ModelProvider {
            var label: String { "Ollama qwen2.5vl:7b" }
            var supportsVision: Bool { true }
            func chat(_ m: [ChatMessage], tools: [ToolSpec]) async throws -> ChatReply { throw ProviderError("Ollama answered 400: registry.ollama.ai/library/qwen2.5vl:7b does not support tools") }
        }
        struct Host: ComputerHost {
            func screenshot() async throws -> Screenshot { Screenshot(base64: "", width: 10, height: 10, note: "") }
            func click(x: Int, y: Int, double: Bool, right: Bool) async throws {}
            func type(_ text: String) async throws {}
            func key(_ combo: String) async throws {}
            func scroll(x: Int, y: Int, direction: String, amount: Int) async throws {}
            func findElements(_ query: String) async throws -> String { "" }
            func pressElement(_ id: String, text: String?) async throws -> String { "" }
        }
        let out = await ComputerLoop.run(goal: "x", host: Host(), provider: NoTools()) { _ in }
        #expect(out.contains("qwen3-vl:8b"))
    }
}

struct ContextSizeTests {
    @Test func screenshotsGetARoomierContext() {
        let text = OllamaWire.body(model: "m", messages: [.user("hi")], tools: [], stream: false, think: false)
        let shot = OllamaWire.body(model: "m", messages: [ChatMessage(role: .user, content: "screen", images: ["abc"])], tools: [], stream: false, think: false)
        #expect((text["options"] as? [String: Any])?["num_ctx"] as? Int == 8192)
        #expect((shot["options"] as? [String: Any])?["num_ctx"] as? Int == 16384)
    }
}

struct OnScreenTests {
    @Test func nthResultOnThePage() {
        let cases: [(String, Int)] = [("play the second video in this page", 2), ("Play the second video on this page.", 2), ("click on the third video", 3), ("play the first one", 1), ("open the 4th result", 4), ("play video 5", 5), ("watch the second one on the screen", 2)]
        for (t, n) in cases { #expect(QuickCommand.resultIndex(t) == n, Comment(rawValue: t)) }
        #expect(QuickCommand.resultIndex("play the second season of Friends") == nil)
        #expect(QuickCommand.match("play the second video in this page") == nil)
    }

    @Test func theVideoOnTheScreenIsNotASearch() {
        for t in ["play the video in the speech", "play the video on the screen", "play this video", "play the video here", "pause the video", "stop the video on this page"] {
            #expect(QuickCommand.match(t)?.action.kind == .media, Comment(rawValue: t))
        }
        #expect(QuickCommand.match("play tum hi ho")?.action.kind == .playVideo)
    }

    @Test func resultsPageVideosInOrder() {
        let html = #"{"videoRenderer":{"videoId":"AAAAAAAAAAA"}} x {"videoRenderer":{"videoId":"BBBBBBBBBBB"}} {"videoRenderer":{"videoId":"AAAAAAAAAAA"}}"#
        #expect(MacAction.youTubeVideos(in: html) == ["AAAAAAAAAAA", "BBBBBBBBBBB"])
        #expect(MacAction.isYouTubeResults("https://www.youtube.com/results?search_query=lofi"))
        #expect(!MacAction.isYouTubeResults("https://www.youtube.com/watch?v=x"))
        #expect(MacAction(["action": "play_result", "value": "2"])?.value == "2")
        #expect(MacAction(["action": "play_result", "value": 3])?.value == "3")
        #expect(MacAction(["action": "play_result", "value": "50"]) == nil)
    }
}
