import Foundation

public enum Phase: Equatable {
    case idle, listening, thinking, speaking
    case error(String)
    public var isActive: Bool { self != .idle }
}

public enum Event: Equatable {
    case hotkey
    case escape
    case partial(String)
    case recordingEnded
    case noSpeech
    case transcribed(String)
    case replyReady(String)
    case speechFinished
    case failed(String)
    case errorTimeout
    case say(String)
    case dictate
    case dictated
}

public enum Effect: Equatable {
    case startListening
    case startFollowUp
    case stopListening
    case cancelListening
    case transcribe
    case transcribeDictation
    case ask(String)
    case speak(String)
    case stopSpeaking
    case cancelRequests
    case scheduleErrorDismiss
    case chime
    case standby
}

public struct IslandStateMachine: Equatable {
    public private(set) var phase: Phase = .idle
    public private(set) var transcript = ""
    public private(set) var followUp = false
    public private(set) var dictating = false
    public var conversation: Bool

    public init(conversation: Bool = true) { self.conversation = conversation }

    static func closing(name: String) -> NSRegularExpression { try! NSRegularExpression(pattern: #"^(?:ok(?:ay)?[, ]*)?(?:thanks|thank you|cheers|great|perfect|cool|nice|got it|alright|all ?right)(?:[, ]*"# + name + #")?\W*$"#, options: .caseInsensitive) }
    static let stopPhrase = try! NSRegularExpression(pattern: #"^(?:ok(?:ay)?[, ]*)?(?:stop|cancel|that'?s all|that is all|that'?s it|goodbye|bye|never ?mind|enough)\W*$"#, options: .caseInsensitive)
    public static let standbyCommands = #"(?:go (?:off|of|offline|to sleep|sleep|away|dark|quiet)|golf|goof|switch (?:yourself )?off|turn (?:yourself )?off|shut (?:down|off|up)|power (?:off|down)|stand ?by|stop listening|sleep(?: now)?|good ?night|off you go|off)"#
    static func standbyPhrase(name: String) -> NSRegularExpression {
        let trailers = #"(?:[\s,.!?;:-]*(?:please|now|for now|thanks|thank you|"# + name + #"))*"#
        return try! NSRegularExpression(pattern: #"^(?:ok(?:ay)?[\s,.!-]*)?(?:(?:that'?s enough|right|please)[\s,.!-]*)?(?:"# + name + #"[\s,.!?;:-]*)?(?:please[\s,]*)?"# + standbyCommands + trailers + #"\W*$"#, options: .caseInsensitive)
    }
    public static var standbyLine: String { standbyLine(for: WakeWord.current) }
    public static func standbyLine(for wake: WakeWord) -> String { "Going off. Say Hey \(wake.name) or clap twice when you want me back." }

    static func matches(_ re: NSRegularExpression, _ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
    }
    public static func isClosing(_ text: String, wake: WakeWord = WakeWord.current) -> Bool { isStopPhrase(text) || matches(closing(name: wake.namePattern), text) }
    public static func isStopPhrase(_ text: String) -> Bool { matches(stopPhrase, text) }
    public static func isStandbyPhrase(_ text: String, wake: WakeWord = WakeWord.current) -> Bool { matches(standbyPhrase(name: wake.namePattern), text) }

    public mutating func handle(_ event: Event) -> [Effect] {
        if case .escape = event { dictating = false }
        if case .failed = event { dictating = false }
        switch (phase, event) {
        case (.idle, .hotkey), (.error, .hotkey):
            phase = .listening; transcript = ""; followUp = false
            return [.startListening]
        case (.idle, .dictate), (.error, .dictate):
            phase = .listening; transcript = ""; followUp = false; dictating = true
            return [.startListening]
        case (_, .dictate):
            return []
        case (.idle, .say(let line)), (.error, .say(let line)):
            phase = .speaking; transcript = line; followUp = false
            return [.chime, .speak(line)]
        case (_, .say):
            return []

        case (.listening, .hotkey):
            return [.stopListening]
        case (.listening, .escape):
            phase = .idle; transcript = ""; followUp = false
            return [.cancelListening]
        case (.listening, .partial(let t)):
            transcript = t; return []
        case (.listening, .recordingEnded):
            phase = .thinking; transcript = ""
            return [dictating ? .transcribeDictation : .transcribe]
        case (.listening, .noSpeech):
            transcript = ""
            if dictating { dictating = false; phase = .idle; return [.cancelListening] }
            if followUp { phase = .idle; followUp = false; return [.cancelListening] }
            phase = .error("I didn't catch that")
            return [.cancelListening, .scheduleErrorDismiss]

        case (.thinking, .dictated):
            phase = .idle; transcript = ""; dictating = false
            return []
        case (.thinking, .transcribed(let t)):
            let said = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if said.isEmpty {
                if followUp { phase = .idle; followUp = false; transcript = ""; return [] }
                phase = .error("I didn't catch that"); return [.scheduleErrorDismiss]
            }
            if Self.isStandbyPhrase(said) { phase = .speaking; transcript = Self.standbyLine; followUp = false; return [.standby, .speak(transcript)] }
            if Self.isStopPhrase(said) || (followUp && Self.isClosing(said)) { phase = .idle; transcript = ""; followUp = false; return [] }
            transcript = said
            return [.ask(said)]
        case (.thinking, .replyReady(let line)):
            phase = .speaking; transcript = line
            return [.speak(line)]
        case (.thinking, .escape), (.thinking, .hotkey):
            phase = .idle; transcript = ""; followUp = false
            return [.cancelRequests]

        case (.speaking, .speechFinished):
            transcript = ""
            if conversation { phase = .listening; followUp = true; return [.startFollowUp] }
            phase = .idle
            return []
        case (.speaking, .hotkey):
            phase = .listening; transcript = ""; followUp = false
            return [.stopSpeaking, .startListening]
        case (.speaking, .escape):
            phase = .idle; transcript = ""; followUp = false
            return [.stopSpeaking]

        case (_, .failed(let message)):
            phase = .error(message); transcript = ""; followUp = false
            return [.cancelRequests, .scheduleErrorDismiss]
        case (.error, .errorTimeout), (.error, .escape):
            phase = .idle; transcript = ""
            return []
        default:
            return []
        }
    }
}
