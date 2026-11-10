import Testing
import Foundation
@testable import SofiaCore

struct FalseWakeTests {
    private let dice = Dice()
    private func random(_ r: ClosedRange<Int16>) -> Int16 { Int16.random(in: r, using: &dice.rng) }
    private func noise(ms: Int, level: Int16 = 150) -> [Int16] { (0..<(16 * ms)).map { _ in random(-level...level) } }
    private func hit(peak: Int16, decayMs: Double, ms: Int = 60) -> [Int16] {
        (0..<(16 * ms)).map { i in Int16(Double(random(-peak...peak)) * exp(-Double(i) / (decayMs * 16))) }
    }
    private func clap(level: Int16 = 20000) -> [Int16] { hit(peak: level, decayMs: 3.75, ms: 40) }
    private func feed(_ det: inout ClapDetector, _ s: [Int16]) -> Int {
        var fired = 0, i = 0
        while i < s.count { let e = min(i + 1024, s.count); if det.feed(Array(s[i..<e])) { fired += 1 }; i = e }
        return fired
    }
    private func overlay(_ base: [Int16], _ add: [Int16], at: Int) -> [Int16] {
        var a = base
        for (k, v) in add.enumerated() where at + k < a.count { a[at + k] = Int16(clamping: Int(a[at + k]) + Int(v)) }
        return a
    }

    @Test func entrancePhraseNeedsTheWholeLine() {
        for s in ["wake up daddy's home", "Wake up, Daddy's home!", "hey wake up daddies home", "so wake up dad is home", "wake up dads home"] {
            #expect(WakeWord.matchesEntrance(s), Comment(rawValue: s))
        }
        for s in ["daddy's home", "my dad is home", "Daddy is home!", "dad's home early", "wake up daddy", "wake up, dad", "wake up daddy, it's late"] {
            #expect(!WakeWord.matchesEntrance(s), Comment(rawValue: s))
        }
    }

    @Test func suIsHerNameButSueIsNot() {
        #expect(WakeWord.matches("Hey Su") && WakeWord.matches("hey su, open spotify"))
        #expect(!WakeWord.matches("hey Sue") && !WakeWord.matches("hey sun") && !WakeWord.matches("hey super"))
    }

    @Test func heyThenHerNameAfterAPause() {
        #expect(WakeWord.greetingThenName(previous: "Hey", current: "Sophia", gap: 2))
        #expect(WakeWord.greetingThenName(previous: "and then I said okay", current: "Sofia open Spotify", gap: 3.5))
        #expect(WakeWord.greetingThenName(previous: "Hey", current: "Sophia", gap: 7), "seen in the log: 7 s between the two")
        #expect(!WakeWord.greetingThenName(previous: "Hey", current: "Sophia", gap: 12), "too far apart")
        #expect(!WakeWord.greetingThenName(previous: "Hey there", current: "Sophia", gap: 1), "the greeting must end the earlier result")
        #expect(!WakeWord.greetingThenName(previous: "Hey", current: "I met Sophia", gap: 1), "her name must start the new result")
        #expect(!WakeWord.greetingThenName(previous: "", current: "Sophia", gap: 1))
    }

    @Test func drumsInQuietMusicAreNotClaps() {
        var d = ClapDetector()
        var a = noise(ms: 2600)
        for bpm in [90.0, 120.0, 140.0] {
            let beat = Int(60 / bpm * 16000)
            var bar = noise(ms: Int(60 / bpm * 4000))
            for k in 0..<4 { bar = overlay(bar, hit(peak: 7000, decayMs: k % 2 == 0 ? 25 : 15), at: k * beat) }
            for _ in 0..<15 { a += bar }
        }
        #expect(feed(&d, a) <= 1)
    }

    @Test func typingIsNotClapping() {
        var d = ClapDetector()
        var a = noise(ms: 2600)
        for _ in 0..<120 {
            var second = noise(ms: 1000)
            for _ in 0..<6 { second = overlay(second, hit(peak: random(2500...9000), decayMs: 4, ms: 15), at: Int(random(0...15000))) }
            a += second
        }
        #expect(feed(&d, a) <= 1)
    }

    @Test func aDoubleClapAfterQuietStillWorks() {
        var d = ClapDetector()
        #expect(feed(&d, noise(ms: 2600) + clap() + noise(ms: 300) + clap() + noise(ms: 600)) == 1)
        var q = ClapDetector()
        #expect(feed(&q, noise(ms: 2600) + clap(level: 6000) + noise(ms: 350) + clap(level: 6000) + noise(ms: 600)) == 1)
    }

    @Test func aDoubleClapStraightAfterOtherBangsIsIgnored() {
        var d = ClapDetector()
        let busy = noise(ms: 2600) + hit(peak: 15000, decayMs: 10) + noise(ms: 400) + hit(peak: 15000, decayMs: 10) + noise(ms: 900)
        #expect(feed(&d, busy + clap(level: 18000) + noise(ms: 300) + clap(level: 18000) + noise(ms: 600)) <= 1, "at most the first pair")
        var e = ClapDetector()
        let music = (0..<6).reduce(noise(ms: 2600)) { acc, _ in acc + hit(peak: 12000, decayMs: 20) + noise(ms: 440) }
        #expect(feed(&e, music + clap(level: 14000) + noise(ms: 300) + clap(level: 14000) + noise(ms: 600)) <= 1, "only the music's first two beats, not the claps among the beats")
    }

