import Testing
@testable import SofiaCore

struct StandbyTests {
    @Test func phrases() {
        for s in ["go off", "Sofia, go off", "okay sofia go to sleep", "stop listening", "power down please", "stand by", "standby", "switch yourself off", "go offline now", "off you go"] {
            #expect(IslandStateMachine.isStandbyPhrase(s), Comment(rawValue: s))
        }
        for s in ["go off the record", "turn off the lights", "stop", "sleep timer for 20 minutes", "power off the tv", "go to sleep mode on my mac", "how do I stand by a friend"] {
            #expect(!IslandStateMachine.isStandbyPhrase(s), Comment(rawValue: s))
        }
    }
    @Test func goingOffSpeaksOnceAndDoesNotListenAgain() {
        var m = IslandStateMachine(conversation: true)
        _ = m.handle(.hotkey); _ = m.handle(.recordingEnded)
        let effects = m.handle(.transcribed("Sofia, go off"))
        #expect(effects == [.standby, .speak(IslandStateMachine.standbyLine)] && m.phase == .speaking)
        _ = m.handle(.speechFinished)
        #expect(m.phase == .listening || m.phase == .idle)
    }
}

struct StandbyRootCauseTests {
    @Test func everydayWaysOfSayingItAreAccepted() {
        for s in ["turn off", "Sofia, turn off", "shut down", "shut off", "switch off", "go to sleep now please", "sleep", "go sleep", "good night", "goodnight sofia", "go off now", "golf", "go of", "sofia go off", "please go off", "go off for now", "that's enough, go off", "off"] {
            #expect(IslandStateMachine.isStandbyPhrase(s), Comment(rawValue: s))
        }
        for s in ["turn off the lights", "shut down my mac", "switch off the wifi", "sleep timer 20 minutes", "good night message to Sam", "how do I play golf", "turn off dark mode", "go off the record"] {
            #expect(!IslandStateMachine.isStandbyPhrase(s), Comment(rawValue: s))
        }
    }
    @Test func nameAndStandbyCommandWakeHerOutsideTheCasualWindow() {
        let w = WakeWord(name: "Sofia")
        #expect(w.standbyCommand("Sofia, go off") == "go off")
        #expect(w.standbyCommand("so earlier I told you sofia turn off") == "turn off")
        #expect(w.standbyCommand("sofia, what's the weather") == nil)
        #expect(w.standbyCommand("go off") == nil)
        #expect(!w.matches("Sofia, go off", casual: false) && w.standbyCommand("Sofia, go off") != nil)
        #expect(WakeWord(name: "Nova").standbyCommand("nova shut down") == "shut down")
    }
}
