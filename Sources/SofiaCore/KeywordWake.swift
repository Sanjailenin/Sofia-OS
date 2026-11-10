import Foundation

public struct KeywordWake: Sendable, Equatable {
    public static let threshold: Float = 0.05
    public static let score: Float = 3.0
    public static let trailingBlanks: Int32 = 1
    public static let cooldown: TimeInterval = 2
    static let greetings = ["hey", "hi", "ok", "hello"]
    static let bonus = "2.0"

    public let phrases: [String]

    public init(name: String) {
        let n = name.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !n.isEmpty else { phrases = []; return }
        var names = [n]
        if n == "sofia" { names.append("sophia") }
        if n == "sophia" { names.append("sofia") }
        phrases = names.flatMap { name in Self.greetings.map { "\($0) \(name)" } }
    }

    public static func label(_ phrase: String) -> String { phrase.uppercased().replacingOccurrences(of: " ", with: "_") }
    public func isWake(_ label: String) -> Bool { phrases.contains { Self.label($0) == label } }

    public func keywordFile(_ tokenizer: WakeTokenizer) -> String {
        let lines = phrases.compactMap { p in tokenizer.encode(p).map { $0.joined(separator: " ") + " :\(Self.bonus) @\(Self.label(p))" } }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }
}

public struct KeywordGate {
    private var last = Date.distantPast
    public init() {}
    public mutating func accept(_ label: String, for wake: KeywordWake, at time: Date = Date()) -> Bool {
        guard wake.isWake(label), time.timeIntervalSince(last) >= KeywordWake.cooldown else { return false }
        last = time
        return true
    }
}