    @Test func aLoudClapThatRingsStillCounts() {
        var d = ClapDetector()
        let ringing = hit(peak: 32767, decayMs: 90, ms: 260)
        #expect(feed(&d, noise(ms: 2600) + ringing + noise(ms: 200) + ringing + noise(ms: 600)) == 1)
    }

    @Test func unhurriedClapsStillPair() {
        var d = ClapDetector()
        #expect(feed(&d, noise(ms: 2600) + clap() + noise(ms: 910) + clap() + noise(ms: 600)) == 1, "about 0.95 s apart")
        var e = ClapDetector()
        #expect(feed(&e, noise(ms: 2600) + clap() + noise(ms: 1400) + clap() + noise(ms: 600)) == 0, "1.4 s apart is two single claps")
    }

    @Test func aLoudSyllableIsStillNotAClap() {
        var d = ClapDetector()
        let syllable: [Int16] = (0..<(16 * 300)).map { _ in random(-30000...30000) }
        #expect(feed(&d, noise(ms: 2600) + syllable + noise(ms: 250) + syllable + noise(ms: 600)) == 0)
    }

    @Test func aDoubleClapReportsHowLoudItWas() {
        var d = ClapDetector()
        #expect(d.lastPair == nil)
        #expect(feed(&d, noise(ms: 2600) + clap(level: 12000) + noise(ms: 300) + clap(level: 12000) + noise(ms: 600)) == 1)
        let pair = d.lastPair
        #expect(pair != nil)
        #expect((pair?.first ?? 0) > 6000 && (pair?.first ?? 0) <= 12000 && (pair?.second ?? 0) > 6000)
        #expect((pair?.gap ?? 0) > 0.25 && (pair?.gap ?? 0) < 0.45)
        #expect(pair?.describe(sensitivity: .normal) == "peaks \(Int(pair!.first)) and \(Int(pair!.second)) of 32767, \(String(format: "%.2f", pair!.gap)) s apart, sensitivity normal (needs \(4500))")
    }

    @Test func clapGateReasons() {
        #expect(ClapGate.block(locked: false, secondsSinceKey: 60, secondsSinceClick: 60, macPlaying: false, videoInFront: false) == nil)
        #expect(ClapGate.block(locked: true, secondsSinceKey: 60, secondsSinceClick: 60, macPlaying: false, videoInFront: false) == "screen locked")
        #expect(ClapGate.block(locked: false, secondsSinceKey: 0.8, secondsSinceClick: 60, macPlaying: false, videoInFront: false) == "typing")
        #expect(ClapGate.block(locked: false, secondsSinceKey: 60, secondsSinceClick: 0.4, macPlaying: false, videoInFront: false) == "clicking")
        #expect(ClapGate.block(locked: false, secondsSinceKey: 60, secondsSinceClick: 60, macPlaying: true, videoInFront: false) == "Mac playing audio")
        #expect(ClapGate.block(locked: false, secondsSinceKey: 60, secondsSinceClick: 60, macPlaying: false, videoInFront: true) == "video in front")
    }
}

struct SplitGreetingTests {
    private let sofia = WakeWord(name: "Sofia")

    @Test func sufiIsHerName() {
        #expect(sofia.matches("Hey Sufi"))
        #expect(sofia.matches("hi sufi open spotify"))
        #expect(!sofia.matches("hey Siri"))
        #expect(WakeWord(name: "Sophia").matches("Hey Sufi"))
    }

    @Test func aResetInsideOneTaskKeepsTheGreeting() {
        var h = HeardHistory()
        let t = Date()
        h.heard("Hey", at: t)
        h.heard("Sofia", at: t.addingTimeInterval(3))
        #expect(h.previous == "Hey")
        #expect(sofia.greetingThenName(previous: h.previous, current: "Sofia", gap: 3))
    }

    @Test func aGrowingResultIsNotASecondUtterance() {
        var h = HeardHistory()
        let t = Date()
        h.heard("Hey", at: t); h.heard("Hey there", at: t.addingTimeInterval(1)); h.heard("hey there how are you", at: t.addingTimeInterval(2))
        #expect(h.previous == "")
        #expect(h.latest == "hey there how are you")
    }

    @Test func aNewTaskMovesTheLastResultBack() {
        var h = HeardHistory()
        let t = Date()
        h.heard("Hey", at: t)
        h.newTask()
        #expect(h.previous == "Hey" && h.previousAt == t && h.latest == "")
        h.newTask()
        #expect(h.previous == "Hey")
    }

    @Test func withMediaOnlyABareQuickGreetingCounts() {
        #expect(sofia.greetingThenName(previous: "Hey", current: "Sofia", gap: 3, media: true))
        #expect(!sofia.greetingThenName(previous: "Hey", current: "Sofia", gap: 6, media: true))
        #expect(!sofia.greetingThenName(previous: "and then she said hey", current: "Sofia", gap: 1, media: true))
        #expect(sofia.greetingThenName(previous: "and then she said hey", current: "Sofia", gap: 1))
    }
}
