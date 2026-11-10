import Foundation

public enum ActionOutcome: Equatable { case done(String), failed(String) }

public protocol ActionPerformer: Sendable {
    func perform(_ action: MacAction) async -> ActionOutcome
    func computerTask(_ goal: String, progress: @escaping @Sendable (String) -> Void) async -> String
}

public protocol MemoryStoring: AnyObject, Sendable {
    var facts: [String] { get }
    func remember(_ fact: String)
    func forget(matching words: String) -> Int
}

public struct TurnResult: Equatable {
    public var reply: String
    public var performed: [String]
    public var failed: [String]
    public init(reply: String, performed: [String] = [], failed: [String] = []) { self.reply = reply; self.performed = performed; self.failed = failed }
}

public actor AssistantTurn {
    private var history: [String: [ChatMessage]] = [:]
    private var lastVideoSearch: [String: String] = [:]
    private let memory: MemoryStoring
    private let performer: ActionPerformer
    public static let maxRounds = 6
    public static let historyKept = 30

    public init(memory: MemoryStoring, performer: ActionPerformer) { self.memory = memory; self.performer = performer }

    public func clear(_ channel: String) { history[channel] = nil }

    public func run(_ text: String, channel: String, provider: ModelProvider, ownerName: String, allowComputer: Bool, assistantName: String = WakeWord.defaultName, onSentence: (@Sendable (String) -> Void)? = nil, progress: (@Sendable (String) -> Void)? = nil) async throws -> TurnResult {
        currentChannel = channel
        var messages = history[channel] ?? []
        messages.append(.user(text))
        var performed: [String] = [], failed: [String] = []
        var quickMatch = QuickCommand.match(text)
        if quickMatch == nil, let n = QuickCommand.resultIndex(text), let a = MacAction(["action": "play_result", "target": lastVideoSearch[channel] ?? "", "value": String(n)]) {
            quickMatch = (a, "Playing video \(n).")
        }
        if quickMatch == nil, allowComputer, QuickCommand.screenGoal(text) {
            let summary = await performer.computerTask(text) { progress?($0) }
            performed.append("a screen task")
            let call = ToolCall(id: "quick_\(UUID().uuidString.prefix(8))", name: "computer_task", arguments: (try? JSONSerialization.data(withJSONObject: ["goal": text])).map { String(decoding: $0, as: UTF8.self) } ?? "{}")
            messages.append(.assistant("", calls: [call]))
            messages.append(.tool(call.id, summary))
            messages.append(.assistant(summary, calls: []))
            history[channel] = Array(messages.suffix(Self.historyKept))
            return TurnResult(reply: summary, performed: performed, failed: failed)
        }
        if let quick = quickMatch {
            noteVideo(quick.action, channel: channel)
            let reply: String
            switch await performer.perform(quick.action) {
            case .done: performed.append(quick.action.summary); reply = quick.reply
            case .failed(let why): failed.append(why); reply = ""
            }
            var args: [String: String] = [:]
            if !quick.action.target.isEmpty { args["target"] = quick.action.target }
            if !quick.action.value.isEmpty { args["value"] = quick.action.value }
            let json = (try? JSONSerialization.data(withJSONObject: args)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
            let call = ToolCall(id: "quick_\(UUID().uuidString.prefix(8))", name: quick.action.kind.rawValue, arguments: json)
            messages.append(.assistant("", calls: [call]))
            messages.append(.tool(call.id, reply.isEmpty ? "Failed: \(failed.joined(separator: "; "))" : "Done: \(quick.action.summary)."))
            messages.append(.assistant(reply.isEmpty ? "I couldn't do that." : reply, calls: []))
            history[channel] = Array(messages.suffix(Self.historyKept))
            return TurnResult(reply: reply, performed: performed, failed: failed)
        }
        var reply = ""
        let tools = allowComputer ? Prompt.tools + [Prompt.computerTask] : Prompt.tools
        for _ in 0..<Self.maxRounds {
            let all = [ChatMessage.system(Prompt.system(ownerName: ownerName, facts: memory.facts, channel: channel, computer: allowComputer, assistantName: assistantName))] + messages.suffix(24)
            let splitter = SplitterBox()
            let out = try await provider.stream(all, tools: tools) { piece in
                if let onSentence { for s in splitter.push(piece) { onSentence(s) } }
            }
            if let onSentence, let tail = splitter.flush(), out.calls.isEmpty { onSentence(tail) }
            messages.append(.assistant(out.text, calls: out.calls))
            if out.calls.isEmpty { reply = out.text; break }
            for call in out.calls {
                let result = await handle(call, performed: &performed, failed: &failed, progress: progress)
                messages.append(.tool(call.id, result))
            }
            reply = out.text
        }
        history[channel] = Array(messages.suffix(Self.historyKept))
        if reply.isEmpty { reply = performed.isEmpty ? "Done." : "Done: \(performed.joined(separator: ", "))." }
        return TurnResult(reply: reply, performed: performed, failed: failed)
    }

    private var currentChannel = ""

    private func noteVideo(_ a: MacAction, channel: String) {
        if (a.kind == .webSearch && a.value == "youtube") || a.kind == .playVideo { lastVideoSearch[channel] = a.target }
    }

    private func handle(_ call: ToolCall, performed: inout [String], failed: inout [String], progress: (@Sendable (String) -> Void)?) async -> String {
        switch call.name {
        case "mac_control", _ where MacAction.Kind(rawValue: call.name) != nil:
            var input = call.input
            if call.name != "mac_control" { input["action"] = call.name }
            guard let action = MacAction(input) else { return "Refused: not a valid Mac action." }
            noteVideo(action, channel: currentChannel)
            switch await performer.perform(action) {
            case .done(let note):
                performed.append(action.summary)
                let base = note.isEmpty ? "Done: \(action.summary)." : note
                return action.kind == .webSearch || action.kind == .openURL ? base + " The page is open on screen for the user; you have not seen it, so don't describe what it shows." : base
            case .failed(let why): failed.append(why); return "Failed: \(why)"
            }
        case "computer_task":
            let goal = (call.input["goal"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !goal.isEmpty else { return "Refused: no goal." }
            let summary = await performer.computerTask(goal) { progress?($0) }
            performed.append("a screen task")
            return summary
        case "remember_fact":
            let fact = call.input["fact"] as? String ?? ""
            memory.remember(fact)
            return fact.isEmpty ? "Nothing to remember." : "Remembered."
        case "forget_fact":
            let n = memory.forget(matching: call.input["words"] as? String ?? "")
            return n == 0 ? "Nothing matched." : "Forgot \(n)."
        default:
            return "Unknown tool."
        }
    }
}

final class SplitterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var splitter = SentenceSplitter()
    func push(_ piece: String) -> [String] { lock.lock(); defer { lock.unlock() }; return splitter.push(piece) }
    func flush() -> String? { lock.lock(); defer { lock.unlock() }; return splitter.flush() }
}
