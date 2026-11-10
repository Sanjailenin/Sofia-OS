import Foundation

public enum WAV {
    public static func encode(_ samples: [Int16], sampleRate: Int = 16000) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        let bytes = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes)
        d.append(contentsOf: Array("WAVE".utf8)); d.append(contentsOf: Array("fmt ".utf8))
        u32(16); u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        samples.withUnsafeBufferPointer { d.append(UnsafeBufferPointer(start: UnsafeRawPointer($0.baseAddress!).assumingMemoryBound(to: UInt8.self), count: samples.count * 2)) }
        return d
    }
}

public struct Endpointer {
    public enum Decision: Equatable { case keepGoing, finished, noSpeech }

    public var silenceAfterSpeech: Double
    public var noSpeechTimeout: Double
    public var maxDuration: Double
    private var floor = 0.0005
    private var voicedRun = 0
    private var heardSpeech = false
    private var silentFor = 0.0
    private var elapsed = 0.0

    public init(silenceAfterSpeech: Double = 1.6, noSpeechTimeout: Double = 9, maxDuration: Double = 60, primed: Bool = false) {
        self.silenceAfterSpeech = silenceAfterSpeech
        self.noSpeechTimeout = noSpeechTimeout
        self.maxDuration = maxDuration
        self.heardSpeech = primed
    }

    public var hasHeardSpeech: Bool { heardSpeech }
    public private(set) var peak = 0.0

    public mutating func feed(rms: Double, dt: Double) -> Decision {
        elapsed += dt
        peak = max(peak, rms)
        let loud = rms > max(0.0025, floor * 4)
        if !loud && !heardSpeech { floor = floor * 0.97 + rms * 0.03 }
        if loud { voicedRun += 1; silentFor = 0 } else { voicedRun = 0; silentFor += dt }
        if voicedRun >= 2 { heardSpeech = true }
        if heardSpeech && silentFor >= silenceAfterSpeech { return .finished }
        if !heardSpeech && elapsed >= noSpeechTimeout { return .noSpeech }
        if elapsed >= maxDuration { return heardSpeech ? .finished : .noSpeech }
        return .keepGoing
    }
}

public struct PreRoll {
    public let capacity: Int
    private var buf: [Int16] = []
    public init(seconds: Double = 3, sampleRate: Int = 16000) { capacity = Int(seconds * Double(sampleRate)) }
    public mutating func append(_ samples: [Int16]) {
        buf.append(contentsOf: samples)
        if buf.count > capacity * 2 { buf.removeFirst(buf.count - capacity) }
    }
    public var samples: [Int16] { Array(buf.suffix(capacity)) }
    public mutating func clear() { buf.removeAll(keepingCapacity: true) }
}

public func rms(_ x: UnsafeBufferPointer<Float>) -> Double {
    guard x.count > 0 else { return 0 }
    var s = 0.0
    for v in x { s += Double(v) * Double(v) }
    return (s / Double(x.count)).squareRoot()
}

public enum Level {
    public static func display(_ rms: Double) -> Float { Float(max(0, min(1, (20 * log10(max(rms, 1e-5)) + 62) / 40))) }

    public static func normalize(_ samples: [Int16]) -> [Int16] {
        let peak = Double(samples.map { abs(Int($0)) }.max() ?? 0) / 32767
        guard peak > 0.004 else { return samples }
        let gain = min(25, 0.6 / peak)
        return gain <= 1.05 ? samples : samples.map { Int16(max(-32767, min(32767, Double($0) * gain))) }
    }
}

public struct SilenceProbe {
    public var seconds: Double
    private var silent = 0.0
    private var done = false
    public init(seconds: Double = 1) { self.seconds = seconds }
    public mutating func feed(level: Double, dt: Double) -> Bool {
        guard !done else { return false }
        if level > 0 { done = true; return false }
        silent += dt
        guard silent >= seconds else { return false }
        done = true
        return true
    }
}
