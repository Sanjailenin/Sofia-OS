import Foundation

public struct WakeWord: Sendable {
    public static let defaultName = "Sofia"
    nonisolated(unsafe) public static var current = WakeWord(name: defaultName)

    public let name: String
    public let namePattern: String
    private let full: NSRegularExpression
    private let casual: NSRegularExpression
    private let leadingName: NSRegularExpression
    private let standby: NSRegularExpression
    private static let entrance = try! NSRegularExpression(
        pattern: #"\bwake\s*up[\s,.!]*(?:daddy|daddies|dad)(?:'?s|\s+is)?\s+home\b"#, options: .caseInsensitive)

    public init(name rawName: String) {
        let cleaned = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        name = cleaned.isEmpty ? Self.defaultName : cleaned
        namePattern = "(?:" + Self.variants(of: name).map { NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: " ", with: #"\s?"#) }.joined(separator: "|") + ")"
        full = try! NSRegularExpression(pattern: #"\b(?:hey|hay|hei|hai|hi|hello|okay|ok|yo)[\s,.!-]*"# + namePattern + #"\b"#, options: .caseInsensitive)
        casual = try! NSRegularExpression(pattern: #"\b"# + namePattern + #"\b[\s,.!?;:-]+(?=\w)"#, options: .caseInsensitive)
        leadingName = try! NSRegularExpression(pattern: #"^\W*"# + namePattern + #"\b[\s,.!?;:-]*"#, options: .caseInsensitive)
        standby = try! NSRegularExpression(pattern: #"\b"# + namePattern + #"\b[\s,.!?;:-]*("# + IslandStateMachine.standbyCommands + #")(?:[\s,.!?;:-]*(?:please|now|for now|thanks|thank you))*\W*$"#, options: .caseInsensitive)
    }

    public static func variants(of name: String) -> [String] {
        let base = name.lowercased()
        if ["sofia", "sophia"].contains(base) {
            return ["sofia", "sophia", "sofie", "sofiya", "sophie", "safia", "sofi", "sophea", "zofia", "so fear", "so fia", "sufi", "su"]
        }
        var set: [String] = [base]
        func add(_ v: String) { if !v.isEmpty, !set.contains(v) { set.append(v) } }
        add(base.replacingOccurrences(of: "ph", with: "f")); add(base.replacingOccurrences(of: "f", with: "ph"))
        add(base.replacingOccurrences(of: "y", with: "i")); add(base.replacingOccurrences(of: "ie", with: "y"))
        if base.hasSuffix("a") { add(String(base.dropLast()) + "ah") }
        if base.hasSuffix("ah") { add(String(base.dropLast(2)) + "a") }
        add(base.replacingOccurrences(of: "ck", with: "k")); add(base.replacingOccurrences(of: "c", with: "k"))
        var dedup = ""; var last: Character? = nil
        for ch in base { if ch != last { dedup.append(ch) }; last = ch }
        add(dedup)
        return set
    }

    private static let trailingGreeting = try! NSRegularExpression(pattern: #"\b(?:hey|hay|hei|hai|hi|hello|okay|ok|yo)\W*$"#, options: .caseInsensitive)
    public static let maxGreetingGap: TimeInterval = 8

    public static let maxGreetingGapWithMedia: TimeInterval = 4
    private static let bareGreeting = try! NSRegularExpression(pattern: #"^\W*(?:hey|hay|hei|hai|hi|hello|okay|ok|yo)\W*$"#, options: .caseInsensitive)

    public func greetingThenName(previous: String, current: String, gap: TimeInterval, media: Bool = false) -> Bool {
        guard gap >= 0, gap <= (media ? Self.maxGreetingGapWithMedia : Self.maxGreetingGap) else { return false }
        let p = NSRange(previous.startIndex..., in: previous), c = NSRange(current.startIndex..., in: current)
        if media, Self.bareGreeting.firstMatch(in: previous, range: p) == nil { return false }
        return Self.trailingGreeting.firstMatch(in: previous, range: p) != nil && leadingName.firstMatch(in: current, range: c) != nil
    }
    public static func greetingThenName(previous: String, current: String, gap: TimeInterval, media: Bool = false) -> Bool { Self.current.greetingThenName(previous: previous, current: current, gap: gap, media: media) }

    public static func matchesEntrance(_ text: String) -> Bool {
        entrance.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    public func matches(_ text: String, casual: Bool = false) -> Bool { match(text, casual: casual) != nil }
    public static func matches(_ text: String, casual: Bool = false) -> Bool { current.matches(text, casual: casual) }

    private func match(_ text: String, casual: Bool) -> NSTextCheckingResult? {
        let range = NSRange(text.startIndex..., in: text)
        if let m = full.firstMatch(in: text, range: range) { return m }
        return casual ? self.casual.firstMatch(in: text, range: range) : nil
    }

    public func remainder(_ text: String, casual: Bool = false) -> String {
        guard let m = match(text, casual: casual), let r = Range(m.range, in: text) else { return "" }
        return String(text[r.upperBound...]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }
    public static func remainder(_ text: String, casual: Bool = false) -> String { current.remainder(text, casual: casual) }

    public func stripLeading(_ text: String) -> String {
        let all = NSRange(text.startIndex..., in: text)
        let m = full.firstMatch(in: text, range: all) ?? leadingName.firstMatch(in: text, range: all)
        guard let m, let r = Range(m.range, in: text) else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let rest = String(String(text[r.upperBound...]).drop(while: { $0.isWhitespace || ",.!?;:-".contains($0) })).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = rest.first else { return "" }
        return first.uppercased() + rest.dropFirst()
    }
    public static func stripLeading(_ text: String) -> String { current.stripLeading(text) }

    public func standbyCommand(_ text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = standby.firstMatch(in: text, range: range), let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r]).lowercased()
    }
    public static func standbyCommand(_ text: String) -> String? { current.standbyCommand(text) }

    public var hints: [String] { ["Hey \(name)", "Hi \(name)", "Okay \(name)", name, "\(name), go off"] }
}

public struct HeardHistory: Sendable {
    public private(set) var latest = "", latestAt = Date.distantPast
    public private(set) var previous = "", previousAt = Date.distantPast
    public init() {}

    public mutating func newTask() {
        if !latest.isEmpty { previous = latest; previousAt = latestAt }
        latest = ""
    }

    public mutating func heard(_ text: String, at time: Date) {
        if !latest.isEmpty, Self.firstWord(text) != Self.firstWord(latest) { previous = latest; previousAt = latestAt }
        latest = text; latestAt = time
    }

    private static func firstWord(_ s: String) -> String {
        s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).first.map(String.init) ?? ""
    }
}
