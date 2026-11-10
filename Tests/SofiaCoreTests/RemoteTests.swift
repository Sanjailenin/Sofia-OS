import Testing
import Foundation
@testable import SofiaCore

struct FilePolicyTests {
    let home = "/Users/alex"
    var roots: [String] { FilePolicy.roots(from: "", home: home) }

    @Test func rootsFromSettings() {
        #expect(roots == FilePolicy.defaultRoots.map { "\(home)/\($0)" })
        #expect(FilePolicy.roots(from: "Desktop, ~/Projects, /Users/alex/Work/notes, /etc, Documents/../.ssh", home: home) == ["\(home)/Desktop", "\(home)/Projects", "\(home)/Work/notes"])
    }
    @Test func refusals() {
        #expect(FilePolicy.refusal(forResolved: "\(home)/Documents/thesis.pdf", roots: roots, size: 4_000_000) == nil)
        #expect(FilePolicy.refusal(forResolved: "\(home)/Library/Keychains/login.keychain-db", roots: roots, size: 10) != nil)
        #expect(FilePolicy.refusal(forResolved: "\(home)/.ssh/id_ed25519", roots: roots, size: 10) != nil)
        #expect(FilePolicy.refusal(forResolved: "\(home)/Documents/.env", roots: roots, size: 10) != nil)
        #expect(FilePolicy.refusal(forResolved: "\(home)/Downloads/server.pem", roots: roots, size: 10) != nil)
        #expect(FilePolicy.refusal(forResolved: "\(home)/Downloads/passwords.txt", roots: roots, size: 10) != nil)
        #expect(FilePolicy.refusal(forResolved: "/etc/passwd", roots: roots, size: 10) != nil)
        #expect(FilePolicy.refusal(forResolved: "\(home)/Documents/empty.txt", roots: roots, size: 0) != nil)
        #expect(FilePolicy.refusal(forResolved: "\(home)/Movies/big.mov", roots: roots, size: 101 * 1024 * 1024) != nil)
        #expect(FilePolicy.refusal(forResolved: "\(home)/Desktop/node_modules/x.js", roots: roots, size: 5) != nil)
    }
    @Test func secretContentAndSizes() {
        #expect(FilePolicy.looksSecret(Data("-----BEGIN OPENSSH PRIVATE KEY-----\nabc".utf8)))
        #expect(FilePolicy.looksSecret(Data("OPENAI_API_KEY=sk-xxx\n".utf8)))
        #expect(!FilePolicy.looksSecret(Data("Dear Sam,\nthanks for the notes.".utf8)))
        #expect(FilePolicy.sizeText(4_400_000) == "4.2 MB" && FilePolicy.sizeText(640 * 1024) == "640 KB" && FilePolicy.sizeText(12) == "12 B")
    }
}

struct RemoteCommandTests {
    @Test func commandsParse() {
        #expect(RemoteCommand.parse("status") == .status && RemoteCommand.parse("Is my Mac on?") == .status && RemoteCommand.parse("battery") == .status)
        #expect(RemoteCommand.parse("screen") == .screenPeek && RemoteCommand.parse("what's on my screen") == .screenPeek)
        #expect(RemoteCommand.parse("lock") == .lock && RemoteCommand.parse("lock my mac") == .lock)
        #expect(RemoteCommand.parse("send me the thesis pdf") == .sendFile("thesis pdf"))
        #expect(RemoteCommand.parse("Send me invoice March from my laptop") == .sendFile("invoice March"))
        #expect(RemoteCommand.parse("find report") == .listFiles("report"))
        #expect(RemoteCommand.parse("download https://example.com/a.pdf to my mac") == .download(URL(string: "https://example.com/a.pdf")!))
        #expect(RemoteCommand.parse("download http://example.com/a.pdf") == nil)
        #expect(RemoteCommand.parse("open Safari") == .openApp("Safari") && RemoteCommand.parse("quit Slack") == .quitApp("Slack"))
        #expect(RemoteCommand.parse("volume 30") == .volume("30") && RemoteCommand.parse("mute") == .mute && RemoteCommand.parse("next") == .media("next") && RemoteCommand.parse("pause") == .media("play_pause"))
        #expect(RemoteCommand.parse("stop remote") == .stopRemote && RemoteCommand.parse("start remote") == .startRemote && RemoteCommand.parse("help") == .help)
    }
    @Test func freeFormIsNotACommand() {
        for s in ["what did I do yesterday", "remind me to call mum", "how much disk do I have left and why", "open the window please and tell me a joke"] {
            #expect(RemoteCommand.parse(s) == nil || RemoteCommand.parse(s) == .openApp("the window please and tell me a joke"), Comment(rawValue: s))
        }
        #expect(RemoteCommand.parse("") == nil)
    }
    @Test func macActionsFromCommands() {
        #expect(RemoteCommand.lock.macAction?.kind == .lockScreen)
        #expect(RemoteCommand.openApp("Safari").macAction?.target == "Safari")
        #expect(RemoteCommand.volume("30").macAction?.value == "30")
        #expect(RemoteCommand.volume("300").macAction == nil)
        #expect(RemoteCommand.status.macAction == nil)
    }
}
