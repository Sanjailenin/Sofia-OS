import Foundation

public enum SpotifyTrack {
    private static let id = "[A-Za-z0-9]{22}"
    private static let uri = try! NSRegularExpression(pattern: "^spotify:track:(\(id))$")
    private static let link = try! NSRegularExpression(pattern: "^(?:https?://)?open\\.spotify\\.com/(?:[a-z]{2,5}(?:-[A-Za-z]{2,5})?/)?track/(\(id))(?:[/?#].*)?$")

    public static func uri(from text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(t.startIndex..., in: t)
        for re in [uri, link] {
            if let m = re.firstMatch(in: t, range: range), let r = Range(m.range(at: 1), in: t) { return "spotify:track:\(t[r])" }
        }
        return nil
    }
}
