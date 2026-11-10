import Foundation

public enum QuickCommand {
    static let polite = #"^(?:(?:please|can you|could you|hey)\s+)*(.+?)(?:\s+(?:please|now|thanks|thank you))*[.!?]*$"#

    static let table: [(pattern: String, action: [String: String], reply: String)] = [
        (#"mute(?: the)?(?: sound| audio| volume| mac)?"#, ["action": "mute"], "Muted."),
        (#"unmute(?: the)?(?: sound| audio| volume| mac)?"#, ["action": "unmute"], "Unmuted."),
        (#"(?:pause|stop)(?: the)?(?: music| song| video| playback)?"#, ["action": "media", "value": "play_pause"], "Paused."),
        (#"(?:resume|play|start)(?: the| this)?(?: music| song| video| playback)?(?:\s+(?:on|in)\s+(?:the|this)\s+(?:screen|speech|page|tab))?(?: here)?"#, ["action": "media", "value": "play_pause"], "Playing."),
        (#"(?:pause|stop)(?: the| this)? video(?:\s+(?:on|in)\s+(?:the|this)\s+(?:screen|speech|page|tab))?(?: here)?"#, ["action": "media", "value": "play_pause"], "Paused."),
        (#"(?:next|skip)(?: the)?(?: song| track)?"#, ["action": "media", "value": "next"], "Next one."),
        (#"(?:previous|last)(?: song| track)?"#, ["action": "media", "value": "previous"], "Previous one."),
        (#"lock(?: the)?(?: screen| mac| computer)?"#, ["action": "lock_screen"], "Locking."),
        (#"(?:turn |switch )?(?:on )?dark mode(?: on)?"#, ["action": "dark_mode", "value": "on"], "Dark mode is on."),
        (#"(?:turn |switch )?(?:off )?dark mode off|(?:turn |switch )?off dark mode|light mode"#, ["action": "dark_mode", "value": "off"], "Dark mode is off."),
        (#"(?:turn (?:the )?)?volume up|louder|turn it up"#, ["action": "set_volume", "value": "up"], "Louder."),
        (#"(?:turn (?:the )?)?volume down|quieter|turn it down"#, ["action": "set_volume", "value": "down"], "Quieter."),
    ]

    public static func match(_ text: String) -> (action: MacAction, reply: String)? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard t.count <= 100, let core = capture(polite, in: t) else { return nil }
        for row in table where full(row.pattern, core) {
            if let a = MacAction(row.action) { return (a, row.reply) }
        }
        if let n = capture(#"^(?:set |turn )?(?:the )?volume(?: to| at)? (\d{1,3})(?: percent| ?%)?$"#, in: core), let a = MacAction(["action": "set_volume", "value": n]) {
            return (a, "Volume \(n).")
        }
        if let name = capture(#"^(?:open|go to|launch|show me|pull up)\s+(?:the\s+)?(.+?)(?:\s+website|\s+site)?$"#, in: core), let url = MacAction.site(name) ?? (MacAction.isDomain(name) ? "https://" + name : nil), let a = MacAction(["action": "open_url", "target": url]) {
            return (a, "Opening \(display(name)).")
        }
        for (pattern, queryFirst) in [(#"^(?:search|look up|find)\s+(?:for\s+)?(.+?)\s+(?:on|in)\s+(youtube|google|maps|wikipedia|amazon|reddit|github|imdb|spotify|netflix|ebay|linkedin|[a-z0-9-]+\.[a-z.]{2,})$"#, true),
                                     (#"^search\s+(youtube|google|maps|wikipedia|amazon|reddit|github|imdb|spotify|netflix|ebay|linkedin|[a-z0-9-]+\.[a-z.]{2,})\s+for\s+(.+)$"#, false),
                                     (#"^(?:open|go to)\s+(youtube|google|maps|wikipedia|amazon|reddit|github|imdb|spotify|netflix|ebay|linkedin|[a-z0-9-]+\.[a-z.]{2,})\s+and\s+search\s+(?:for\s+)?(.+)$"#, false),
                                     ] {
            guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: core, range: NSRange(core.startIndex..., in: core)),
                  let r1 = Range(m.range(at: 1), in: core), let r2 = Range(m.range(at: 2), in: core) else { continue }
            let (query, site) = queryFirst ? (String(core[r1]), String(core[r2])) : (String(core[r2]), String(core[r1]))
            if let a = MacAction(["action": "web_search", "target": query, "value": site]) { return (a, "Searching \(display(site)) for \(query).") }
        }
        if let q = capture(#"^(?:play|watch|put on)\s+(.+?)\s+(?:on|from)\s+youtube$"#, in: core), let a = MacAction(["action": "play_video", "target": q]) {
            return (a, "Playing \(q) on YouTube.")
        }
        if let q = capture(#"^(?:play|put on)\s+(.+?)\s+(?:on|in)\s+spotify$"#, in: core), let a = MacAction(["action": "play_music", "target": q, "value": "spotify"]) {
            return (a, "Looking up \(q) on Spotify.")
        }
        if !firstResult(text), resultIndex(text) == nil, !mentionsScreen(core), let q = capture(#"^(?:play|put on|watch)\s+(?:me\s+)?(.+)$"#, in: core), q.count >= 3,
           q.range(of: #"^(?:the |some |a )?(?:music|song|video|playback|it|that|this)$"#, options: .regularExpression) == nil,
           let a = MacAction(["action": "play_video", "target": q]) {
            return (a, "Playing \(q).")
        }
        return nil
    }

    public static func screenGoal(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard t.count <= 200 else { return false }
        let patterns = [
            #"^(?:(?:please|can you|could you)\s+)*(?:click|double[- ]click|right[- ]click|tap|press the|scroll|skip(?: the)? ad|close the|dismiss|select the|choose the|check the box|fill (?:in|out))\b"#,
            #"^(?:(?:please|can you|could you)\s+)*(?:what(?:'s| is) on (?:my|the) screen|read (?:my|the|this) screen|describe (?:my|the) screen|look at (?:my|the) screen|what am i looking at|what do you see)"#,
        ]
        return patterns.contains { t.range(of: $0, options: .regularExpression) != nil }
    }

    static let ordinals: [String: Int] = ["first": 1, "1st": 1, "one": 1, "second": 2, "2nd": 2, "two": 2, "third": 3, "3rd": 3, "three": 3, "fourth": 4, "4th": 4, "four": 4, "fifth": 5, "5th": 5, "five": 5, "sixth": 6, "6th": 6, "seventh": 7, "7th": 7, "eighth": 8, "8th": 8, "ninth": 9, "9th": 9, "tenth": 10, "10th": 10]

    public static func mentionsScreen(_ t: String) -> Bool {
        t.range(of: #"\b(?:on|in|from)\s+(?:the|this|my)\s+(?:screen|speech|page|tab|list)\b|\bhere$"#, options: .regularExpression) != nil
    }

    public static func resultIndex(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pattern = #"^(?:(?:please|can you|could you)\s+)*(?:play|open|click(?: on)?|watch|start|put on)\s+(?:the\s+)?(first|1st|second|2nd|third|3rd|fourth|4th|fifth|5th|sixth|6th|seventh|7th|eighth|8th|ninth|9th|tenth|10th)(?:\s+(?:one|video|result|link))?(?:\s+(?:on|in|from)\s+(?:the|this|my)\s+(?:screen|speech|page|tab|list))?(?:\s+(?:here|please))?[.!]*$"#
        guard let word = capture(pattern, in: t) else {
            if let n = capture(#"^(?:play|open|click(?: on)?|watch)\s+(?:video|result|number)\s+(\d{1,2})\b"#, in: t) { return Int(n) }
            return nil
        }
        return ordinals[word]
    }

    public static func firstResult(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return t.range(of: #"^(?:(?:please|can you|could you)\s+)*(?:play|open|click(?: on)?|watch|start)\s+(?:the\s+)?(?:first|top|1st)(?:\s+one|\s+video|\s+result)?(?:\s+please)?[.!]*$"#, options: .regularExpression) != nil
    }

    static func display(_ site: String) -> String {
        if MacAction.isDomain(site) { return site.lowercased() }
        return ["youtube": "YouTube", "gmail": "Gmail", "chatgpt": "ChatGPT", "github": "GitHub", "linkedin": "LinkedIn", "imdb": "IMDb", "ebay": "eBay"][site.lowercased()] ?? site.capitalized
    }

    static func full(_ pattern: String, _ s: String) -> Bool {
        s.range(of: "^(?:" + pattern + ")$", options: .regularExpression) != nil
    }

    static func capture(_ pattern: String, in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }
}
