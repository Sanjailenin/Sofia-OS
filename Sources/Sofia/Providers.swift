import Foundation
import SofiaCore

struct OllamaProvider: ModelProvider {
    let baseURL: URL
    let model: String
    let think: Bool
    var label: String { "Ollama \(model)" }
    var supportsVision: Bool { Self.visionModel(model) }

    init(url: String, model: String, think: Bool = false) {
        baseURL = URL(string: url) ?? URL(string: "http://localhost:11434")!
        self.model = model; self.think = think
    }

    static func visionModel(_ name: String) -> Bool {
        let n = name.lowercased()
        return ["vl", "llava", "gemma3", "minicpm-v", "moondream", "llama3.2-vision", "pixtral", "bakllava", "granite3.2-vision"].contains { n.contains($0) }
    }

    private func request(_ body: [String: Any], timeout: TimeInterval) throws -> URLRequest {
        var r = URLRequest(url: baseURL.appendingPathComponent("api/chat"), timeoutInterval: timeout)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return r
    }

    func chat(_ messages: [ChatMessage], tools: [ToolSpec]) async throws -> ChatReply {
        let r = try request(OllamaWire.body(model: model, messages: messages, tools: tools, stream: false, think: think), timeout: 180)
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard let http = resp as? HTTPURLResponse else { throw ProviderError("no response from \(label)") }
        guard (200..<300).contains(http.statusCode) else { throw ProviderError(Self.explain(http.statusCode, data, model: model)) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let reply = OllamaWire.reply(from: json) else { throw ProviderError("\(label) sent something unexpected") }
        return reply
    }

    func stream(_ messages: [ChatMessage], tools: [ToolSpec], onText: @escaping @Sendable (String) -> Void) async throws -> ChatReply {
        let r = try request(OllamaWire.body(model: model, messages: messages, tools: tools, stream: true, think: think), timeout: 180)
        let (bytes, resp) = try await URLSession.shared.bytes(for: r)
        guard let http = resp as? HTTPURLResponse else { throw ProviderError("no response from \(label)") }
        guard (200..<300).contains(http.statusCode) else {
            var body = Data(); for try await b in bytes { body.append(b); if body.count > 4000 { break } }
            throw ProviderError(Self.explain(http.statusCode, body, model: model))
        }
        var state = OllamaWire.StreamState()
        var line: [UInt8] = []
        for try await b in bytes {
            if b == 0x0A {
                if let piece = state.feed(line: String(decoding: line, as: UTF8.self)) { onText(piece) }
                line.removeAll(keepingCapacity: true)
                if state.done { break }
            } else { line.append(b) }
        }
        if !line.isEmpty, let piece = state.feed(line: String(decoding: line, as: UTF8.self)) { onText(piece) }
        return state.reply
    }

    func isReachable() async -> Bool {
        var r = URLRequest(url: baseURL.appendingPathComponent("api/tags"), timeoutInterval: 3)
        r.httpMethod = "GET"
        guard let (data, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let models = json["models"] as? [[String: Any]] else { return true }
        let names = models.compactMap { $0["name"] as? String }
        return names.isEmpty || names.contains { $0 == model || $0.hasPrefix(model + ":") || model.hasPrefix($0) }
    }

    static func explain(_ status: Int, _ data: Data, model: String) -> String {
        let msg = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String) ?? ""
        if status == 404 || msg.contains("not found") { return "The model \(model) isn't pulled. Run: ollama pull \(model)" }
        if msg.lowercased().contains("memory") { return "Ollama ran out of memory for \(model); try a smaller model in Settings." }
        return "Ollama answered \(status)\(msg.isEmpty ? "" : ": \(msg)")"
    }
}

struct OpenAICompatibleProvider: ModelProvider {
    let baseURL: URL
    let apiKey: String?
    let model: String
    let label: String
    let supportsVision: Bool

    init(baseURL: URL, apiKey: String? = nil, model: String, label: String, supportsVision: Bool = true) {
        self.baseURL = baseURL; self.apiKey = apiKey; self.model = model; self.label = label; self.supportsVision = supportsVision
    }

    func chat(_ messages: [ChatMessage], tools: [ToolSpec]) async throws -> ChatReply {
        var r = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"), timeoutInterval: 120)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty { r.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        r.httpBody = try JSONSerialization.data(withJSONObject: OpenAIWire.body(model: model, messages: messages, tools: tools))
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard let http = resp as? HTTPURLResponse else { throw ProviderError("no response from \(label)") }
        guard (200..<300).contains(http.statusCode) else { throw ProviderError("\(label) answered \(http.statusCode)") }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let reply = OpenAIWire.reply(from: json) else { throw ProviderError("\(label) sent something unexpected") }
        return reply
    }
}

