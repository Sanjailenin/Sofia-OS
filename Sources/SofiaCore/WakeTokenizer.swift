import Foundation

public struct WakeTokenizer: Sendable {
    private let scores: [String: Float]
    private let longest: Int

    public init(pieces: [(String, Float, Int32)]) {
        var s: [String: Float] = [:]
        for (piece, score, type) in pieces where type == 1 { s[piece] = score }
        scores = s
        longest = s.keys.map(\.count).max() ?? 1
    }

    public init?(model: Data) {
        var reader = ProtoReader(model)
        var pieces: [(String, Float, Int32)] = []
        while !reader.atEnd {
            guard let (field, wire) = reader.key() else { return nil }
            if field == 1, wire == 2 {
                guard let body = reader.bytes() else { return nil }
                var inner = ProtoReader(body)
                var piece = "", score: Float = 0, type: Int32 = 1
                while !inner.atEnd {
                    guard let (f, w) = inner.key() else { return nil }
                    switch (f, w) {
                    case (1, 2): guard let b = inner.bytes(), let s = String(data: b, encoding: .utf8) else { return nil }; piece = s
                    case (2, 5): guard let v = inner.fixed32() else { return nil }; score = Float(bitPattern: v)
                    case (3, 0): guard let v = inner.varint() else { return nil }; type = Int32(truncatingIfNeeded: v)
                    default: guard inner.skip(w) else { return nil }
                    }
                }
                pieces.append((piece, score, type))
            } else if !reader.skip(wire) { return nil }
        }
        guard !pieces.isEmpty else { return nil }
        self.init(pieces: pieces)
    }

    public func encode(_ text: String) -> [String]? {
        let words = text.uppercased().split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty else { return nil }
        let chars = Array(words.map { "▁" + $0 }.joined())
        var best = [Float](repeating: -.infinity, count: chars.count + 1)
        var from = [Int](repeating: -1, count: chars.count + 1)
        best[0] = 0
        for end in 1...chars.count {
            for start in max(0, end - longest)..<end where best[start] > -.infinity {
                guard let score = scores[String(chars[start..<end])] else { continue }
                let total = best[start] + score
                if total > best[end] { best[end] = total; from[end] = start }
            }
        }
        guard from[chars.count] >= 0 else { return nil }
        var out: [String] = []
        var end = chars.count
        while end > 0 { let start = from[end]; out.append(String(chars[start..<end])); end = start }
        return out.reversed()
    }
}

struct ProtoReader {
    private let data: [UInt8]
    private var at = 0
    init(_ d: Data) { data = [UInt8](d) }
    var atEnd: Bool { at >= data.count }

    mutating func varint() -> UInt64? {
        var v: UInt64 = 0, shift: UInt64 = 0
        while at < data.count, shift < 64 {
            let b = data[at]; at += 1
            v |= UInt64(b & 0x7f) << shift
            if b < 0x80 { return v }
            shift += 7
        }
        return nil
    }
    mutating func key() -> (Int, Int)? { varint().map { (Int($0 >> 3), Int($0 & 7)) } }
    mutating func bytes() -> Data? {
        guard let n = varint(), n <= UInt64(data.count - at) else { return nil }
        defer { at += Int(n) }
        return Data(data[at..<at + Int(n)])
    }
    mutating func fixed32() -> UInt32? {
        guard at + 4 <= data.count else { return nil }
        defer { at += 4 }
        return UInt32(data[at]) | UInt32(data[at + 1]) << 8 | UInt32(data[at + 2]) << 16 | UInt32(data[at + 3]) << 24
    }
    mutating func skip(_ wire: Int) -> Bool {
        switch wire {
        case 0: return varint() != nil
        case 1: guard at + 8 <= data.count else { return false }; at += 8; return true
        case 2: return bytes() != nil
        case 5: return fixed32() != nil
        default: return false
        }
    }
}
