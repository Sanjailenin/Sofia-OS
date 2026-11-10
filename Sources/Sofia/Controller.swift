import AppKit
import Combine
import SofiaCore

@MainActor
final class Controller {
    let model = IslandModel()
    var panel: NotchPanel?
    private var machine = IslandStateMachine(conversation: AppSettings.shared.conversation)
    let settings = AppSettings.shared
    private let recorder = Recorder()
    private let speech = Speech()
    private let wake = WakeListener()
    private let entrance = Entrance()
    private let nudges = NudgeMonitor()
    private let keepAwake = KeepAwake()
    let calendar = CalendarWatch()
    let phone: PhoneChannel
    let turn: AssistantTurn
    private var bag = Set<AnyCancellable>()
    private var generation = 0
    private var work: Task<Void, Never>?
    private var heldClip: Data?
    private var wakeAudio: (preRoll: [Int16], primed: Bool)?
    private var errorTimer: Timer?
    private var videoTimer: Timer?
    private var macAudio = false
    private var escKey: HotKey?
    private var pendingLines: [String] = []
    private var streaming = false

    init() {
        let progress = ProgressRelay()
        turn = AssistantTurn(memory: MemoryStore.shared, performer: MacPerformer(settings: AppSettings.shared, progressSink: { progress.send($0) }))
        phone = PhoneChannel(settings: AppSettings.shared, turn: turn)
        progress.onLine = { [weak self] line in self?.model.transcript = line }
        model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        model.name = settings.assistantName
        wake.onWake = { [weak self] preRoll, remainder in MainActor.assumeIsolated {
            self?.wakeFromStandby()
            self?.wakeAudio = (preRoll, !remainder.isEmpty)
            self?.hotkeyPressed()
        } }
        wake.onEntrance = { [weak self] how in MainActor.assumeIsolated { self?.entranceTriggered(how) } }
        nudges.onNudge = { [weak self] line in MainActor.assumeIsolated { self?.say(line) } }
        nudges.eventWithinHour = { [weak self] in MainActor.assumeIsolated { self?.calendar.eventWithin(minutes: 60) ?? false } }
        settings.$conversation.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] on in MainActor.assumeIsolated { self?.machine.conversation = on } }.store(in: &bag)
        settings.$wakeWord.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] on in MainActor.assumeIsolated { self?.applyWake(on) } }.store(in: &bag)
        settings.$clapSensitivity.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] s in MainActor.assumeIsolated { self?.wake.clapSensitivity = ClapDetector.Sensitivity(rawValue: s) ?? .normal } }.store(in: &bag)
        settings.$keywordWake.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] on in MainActor.assumeIsolated { self?.wake.keywordWakeOn = on } }.store(in: &bag)
        settings.$clapVerify.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] on in MainActor.assumeIsolated { self?.wake.clapVerifyOn = on } }.store(in: &bag)
        settings.$entrance.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] on in MainActor.assumeIsolated { self?.wake.entranceOn = on } }.store(in: &bag)
        settings.$nudges.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] on in MainActor.assumeIsolated { guard let self else { return }; on && !self.settings.standby ? self.nudges.start() : self.nudges.stop() } }.store(in: &bag)
        settings.$keepAwake.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] on in MainActor.assumeIsolated { self?.keepAwake.enabled = on } }.store(in: &bag)
        settings.$standby.removeDuplicates().dropFirst().receive(on: DispatchQueue.main).sink { [weak self] on in MainActor.assumeIsolated { guard let self else { return }; if on { if self.machine.phase != .speaking { self.enterStandby() } } else { self.resumeFromStandby() } } }.store(in: &bag)
        keepAwake.start()
        videoTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in guard let self else { return }; self.wake.videoInFront = VideoDetector.isVideoInFront(); let src = MacState.audioSources(); let a = !src.isEmpty; if a != self.macAudio { self.macAudio = a; WakeLog.write("Mac playing audio: \(a ? src.joined(separator: ", ") : "nothing")") } } }
    }

    func startBackground() {
        phone.start()
        calendar.start()
        if settings.nudges && !settings.standby { nudges.start() }
        if settings.entrance && !settings.standby { entrance.play(settings, allowSpotify: !calendar.inMeeting) }
    }

    func hotkeyPressed() {
        if settings.standby { wakeFromStandby() }
        if !machine.phase.isActive { panel?.reposition(model: model) }
        dispatch(.hotkey)
    }

    func dictationPressed() {
        if machine.phase == .listening && machine.dictating { recorder.stopAndDeliver(); return }
        dispatch(.dictate)
    }

    func escapePressed() { dispatch(.escape) }

    func say(_ line: String) {
        if machine.phase.isActive { pendingLines.append(line); return }
        panel?.reposition(model: model)
        dispatch(.say(line))
    }

    func previewEntrance() { entrance.play(settings, allowSpotify: !calendar.inMeeting) }

    private func entranceTriggered(_ how: String) {
        guard settings.entrance, !entrance.inCooldown, !wake.videoInFront else { return }
        if settings.standby { wakeFromStandby() }
        WakeLog.event("entrance (\(how))")
        entrance.play(settings, allowSpotify: !calendar.inMeeting)
    }

    private func enterStandby() {
        settings.standby = true
        nudges.stop(); entrance.stop()
        syncWake()
        WakeLog.event("standby on")
    }
    func wakeFromStandby() {
        guard settings.standby else { return }
        settings.standby = false
    }
    private func resumeFromStandby() {
        WakeLog.event("standby off")
        applyWake(settings.wakeWord)
        if settings.nudges { nudges.start() }
    }

    private func applyWake(_ on: Bool) {
        guard on else { wake.stop(); model.wakeListening = false; return }
        settings.wakeMessage = ""
        WakeListener.prepare { [weak self] ok, why in
            guard let self else { return }
            if ok { self.syncWake() } else { self.settings.wakeMessage = why ?? ""; self.settings.wakeWord = false }
        }
    }
    private func syncWake() {
        let shouldRun = settings.wakeWord && machine.phase == .idle
        if shouldRun { wake.start() } else { wake.stop() }
        model.wakeListening = wake.running
    }

    func dispatch(_ event: Event) {
        let before = machine.phase
        let effects = machine.handle(event)
        model.phase = machine.phase
        model.transcript = machine.transcript
        panel?.ignoresMouseEvents = !machine.phase.isActive
        updateEscKey()
        if settings.wakeWord { syncWake() }
        if before != machine.phase {
            if !before.isActive && machine.phase.isActive { panel?.reposition(model: model) }
            if before.isActive && machine.phase == .idle {
                wake.casualUntil = settings.casualWake ? Date().addingTimeInterval(AppSettings.casualWindow) : .distantPast
                if let next = pendingLines.first { pendingLines.removeFirst(); Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in Task { @MainActor in self?.say(next) } } }
            }
            cue(before, machine.phase)
        }
        effects.forEach(perform)
    }

    private func perform(_ e: Effect) {
        switch e {
        case .startListening: startListening()
        case .startFollowUp: startListening(followUp: true)
        case .stopListening: recorder.stopAndDeliver()
        case .cancelListening: recorder.cancel(); model.level = 0
        case .transcribe: transcribe()
        case .transcribeDictation: transcribeDictation()
        case .ask(let t): ask(t)
        case .speak(let line): beginSpeech(); speech.add(line); if !streaming { speech.finish() }
        case .stopSpeaking: speech.stop(); streaming = false; model.level = 0
        case .cancelRequests: generation += 1; work?.cancel(); work = nil; heldClip = nil; speech.stop(); streaming = false; model.level = 0
        case .scheduleErrorDismiss:
            errorTimer?.invalidate()
            errorTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in Task { @MainActor in self?.dispatch(.errorTimeout) } }
        case .chime: NSSound(named: "Glass")?.play()
        case .standby: enterStandby()
        }
    }

    private func startListening(followUp: Bool = false) {
        if followUp && settings.standby { dispatch(.escape); return }
        generation += 1
        Recorder.requestPermission { [weak self] ok in
            guard let self, self.machine.phase == .listening else { return }
            guard ok else { self.dispatch(.failed("Microphone access is off. Allow it in System Settings → Privacy → Microphone.")); return }
            let wake = self.wakeAudio; self.wakeAudio = nil
            self.recorder.start(preRoll: wake?.preRoll ?? [], primed: wake?.primed ?? false, noSpeechTimeout: followUp ? 8 : 9, onLevel: { [weak self] l in Task { @MainActor in self?.model.level = l } }) { [weak self] outcome in
                Task { @MainActor in
                    guard let self, self.machine.phase == .listening else { return }
                    switch outcome {
                    case .clip(let d): self.heldClip = d; self.dispatch(.recordingEnded)
                    case .noSpeech: self.dispatch(.noSpeech)
                    case .silentMic: self.dispatch(.failed("The microphone is silent. Check System Settings → Sound → Input."))
                    case .failed(let m): self.dispatch(.failed(m))
                    }
                }
            }
        }
    }

    private func transcribe() {
        model.level = 0
        let gen = generation
        guard let clip = heldClip else { dispatch(.failed("Nothing was recorded")); return }
        heldClip = nil
        work = Task { [weak self] in
            guard let self else { return }
            let text = WakeWord.stripLeading(await LocalEar.transcribe(wav: clip, hints: WakeWord.current.hints, timeout: 12) ?? "")
            WakeLog.write("request heard: \(text)")
            guard gen == self.generation else { return }
            self.dispatch(.transcribed(text))
        }
    }

    private func transcribeDictation() {
        model.level = 0
        let gen = generation
        guard let clip = heldClip else { dispatch(.dictated); return }
        heldClip = nil
        work = Task { [weak self] in
            guard let self else { return }
            let text = Dictation.clean(await LocalEar.transcribe(wav: clip, hints: [], timeout: 20) ?? "")
            guard gen == self.generation else { return }
            if !text.isEmpty { _ = try? await InputDriver.perform("type", ["text": text], scale: ScreenScale(displayWidth: 1, displayHeight: 1)) }
            self.dispatch(.dictated)
        }
    }

    private func ask(_ text: String) {
        let gen = generation
        work = Task { [weak self] in
            guard let self else { return }
            var spokenCount = 0
            let onSentence: @Sendable (String) -> Void = { sentence in Task { @MainActor in
                guard gen == self.generation else { return }
                let line = spokenForm(reply: sentence)
                if spokenCount == 0 {
                    self.streaming = true
                    self.dispatch(.replyReady(line))
                } else { self.speech.add(line) }
                spokenCount += 1
            } }
            do {
                let result = try await self.turn.run(text, channel: "mac", provider: self.settings.localProvider, ownerName: self.settings.ownerName, allowComputer: self.settings.allowComputer, assistantName: self.settings.assistantName, onSentence: onSentence)
                WakeLog.write("did: \(result.performed.joined(separator: " | ")) | failed: \(result.failed.joined(separator: " | ")) | reply: \(result.reply.prefix(160))")
                guard gen == self.generation else { return }
                var tail = spokenCount == 0 ? spokenForm(reply: result.reply) : ""
                if !result.failed.isEmpty { tail += (tail.isEmpty ? "" : " ") + "I couldn't " + result.failed.joined(separator: "; ") + "." }
                if spokenCount == 0 { self.dispatch(.replyReady(tail.isEmpty ? "Done." : tail)) }
                else { if !tail.isEmpty { self.speech.add(tail) }; self.speech.finish(); self.streaming = false }
            } catch is CancellationError {
            } catch {
                guard gen == self.generation else { return }
                self.streaming = false
                let reachable = await self.settings.localProvider.isReachable()
                self.dispatch(.failed(reachable ? "The model didn't answer: \(error.localizedDescription)" : "Ollama isn't running, or the model isn't pulled. Start it with: ollama serve"))
            }
        }
    }

    private func beginSpeech() {
        speech.begin(voice: settings.voiceName, elevenLabsKey: settings.elevenLabsKey.read(), elevenLabsVoice: settings.elevenLabsVoice,
                     onLevel: { [weak self] l in Task { @MainActor in self?.model.level = l } },
                     onDone: { [weak self] in Task { @MainActor in self?.model.level = 0; self?.dispatch(.speechFinished) } })
    }

    private func speak(_ line: String) {
        beginSpeech()
        speech.add(line)
        speech.finish()
    }

    private func updateEscKey() {
        if machine.phase.isActive {
            if escKey == nil { escKey = HotKey(keyCode: 53, modifiers: 0) { [weak self] in Task { @MainActor in self?.dispatch(.escape) } } }
        } else { escKey?.unregister(); escKey = nil }
    }

    private func cue(_ from: Phase, _ to: Phase) {
        if to == .listening { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now); NSSound(named: "Tink")?.play() }
        if from == .listening && to == .thinking { NSSound(named: "Pop")?.play() }
        if case .error = to { NSSound(named: "Basso")?.play() }
    }
}

final class ProgressRelay: @unchecked Sendable {
    var onLine: ((String) -> Void)?
    func send(_ line: String) { Task { @MainActor in self.onLine?(line) } }
}
