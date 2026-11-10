import Foundation
import CSherpa
import SofiaCore

final class Kokoro: @unchecked Sendable {
    static let shared = Kokoro()

    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Sofia/Voices")
    }
    private static var library: URL { folder.appendingPathComponent("lib/libsherpa-onnx-c-api.dylib") }
    private static var model: URL { folder.appendingPathComponent("kokoro") }

    static var installed: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: library.path)
            && ["model.onnx", "voices.bin", "tokens.txt", "espeak-ng-data"].allSatisfy { fm.fileExists(atPath: model.appendingPathComponent($0).path) }
    }

    private typealias Create = @convention(c) (UnsafePointer<SherpaOnnxOfflineTtsConfig>?) -> OpaquePointer?
    private typealias Generate = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<SherpaOnnxGenerationConfig>?, SherpaOnnxGeneratedAudioProgressCallbackWithArg?, UnsafeMutableRawPointer?) -> UnsafePointer<SherpaOnnxGeneratedAudio>?
    private typealias Free = @convention(c) (UnsafePointer<SherpaOnnxGeneratedAudio>?) -> Void

    private let queue = DispatchQueue(label: "sofia.kokoro", qos: .userInitiated)
    private var tts: OpaquePointer?
    private var generate: Generate?
    private var free: Free?
    private var failed = false

    private(set) var lastError = ""

    private func load() -> Bool {
        if tts != nil { return true }
        if failed { return false }
        guard Self.installed else { lastError = "voices not downloaded"; return false }
        let engine = EngineLibrary.open()
        guard let h = engine.handle else {
            lastError = engine.error; failed = true; return false
        }
        guard let c = dlsym(h, "SherpaOnnxCreateOfflineTts"), let g = dlsym(h, "SherpaOnnxOfflineTtsGenerateWithConfig"), let f = dlsym(h, "SherpaOnnxDestroyOfflineTtsGeneratedAudio") else {
            lastError = "engine functions missing"; failed = true; return false
        }
        let dir = Self.model.path
        let strings = ["\(dir)/model.onnx", "\(dir)/voices.bin", "\(dir)/tokens.txt", "\(dir)/espeak-ng-data", "cpu", "en-us"].map { s in s.withCString { strdup($0) } }
        defer { strings.forEach { Foundation.free($0) } }
        var cfg = SherpaOnnxOfflineTtsConfig()
        cfg.model.kokoro.model = UnsafePointer(strings[0])
        cfg.model.kokoro.voices = UnsafePointer(strings[1])
        cfg.model.kokoro.tokens = UnsafePointer(strings[2])
        cfg.model.kokoro.data_dir = UnsafePointer(strings[3])
        cfg.model.kokoro.length_scale = 1
        cfg.model.kokoro.lang = UnsafePointer(strings[5])
        cfg.model.provider = UnsafePointer(strings[4])
        cfg.model.num_threads = Int32(max(2, min(4, ProcessInfo.processInfo.activeProcessorCount / 2)))
        cfg.max_num_sentences = 1
        let create = unsafeBitCast(c, to: Create.self)
        guard let t = withUnsafePointer(to: &cfg, { create($0) }) else { lastError = "model failed to load"; failed = true; return false }
        tts = t
        generate = unsafeBitCast(g, to: Generate.self)
        free = unsafeBitCast(f, to: Free.self)
        return true
    }

    func warm() { queue.async { _ = self.load() } }

    func wav(_ text: String, voice: SofiaVoice) async -> Data? {
        await withCheckedContinuation { cont in
            queue.async {
                guard self.load(), let generate = self.generate, let free = self.free else { return cont.resume(returning: nil) }
                var g = SherpaOnnxGenerationConfig()
                g.sid = voice.speaker
                g.speed = voice.speed
                g.silence_scale = 0.2
                guard let audio = text.withCString({ s in withUnsafePointer(to: &g) { generate(self.tts, s, $0, nil, nil) } }) else { return cont.resume(returning: nil) }
                defer { free(audio) }
                let a = audio.pointee
                guard a.n > 0, let p = a.samples else { return cont.resume(returning: nil) }
                cont.resume(returning: WaveFile.pcm16(Array(UnsafeBufferPointer(start: p, count: Int(a.n))), sampleRate: Int(a.sample_rate)))
            }
        }
    }
}
