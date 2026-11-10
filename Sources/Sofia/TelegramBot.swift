import Foundation
import SofiaCore

@MainActor
final class TelegramBot {
    var onPaired: ((Int) -> Void)?
    var freeform: ((String) async -> String)?
    var remoteEnabled: () -> Bool = { true }
    var setRemoteEnabled: (Bool) -> Void = { _ in }
    private var token = ""
    private var state = TelegramState()
    private var loop: Task<Void, Never>?
    private var offset = 0
    private var settings: AppSettings?
    private var recent: [Date] = []
    var pairingCode: String { state.pairingCode }

    func start(token: String, chatID: Int, settings: AppSettings) {
        stop()
        self.token = token; self.settings = settings
        state = TelegramState(pairedChat: chatID, pairingCode: chatID == 0 ? Pairing.code() : "", remoteEnabled: remoteEnabled())
        guard !token.isEmpty else { return }
        loop = Task { [weak self] in await self?.run() }
    }

    func stop() { loop?.cancel(); loop = nil }

    private func api(_ method: String) -> URL { URL(string: "https://api.telegram.org/bot\(token)/\(method)")! }

    private func run() async {
        var failures = 0
        while !Task.isCancelled {
            do {
                var r = URLRequest(url: api("getUpdates"), timeoutInterval: 40)
                r.httpMethod = "POST"
                r.setValue("application/json", forHTTPHeaderField: "Content-Type")
                r.httpBody = try JSONSerialization.data(withJSONObject: ["timeout": 25, "offset": offset, "allowed_updates": ["message"]])
                let (data, resp) = try await URLSession.shared.data(for: r)
                guard (resp as? HTTPURLResponse)?.statusCode == 200, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ProviderError("telegram") }
                failures = 0
                for u in TelegramUpdate.list(from: json) {
                    offset = max(offset, u.updateID + 1)
                    await handle(u)
                }
            } catch is CancellationError { return }
            catch {
                failures += 1
                WakeLog.event("telegram poll failed")
                try? await Task.sleep(for: .seconds(TelegramRouter.backoff(failures: failures, jitter: Double.random(in: 0...1))))
            }
        }
    }

    private func handle(_ u: TelegramUpdate) async {
        state.remoteEnabled = remoteEnabled()
        switch TelegramRouter.route(u, state: &state) {
        case .ignore: return
        case .reply(let text): await send(u.chatID, text)
        case .paired(let chat, let text): onPaired?(chat); await send(chat, text)
        case .setRemote(let on, let text): setRemoteEnabled(on); await send(u.chatID, text)
        case .command(let command):
            guard rateOK() else { await send(u.chatID, "Too many requests; give me a minute."); return }
            guard let settings else { return }
            WakeLog.event("telegram command")
            let out = await RemoteRunner.run(command, settings: settings)
            if !out.text.isEmpty { await send(u.chatID, out.text) }
            if let file = out.file { await sendFile(u.chatID, file, asPhoto: out.isImage); if out.isImage { try? FileManager.default.removeItem(at: file) } }
        case .freeform(let text):
            guard rateOK() else { await send(u.chatID, "Too many requests; give me a minute."); return }
            guard let freeform else { await send(u.chatID, RemoteCommand.helpText); return }
            WakeLog.event("telegram message")
            let reply = await freeform(text)
            await send(u.chatID, reply.isEmpty ? "Done." : reply)
        }
    }

    private func rateOK() -> Bool {
        let now = Date()
        recent = recent.filter { now.timeIntervalSince($0) < 3600 }
        guard recent.count < 60 else { return false }
        recent.append(now)
        return true
    }

    func send(_ chat: Int, _ text: String) async {
        var r = URLRequest(url: api("sendMessage"), timeoutInterval: 20)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["chat_id": chat, "text": String(text.prefix(4000))])
        _ = try? await URLSession.shared.data(for: r)
    }

    func sendFile(_ chat: Int, _ file: URL, asPhoto: Bool) async {
        guard let data = try? Data(contentsOf: file), data.count <= 2_000_000_000 else { await send(chat, "That file is too large to send."); return }
        let boundary = "sofia-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) { body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!) }
        field("chat_id", String(chat))
        let part = asPhoto && data.count <= 10_000_000 ? "photo" : "document"
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(part)\"; filename=\"\(file.lastPathComponent)\"\r\nContent-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        var r = URLRequest(url: api(part == "photo" ? "sendPhoto" : "sendDocument"), timeoutInterval: 300)
        r.httpMethod = "POST"
        r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        r.httpBody = body
        _ = try? await URLSession.shared.data(for: r)
    }
}
