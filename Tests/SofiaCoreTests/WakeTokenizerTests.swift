import Testing
import Foundation
@testable import SofiaCore

struct WakeTokenizerTests {
    let tokenizer = WakeTokenizer(pieces: GigaspeechPieces.all)

    @Test func matchesSentencepieceOnEveryGoldenPhrase() {
        var wrong: [String] = []
        for (phrase, pieces) in GigaspeechPieces.gold where tokenizer.encode(phrase) != pieces { wrong.append("\(phrase): \(tokenizer.encode(phrase) ?? []) vs \(pieces)") }
        #expect(wrong.isEmpty, Comment(rawValue: wrong.prefix(5).joined(separator: "\n")))
        #expect(GigaspeechPieces.gold.count == 176)
    }

    @Test func normalisesCaseAndSpacing() {
        #expect(tokenizer.encode("hey sofia") == ["▁HE", "Y", "▁SO", "F", "IA"])
        #expect(tokenizer.encode("  Hey   Sofia ") == ["▁HE", "Y", "▁SO", "F", "IA"])
    }

    @Test func charactersOutsideTheVocabularyGiveNothing() {
        #expect(tokenizer.encode("hey 2pac") == nil)
        #expect(tokenizer.encode("hey zoë") == nil)
        #expect(tokenizer.encode("") == nil)
    }

    @Test func readsTheSentencepieceModelFile() {
        var data = Data()
        func varint(_ v: UInt64) { var v = v; while v >= 0x80 { data.append(UInt8(v & 0x7f) | 0x80); v >>= 7 }; data.append(UInt8(v)) }
        func piece(_ p: String, _ score: Float, _ type: UInt64) {
            var inner = Data()
            let bytes = Array(p.utf8)
            inner.append(0x0a); inner.append(UInt8(bytes.count)); inner.append(contentsOf: bytes)
            inner.append(0x15); withUnsafeBytes(of: score.bitPattern.littleEndian) { inner.append(contentsOf: $0) }
            inner.append(0x18); inner.append(UInt8(type))
            data.append(0x0a); varint(UInt64(inner.count)); data.append(inner)
        }
        piece("<unk>", 0, 2); piece("▁HE", -3, 1); piece("Y", -4, 1); piece("▁", -5, 1); piece("H", -6, 1); piece("E", -6, 1)
        data.append(contentsOf: [0x12, 0x02, 0x08, 0x01])
        let t = WakeTokenizer(model: data)
        #expect(t?.encode("hey") == ["▁HE", "Y"])
        #expect(WakeTokenizer(model: Data([0x0a, 0xff])) == nil)
    }
}
