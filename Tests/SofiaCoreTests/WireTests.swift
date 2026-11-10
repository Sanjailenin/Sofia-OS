import Testing
import Foundation
@testable import SofiaCore

struct WireTests {
    func json(_ s: String) -> [String: Any] { try! JSONSerialization.jsonObject(with: Data(s.utf8)) as! [String: Any] }

    @Test func openAIReplyWithToolCalls() {
        let r = OpenAIWire.reply(from: json(#"{"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"c1","type":"function","function":{"name":"mac_control","arguments":"{\"action\":\"open_app\",\"target\":\"Safari\"}"}}]}}]}"#))!
        #expect(r.text == "" && r.calls.count == 1 && r.calls[0].name == "mac_control" && r.calls[0].input["target"] as? String == "Safari")
        let plain = OpenAIWire.reply(from: json(#"{"choices":[{"message":{"role":"assistant","content":" Opening Safari. "}}]}"#))!
        #expect(plain == ChatReply(text: "Opening Safari."))
        #expect(OpenAIWire.reply(from: json(#"{"error":"nope"}"#)) == nil)
        let objArgs = OpenAIWire.reply(from: json(#"{"choices":[{"message":{"tool_calls":[{"id":"c2","function":{"name":"remember_fact","arguments":{"fact":"likes tea"}}}]}}]}"#))!
        #expect(objArgs.calls[0].input["fact"] as? String == "likes tea")
    }
    @Test func openAIBodyCarriesToolsAndToolResults() {
        let body = OpenAIWire.body(model: "qwen3:8b", messages: [.system("sys"), .user("hi"), .assistant("", calls: [ToolCall(id: "c1", name: "mac_control", arguments: "{}")]), .tool("c1", "Done.")], tools: Prompt.tools)
        let msgs = body["messages"] as! [[String: Any]]
        #expect(msgs.count == 4 && msgs[3]["tool_call_id"] as? String == "c1" && (msgs[2]["tool_calls"] as? [[String: Any]])?.count == 1)
        #expect((body["tools"] as? [[String: Any]])?.count == Prompt.tools.count)
        #expect(body["model"] as? String == "qwen3:8b")
    }
    @Test func telegramUpdatesAndPairing() {
        let list = TelegramUpdate.list(from: json(#"{"ok":true,"result":[{"update_id":7,"message":{"chat":{"id":42,"type":"private"},"from":{"first_name":"Sam"},"text":" send me the thesis "}},{"update_id":8,"message":{"chat":{"id":42},"photo":[]}},{"update_id":9,"edited_message":{}}]}"#))
        #expect(list.count == 2 && list[0] == TelegramUpdate(updateID: 7, chatID: 42, text: "send me the thesis", senderName: "Sam") && list[1].text == "")
        #expect(TelegramUpdate.list(from: json(#"{"ok":false}"#)).isEmpty)
        let code = Pairing.code()
        #expect(code.count == 6 && Pairing.isCode(" \(code.prefix(3)) \(code.suffix(3)) ", code) && !Pairing.isCode("000000", code == "000000" ? "111111" : code) && !Pairing.isCode("x", ""))
    }
    @Test func promptMentionsToolsAndFacts() {
        let p = Prompt.system(ownerName: "Alex", facts: ["Prefers tea"], channel: "phone")
        #expect(p.contains("Alex") && p.contains("Prefers tea") && p.contains("phone"))
        #expect(Prompt.macControl.description.contains("open_app") && (Prompt.macControl.parameters["required"] as? [String]) == ["action"])
    }
}
