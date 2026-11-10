import Foundation

public struct ToolCall: Equatable {
    public var id: String
    public var name: String
    public var arguments: String
    public init(id: String, name: String, arguments: String) { self.id = id; self.name = name; self.arguments = arguments }
    public var input: [String: Any] { (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any] ?? [:] }
}

public struct ToolSpec {
    public var name: String
    public var description: String
    public var parameters: [String: Any]
    public init(name: String, description: String, parameters: [String: Any]) { self.name = name; self.description = description; self.parameters = parameters }
}

public struct ChatMessage: Equatable {
    public enum Role: String { case system, user, assistant, tool }
    public var role: Role
    public var content: String
    public var toolCalls: [ToolCall]
    public var toolCallID: String?
    public var images: [String]
    public init(role: Role, content: String, toolCalls: [ToolCall] = [], toolCallID: String? = nil, images: [String] = []) {
        self.role = role; self.content = content; self.toolCalls = toolCalls; self.toolCallID = toolCallID; self.images = images
    }
    public static func system(_ s: String) -> ChatMessage { .init(role: .system, content: s) }
    public static func user(_ s: String) -> ChatMessage { .init(role: .user, content: s) }
    public static func assistant(_ s: String, calls: [ToolCall] = []) -> ChatMessage { .init(role: .assistant, content: s, toolCalls: calls) }
    public static func tool(_ id: String, _ s: String, images: [String] = []) -> ChatMessage { .init(role: .tool, content: s, toolCallID: id, images: images) }
}

public protocol ModelProvider: Sendable {
    var label: String { get }
    var supportsVision: Bool { get }
    func chat(_ messages: [ChatMessage], tools: [ToolSpec]) async throws -> ChatReply
    func stream(_ messages: [ChatMessage], tools: [ToolSpec], onText: @escaping @Sendable (String) -> Void) async throws -> ChatReply
}

public extension ModelProvider {
    var supportsVision: Bool { false }
    func stream(_ messages: [ChatMessage], tools: [ToolSpec], onText: @escaping @Sendable (String) -> Void) async throws -> ChatReply {
        let r = try await chat(messages, tools: tools)
        if !r.text.isEmpty { onText(r.text) }
        return r
    }
}

public struct ProviderError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct ChatReply: Equatable {
    public var text: String
    public var calls: [ToolCall]
    public init(text: String, calls: [ToolCall] = []) { self.text = text; self.calls = calls }
}

