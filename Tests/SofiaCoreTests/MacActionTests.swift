import Testing
@testable import SofiaCore

@Suite struct MacActionTests {
    @Test func listedActionsPass() {
        #expect(MacAction(["action": "open_app", "target": "Spotify"])?.summary == "open Spotify")
        #expect(MacAction(["action": "set_volume", "value": "30"])?.value == "30")
        #expect(MacAction(["action": "dark_mode", "value": "Toggle"])?.value == "toggle")
        #expect(MacAction(["action": "open_url", "target": "https://example.com/a"]) != nil)
        #expect(MacAction(["action": "open_path", "target": "~/Downloads"]) != nil)
        #expect(MacAction(["action": "lock_screen"]) != nil)
    }

    @Test func anythingElseIsRefused() {
        #expect(MacAction(["action": "run_shell", "target": "ls"]) == nil)
        #expect(MacAction(["action": "open_app", "target": "Spotify\"; do shell script \"rm"]) == nil)
        #expect(MacAction(["action": "open_url", "target": "file:///etc/passwd"]) == nil)
        #expect(MacAction(["action": "open_url", "target": "javascript:alert(1)"]) == nil)
        for bad in ["~/evil.command", "/Applications/Terminal.app", "~/a/../../etc", "Downloads", "~/x.sh"] {
            #expect(MacAction(["action": "open_path", "target": bad]) == nil, "\(bad)")
        }
        #expect(MacAction(["action": "set_volume", "value": "101"]) == nil)
        #expect(MacAction(["action": "wifi", "value": "maybe"]) == nil)
        #expect(MacAction(["action": "type_text", "target": String(repeating: "x", count: 501)]) == nil)
    }

    @Test func listDropsBadItemsAndCapsAtEight() {
        let raw: [[String: Any]] = [["action": "mute"], ["action": "nope"]] + Array(repeating: ["action": "unmute"], count: 9)
        let r = MacAction.list(from: raw)
        #expect(r.actions.count == 8)
        #expect(r.rejected == 3)
        #expect(MacAction.list(from: nil).actions.isEmpty)
    }

    @Test func searchAndEverydayActions() {
        #expect(MacAction(["action": "web_search", "target": "flights to Lisbon"])?.value == "google")
        #expect(MacAction(["action": "web_search", "target": "lo-fi", "value": "YouTube"])?.value == "youtube")
        #expect(MacAction(["action": "web_search", "target": "x", "value": "javascript:alert(1)"]) == nil)
        #expect(MacAction.searchURL("a&b=c d", site: "google")?.absoluteString == "https://www.google.com/search?q=a%26b%3Dc%20d")
        #expect(MacAction.searchURL("cafés Lisbon", site: "maps")?.absoluteString == "https://www.google.com/maps/search/caf%C3%A9s%20Lisbon")
        #expect(MacAction(["action": "find_file", "target": "thesis draft"]) != nil)
        #expect(MacAction(["action": "find_file", "target": "../etc/passwd"]) == nil)
        #expect(MacAction(["action": "find_file", "target": "*"]) == nil)
        #expect(MacAction(["action": "open_settings", "target": "Bluetooth"])?.target == "bluetooth")
        #expect(MacAction(["action": "open_settings", "target": "terminal"]) == nil)
        #expect(MacAction(["action": "set_volume", "value": "up"]) != nil)
        #expect(MacAction(["action": "clipboard_copy", "target": "hello"]) != nil)
        #expect(MacAction(["action": "new_note", "target": String(repeating: "x", count: 2001)]) == nil)
        #expect(MacAction(["action": "play_music", "target": "Arijit Singh"])?.summary == "play Arijit Singh")
    }

    @Test func appleScriptStringsAreEscaped() {
        #expect(MacAction.appleScriptString(#"say "hi" \ now"#) == #""say \"hi\" \\ now""#)
        #expect(MacAction.appleScriptString("a\nb") == #""a\nb""#)
    }
}
