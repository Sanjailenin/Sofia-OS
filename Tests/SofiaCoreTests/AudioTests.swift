import Testing
import Foundation
@testable import SofiaCore

@Suite struct AudioTests {
    @Test func silenceProbeFiresOnceAfterASecondOfDigitalSilence() {
        var p = SilenceProbe()
        var fired = 0
        for _ in 0..<12 { if p.feed(level: 0, dt: 0.1) { fired += 1 } }
        #expect(fired == 1)
        var q = SilenceProbe()
        #expect(!q.feed(level: 0, dt: 0.5) && !q.feed(level: 0.0001, dt: 0.5) && !q.feed(level: 0, dt: 5))
        var r = SilenceProbe(seconds: 0.3)
        #expect(!r.feed(level: 0, dt: 0.2) && r.feed(level: 0, dt: 0.2))
    }

    @Test func wavHeader() {
        let d = WAV.encode([1, -1, 300])
        #expect(String(decoding: d[0..<4], as: UTF8.self) == "RIFF")
        #expect(String(decoding: d[8..<12], as: UTF8.self) == "WAVE")
        #expect(d.count == 44 + 6)
        #expect(d.subdata(in: 24..<28) == Data([0x80, 0x3E, 0, 0]))
    }

    @Test func endpointerFinishesAfterSilenceFollowingSpeech() {
        var e = Endpointer(); var r = Endpointer.Decision.keepGoing
        for _ in 0..<10 { r = e.feed(rms: 0.0005, dt: 0.1) }
        #expect(r == .keepGoing)
        for _ in 0..<10 { r = e.feed(rms: 0.2, dt: 0.1) }
        #expect(e.hasHeardSpeech)
        for _ in 0..<15 { r = e.feed(rms: 0.0005, dt: 0.1) }
        #expect(r == .keepGoing)
        for _ in 0..<2 { r = e.feed(rms: 0.0005, dt: 0.1) }
        #expect(r == .finished)
    }

    @Test func endpointerNoSpeech() {
        var e = Endpointer(); var r = Endpointer.Decision.keepGoing
        for _ in 0..<95 { r = e.feed(rms: 0.0005, dt: 0.1); if r != .keepGoing { break } }
        #expect(r == .noSpeech)
    }

    @Test func singleClickIsNotSpeech() {
        var e = Endpointer(); _ = e.feed(rms: 0.5, dt: 0.1)
        #expect(!(e.hasHeardSpeech))
    }

    @Test func spokenFormMatchesDashboardRules() {
        #expect(spokenForm(reply: "**Hi** see https://x.com/a\n\nNext") == "Hi see a link. Next")
        #expect(spokenForm(reply: "") == "Done.")
        #expect(spokenForm(reply: "Ok", actions: 2) == "Ok I've prepared 2 drafts. They're waiting for your OK on screen.")
        #expect(spokenForm(reply: "Ok", choices: 1).hasSuffix("You can tap one on screen or just tell me."))
        #expect(spokenForm(reply: String(repeating: "Word. ", count: 200)).hasSuffix("The rest is on screen."))
    }
}

@Suite struct WakeWordTests {
    @Test func wakesOnGreetingPlusName() {
        for t in ["Hey Sofia", "hey, Sofia what's on", "Okay Sofi", "hi sofia!", "Hello so fear", "and then hey Sophie"] { #expect(WakeWord.matches(t), Comment(rawValue: t)) }
    }
    @Test func ignoresNameWithoutGreetingAndOtherSpeech() {
        for t in ["Sofia", "I met Sofia yesterday", "hey there", "heysofia2", "they sofia"] { #expect(!WakeWord.matches(t), Comment(rawValue: t)) }
    }

    @Test func casualFormNeedsHerNameAndARequest() {
        for t in ["Sofia, what's on today", "sofia open spotify", "so fia what time is it", "right so Sofia, play some music"] {
            #expect(WakeWord.matches(t, casual: true), Comment(rawValue: t))
            #expect(!WakeWord.matches(t), Comment(rawValue: t))
        }
        for t in ["Sofia", "Sofia,", "I met Sofia", "that was Sofia.", "sofiatown is nice"] { #expect(!WakeWord.matches(t, casual: true), Comment(rawValue: t)) }
        #expect(WakeWord.remainder("Sofia, what's on today", casual: true) == "what's on today")
        #expect(WakeWord.remainder("Hey Sofia what's on", casual: true) == "what's on")
        #expect(WakeWord.remainder("Sofia", casual: true) == "")
    }
}

@Suite struct LevelTests {
    @Test func quietSpeechStillCountsAsSpeech() {
        var e = Endpointer(); var r = Endpointer.Decision.keepGoing
        for _ in 0..<10 { r = e.feed(rms: 0.0003, dt: 0.1) }
        for _ in 0..<5 { r = e.feed(rms: 0.008, dt: 0.1) }
        #expect(e.hasHeardSpeech)
        for _ in 0..<17 { r = e.feed(rms: 0.0003, dt: 0.1) }
        #expect(r == .finished)
        #expect(e.peak >= 0.008)
    }
    @Test func displayLevelIsOnDbScale() {
        #expect(Level.display(0.0003) == 0); #expect(Level.display(0.01) > 0.4 && Level.display(0.01) < 0.7); #expect(Level.display(0.2) == 1)
    }
    @Test func normalizeBoostsQuietClipsOnly() {
        let quiet: [Int16] = [0, 300, -300, 150]
        #expect(Level.normalize(quiet).map { abs(Int($0)) }.max()! > 5000)
        let loud: [Int16] = [0, 20000, -20000]; #expect(Level.normalize(loud) == loud)
        let silent: [Int16] = [0, 3, -3]; #expect(Level.normalize(silent) == silent)
    }
}
