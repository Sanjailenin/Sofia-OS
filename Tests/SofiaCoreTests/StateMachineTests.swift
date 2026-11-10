import Testing
@testable import SofiaCore

struct StateMachineTests {
    @Test func hotkeyRoundTrip() {
        var m = IslandStateMachine(conversation: false)
        #expect(m.handle(.hotkey) == [.startListening] && m.phase == .listening)
        #expect(m.handle(.recordingEnded) == [.transcribe] && m.phase == .thinking)
        #expect(m.handle(.transcribed("open safari")) == [.ask("open safari")])
        #expect(m.handle(.replyReady("Opening Safari.")) == [.speak("Opening Safari.")] && m.phase == .speaking)
        #expect(m.handle(.speechFinished) == [] && m.phase == .idle)
    }
    @Test func conversationModeListensAgainAndClosesOnThanks() {
        var m = IslandStateMachine(conversation: true)
        _ = m.handle(.hotkey); _ = m.handle(.recordingEnded); _ = m.handle(.transcribed("hi")); _ = m.handle(.replyReady("Hello."))
        #expect(m.handle(.speechFinished) == [.startFollowUp] && m.followUp)
        _ = m.handle(.recordingEnded)
        #expect(m.handle(.transcribed("thanks")) == [] && m.phase == .idle)
        _ = m.handle(.hotkey); _ = m.handle(.recordingEnded); _ = m.handle(.transcribed("hi")); _ = m.handle(.replyReady("Hello.")); _ = m.handle(.speechFinished)
        #expect(m.handle(.noSpeech) == [.cancelListening] && m.phase == .idle)
    }
    @Test func errorsAndEscape() {
        var m = IslandStateMachine(conversation: false)
        _ = m.handle(.hotkey)
        #expect(m.handle(.noSpeech) == [.cancelListening, .scheduleErrorDismiss])
        #expect(m.phase == .error("I didn't catch that"))
        #expect(m.handle(.errorTimeout) == [] && m.phase == .idle)
        _ = m.handle(.hotkey); _ = m.handle(.recordingEnded)
        #expect(m.handle(.failed("boom")) == [.cancelRequests, .scheduleErrorDismiss])
        _ = m.handle(.escape); #expect(m.phase == .idle)
        _ = m.handle(.hotkey)
        #expect(m.handle(.escape) == [.cancelListening] && m.phase == .idle)
    }
    @Test func bargeInWhileSpeaking() {
        var m = IslandStateMachine(conversation: false)
        _ = m.handle(.hotkey); _ = m.handle(.recordingEnded); _ = m.handle(.transcribed("x")); _ = m.handle(.replyReady("Long answer."))
        #expect(m.handle(.hotkey) == [.stopSpeaking, .startListening] && m.phase == .listening)
    }
    @Test func sayFromIdleSpeaksWithAChime() {
        var m = IslandStateMachine(conversation: true)
        #expect(m.handle(.say("Battery is at 18 percent.")) == [.chime, .speak("Battery is at 18 percent.")])
        #expect(m.handle(.speechFinished) == [.startFollowUp])
        var busy = IslandStateMachine(conversation: false)
        _ = busy.handle(.hotkey)
        #expect(busy.handle(.say("later")) == [] && busy.phase == .listening)
    }
    @Test func stopPhrases() {
        for s in ["stop", "okay, that's all", "never mind", "bye"] { #expect(IslandStateMachine.isStopPhrase(s), Comment(rawValue: s)) }
        for s in ["stop the music", "cancel my meeting on Monday", "that's all for the list"] { #expect(!IslandStateMachine.isStopPhrase(s), Comment(rawValue: s)) }
        var m = IslandStateMachine(conversation: false)
        _ = m.handle(.hotkey); _ = m.handle(.recordingEnded)
        #expect(m.handle(.transcribed("stop")) == [] && m.phase == .idle)
    }
    @Test func dictation() {
        var m = IslandStateMachine(conversation: true)
        #expect(m.handle(.dictate) == [.startListening] && m.dictating)
        #expect(m.handle(.recordingEnded) == [.transcribeDictation])
        #expect(m.handle(.dictated) == [] && m.phase == .idle && !m.dictating)
        var n = IslandStateMachine(conversation: true)
        _ = n.handle(.dictate)
        #expect(n.handle(.noSpeech) == [.cancelListening] && n.phase == .idle)
        var busy = IslandStateMachine(conversation: true)
        _ = busy.handle(.hotkey)
        #expect(busy.handle(.dictate) == [] && busy.phase == .listening)
    }
}
