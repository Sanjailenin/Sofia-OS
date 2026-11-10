import SwiftUI
import SofiaCore

extension Notification.Name {
    static let sofiaEntrance = Notification.Name("sofiaEntrance")
    static let sofiaTelegramChanged = Notification.Name("sofiaTelegramChanged")
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let pairingCode: () -> String
    @ObservedObject private var fields = SecretFields()

    var body: some View {
        Form {
            Section("Permissions") { PermissionsView() }
            Section("You and her") {
                TextField("Her name (what you call her: “Hey …”)", text: $settings.assistantName).textFieldStyle(.roundedBorder)
                TextField("Your first name (how she addresses you)", text: $settings.ownerName).textFieldStyle(.roundedBorder)
                Toggle("Open at login", isOn: $settings.openAtLogin)
                if !settings.loginMessage.isEmpty { Text(settings.loginMessage).font(.caption).foregroundStyle(.red) }
            }
            Section("Model (runs on this Mac)") {
                TextField("Ollama address", text: $settings.ollamaURL).textFieldStyle(.roundedBorder)
                TextField("Model", text: $settings.ollamaModel).textFieldStyle(.roundedBorder)
                TextField("Vision model for screen tasks, with vision and tools (e.g. qwen3-vl:8b)", text: $settings.visionModel).textFieldStyle(.roundedBorder)
                Toggle("Let the model think before answering (slower, more careful)", isOn: $settings.thinking)
                Toggle("Let her use the screen, mouse and keyboard for multi-step tasks", isOn: $settings.allowComputer)
                HStack {
                    Text(fields.ollamaState.isEmpty ? "Everything you say to the notch is answered here, on this Mac." : fields.ollamaState).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Check") { Task { let ok = await settings.localProvider.isReachable(); fields.ollamaState = ok ? "Ollama is running and the model is ready." : "Ollama isn't reachable, or the model isn't pulled (ollama pull \(settings.ollamaModel))." } }
                }
            }
            Section("Voice") {
                Picker("Voice", selection: $settings.voiceName) {
                    ForEach(SofiaVoice.all) { v in Text(v.label).tag(v.id) }
                }
                Text(Kokoro.installed ? "Six natural voices that run on this Mac. Nothing is sent anywhere." : "Her voices aren't downloaded yet, so the Mac's own voice is used. Run the installer again to get them: \(Speech.installCommand)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                HStack { SecureField("ElevenLabs API key (optional, for a premium voice)", text: $fields.elevenLabsKey); Button("Save") { save(settings.elevenLabsKey, fields.elevenLabsKey) } }
                TextField("ElevenLabs voice id (optional)", text: $settings.elevenLabsVoice).textFieldStyle(.roundedBorder)
            }
            Section("Wake") {
                Toggle("Wake with “Hey \(settings.assistantName)” (on this Mac only)", isOn: $settings.wakeWord)
                if !settings.wakeMessage.isEmpty {
                    let help = WakeHelp(message: settings.wakeMessage, name: settings.assistantName)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(settings.wakeMessage).font(.callout.bold()).foregroundStyle(.red)
                        Text("To turn it on:").font(.caption.bold())
                        ForEach(Array(help.steps.enumerated()), id: \.offset) { i, step in
                            Text("\(i + 1). \(step)").font(.caption).fixedSize(horizontal: false, vertical: true)
                        }
                        HStack {
                            Button(help.button) { NSWorkspace.shared.open(help.url) }
                            Button("Try again") { settings.wakeWord = true }
                        }
                    }.padding(.vertical, 4)
                }
                Toggle("Just “\(settings.assistantName), …” for 10 minutes after a conversation", isOn: $settings.casualWake).disabled(!settings.wakeWord)
                Toggle("Also hear “Hey \(settings.assistantName)” with the keyword spotter", isOn: $settings.keywordWake).disabled(!settings.wakeWord)
                Text(KeywordSpotter.installed
                     ? "A small model on this Mac listens for the sound of “Hey \(settings.assistantName)” next to Apple's speech recognition, which often writes the name wrong. Whichever hears it first wakes her. It needs a restart after changing her name."
                     : "Not installed yet. Run the installer again to add it: \(Speech.installCommand)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Toggle("Keep listening after she answers", isOn: $settings.conversation)
                Toggle("Noise suppression and echo cancellation", isOn: $settings.cleanAudio)
                Text("Cleans your voice while you speak a request; other audio is turned down only for those few seconds. While the Mac plays any audio, claps and the entrance phrase are ignored and only “Hey \(settings.assistantName)” wakes her.").font(.caption).foregroundStyle(.secondary)
                Text("⌃⌥Space or ⌃⌥S talks, ⌃⌥D dictates into the field in front, Esc cancels.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Display") {
                Picker("Island appears on", selection: $settings.islandScreen) { Text("The screen I'm using").tag("follow"); Text("The built-in screen").tag("builtin"); Text("The main display").tag("main") }.pickerStyle(.segmented)
            }
            Section("Entrance") {
                Toggle("Play a song on a double clap or “wake up, daddy's home”", isOn: $settings.entrance)
                Picker("Clap sensitivity", selection: $settings.clapSensitivity) { Text("Low").tag("low"); Text("Normal").tag("normal"); Text("High").tag("high") }.pickerStyle(.segmented).disabled(!settings.entrance)
                Toggle("Check claps with Apple's sound classifier", isOn: $settings.clapVerify).disabled(!settings.entrance)
                Text("Two sharp sounds are checked by macOS's built-in classifier before they count: a knock, a door, a finger snap, typing or a glass with a clear lead over clapping is ignored; anything close still counts.").font(.caption).foregroundStyle(.secondary)
                TextField("Spotify track link (optional)", text: $settings.entranceSpotify).textFieldStyle(.roundedBorder).disabled(!settings.entrance)
                HStack {
                    TextField("Or your own mp3/wav path", text: $settings.entranceFile).textFieldStyle(.roundedBorder).disabled(!settings.entrance)
                    Button("Play") { NotificationCenter.default.post(name: .sofiaEntrance, object: nil) }.disabled(!settings.entrance)
                }
            }
            Section("Nudges and standby") {
                Toggle("Nudges: low battery, disk nearly full, network lost and back", isOn: $settings.nudges)
                Toggle("\(settings.assistantName) is off (say “\(settings.assistantName), go off”; “Hey \(settings.assistantName)”, a clap, the hotkey or this switch wakes her)", isOn: $settings.standby)
            }
            Section("From your phone (Telegram)") {
                Toggle("Let her do things on this Mac when I message her", isOn: $settings.remoteAccess)
                HStack { SecureField("Telegram bot token (from @BotFather)", text: $fields.telegramToken); Button("Save") { save(settings.telegramToken, fields.telegramToken); NotificationCenter.default.post(name: .sofiaTelegramChanged, object: nil) } }
                if settings.telegramChatID == 0 {
                    Text(pairingCode().isEmpty ? "Save a token, then send the pairing code to your bot from your phone." : "Send this code to your bot from your phone: \(pairingCode())").font(.caption)
                } else {
                    HStack { Text("Paired with one chat.").font(.caption); Button("Unpair") { settings.telegramChatID = 0 } }
                }
                TextField("Folders files may be sent from (comma-separated; empty = Desktop, Documents, Downloads, Movies, Pictures, Music)", text: $settings.remoteRoots).textFieldStyle(.roundedBorder)
                Toggle("Keep this Mac awake while plugged in", isOn: $settings.keepAwake)
                Picker("Model for free-form requests from the phone", selection: $settings.phoneProvider) { Text("Ollama (local)").tag("ollama"); Text("OpenAI").tag("openai") }
                if settings.phoneProvider == "openai" { HStack { SecureField("OpenAI API key", text: $fields.openAIKey); Button("Save") { save(settings.openAIKey, fields.openAIKey) } } }
                if settings.phoneProvider != "ollama" { TextField("Model name (optional)", text: $settings.phoneModel).textFieldStyle(.roundedBorder) }
                Text("Commands like “send me the thesis pdf”, “screen”, “status”, “lock” never use a model. Only free-form messages do, and only from the phone. Keys live in your Keychain.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, minHeight: 640)
        .onAppear {
            fields.telegramToken = settings.telegramToken.read() ?? ""
            fields.elevenLabsKey = settings.elevenLabsKey.read() ?? ""
            fields.openAIKey = settings.openAIKey.read() ?? ""
        }
    }

    private func save(_ store: SecretStore, _ value: String) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { store.delete() } else { try? store.write(v) }
    }
}

final class SecretFields: ObservableObject {
    @Published var telegramToken = ""
    @Published var elevenLabsKey = ""
    @Published var openAIKey = ""
    @Published var ollamaState = ""
}

struct WakeHelp {
    let steps: [String]
    let button: String
    let url: URL

    init(message: String, name: String) {
        let privacy = "x-apple.systempreferences:com.apple.preference.security?"
        if message.contains("Microphone") {
            steps = [
                "Click Open Microphone Settings below. System Settings opens at Privacy & Security → Microphone.",
                "Find Sofia in the list and turn its switch on. If macOS asks, choose Quit & Reopen.",
                "If Sofia isn't in the list, quit Sofia from the menu bar, open it again, and allow the microphone when macOS asks.",
                "Come back here and click Try again.",
            ]
            button = "Open Microphone Settings"
            url = URL(string: privacy + "Privacy_Microphone")!
        } else if message.contains("no on-device speech model") {
            steps = [
                "Click Open Keyboard Settings below.",
                "Under Dictation, turn Dictation on and set the language to English (United States).",
                "Wait a minute while macOS downloads the speech model. It stays on this Mac.",
                "Come back here and click Try again.",
            ]
            button = "Open Keyboard Settings"
            url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
        } else {
            steps = [
                "Click Open Speech Recognition Settings below. System Settings opens at Privacy & Security → Speech Recognition.",
                "Find Sofia in the list and turn its switch on.",
                "If Sofia isn't in the list, quit Sofia from the menu bar, open it again, and click Allow when macOS asks about speech recognition.",
                "If you updated Sofia, macOS may treat it as a new app: turn the old Sofia entry off and on again, or remove it with the minus button and repeat step 3.",
                "Come back here and click Try again. Then say “Hey \(name)”.",
            ]
            button = "Open Speech Recognition Settings"
            url = URL(string: privacy + "Privacy_SpeechRecognition")!
        }
    }
}

