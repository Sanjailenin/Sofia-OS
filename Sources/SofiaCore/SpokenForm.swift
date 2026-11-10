import Foundation

public func spokenForm(reply: String?, actions: Int = 0, choices: Int = 0) -> String {
    var t = (reply ?? "")
        .replacingOccurrences(of: "**", with: "")
        .replacingOccurrences(of: #"(?m)^\s*[-*•]\s+"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"https?://\S+"#, with: "a link", options: .regularExpression)
        .replacingOccurrences(of: #"\n{2,}"#, with: ". ", options: .regularExpression)
        .replacingOccurrences(of: "\n", with: ", ")
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if t.count > 650 {
        let cut = String(t.prefix(650))
        let ns = cut as NSString
        let end = max(ns.range(of: ". ", options: .backwards).location, ns.range(of: "? ", options: .backwards).location)
        let keep = max(end == NSNotFound ? 0 : end, 400) + 1
        t = ns.substring(to: min(keep, ns.length)) + " The rest is on screen."
    }
    t += spokenSuffix(actions: actions, choices: choices)
    return t.isEmpty ? "Done." : t
}

public func spokenSuffix(actions: Int = 0, choices: Int = 0) -> String {
    var t = ""
    if actions > 0 {
        t += " I've prepared \(actions == 1 ? "one draft" : "\(actions) drafts"). \(actions == 1 ? "It's" : "They're") waiting for your OK on screen."
    }
    if choices > 0 { t += " You can tap one on screen or just tell me." }
    return t
}
