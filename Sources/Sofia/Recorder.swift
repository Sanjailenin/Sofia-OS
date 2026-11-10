import AVFoundation
import SofiaCore

final class Recorder {
    enum Outcome { case clip(Data), noSpeech, silentMic, failed(String) }

    private let engine = AVAudioEngine()
    private var samples: [Int16] = []
    private var endpointer = Endpointer()
    private var finished = false
    private var onLevel: ((Float) -> Void)?
    private var onDone: ((Outcome) -> Void)?
    private let lock = NSLock()

    static func requestPermission(_ done: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: done(true)
        case .notDetermined: AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { done(ok) } }
        default: done(false)
        }
    }

    func start(preRoll: [Int16] = [], primed: Bool = false, noSpeechTimeout: Double = 9, onLevel: @escaping (Float) -> Void, onDone: @escaping (Outcome) -> Void) {
        self.onLevel = onLevel; self.onDone = onDone
        samples = preRoll; endpointer = Endpointer(noSpeechTimeout: noSpeechTimeout, primed: primed); finished = false
        if attempt(voiceProcessing: AppSettings.shared.cleanAudio) { return }
        if AppSettings.shared.cleanAudio, attempt(voiceProcessing: false) { return }
        finish(.failed("Couldn't start the microphone"))
    }

    private func attempt(voiceProcessing: Bool) -> Bool {
        let input = engine.inputNode
        if voiceProcessing { if !CleanMic.enable(engine) { return false } } else { CleanMic.disable(engine) }
        probe = voiceProcessing ? SilenceProbe() : nil
        gotBuffer = false
        let inFormat = input.outputFormat(forBus: 0)
        guard let resampler = MonoResampler(from: inFormat) else { return false }
        input.installTap(onBus: 0, bufferSize: 2048, format: inFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.lock.lock(); self.gotBuffer = true; self.lock.unlock()
            guard let mono = resampler.firstChannel(buffer), let out = resampler.resample(mono), let ch = out.floatChannelData?[0] else { return }
            let buf = UnsafeBufferPointer(start: ch, count: Int(out.frameLength))
            let level = rms(buf)
            if self.probe != nil, self.probe?.feed(level: level, dt: Double(out.frameLength) / 16000) == true { DispatchQueue.main.async { self.fallBackToPlainMic() }; return }
            let pcm = buf.map { Int16(max(-1, min(1, $0)) * 32767) }
            let dt = Double(out.frameLength) / 16000
            self.lock.lock()
            if self.finished { self.lock.unlock(); return }
            self.samples.append(contentsOf: pcm)
            let decision = self.endpointer.feed(rms: level, dt: dt)
            self.lock.unlock()
            DispatchQueue.main.async { self.onLevel?(Level.display(level)) }
            switch decision {
            case .keepGoing: break
            case .finished: self.finish(nil)
            case .noSpeech: self.finish(.noSpeech)
            }
        }
        engine.prepare()
        do { try engine.start() } catch { input.removeTap(onBus: 0); return false }
        if voiceProcessing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                self.lock.lock(); let got = self.gotBuffer; let done = self.finished; self.lock.unlock()
                if !got, !done, self.engine.inputNode.isVoiceProcessingEnabled { WakeLog.write("recorder: no audio in 1.5 s with voice processing"); self.fallBackToPlainMic() }
            }
        }
        return true
    }

    private var probe: SilenceProbe?
    private var gotBuffer = false

    @MainActor private func fallBackToPlainMic() {
        lock.lock(); let done = finished; lock.unlock()
        guard !done else { return }
        engine.stop(); engine.inputNode.removeTap(onBus: 0)
WakeLog.event("echo cancellation off (silent input while recording)")
                AppSettings.shared.cleanAudio = false
        if !attempt(voiceProcessing: false) { finish(.failed("Couldn't start the microphone")) }
    }

    func stopAndDeliver() { finish(nil) }
    func cancel() { lock.lock(); finished = true; lock.unlock(); teardown() }

    private func finish(_ forced: Outcome?) {
        lock.lock()
        if finished { lock.unlock(); return }
        finished = true
        let heard = endpointer.hasHeardSpeech
        let peak = endpointer.peak
        let data = samples
        lock.unlock()
        teardown()
        let manualLongEnough = forced == nil && data.count > 16000 * 4 / 10 && peak > 0.0015
        var outcome: Outcome
        if let forced { if case .noSpeech = forced { outcome = peak < 0.0015 ? .silentMic : .noSpeech } else { outcome = forced } }
        else if heard || manualLongEnough { outcome = .clip(WAV.encode(Level.normalize(data))) }
        else { outcome = peak < 0.0015 ? .silentMic : .noSpeech }
        let cb = onDone
        DispatchQueue.main.async { cb?(outcome) }
    }

    private func teardown() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        CleanMic.disable(engine)
    }
}
