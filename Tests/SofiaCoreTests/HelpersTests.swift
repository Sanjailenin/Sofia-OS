import Testing
import Foundation
@testable import SofiaCore

struct WindowGeometryTests {
    typealias R = WindowGeometry.Rect
    let laptop = R(x: 0, y: 38, width: 1512, height: 944)
    let external = R(x: 1512, y: -200, width: 2560, height: 1400)
    let win = R(x: 100, y: 100, width: 800, height: 600)

    @Test func halvesAndFull() {
        #expect(WindowGeometry.frame(for: "left", window: win, displays: [laptop, external], builtin: 0) == R(x: 0, y: 38, width: 756, height: 944))
        #expect(WindowGeometry.frame(for: "right", window: win, displays: [laptop, external], builtin: 0) == R(x: 756, y: 38, width: 756, height: 944))
        #expect(WindowGeometry.frame(for: "full", window: win, displays: [laptop, external], builtin: 0) == laptop)
        let c = WindowGeometry.frame(for: "center", window: win, displays: [laptop], builtin: 0)!
        #expect(c.width == 800 && c.height == 600 && c.midX == laptop.midX)
    }
    @Test func movesBetweenDisplays() {
        let moved = WindowGeometry.frame(for: "external", window: win, displays: [laptop, external], builtin: 0)!
        #expect(moved.x >= external.x && moved.x + moved.width <= external.x + external.width)
        let back = WindowGeometry.frame(for: "laptop", window: moved, displays: [laptop, external], builtin: 0)!
        #expect(laptop.contains(back.midX, back.midY))
        #expect(WindowGeometry.frame(for: "next_display", window: win, displays: [laptop], builtin: 0) == nil)
        #expect(WindowGeometry.frame(for: "sideways", window: win, displays: [laptop], builtin: 0) == nil)
    }
}

struct PreferenceTests {
    @Test func allowList() {
        #expect(Preference(rawValue: "wake_word") == nil && Preference(rawValue: "ollama_url") == nil)
        #expect(Preference.entrance.normalize("Off") == "off" && Preference.entrance.normalize("yes") == "on" && Preference.entrance.normalize("maybe") == nil)
        #expect(Preference.clapSensitivity.normalize("HIGH") == "high" && Preference.clapSensitivity.normalize("max") == nil)
        #expect(MacAction(["action": "set_preference", "target": "remote_access", "value": "off"])?.value == "off")
        #expect(MacAction(["action": "set_preference", "target": "wake_word", "value": "off"]) == nil)
    }
}

struct MacActionExtraTests {
    @Test func windowAndFocusActions() {
        #expect(MacAction(["action": "move_window", "target": "Slack", "value": "left"])?.summary == "move Slack left")
        #expect(MacAction(["action": "move_window", "target": "Slack", "value": "upstairs"]) == nil)
        #expect(MacAction(["action": "focus", "value": "on"]) != nil && MacAction(["action": "focus", "value": "later"]) == nil)
        #expect(MacAction(["action": "hide_app", "target": "Mail"])?.summary == "hide Mail")
        #expect(MacAction(["action": "unhide_app", "target": "rm -rf /"]) == nil)
        #expect(MacAction(["action": "read_screen"]) == nil && MacAction(["action": "computer_task", "target": "x"]) == nil)
    }
}

struct DictationAndNudgeTests {
    @Test func cleanText() {
        #expect(Dictation.clean("  hello there how are you ") == "Hello there how are you.")
        #expect(Dictation.clean("Done!") == "Done!" && Dictation.clean("") == "")
    }
    @Test func nudgeRules() {
        var mem = NudgeRules.Memory()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        var f = NudgeRules.Facts(batteryPercent: 18, charging: false, diskFreeGB: 120, online: true, eventWithinHour: false)
        #expect(NudgeRules.evaluate(f, now: t0, memory: &mem) == ["Battery is at 18 percent; plug in when you can."])
        #expect(NudgeRules.evaluate(f, now: t0.addingTimeInterval(600), memory: &mem) == [])
        f.charging = true
        #expect(NudgeRules.evaluate(f, now: t0.addingTimeInterval(4000), memory: &mem) == [])
        f = NudgeRules.Facts(batteryPercent: 80, charging: true, diskFreeGB: 6.4, online: true, eventWithinHour: false)
        #expect(NudgeRules.evaluate(f, now: t0.addingTimeInterval(4000), memory: &mem) == ["Your disk has 6 gigabytes left."])
        var o = NudgeRules.Memory()
        let off = NudgeRules.Facts(batteryPercent: 80, charging: true, diskFreeGB: 100, online: false, eventWithinHour: false)
        #expect(NudgeRules.evaluate(off, now: t0, memory: &o) == [])
        #expect(NudgeRules.evaluate(off, now: t0.addingTimeInterval(130), memory: &o) == ["You've been offline for two minutes."])
        var on = off; on.online = true
        #expect(NudgeRules.evaluate(on, now: t0.addingTimeInterval(400), memory: &o) == ["You're back online."])
    }
}
