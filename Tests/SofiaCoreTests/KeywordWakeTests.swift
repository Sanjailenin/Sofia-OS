import Testing
import Foundation
@testable import SofiaCore

struct KeywordWakeTests {
    let tokenizer = WakeTokenizer(pieces: GigaspeechPieces.all)

    @Test func greetingsTimesTheName() {
        #expect(KeywordWake(name: "Jarvis").phrases == ["hey jarvis", "hi jarvis", "ok jarvis", "hello jarvis"])
        #expect(KeywordWake(name: "  Nova ").phrases.first == "hey nova")
        #expect(KeywordWake(name: "Sofia").phrases.contains("hey sophia"))
        #expect(KeywordWake(name: "Sophia").phrases.contains("hey sofia"))
    }

    @Test func theKeywordFileHasThePiecesTheBonusAndALabel() {
        let file = KeywordWake(name: "Sofia").keywordFile(tokenizer)
        let lines = file.split(separator: "\n").map(String.init)
        #expect(lines.first == "▁HE Y ▁SO F IA :2.0 @HEY_SOFIA")
        #expect(lines.contains("▁HE Y ▁SO PH IA :2.0 @HEY_SOPHIA"))
        #expect(lines.count == 8)
        #expect(file.hasSuffix("\n"))
        let jarvis = KeywordWake(name: "Jarvis").keywordFile(tokenizer).split(separator: "\n")
        #expect(jarvis.count == 4 && jarvis.allSatisfy { $0.hasPrefix("▁") && $0.contains(":2.0 @") })
    }

    @Test func aNameTheModelCannotSpellGivesNoFile() {
        #expect(KeywordWake(name: "2pac").keywordFile(tokenizer).isEmpty)
        #expect(KeywordWake(name: "").keywordFile(tokenizer).isEmpty)
    }

    @Test func labelsOfTwoWordNames() {
        let w = KeywordWake(name: "Mister Robot")
        #expect(w.phrases.first == "hey mister robot")
        #expect(w.isWake("HEY_MISTER_ROBOT") && !w.isWake("HEY_SIRI"))
    }

    @Test func oneWakePerUtterance() {
        let w = KeywordWake(name: "Sofia")
        var gate = KeywordGate()
        let t = Date()
        let first = gate.accept("HEY_SOFIA", for: w, at: t)
        let again = gate.accept("HI_SOFIA", for: w, at: t.addingTimeInterval(0.5))
        let other = gate.accept("HEY_SIRI", for: w, at: t.addingTimeInterval(5))
        let later = gate.accept("HEY_SOFIA", for: w, at: t.addingTimeInterval(KeywordWake.cooldown + 0.1))
        #expect(first && !again && !other && later)
    }
}
