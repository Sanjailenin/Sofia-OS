import Foundation
import ServiceManagement
import SofiaCore

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var ownerName: String { didSet { d.set(ownerName, forKey: "ownerName") } }
    @Published var assistantName: String { didSet { d.set(assistantName, forKey: "assistantName"); WakeWord.current = WakeWord(name: assistantName) } }
    @Published var setupDone: Bool { didSet { d.set(setupDone, forKey: "setupDone") } }
    @Published var ollamaURL: String { didSet { d.set(ollamaURL, forKey: "ollamaURL") } }
    @Published var ollamaModel: String { didSet { d.set(ollamaModel, forKey: "ollamaModel") } }
    @Published var visionModel: String { didSet { d.set(visionModel, forKey: "visionModel") } }
    @Published var allowComputer: Bool { didSet { d.set(allowComputer, forKey: "allowComputer") } }
    @Published var thinking: Bool { didSet { d.set(thinking, forKey: "thinking") } }
    @Published var phoneProvider: String { didSet { d.set(phoneProvider, forKey: "phoneProvider") } }
    @Published var phoneModel: String { didSet { d.set(phoneModel, forKey: "phoneModel") } }
    @Published var voiceName: String { didSet { d.set(voiceName, forKey: "voiceName") } }
    @Published var elevenLabsVoice: String { didSet { d.set(elevenLabsVoice, forKey: "elevenLabsVoice") } }
    @Published var wakeWord: Bool { didSet { d.set(wakeWord, forKey: "wakeWord") } }
    @Published var wakeMessage = ""
    @Published var casualWake: Bool { didSet { d.set(casualWake, forKey: "casualWake") } }
    @Published var keywordWake: Bool { didSet { d.set(keywordWake, forKey: "keywordWake") } }
    @Published var clapVerify: Bool { didSet { d.set(clapVerify, forKey: "clapVerify") } }
    static let casualWindow: TimeInterval = 10 * 60
    @Published var conversation: Bool { didSet { d.set(conversation, forKey: "conversation") } }
    @Published var cleanAudio: Bool { didSet { d.set(cleanAudio, forKey: "cleanAudio") } }
    @Published var entrance: Bool { didSet { d.set(entrance, forKey: "entrance") } }
    @Published var entranceFile: String { didSet { d.set(entranceFile, forKey: "entranceFile") } }
    @Published var entranceSpotify: String { didSet { d.set(entranceSpotify, forKey: "entranceSpotify") } }
    @Published var entranceSpotifyStart: Double { didSet { d.set(entranceSpotifyStart, forKey: "entranceSpotifyStart") } }
    @Published var entranceSpotifyStop: Double { didSet { d.set(entranceSpotifyStop, forKey: "entranceSpotifyStop") } }
    @Published var clapSensitivity: String { didSet { d.set(clapSensitivity, forKey: "clapSensitivity") } }
    @Published var islandScreen: String { didSet { d.set(islandScreen, forKey: "islandScreen") } }
    @Published var nudges: Bool { didSet { d.set(nudges, forKey: "nudges") } }
    @Published var standby: Bool { didSet { d.set(standby, forKey: "standby") } }
    @Published var remoteAccess: Bool { didSet { d.set(remoteAccess, forKey: "remoteAccess") } }
    @Published var remoteRoots: String { didSet { d.set(remoteRoots, forKey: "remoteRoots") } }
    @Published var keepAwake: Bool { didSet { d.set(keepAwake, forKey: "keepAwake") } }
    @Published var telegramChatID: Int { didSet { d.set(telegramChatID, forKey: "telegramChatID") } }
    @Published var loginMessage = ""
    @Published var openAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            guard openAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do { if openAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginMessage = "" }
            catch { loginMessage = "Couldn't change the login item: \(error.localizedDescription)"; openAtLogin = SMAppService.mainApp.status == .enabled }
        }
    }

    let telegramToken: SecretStore = CachedSecretStore(KeychainSecretStore(service: "dev.sofia.app", account: "telegram-token"))
    let elevenLabsKey: SecretStore = CachedSecretStore(KeychainSecretStore(service: "dev.sofia.app", account: "elevenlabs-key"))
    let openAIKey: SecretStore = CachedSecretStore(KeychainSecretStore(service: "dev.sofia.app", account: "openai-key"))

    init() {
        let d = UserDefaults.standard
        func flag(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: key) == nil ? fallback : d.bool(forKey: key) }
        ownerName = d.string(forKey: "ownerName") ?? ""
        assistantName = d.string(forKey: "assistantName") ?? WakeWord.defaultName
        setupDone = d.bool(forKey: "setupDone")
        WakeWord.current = WakeWord(name: d.string(forKey: "assistantName") ?? WakeWord.defaultName)
        ollamaURL = d.string(forKey: "ollamaURL") ?? "http://localhost:11434"
        ollamaModel = d.string(forKey: "ollamaModel") ?? "qwen3:8b"
        let storedVision = d.string(forKey: "visionModel") ?? ""
        visionModel = storedVision.isEmpty || storedVision.hasPrefix("qwen2.5vl") ? "qwen3-vl:8b" : storedVision
        allowComputer = flag("allowComputer", true)
        thinking = d.bool(forKey: "thinking")
        phoneProvider = d.string(forKey: "phoneProvider") ?? "ollama"
        phoneModel = d.string(forKey: "phoneModel") ?? ""
        voiceName = SofiaVoice.resolve(d.string(forKey: "voiceName") ?? "").id
        elevenLabsVoice = d.string(forKey: "elevenLabsVoice") ?? ""
        wakeWord = flag("wakeWord", true)
        casualWake = flag("casualWake", true)
        keywordWake = flag("keywordWake", true)
        clapVerify = flag("clapVerify", true)
        conversation = flag("conversation", true)
        cleanAudio = flag("cleanAudio", true)
        entrance = flag("entrance", false)
        entranceFile = d.string(forKey: "entranceFile") ?? ""
        entranceSpotify = d.string(forKey: "entranceSpotify") ?? ""
        entranceSpotifyStart = d.double(forKey: "entranceSpotifyStart")
        entranceSpotifyStop = d.double(forKey: "entranceSpotifyStop")
        clapSensitivity = d.string(forKey: "clapSensitivity") ?? "normal"
        islandScreen = d.string(forKey: "islandScreen") ?? "follow"
        nudges = flag("nudges", true)
        standby = d.bool(forKey: "standby")
        remoteAccess = flag("remoteAccess", true)
        remoteRoots = d.string(forKey: "remoteRoots") ?? ""
        keepAwake = d.bool(forKey: "keepAwake")
        telegramChatID = d.integer(forKey: "telegramChatID")
    }

    var localProvider: OllamaProvider { OllamaProvider(url: ollamaURL, model: ollamaModel, think: thinking) }

    var phoneProviderInstance: ModelProvider {
        switch phoneProvider {
        case "openai":
            if let key = openAIKey.read(), !key.isEmpty { return OpenAICompatibleProvider(baseURL: URL(string: "https://api.openai.com")!, apiKey: key, model: phoneModel.isEmpty ? "gpt-4o-mini" : phoneModel, label: "OpenAI") }
        default: break
        }
        return OllamaProvider(url: ollamaURL, model: ollamaModel, think: true)
    }

    var visionProvider: ModelProvider {
        if OllamaProvider.visionModel(ollamaModel) { return OllamaProvider(url: ollamaURL, model: ollamaModel, think: false) }
        return OllamaProvider(url: ollamaURL, model: visionModel, think: false)
    }
}

final class CachedSecretStore: SecretStore, @unchecked Sendable {
    private let inner: SecretStore
    private var cached: String??
    private let lock = NSLock()
    init(_ inner: SecretStore) { self.inner = inner }
    func read() -> String? {
        lock.lock(); defer { lock.unlock() }
        if let c = cached { return c }
        let v = inner.read(); cached = .some(v); return v
    }
    func write(_ value: String) throws { lock.lock(); defer { lock.unlock() }; try inner.write(value); cached = .some(value) }
    func delete() { lock.lock(); defer { lock.unlock() }; inner.delete(); cached = .some(nil) }
}
