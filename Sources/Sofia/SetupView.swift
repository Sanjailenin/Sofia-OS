import SwiftUI
import SofiaCore

struct SetupView: View {
    @ObservedObject var settings: AppSettings
    let done: () -> Void
    @ObservedObject private var state = SetupState()

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            Text("Welcome").font(.largeTitle.bold())
            Text("Two choices before we start. You can change both later in Settings.").foregroundStyle(.secondary)

            GroupBox("Her name") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Name", text: $settings.assistantName).textFieldStyle(.roundedBorder)
                    Text("You'll wake her with “Hey \(settings.assistantName.isEmpty ? WakeWord.defaultName : settings.assistantName)”. Short names with clear vowels are heard best.").font(.caption).foregroundStyle(.secondary)
                    TextField("Your first name (how she addresses you)", text: $settings.ownerName).textFieldStyle(.roundedBorder)
                }.padding(6)
            }

            GroupBox("Her voice") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Voice", selection: $settings.voiceName) {
                        Section("Women") { ForEach(SofiaVoice.all.filter { $0.gender == .woman }) { v in Text(v.name).tag(v.id) } }
                        Section("Men") { ForEach(SofiaVoice.all.filter { $0.gender == .man }) { v in Text(v.name).tag(v.id) } }
                    }
                    HStack {
                        Button(state.previewing ? "Speaking…" : "Preview") { state.preview(name: settings.assistantName.isEmpty ? WakeWord.defaultName : settings.assistantName, voice: settings.voiceName) }.disabled(state.previewing)
                        Text(Kokoro.installed ? "Natural voices that run on this Mac." : "Her voices aren't downloaded yet; the Mac's own voice is used until you run the installer again.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(6)
            }

            GroupBox("Permissions") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("macOS asks once for each. Click Allow everything and answer each prompt; Accessibility and Screen Recording open System Settings, where you switch Sofia on.").font(.caption).foregroundStyle(.secondary)
                    PermissionsView()
                }.padding(6)
            }

            GroupBox("The model") {
                HStack {
                    Text(state.ollama.isEmpty ? "She thinks with Ollama on this Mac (\(settings.ollamaModel))." : state.ollama).font(.caption)
                    Spacer()
                    Button("Check") { Task { let ok = await settings.localProvider.isReachable(); state.ollama = ok ? "Ollama is running and \(settings.ollamaModel) is ready." : "Ollama isn't reachable, or \(settings.ollamaModel) isn't pulled (ollama pull \(settings.ollamaModel))." } }
                }.padding(6)
            }

            Spacer()
            HStack {
                Text("You can allow anything you skip later in Settings → Permissions.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Continue") { if settings.assistantName.trimmingCharacters(in: .whitespaces).isEmpty { settings.assistantName = WakeWord.defaultName }; done() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        }
        .frame(minWidth: 580, minHeight: 640)
        .onAppear { if settings.assistantName.isEmpty { settings.assistantName = WakeWord.defaultName } }
    }
}

@MainActor
final class SetupState: ObservableObject {
    @Published var previewing = false
    @Published var ollama = ""
    private let speech = Speech()

    func preview(name: String, voice: String) {
        previewing = true
        speech.speak("Hi, I'm \(name). Say Hey \(name) whenever you need me.", voice: voice, elevenLabsKey: nil, elevenLabsVoice: "", onLevel: { _ in }, onDone: { [weak self] in Task { @MainActor in self?.previewing = false } })
    }
}
