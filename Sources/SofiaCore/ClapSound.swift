import Foundation

public enum ClapSound {
    public enum Verdict: Equatable { case clap, other(String), unsure }

    static let clapLabels: Set<String> = ["clapping", "applause", "slap_smack"]
    static let impactLabels: Set<String> = ["knock", "door", "door_slam", "door_sliding", "glass_clink", "thump_thud", "tap", "typing",
                                            "typing_computer_keyboard", "finger_snapping", "water_tap_faucet", "guitar_tapping"]
    public static let minimum = 0.3
    public static let margin = 0.15

    static func strongest(_ scores: [String: Double]) -> (clap: Double, other: (label: String, score: Double)?) {
        let clap = scores.filter { clapLabels.contains($0.key) }.map(\.value).max() ?? 0
        let other = scores.filter { impactLabels.contains($0.key) }.max { $0.value < $1.value }
        return (clap, other.map { ($0.key, $0.value) })
    }

    public static func verdict(_ scores: [String: Double]) -> Verdict {
        let (clap, other) = strongest(scores)
        let otherScore = other?.score ?? 0
        if clap >= minimum, clap >= otherScore { return .clap }
        if let other, otherScore >= minimum, otherScore >= clap + margin { return .other(other.label) }
        return .unsure
    }

    public static func versus(_ scores: [String: Double]) -> String {
        let (clap, other) = strongest(scores)
        return "clap-like \(String(format: "%.2f", clap)) vs other " + (other.map { "\($0.label) \(String(format: "%.2f", $0.score))" } ?? "none")
    }

    public static func describe(_ scores: [String: Double]) -> String {
        let name: String
        switch verdict(scores) { case .clap: name = "clap"; case .other(let l): name = "not a clap (\(l))"; case .unsure: name = "unsure" }
        let top = scores.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(4)
            .map { "\($0.key) \(String(format: "%.2f", $0.value))" }
        return "\(name) | " + (top.isEmpty ? "nothing recognised" : top.joined(separator: ", "))
    }
}