public enum OpenAIWire {
    public static func body(model: String, messages: [ChatMessage], tools: [ToolSpec], temperature: Double = 0.4) -> [String: Any] {
        var out: [String: Any] = ["model": model, "temperature": temperature, "messages": messages.map(encode)]
        if !tools.isEmpty {
            out["tools"] = tools.map { ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.parameters]] }
        }
        return out
    }
    static func encode(_ m: ChatMessage) -> [String: Any] {
        var o: [String: Any] = ["role": m.role.rawValue, "content": m.content]
        if !m.images.isEmpty, m.role == .user {
            o["content"] = [["type": "text", "text": m.content]] + m.images.map { ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\($0)"]] }
        }
        if !m.toolCalls.isEmpty { o["tool_calls"] = m.toolCalls.map { ["id": $0.id, "type": "function", "function": ["name": $0.name, "arguments": $0.arguments]] } }
        if let id = m.toolCallID { o["tool_call_id"] = id }
        return o
    }
    public static func reply(from json: [String: Any]) -> ChatReply? {
        guard let choice = (json["choices"] as? [[String: Any]])?.first, let message = choice["message"] as? [String: Any] else { return nil }
        let text = (message["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let calls = (message["tool_calls"] as? [[String: Any]] ?? []).compactMap { c -> ToolCall? in
            guard let f = c["function"] as? [String: Any], let name = f["name"] as? String else { return nil }
            let args: String
            if let s = f["arguments"] as? String { args = s }
            else if let o = f["arguments"], let d = try? JSONSerialization.data(withJSONObject: o) { args = String(decoding: d, as: UTF8.self) }
            else { args = "{}" }
            return ToolCall(id: c["id"] as? String ?? UUID().uuidString, name: name, arguments: args)
        }
        return ChatReply(text: text, calls: calls)
    }
}

public enum OllamaWire {
    public static func body(model: String, messages: [ChatMessage], tools: [ToolSpec], stream: Bool, think: Bool) -> [String: Any] {
        let images = messages.contains { !$0.images.isEmpty }
        var out: [String: Any] = ["model": model, "stream": stream, "think": think, "options": ["temperature": 0.4, "num_ctx": images ? 16384 : 8192] as [String: Any], "keep_alive": "30m", "messages": messages.map(encode)]
        if !tools.isEmpty { out["tools"] = tools.map { ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.parameters]] } }
        return out
    }
    static func encode(_ m: ChatMessage) -> [String: Any] {
        var o: [String: Any] = ["role": m.role.rawValue, "content": m.content]
        if !m.toolCalls.isEmpty { o["tool_calls"] = m.toolCalls.map { ["function": ["name": $0.name, "arguments": $0.input]] } }
        if !m.images.isEmpty { o["images"] = m.images }
        return o
    }
    public static func reply(from json: [String: Any]) -> ChatReply? {
        guard let message = json["message"] as? [String: Any] else { return nil }
        return ChatReply(text: (message["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines), calls: calls(in: message))
    }
    static func calls(in message: [String: Any]) -> [ToolCall] {
        (message["tool_calls"] as? [[String: Any]] ?? []).compactMap { c in
            guard let f = c["function"] as? [String: Any], let name = f["name"] as? String else { return nil }
            let args = (f["arguments"] as? [String: Any]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }.map { String(decoding: $0, as: UTF8.self) } ?? (f["arguments"] as? String ?? "{}")
            return ToolCall(id: c["id"] as? String ?? "call_\(UUID().uuidString.prefix(8))", name: name, arguments: args)
        }
    }
    public struct StreamState: Equatable {
        public var text = ""
        public var calls: [ToolCall] = []
        public var done = false
        public init() {}
        public mutating func feed(line: String) -> String? {
            guard let d = line.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }
            if o["done"] as? Bool == true { done = true }
            guard let m = o["message"] as? [String: Any] else { return nil }
            calls += OllamaWire.calls(in: m)
            let piece = m["content"] as? String ?? ""
            text += piece
            return piece.isEmpty ? nil : piece
        }
        public var reply: ChatReply { ChatReply(text: text.trimmingCharacters(in: .whitespacesAndNewlines), calls: calls) }
    }
}

public struct SentenceSplitter {
    static let boundary = try! NSRegularExpression(pattern: #"[.!?]["”’)\]]?(?=\s)|\n"#)
    static let abbreviations = try! NSRegularExpression(pattern: #"\b(?:e\.g|i\.e|etc|vs|Mr|Mrs|Ms|Dr|St|No|approx)\.$"#, options: .caseInsensitive)
    private var buffer = ""
    public let minLength: Int
    public init(minLength: Int = 12) { self.minLength = minLength }

    public mutating func push(_ delta: String) -> [String] {
        buffer += delta
        var out: [String] = []
        while true {
            let range = NSRange(buffer.startIndex..., in: buffer)
            guard let m = Self.boundary.firstMatch(in: buffer, range: range), let r = Range(m.range, in: buffer) else { break }
            let head = String(buffer[..<r.upperBound])
            let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count < minLength || Self.abbreviations.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
                if buffer.distance(from: buffer.startIndex, to: r.upperBound) >= buffer.count { break }
                let after = buffer.index(after: r.upperBound)
                if Self.boundary.firstMatch(in: buffer, range: NSRange(after..., in: buffer)) == nil { break }
                let rest = String(buffer[r.upperBound...])
                guard let m2 = Self.boundary.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)), let r2 = Range(m2.range, in: rest) else { break }
                let head2 = head + String(rest[..<r2.upperBound])
                out.append(head2.trimmingCharacters(in: .whitespacesAndNewlines))
                buffer = String(rest[r2.upperBound...])
                continue
            }
            if !trimmed.isEmpty { out.append(trimmed) }
            buffer = String(buffer[r.upperBound...])
        }
        return out
    }
    public mutating func flush() -> String? {
        let t = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return t.isEmpty ? nil : t
    }
}
