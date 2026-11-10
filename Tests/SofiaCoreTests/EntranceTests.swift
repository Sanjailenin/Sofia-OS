import Testing
import Foundation
@testable import SofiaCore

struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

final class Dice { var rng = SeededGenerator(42) }

struct EntranceTests {
    private let dice = Dice()
    private func random(_ r: ClosedRange<Int16>) -> Int16 { Int16.random(in: r, using: &dice.rng) }
    private func silence(ms: Int) -> [Int16] { Array(repeating: 0, count: 16 * ms) }
    private func noise(ms: Int, level: Int16 = 300) -> [Int16] { (0..<(16 * ms)).map { _ in random(-level...level) } }
    private func clap(level: Int16 = 20000, tail: Int16 = 0) -> [Int16] {
        var out = (0..<(16 * 40)).map { i in Int16(Double(random(-level...level)) * exp(-Double(i) / 60)) }
        if tail > 0 { for i in 0..<out.count { out[i] = Int16(clamping: Int(out[i]) + Int(Double(random(-tail...tail)) * exp(-Double(i) / 900))) } }
        return out
    }
    private func syllable(level: Int16 = 9000) -> [Int16] {
        let n = 16 * 120
        return (0..<n).map { i in Int16(Double(random(-level...level)) * min(1, Double(i) / 160, Double(n - i) / 160)) }
    }
    private func feed(_ det: inout ClapDetector, _ s: [Int16]) -> Int {
        var fired = 0, start = 0
        let sizes = [160, 96, 240, 80, 512]
        var k = 0
        while start < s.count { let end = min(start + sizes[k % sizes.count], s.count); if det.feed(Array(s[start..<end])) { fired += 1 }; start = end; k += 1 }
        return fired
    }
    private let warm = 2400

    @Test func startupBumpsDoNotFire() {
        var d = ClapDetector()
        #expect(feed(&d, noise(ms: 300) + clap() + noise(ms: 260) + clap() + noise(ms: 1400)) == 0)
    }
    @Test func doubleClapFires() {
        var d = ClapDetector()
        #expect(feed(&d, noise(ms: warm) + clap() + noise(ms: 260) + clap() + noise(ms: 400)) == 1)
    }
    @Test func quietAndDistantClapsFire() {
        var d = ClapDetector()
        #expect(feed(&d, noise(ms: warm) + clap(level: 6500, tail: 1200) + noise(ms: 300) + clap(level: 6500, tail: 1200) + noise(ms: 400)) == 1)
    }
    @Test func slowAndFastDoubleClapsFire() {
        var d = ClapDetector()
        #expect(feed(&d, noise(ms: warm) + clap() + noise(ms: 130) + clap() + noise(ms: 2000) + clap() + noise(ms: 700) + clap() + noise(ms: 400)) == 2)
    }
    @Test func clapsOverBackgroundNoiseFire() {
        var d = ClapDetector()
        #expect(feed(&d, noise(ms: warm, level: 1200) + clap(level: 14000) + noise(ms: 250, level: 1200) + clap(level: 14000) + noise(ms: 400, level: 1200)) == 1)
    }
    @Test func singleClapDoesNot() {
        var d = ClapDetector()
        #expect(feed(&d, noise(ms: warm) + clap() + noise(ms: 1200)) == 0)
    }
    @Test func clapsTooFarApartDoNot() {
        var d = ClapDetector()
        #expect(feed(&d, noise(ms: warm) + clap() + noise(ms: 1000) + clap() + noise(ms: 400)) == 0)
    }
    @Test func clapsTooCloseDoNot() {
        var d = ClapDetector()
        #expect(feed(&d, noise(ms: warm) + clap() + noise(ms: 20) + clap() + noise(ms: 600)) == 0)
    }
    @Test func steadyLoudSoundDoesNot() {
        var d = ClapDetector()
        #expect(feed(&d, noise(ms: warm) + noise(ms: 1500, level: 20000)) == 0)
    }
    @Test func speechDoesNot() {
        var d = ClapDetector()
        #expect(feed(&d, noise(ms: warm) + syllable() + noise(ms: 180) + syllable() + noise(ms: 600)) == 0)
    }
    @Test func typingDoesNot() {
        var d = ClapDetector()
        var a = noise(ms: warm)
        for _ in 0..<6 { a += clap(level: 1500) + noise(ms: 160) }
        #expect(feed(&d, a) == 0)
    }
    @Test func aFilmPlayingInTheRoomDoesNot() {
        var d = ClapDetector()
        #expect(feed(&d, noise(ms: warm, level: 3000) + clap(level: 24000) + noise(ms: 300, level: 3000) + clap(level: 24000) + noise(ms: 400, level: 3000)) == 0)
    }
    @Test func twoVeryDifferentHitsDoNot() {
        var d = ClapDetector()
        #expect(feed(&d, noise(ms: warm) + clap(level: 28000) + noise(ms: 300) + clap(level: 5000) + noise(ms: 400)) == 0)
    }
    @Test func noDipBetweenDoesNot() {
        var d = ClapDetector()
        #expect(feed(&d, noise(ms: warm) + clap() + noise(ms: 300, level: 12000) + clap() + noise(ms: 400)) == 0)
    }
    @Test func thirdClapAfterFiringNeedsAFreshPair() {
        var d = ClapDetector()
        #expect(feed(&d, noise(ms: warm) + clap() + noise(ms: 260) + clap() + noise(ms: 260) + clap() + noise(ms: 600)) == 1)
    }
    @Test func lowSensitivityNeedsLoudClaps() {
        var d = ClapDetector(sensitivity: .low)
        #expect(feed(&d, noise(ms: warm) + clap(level: 5000) + noise(ms: 300) + clap(level: 5000) + noise(ms: 400)) == 0)
        var h = ClapDetector(sensitivity: .high)
        #expect(feed(&h, noise(ms: warm) + clap(level: 3200) + noise(ms: 300) + clap(level: 3200) + noise(ms: 400)) == 1)
    }

    @Test func entrancePhrase() {
        for s in ["wake up daddy's home", "Wake up, Daddy's home!", "hey wake up daddies home", "so wake up dad is home"] {
            #expect(WakeWord.matchesEntrance(s), Comment(rawValue: s))
        }
        for s in ["hey sofia", "wake up", "my daddy is at home with me", "home", "wake up the dog", "daddy", "daddy's home", "wake up daddy"] {
            #expect(!WakeWord.matchesEntrance(s), Comment(rawValue: s))
        }
    }
}

struct SpotifyTrackTests {
    @Test func acceptsLinksAndURIs() {
        let want = "spotify:track:4uLU6hMCjMI75M1A2tKUQC"
        for s in ["https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC?si=a1b2c3d4e5f60718", "open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC",
                  "https://open.spotify.com/intl-de/track/4uLU6hMCjMI75M1A2tKUQC", " spotify:track:4uLU6hMCjMI75M1A2tKUQC\n"] {
            #expect(SpotifyTrack.uri(from: s) == want, Comment(rawValue: s))
        }
    }
    @Test func rejectsEverythingElse() {
        for s in ["", "spotify:album:4uLU6hMCjMI75M1A2tKUQC", "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M", "spotify:track:short",
                  "https://example.com/track/4uLU6hMCjMI75M1A2tKUQC", "spotify:track:4uLU6hMCjMI75M1A2tKUQC\" & do shell script \"x"] {
            #expect(SpotifyTrack.uri(from: s) == nil, Comment(rawValue: s))
        }
    }
}
