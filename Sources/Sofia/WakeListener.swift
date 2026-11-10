import AppKit
import AVFoundation
import Speech
import SofiaCore

final class WakeListener {
    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recycle: Timer?
    private(set) var running = false
    var onWake: ((_ preRoll: [Int16], _ remainder: String) -> Void)?
    var onEntrance: ((_ how: String) -> Void)?
    var entranceOn = true
    var videoInFront = false
    var mediaPlaying: Bool { videoInFront || MacState.audioPlaying() }
    var clapSensitivity: ClapDetector.Sensitivity = .normal { didSet { lock.lock(); claps.sensitivity = clapSensitivity; lock.unlock() } }
    var keywordWakeOn = true
    var clapVerifyOn = true
    private var claps = ClapDetector()
    private var keywordGate = KeywordGate()
    private var loggedRejections = 0
    private var loggedSharpSounds = 0
    private var lastSoundCheck = Date.distantPast
    var casualUntil = Date.distantPast
    var casualNow: Bool { Date() < casualUntil }
    private var preRoll = PreRoll(seconds: 3)

    static func prepare(_ done: @escaping (Bool, String?) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else { return done(false, "Speech recognition is off for Sofia (System Settings → Privacy → Speech Recognition).") }
                guard Self.makeRecognizer() != nil else { return done(false, "This Mac has no on-device speech model for English, so the wake word stays off (nothing is sent to the cloud).") }
                Recorder.requestPermission { ok in done(ok, ok ? nil : "Microphone access is off for Sofia.") }
            }
        }
    }

    private static func makeRecognizer() -> SFSpeechRecognizer? {
        for id in ["en-GB", "en-US", "en-AU", "en-IE"] {
            if let r = SFSpeechRecognizer(locale: Locale(identifier: id)), r.isAvailable, r.supportsOnDeviceRecognition { return r }
        }
        return nil
    }

    private var configObserver: NSObjectProtocol?
    private var startedAt = Date.distantPast
    private let lock = NSLock()
    private var currentRequest: SFSpeechAudioBufferRecognitionRequest?

    private var tapSeen = false
    private var deadStarts = 0
    private var history = HeardHistory()

    func start() {
        guard !running, let r = Self.makeRecognizer() else { return }
        CleanMic.disable(engine)
        tapSeen = false
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        recognizer = r
        let resampler = MonoResampler(from: format)
        preRoll.clear()
        claps = ClapDetector(sensitivity: clapSensitivity); loggedRejections = 0; loggedSharpSounds = 0
        keywordGate = KeywordGate()
        let spotter: KeywordSpotter? = keywordWakeOn && KeywordSpotter.installed ? KeywordSpotter.shared : nil
        spotter?.restart(name: WakeWord.current.name)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buf, _ in
            guard let self else { return }
            self.lock.lock(); let req = self.currentRequest; self.lock.unlock()
            self.lock.lock(); let firstBuffer = !self.tapSeen; self.tapSeen = true; self.lock.unlock()
            if firstBuffer { WakeLog.write("microphone delivering: \(buf.frameLength) frames, \(buf.format.channelCount) ch") }
            guard let resampler, let mono = resampler.firstChannel(buf) else { return }
            req?.append(mono)
            guard let out = resampler.resample(mono), let ch = out.floatChannelData?[0] else { return }
            let floats = UnsafeBufferPointer(start: ch, count: Int(out.frameLength))
            let samples = floats.map { Int16(max(-1, min(1, $0)) * 32767) }
            self.lock.lock(); self.preRoll.append(samples); self.lock.unlock()
            spotter?.feed(Array(floats)) { [weak self] label, wake in DispatchQueue.main.async { self?.heardKeyword(label, wake) } }
            if self.entranceOn {
                self.lock.lock(); let hit = self.claps.feed(samples); let pair = self.claps.lastPair; let level = self.claps.sensitivity
                let rejected = self.claps.rejections != self.loggedRejections ? self.claps.lastRejection : nil; self.loggedRejections = self.claps.rejections
                let sharp = self.claps.sharpSounds != self.loggedSharpSounds; self.loggedSharpSounds = self.claps.sharpSounds; self.lock.unlock()
                if let rejected { WakeLog.write("clap candidate rejected: \(rejected)") }
                if sharp, !hit { self.checkSound() }
                if hit { self.verifyDoubleClap(pair?.describe(sensitivity: level) ?? "") }
            }
        }
        engine.prepare()
        do { try engine.start() } catch { input.removeTap(onBus: 0); return }
        running = true
        startedAt = Date()
        let thisStart = startedAt
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.running, self.startedAt == thisStart else { return }
            self.lock.lock(); let seen = self.tapSeen; self.lock.unlock()
            if seen { self.deadStarts = 0; return }
            self.deadStarts += 1
            WakeLog.write("no audio from the microphone in 3 s (dead start \(self.deadStarts))")
            if self.deadStarts <= 3 { WakeLog.event("microphone silent at start, restarting") }
            if self.deadStarts >= 6 { WakeLog.event("microphone silent, wake word paused"); self.stop(); return }
            self.stop(); self.start()
        }
        WakeLog.write("listening (\(r.locale.identifier), \(Int(format.sampleRate)) Hz, \(format.channelCount) ch)")
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.running, Date().timeIntervalSince(self.startedAt) > 3 else { return }
            WakeLog.write("audio device changed, restarting the mic")
            self.stop(); DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.start() }
        }
        beginTask()
        recycle = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in self?.restartTask() }
    }

    func stop() {
        guard running else { return }
        running = false
        if let o = configObserver { NotificationCenter.default.removeObserver(o); configObserver = nil }
        recycle?.invalidate(); recycle = nil
        endTask()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
    }

    private func beginTask() {
        guard running, let recognizer else { return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        req.taskHint = .search
        req.contextualStrings = WakeWord.current.hints
        if #available(macOS 13.0, *) { req.addsPunctuation = false }
        request = req
        lock.lock(); currentRequest = req; history.newTask(); lock.unlock()
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self, self.running else { return }
            self.lock.lock(); let current = self.currentRequest === req; self.lock.unlock()
            guard current else { return }
            if let text = result?.bestTranscription.formattedString {
                WakeLog.write("heard: \(text.suffix(80))")
                let media = self.mediaPlaying
                self.lock.lock(); self.history.heard(text, at: Date()); let prev = self.history.previous, prevAt = self.history.previousAt; self.lock.unlock()
                if self.entranceOn, !media, WakeWord.matchesEntrance(text) {
                    WakeLog.write("entrance phrase matched"); WakeLog.event("entrance phrase heard")
                    DispatchQueue.main.async { guard self.running else { return }; self.onEntrance?("phrase"); self.restartTask() }
                    return
                }
                let casual = self.casualNow && !media
                if !casual, !self.videoInFront, WakeWord.standbyCommand(text) != nil {
                    WakeLog.event("wake word (standby command)")
                    self.lock.lock(); let audio = self.preRoll.samples; self.lock.unlock()
                    DispatchQueue.main.async { guard self.running else { return }; self.stop(); self.onWake?(audio, "go off") }
                    return
                }
                if WakeWord.matches(text, casual: casual) {
                    WakeLog.write("wake phrase matched\(WakeWord.matches(text) ? "" : " (casual)")"); WakeLog.event("wake word\(WakeWord.matches(text) ? "" : " (casual)")")
                    let remainder = WakeWord.remainder(text, casual: casual)
                    self.lock.lock(); let audio = self.preRoll.samples; self.lock.unlock()
                    DispatchQueue.main.async { guard self.running else { return }; self.stop(); self.onWake?(audio, remainder) }
                    return
                }
                if WakeWord.greetingThenName(previous: prev, current: text, gap: Date().timeIntervalSince(prevAt), media: media) {
                    WakeLog.write("wake phrase matched (greeting, then name)"); WakeLog.event("wake word (greeting, then name)")
                    let remainder = WakeWord.stripLeading(text)
                    self.lock.lock(); let audio = self.preRoll.samples; self.lock.unlock()
                    DispatchQueue.main.async { guard self.running else { return }; self.stop(); self.onWake?(audio, remainder) }
                    return
                }
            }
            if let error {
                WakeLog.write("recognition error: \(error.localizedDescription)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.restartTask() }
            } else if result?.isFinal == true {
                DispatchQueue.main.async { self.restartTask() }
            }
        }
    }

    private func endTask() {
        lock.lock(); currentRequest = nil; lock.unlock()
        request?.endAudio(); task?.cancel(); task = nil; request = nil
    }
    private func restartTask() { guard running else { return }; endTask(); beginTask() }

    private func heardKeyword(_ label: String, _ wake: KeywordWake) {
        guard running else { return }
        guard keywordGate.accept(label, for: wake) else { WakeLog.write("keyword spotter heard \(label), ignored"); return }
        WakeLog.write("keyword spotter heard \(label)"); WakeLog.event("wake word (keyword spotter)")
        lock.lock(); let audio = preRoll.samples; lock.unlock()
        stop(); onWake?(audio, "")
    }

    private func checkSound() {
        guard UserDefaults.standard.bool(forKey: "wakeDebug"), Date().timeIntervalSince(lastSoundCheck) > 0.4 else { return }
        lastSoundCheck = Date()
        lock.lock(); let audio = Array(preRoll.samples.suffix(25600)); lock.unlock()
        DispatchQueue.global(qos: .utility).async {
            guard let scores = SoundClassifier.classify(audio) else { return }
            WakeLog.write("sharp sound: \(ClapSound.describe(scores))")
        }
    }

    private func verifyDoubleClap(_ detail: String) {
        guard clapVerifyOn else { DispatchQueue.main.async { self.heardDoubleClap(detail, sound: nil) }; return }
        lock.lock(); let audio = Array(preRoll.samples.suffix(25600)); lock.unlock()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scores = SoundClassifier.classify(audio)
            DispatchQueue.main.async { self?.heardDoubleClap(detail, sound: scores) }
        }
    }

    private func heardDoubleClap(_ detail: String, sound: [String: Double]?) {
        if let why = ClapGate.block(locked: MacState.screenLocked(), secondsSinceKey: MacState.secondsSinceKey(),
                                    secondsSinceClick: MacState.secondsSinceClick(), macPlaying: MacState.audioPlaying(), videoInFront: videoInFront) {
            WakeLog.write("double clap ignored: \(why)"); WakeLog.event("double clap ignored (\(why); \(detail))")
            return
        }
        if let sound {
            WakeLog.write("sharp sound (double clap): \(ClapSound.describe(sound))")
            if case .other(let label) = ClapSound.verdict(sound) {
                WakeLog.event("double clap ignored (sounded like \(label), not a clap; \(ClapSound.versus(sound)); \(detail))")
                return
            }
        }
        WakeLog.event("double clap (\(detail))"); onEntrance?("clap")
    }
}

enum WakeLog {
    private static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Sofia")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("wake.log")
    }()
    private static let queue = DispatchQueue(label: "sofia.wakelog")
    private static var last = ""
    static func event(_ line: String) {
        let name = { NSWorkspace.shared.frontmostApplication?.localizedName ?? "?" }
        let front = Thread.isMainThread ? name() : DispatchQueue.main.sync(execute: name)
        queue.async {
            let file = url.deletingLastPathComponent().appendingPathComponent("events.log")
            if let size = try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int, size > 200_000 { try? FileManager.default.removeItem(at: file) }
            let data = Data("\(ISO8601DateFormatter().string(from: Date())) \(line) [front: \(front)]\n".utf8)
            if let h = try? FileHandle(forWritingTo: file) { h.seekToEndOfFile(); h.write(data); try? h.close() } else { try? data.write(to: file) }
        }
    }
    static func write(_ line: String) {
        guard UserDefaults.standard.bool(forKey: "wakeDebug") else { return }
        queue.async {
            guard line != last else { return }
            last = line
            let stamp = ISO8601DateFormatter().string(from: Date())
            let data = Data("\(stamp) \(line)\n".utf8)
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
            else { try? data.write(to: url) }
        }
    }
}
