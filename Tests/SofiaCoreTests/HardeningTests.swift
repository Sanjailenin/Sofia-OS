import Foundation
import Testing
@testable import SofiaCore

@Suite struct HardeningTests {
    @Test func enginePinsRefuseChangedLibraries() {
        let a = Data("engine".utf8), b = Data("runtime".utf8)
        let pins = [EnginePins.main: EnginePins.digest(a), EnginePins.runtime: EnginePins.digest(b)]
        #expect(EnginePins.check([EnginePins.main: a, EnginePins.runtime: b], pins: pins) == nil)
        #expect(EnginePins.check([EnginePins.main: a, EnginePins.runtime: Data("swapped".utf8)], pins: pins) != nil)
        #expect(EnginePins.check([EnginePins.main: a], pins: pins) != nil)
        #expect(EnginePins.digest(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        for set in [EnginePins.arm64, EnginePins.x64] { #expect(set.count == 2 && set.values.allSatisfy { $0.count == 64 }) }
    }

    @Test func terminalsAndScriptingAppsAreBlocked() {
        for b in ["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty", "com.apple.ScriptEditor2", "com.apple.shortcuts", "com.apple.systempreferences"] {
            #expect(ComputerGuard.isBlocked(bundleID: b))
        }
        #expect(ComputerGuard.refusal(bundleID: "com.1password.1password")?.contains("password") == true)
        for b in ["com.apple.Safari", "com.apple.Notes", "com.spotify.client", nil] { #expect(ComputerGuard.refusal(bundleID: b) == nil) }
    }

    @Test func openPathRefusesThingsThatRunCode() {
        for p in ["/Users/alex/Downloads/Foo.app", "/Users/alex/Desktop/x.fileloc", "/Users/alex/Downloads/a.webloc", "/Users/alex/Downloads/p.mobileconfig", "/Users/alex/Downloads/s.prefPane", "/Users/alex/Downloads/run.command"] {
            #expect(MacAction.openRefusal(path: p, isDirectory: false, isExecutable: false) != nil)
        }
        #expect(MacAction.openRefusal(path: "/Users/alex/Downloads/tool", isDirectory: false, isExecutable: true) != nil)
        #expect(MacAction.openRefusal(path: "/Users/alex/Documents/report.pdf", isDirectory: false, isExecutable: false) == nil)
        #expect(MacAction.openRefusal(path: "/Users/alex/Documents", isDirectory: true, isExecutable: true) == nil)
        #expect(MacAction(["action": "open_path", "target": "~/Downloads/x.webloc"]) == nil)
    }

    @Test func pairingOnlyFromAPrivateChat() {
        var s = TelegramState(pairingCode: "123456")
        let group = TelegramUpdate(updateID: 1, chatID: -100, text: "123456", chatType: "group")
        #expect(TelegramRouter.route(group, state: &s) == .reply("I only pair with a private chat. Message me directly, not from a group."))
        #expect(s.pairedChat == 0)
        let direct = TelegramUpdate(updateID: 2, chatID: 7, text: "123456", chatType: "private")
        if case .paired(7, _) = TelegramRouter.route(direct, state: &s) {} else { Issue.record("private chat should pair") }
        #expect(TelegramRouter.route(TelegramUpdate(updateID: 3, chatID: 7, text: "status", chatType: "supergroup"), state: &s) == .ignore)
        let parsed = TelegramUpdate(json: ["update_id": 4, "message": ["chat": ["id": -5, "type": "group"], "text": "hi"]])
        #expect(parsed?.chatType == "group")
    }
}
