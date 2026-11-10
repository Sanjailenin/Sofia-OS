import Foundation

public enum RemoteCommand: Equatable {
    case status
    case screenPeek
    case lock
    case sendFile(String)
    case listFiles(String)
    case download(URL)
    case openApp(String)
    case quitApp(String)
    case volume(String)
    case mute, unmute
    case media(String)
    case stopRemote, startRemote
    case help

    static let patterns: [(NSRegularExpression, (NSTextCheckingResult, String) -> RemoteCommand?)] = {
        func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: .caseInsensitive) }
        func group(_ m: NSTextCheckingResult, _ i: Int, _ s: String) -> String { Range(m.range(at: i), in: s).map { String(s[$0]).trimmingCharacters(in: CharacterSet(charactersIn: " \"'“”.,!?")) } ?? "" }
        return [
            (re(#"^(?:/)?(?:help|\?|what can you do)\W*$"#), { _, _ in .help }),
            (re(#"^(?:/)?(?:stop|disable|pause) remote\W*$"#), { _, _ in .stopRemote }),
            (re(#"^(?:/)?(?:start|enable|resume) remote\W*$"#), { _, _ in .startRemote }),
            (re(#"^(?:/)?(?:status|is (?:my )?(?:mac|laptop|computer) (?:on|awake|up|there)|are you (?:on|there|awake)|battery)\W*$"#), { _, _ in .status }),
            (re(#"^(?:/)?(?:screen(?:shot)?|peek|what'?s on (?:my|the) screen|show (?:me )?(?:my|the) screen)\W*$"#), { _, _ in .screenPeek }),
            (re(#"^(?:/)?(?:lock(?: (?:my |the )?(?:mac|laptop|screen|computer))?)\W*$"#), { _, _ in .lock }),
            (re(#"^(?:/)?(?:download|save|get)\s+(https://\S+)(?:\s+(?:to|on|onto) (?:my )?(?:mac|laptop|downloads))?\W*$"#), { m, s in URL(string: group(m, 1, s)).map { .download($0) } }),
            (re(#"^(?:/)?(?:send(?: me)?|get me|give me|share)\s+(?:the |my |a )?(?:file |document |pdf |photo |picture )?(.+?)(?:\s+(?:from|on) (?:my )?(?:mac|laptop|computer))?\W*$"#), { m, s in let t = group(m, 1, s); return t.isEmpty ? nil : .sendFile(t) }),
            (re(#"^(?:/)?(?:find|list|search(?: for)?|look for|which files? (?:match|are called))\s+(?:files? )?(?:called |named |matching )?(.+?)(?:\s+(?:from|on) (?:my )?(?:mac|laptop|computer))?\W*$"#), { m, s in let t = group(m, 1, s); return t.isEmpty ? nil : .listFiles(t) }),
            (re(#"^(?:/)?(?:open|launch|start)\s+(.+?)(?:\s+(?:on|from) (?:my )?(?:mac|laptop))?\W*$"#), { m, s in let t = group(m, 1, s); return t.isEmpty ? nil : .openApp(t) }),
            (re(#"^(?:/)?(?:quit|close|kill)\s+(.+?)(?:\s+(?:on|from) (?:my )?(?:mac|laptop))?\W*$"#), { m, s in let t = group(m, 1, s); return t.isEmpty ? nil : .quitApp(t) }),
            (re(#"^(?:/)?(?:volume|set (?:the )?volume(?: to)?)\s*(\d{1,3}|up|down)\W*$"#), { m, s in .volume(group(m, 1, s).lowercased()) }),
            (re(#"^(?:/)?mute\W*$"#), { _, _ in .mute }),
            (re(#"^(?:/)?unmute\W*$"#), { _, _ in .unmute }),
            (re(#"^(?:/)?(?:(play|pause|play[ /]?pause|resume)(?: (?:the )?music)?|(next|skip)(?: (?:track|song))?|(previous|back)(?: (?:track|song))?)\W*$"#), { m, s in
                let a = group(m, 1, s).lowercased(), n = group(m, 2, s), p = group(m, 3, s)
                return !n.isEmpty ? .media("next") : !p.isEmpty ? .media("previous") : a.isEmpty ? nil : .media("play_pause") }),
        ]
    }()

    public static func parse(_ text: String) -> RemoteCommand? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= 400 else { return nil }
        let range = NSRange(t.startIndex..., in: t)
        for (re, make) in patterns {
            if let m = re.firstMatch(in: t, range: range), let c = make(m, t) { return c }
        }
        return nil
    }

    public var macAction: MacAction? {
        switch self {
        case .lock: return MacAction(["action": "lock_screen"])
        case .openApp(let a): return MacAction(["action": "open_app", "target": a])
        case .quitApp(let a): return MacAction(["action": "quit_app", "target": a])
        case .volume(let v): return MacAction(["action": "set_volume", "value": v])
        case .mute: return MacAction(["action": "mute"])
        case .unmute: return MacAction(["action": "unmute"])
        case .media(let v): return MacAction(["action": "media", "value": v])
        default: return nil
        }
    }

    public static let helpText = """
    I can do these from here, no model needed:
    • status — is the Mac on, battery, what's in front
    • screen — a screenshot of the Mac
    • send me <file name or words> — the file, from your allowed folders
    • find <words> — list matching files
    • download https://… — save a link to Downloads
    • lock, open <app>, quit <app>, volume 30, mute, play, next
    • stop remote / start remote
    Anything else goes to the assistant.
    """
}
