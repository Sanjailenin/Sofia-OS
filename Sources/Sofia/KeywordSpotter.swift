import Foundation
import CSherpa
import SofiaCore

final class KeywordSpotter: @unchecked Sendable {
    static let shared = KeywordSpotter()

    static var folder: URL { Kokoro.folder }
    private static let files = ["lib/libsherpa-onnx-c-api.dylib", "kws/encoder.int8.onnx", "kws/decoder.onnx", "kws/joiner.int8.onnx", "kws/tokens.txt", "kws/bpe.model"]
    static var installed: Bool { files.allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) } }

    private typealias Create = @convention(c) (UnsafePointer<SherpaOnnxKeywordSpotterConfig>?) -> OpaquePointer?
    private typealias NewStream = @convention(c) (OpaquePointer?) -> OpaquePointer?
    private typealias Accept = @convention(c) (OpaquePointer?, Int32, UnsafePointer<Float>?, Int32) -> Void
    private typealias Ready = @convention(c) (OpaquePointer?, OpaquePointer?) -> Int32
    private typealias Step = @convention(c) (OpaquePointer?, OpaquePointer?) -> Void
    private typealias Result = @convention(c) (OpaquePointer?, OpaquePointer?) -> UnsafePointer<SherpaOnnxKeywordResult>?
    private typealias FreeResult = @convention(c) (UnsafePointer<SherpaOnnxKeywordResult>?) -> Void
    private typealias Destroy = @convention(c) (OpaquePointer?) -> Void

    private struct Functions {
        let create: Create, newStream: NewStream, accept: Accept, ready: Ready, decode: Step, reset: Step
        let result: Result, freeResult: FreeResult, destroyStream: Destroy, destroySpotter: Destroy
    }

    private let queue = DispatchQueue(label: "sofia.keyword-spotter", qos: .userInitiated)
    private var fns: Functions?
    private var failedLibrary = false
    private var spotter: OpaquePointer?
    private var stream: OpaquePointer?
    private var loadedName: String?
    private(set) var wake = KeywordWake(name: "")
    private(set) var lastError = ""

    private func functions() -> Functions? {
        if let fns { return fns }
        if failedLibrary { return nil }
        let engine = EngineLibrary.open()
        guard let h = engine.handle else {
            lastError = engine.error; failedLibrary = true; WakeLog.write("keyword spotter: \(lastError)"); return nil
        }
        func sym<T>(_ name: String, _ type: T.Type) -> T? { dlsym(h, name).map { unsafeBitCast($0, to: type) } }
        guard let create = sym("SherpaOnnxCreateKeywordSpotter", Create.self), let newStream = sym("SherpaOnnxCreateKeywordStream", NewStream.self),
              let accept = sym("SherpaOnnxOnlineStreamAcceptWaveform", Accept.self), let ready = sym("SherpaOnnxIsKeywordStreamReady", Ready.self),
              let decode = sym("SherpaOnnxDecodeKeywordStream", Step.self), let reset = sym("SherpaOnnxResetKeywordStream", Step.self),
              let result = sym("SherpaOnnxGetKeywordResult", Result.self), let freeResult = sym("SherpaOnnxDestroyKeywordResult", FreeResult.self),
              let destroyStream = sym("SherpaOnnxDestroyOnlineStream", Destroy.self), let destroySpotter = sym("SherpaOnnxDestroyKeywordSpotter", Destroy.self) else {
            lastError = "engine functions missing"; failedLibrary = true; WakeLog.write("keyword spotter: \(lastError)"); return nil
        }
        fns = Functions(create: create, newStream: newStream, accept: accept, ready: ready, decode: decode, reset: reset,
                        result: result, freeResult: freeResult, destroyStream: destroyStream, destroySpotter: destroySpotter)
        return fns
    }

    private func load(name: String) -> Bool {
        if loadedName == name { return stream != nil }
        guard let f = functions() else { return false }
        if let stream { f.destroyStream(stream) }
        if let spotter { f.destroySpotter(spotter) }
        stream = nil; spotter = nil; loadedName = name
        let model = Self.folder.appendingPathComponent("kws")
        guard let data = try? Data(contentsOf: model.appendingPathComponent("bpe.model")), let tokenizer = WakeTokenizer(model: data) else {
            lastError = "tokenizer missing"; WakeLog.write("keyword spotter: \(lastError)"); return false
        }
        let w = KeywordWake(name: name)
        let keywords = w.keywordFile(tokenizer)
        guard !keywords.isEmpty else { lastError = "the model can't spell \(name)"; WakeLog.write("keyword spotter: \(lastError)"); return false }
        let strings = ["\(model.path)/encoder.int8.onnx", "\(model.path)/decoder.onnx", "\(model.path)/joiner.int8.onnx", "\(model.path)/tokens.txt", "cpu", keywords]
            .map { s in s.withCString { strdup($0) } }
        defer { strings.forEach { free($0) } }
        var cfg = SherpaOnnxKeywordSpotterConfig()
        cfg.feat_config.sample_rate = 16000
        cfg.feat_config.feature_dim = 80
        cfg.model_config.transducer.encoder = UnsafePointer(strings[0])
        cfg.model_config.transducer.decoder = UnsafePointer(strings[1])
        cfg.model_config.transducer.joiner = UnsafePointer(strings[2])
        cfg.model_config.tokens = UnsafePointer(strings[3])
        cfg.model_config.provider = UnsafePointer(strings[4])
        cfg.model_config.num_threads = 1
        cfg.max_active_paths = 4
        cfg.num_trailing_blanks = KeywordWake.trailingBlanks
        cfg.keywords_score = KeywordWake.score
        cfg.keywords_threshold = KeywordWake.threshold
        cfg.keywords_buf = UnsafePointer(strings[5])
        cfg.keywords_buf_size = Int32(keywords.utf8.count)
        guard let sp = withUnsafePointer(to: &cfg, { f.create($0) }), let st = f.newStream(sp) else {
            lastError = "model failed to load"; WakeLog.write("keyword spotter: \(lastError)"); return false
        }
        spotter = sp; stream = st; wake = w; lastError = ""
        WakeLog.write("keyword spotter ready for \(w.phrases.joined(separator: ", "))")
        return true
    }

    func restart(name: String) {
        queue.async { [self] in
            guard load(name: name), let f = fns, let spotter else { return }
            if let stream { f.destroyStream(stream) }
            stream = f.newStream(spotter)
        }
    }

    func feed(_ samples: [Float], onHit: @escaping @Sendable (String, KeywordWake) -> Void) {
        queue.async { [self] in
            guard let f = fns, let spotter, let stream else { return }
            samples.withUnsafeBufferPointer { f.accept(stream, 16000, $0.baseAddress, Int32(samples.count)) }
            while f.ready(spotter, stream) == 1 {
                f.decode(spotter, stream)
                guard let r = f.result(spotter, stream) else { continue }
                if let k = r.pointee.keyword, strlen(k) > 0 {
                    let label = String(cString: k)
                    f.reset(spotter, stream)
                    f.freeResult(r)
                    onHit(label, wake)
                } else { f.freeResult(r) }
            }
        }
    }
}
