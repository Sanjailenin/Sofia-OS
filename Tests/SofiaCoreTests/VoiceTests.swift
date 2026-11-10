import Testing
import Foundation
@testable import SofiaCore

struct VoiceTests {
    @Test func exactlyFourWomenAndTwoMen() {
        #expect(SofiaVoice.all.count == 6)
        #expect(SofiaVoice.all.filter { $0.gender == .woman }.count == 4)
        #expect(SofiaVoice.all.filter { $0.gender == .man }.count == 2)
        #expect(Set(SofiaVoice.all.map(\.id)).count == 6)
        #expect(Set(SofiaVoice.all.map(\.speaker)).count == 6)
    }

    @Test func speakerIdsMatchTheKokoroTable() {
        let ids = Dictionary(uniqueKeysWithValues: SofiaVoice.all.map { ($0.id, $0.speaker) })
        #expect(ids == ["af_aoede": 1, "af_heart": 3, "af_kore": 5, "af_sarah": 9, "am_fenrir": 14, "am_puck": 18])
    }

    @Test func storedNamesResolve() {
        #expect(SofiaVoice.resolve("") == SofiaVoice.standard)
        #expect(SofiaVoice.resolve("am_puck").name == "Puck")
        #expect(SofiaVoice.resolve("Fenrir").id == "am_fenrir")
        #expect(SofiaVoice.resolve(" sarah ").id == "af_sarah")
        #expect(SofiaVoice.resolve("com.apple.voice.compact.en-GB.Daniel") == SofiaVoice.standard)
    }

    @Test func fallbackMatchesGender() {
        for v in SofiaVoice.all { #expect(!v.appleFallback.isEmpty) }
        #expect(SofiaVoice.resolve("am_puck").appleFallback.first == "Daniel")
        #expect(SofiaVoice.resolve("af_kore").appleFallback.first == "Samantha")
    }

    @Test func waveHeaderAndSamples() {
        let d = WaveFile.pcm16([0, 1, -1, 2], sampleRate: 24000)
        #expect(d.count == 44 + 8)
        #expect(String(decoding: d[0..<4], as: UTF8.self) == "RIFF")
        #expect(String(decoding: d[8..<12], as: UTF8.self) == "WAVE")
        let rate = d[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        #expect(UInt32(littleEndian: rate) == 24000)
        let s = d[44...].withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        #expect(s == [0, 32767, -32767, 32767])
    }
}
