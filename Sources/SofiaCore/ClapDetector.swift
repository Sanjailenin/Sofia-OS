import Foundation

public struct ClapDetector {
    public enum Sensitivity: String, CaseIterable, Sendable {
        case low, normal, high
        var minPeak: Double { switch self { case .low: 9000; case .normal: 4500; case .high: 2200 } }
        var floorRatio: Double { switch self { case .low: 18; case .normal: 12; case .high: 8 } }
    }
    public static let blockSamples = 80
    public static let minGap: TimeInterval = 0.12
    public static let maxGap: TimeInterval = 1.0
    public static let warmup: TimeInterval = 2.0
    static let jumpRatio: Double = 3.0
    static let decayRatio: Double = 0.35
    static let decayBlocks = 16
    static let loudPeak: Double = 20000
    static let loudDecayBlocks = 28
    static let historyBlocks = 20
    static let maxAmbientRMS: Double = 900
    static let similarity: Double = 2.5
    static let dipRatio: Double = 0.25
    static let leadInBlocks = 300
    static let leadInGapBlocks = 20
    static let leadRatio: Double = 2.5
    static let maxLeadOnsets = 1

    public var sensitivity: Sensitivity
    private var pending: [Int16] = []
    private var floor: Double = 150
    private var history: [Double] = []
    private var blockIndex = 0
    private var candidate: (block: Int, peak: Double, prior: Double)?
    private var past: [Double] = []
    private var onsets: [Int] = []
    private var lastAnyOnset = -1_000_000
    private var first: Int?
    private var firstPeak = 0.0
    private var dipped = false
    private var lastOnset = -1_000_000

    public struct Pair: Equatable, Sendable {
        public let first: Double, second: Double, gap: TimeInterval
        public func describe(sensitivity: Sensitivity) -> String {
            "peaks \(Int(first)) and \(Int(second)) of 32767, \(String(format: "%.2f", gap)) s apart, sensitivity \(sensitivity.rawValue) (needs \(Int(sensitivity.minPeak)))"
        }
    }
    public private(set) var lastPair: Pair?
    public private(set) var lastRejection = ""
    public private(set) var rejections = 0
    public private(set) var sharpSounds = 0
    private mutating func reject(_ why: String) { lastRejection = why; rejections += 1 }

    public init(sensitivity: Sensitivity = .normal) { self.sensitivity = sensitivity }

    public mutating func feed(_ samples: [Int16]) -> Bool {
        pending.append(contentsOf: samples)
        var fired = false
        while pending.count >= Self.blockSamples {
            let block = pending.prefix(Self.blockSamples)
            pending.removeFirst(Self.blockSamples)
            var peak = 0.0, acc = 0.0
            for s in block { let d = abs(Double(s)); peak = max(peak, d); acc += d * d }
            if process(peak: peak, rms: sqrt(acc / Double(block.count))) { fired = true }
        }
        return fired
    }

    private mutating func process(peak: Double, rms: Double) -> Bool {
        defer { blockIndex += 1; history.append(peak); if history.count > Self.historyBlocks { history.removeFirst() }; past.append(peak); if past.count > Self.leadInBlocks { past.removeFirst() } }
        let perSecond = 16000.0 / Double(Self.blockSamples)
        let warm = Double(blockIndex) / perSecond >= Self.warmup
        var fired = false

        if let c = candidate {
            let age = blockIndex - c.block
            if peak <= c.peak * Self.decayRatio {
                candidate = nil
                fired = confirm(c.block, peak: c.peak, prior: c.prior)
            } else if age >= (c.peak >= Self.loudPeak ? Self.loudDecayBlocks : Self.decayBlocks) {
                candidate = nil
                reject("peak \(Int(c.peak)) held on for \(age * 5) ms instead of dying away (speech or a sustained sound)")
            }
        }
        let recent = history.isEmpty ? 0 : history.reduce(0, +) / Double(history.count)
        let threshold = max(sensitivity.minPeak, floor * sensitivity.floorRatio)
        if peak > threshold * 0.35, peak > recent * Self.jumpRatio, blockIndex - lastAnyOnset > 10 { onsets.append(blockIndex); lastAnyOnset = blockIndex }
        while let o = onsets.first, blockIndex - o > Self.leadInBlocks { onsets.removeFirst() }
        if warm, candidate == nil, floor > Self.maxAmbientRMS, peak > threshold, peak > recent * Self.jumpRatio, blockIndex - lastOnset > 10 {
            lastOnset = blockIndex
            reject("peak \(Int(peak)) but the room is too loud (noise floor \(Int(floor)), limit \(Int(Self.maxAmbientRMS)))")
        }
        if warm, candidate == nil, floor <= Self.maxAmbientRMS, peak > threshold, peak > recent * Self.jumpRatio, blockIndex - lastOnset > 10 {
            candidate = (blockIndex, peak, past.dropLast(Self.leadInGapBlocks).max() ?? 0)
            lastOnset = blockIndex
        }
        if first != nil, candidate == nil, peak < firstPeak * Self.dipRatio { dipped = true }
        if let f = first, Double(blockIndex - f) / perSecond > Self.maxGap { first = nil }
        if peak < threshold { floor = max(40, floor * 0.985 + rms * 0.015) }
        return fired
    }

    private mutating func confirm(_ block: Int, peak: Double, prior: Double) -> Bool {
        sharpSounds += 1
        let perSecond = 16000.0 / Double(Self.blockSamples)
        if let f = first {
            let gap = Double(block - f) / perSecond
            let alike = peak / firstPeak <= Self.similarity && firstPeak / peak <= Self.similarity
            if gap >= Self.minGap && gap <= Self.maxGap && alike && dipped { lastPair = Pair(first: firstPeak, second: peak, gap: gap); first = nil; dipped = false; return true }
            reject("second clap \(Int(peak)) after first \(Int(firstPeak)), \(String(format: "%.2f", gap)) s apart: " + (!alike ? "too different in loudness" : !dipped ? "no quiet between them" : "gap outside \(Self.minGap)-\(Self.maxGap) s"))
        }
        let busy = onsets.filter { $0 < block - Self.leadInGapBlocks && $0 >= block - Self.leadInBlocks }.count > Self.maxLeadOnsets
        if peak >= prior * Self.leadRatio, !busy { first = block; firstPeak = peak } else {
            first = nil
            reject("peak \(Int(peak)) didn't stand out from the 1.5 s before it: loudest before \(Int(prior)) (needs \(Self.leadRatio)x), \(onsets.count - 1) other sharp sounds (at most \(Self.maxLeadOnsets))")
        }
        dipped = false
        return false
    }
}

public enum ClapGate {
    public static let typingWindow: Double = 2
    public static let clickWindow: Double = 1
    public static func block(locked: Bool, secondsSinceKey: Double, secondsSinceClick: Double, macPlaying: Bool, videoInFront: Bool) -> String? {
        if locked { return "screen locked" }
        if secondsSinceKey < typingWindow { return "typing" }
        if secondsSinceClick < clickWindow { return "clicking" }
        if macPlaying { return "Mac playing audio" }
        if videoInFront { return "video in front" }
        return nil
    }
}
