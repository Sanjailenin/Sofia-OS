import Foundation

public struct TelegramUpdate: Equatable {
    public var updateID: Int
    public var chatID: Int
    public var text: String
    public var senderName: String
    public var chatType: String
    public init(updateID: Int, chatID: Int, text: String, senderName: String = "", chatType: String = "private") { self.updateID = updateID; self.chatID = chatID; self.text = text; self.senderName = senderName; self.chatType = chatType }

    public init?(json o: [String: Any]) {
        guard let id = (o["update_id"] as? NSNumber)?.intValue, let m = o["message"] as? [String: Any], let chat = m["chat"] as? [String: Any], let chatID = (chat["id"] as? NSNumber)?.intValue else { return nil }
        let text = (m["text"] as? String ?? m["caption"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let from = m["from"] as? [String: Any]
        self.init(updateID: id, chatID: chatID, text: text, senderName: from?["first_name"] as? String ?? "", chatType: chat["type"] as? String ?? "")
    }

    public static func list(from json: [String: Any]) -> [TelegramUpdate] {
        guard json["ok"] as? Bool == true, let result = json["result"] as? [[String: Any]] else { return [] }
        return result.compactMap(TelegramUpdate.init(json:))
    }
}

public enum Pairing {
    public static func code() -> String { String(format: "%06d", Int.random(in: 0...999_999)) }
    public static func isCode(_ text: String, _ code: String) -> Bool {
        !code.isEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "") == code
    }
}
