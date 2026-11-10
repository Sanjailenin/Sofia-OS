import Foundation

public struct MacAction: Equatable {
    public enum Kind: String, CaseIterable {
        case openApp = "open_app", quitApp = "quit_app", switchApp = "switch_app", openURL = "open_url", openPath = "open_path"
        case setVolume = "set_volume", mute, unmute, darkMode = "dark_mode", media, wifi, lockScreen = "lock_screen", screenshot
        case typeText = "type_text"
        case webSearch = "web_search", findFile = "find_file", playMusic = "play_music", playVideo = "play_video", playResult = "play_result", openSettings = "open_settings"
        case clipboardCopy = "clipboard_copy", newNote = "new_note"
        case openDeeplink = "open_deeplink"
        case moveWindow = "move_window"
        case setPreference = "set_preference"
        case focus, hideApp = "hide_app", unhideApp = "unhide_app"
    }

    public static let searchURLs: [String: String] = [
        "google": "https://www.google.com/search?q=", "youtube": "https://www.youtube.com/results?search_query=",
        "maps": "https://www.google.com/maps/search/", "wikipedia": "https://en.wikipedia.org/w/index.php?search=",
        "images": "https://www.google.com/search?tbm=isch&q=", "news": "https://news.google.com/search?q=",
        "scholar": "https://scholar.google.com/scholar?q=",
    ]
    public static let deeplinkSchemes: Set<String> = ["spotify", "slack", "notion", "obsidian", "things", "bear", "todoist", "zoommtg", "msteams", "mailto"]
    public static let settingsPages: [String: String] = [
        "wifi": "com.apple.wifi-settings-extension", "bluetooth": "com.apple.BluetoothSettings", "sound": "com.apple.Sound-Settings.extension",
        "display": "com.apple.Displays-Settings.extension", "battery": "com.apple.Battery-Settings.extension",
        "notifications": "com.apple.Notifications-Settings.extension", "focus": "com.apple.Focus-Settings.extension",
        "privacy": "com.apple.settings.PrivacySecurity.extension", "keyboard": "com.apple.Keyboard-Settings.extension",
        "network": "com.apple.Network-Settings.extension", "general": "com.apple.systempreferences.GeneralSettings",
        "appearance": "com.apple.Appearance-Settings.extension", "wallpaper": "com.apple.Wallpaper-Settings.extension",
    ]

    public static let webSites: [String: String] = [
        "youtube": "https://www.youtube.com", "youtube music": "https://music.youtube.com", "gmail": "https://mail.google.com",
        "google": "https://www.google.com", "google maps": "https://www.google.com/maps", "maps": "https://www.google.com/maps",
        "google drive": "https://drive.google.com", "google docs": "https://docs.google.com", "google calendar": "https://calendar.google.com",
        "netflix": "https://www.netflix.com", "wikipedia": "https://www.wikipedia.org", "reddit": "https://www.reddit.com",
        "twitter": "https://x.com", "x": "https://x.com", "github": "https://github.com", "linkedin": "https://www.linkedin.com",
        "instagram": "https://www.instagram.com", "facebook": "https://www.facebook.com", "amazon": "https://www.amazon.com",
        "chatgpt": "https://chatgpt.com", "prime video": "https://www.primevideo.com", "twitch": "https://www.twitch.tv",
    ]

    public static func site(_ name: String) -> String? {
        let n = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: #"\.com$"#, with: "", options: .regularExpression)
        return webSites[n]
    }

    static let domainPattern = #"^(?:[a-z0-9-]+\.)+[a-z]{2,}$"#
    static let siteNamePattern = #"^[a-z0-9][a-z0-9 .'&-]{0,40}$"#

    public static func youTubeVideos(in html: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #""videoRenderer":\{"videoId":"([A-Za-z0-9_-]{11})""#) else { return [] }
        var seen: [String] = []
        for m in re.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            if let r = Range(m.range(at: 1), in: html), !seen.contains(String(html[r])) { seen.append(String(html[r])) }
        }
        return seen
    }

    public static func isYouTubeResults(_ url: String) -> Bool {
        url.range(of: #"^https://(?:www\.|m\.)?youtube\.com/results\?"#, options: .regularExpression) != nil
    }

    public static func firstYouTubeVideo(in html: String) -> String? {
        for pattern in [#""videoRenderer":\{"videoId":"[A-Za-z0-9_-]{11}""#, #""videoId":"[A-Za-z0-9_-]{11}""#] {
            if let r = html.range(of: pattern, options: .regularExpression) { return String(html[r].suffix(12).dropLast()) }
        }
        return nil
    }

    public static func isDomain(_ s: String) -> Bool { s.lowercased().range(of: domainPattern, options: .regularExpression) != nil }

    static func encode(_ s: String) -> String? {
        var allowed = CharacterSet.urlQueryAllowed; allowed.remove(charactersIn: "&+=?#/!")
        return s.addingPercentEncoding(withAllowedCharacters: allowed)
    }

    public static func websiteURL(_ name: String) -> URL? {
        let n = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let known = site(n) { return URL(string: known) }
        if isDomain(n) { return URL(string: "https://" + n) }
        guard n.range(of: siteNamePattern, options: .regularExpression) != nil, let q = encode("\\" + n + " official site") else { return nil }
        return URL(string: "https://duckduckgo.com/?q=" + q)
    }

    public static func searchURL(_ query: String, site: String) -> URL? {
        let s = site.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let base = searchURLs[s] { return encode(query).flatMap { URL(string: base + $0) } }
        guard s.range(of: siteNamePattern, options: .regularExpression) != nil else { return nil }
        let bang = s.replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.(com|org|net|io|co|tv|de|fr|co\.uk|in)$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9]"#, with: "", options: .regularExpression)
        guard !bang.isEmpty, let q = encode("!" + bang + " " + query) else { return nil }
        return URL(string: "https://duckduckgo.com/?q=" + q)
    }
    public let kind: Kind
    public let target: String
    public let value: String

    public static let scriptyExtensions: Set<String> = [
        "app", "command", "sh", "bash", "zsh", "fish", "csh", "ksh", "tool", "pkg", "mpkg", "dmg", "scpt", "scptd", "applescript", "workflow", "wflow", "action", "shortcut", "terminal",
        "py", "rb", "pl", "php", "js", "jar", "jnlp", "exe", "fileloc", "webloc", "inetloc", "url", "prefpane", "saver", "qlgenerator", "mobileconfig", "kext", "plugin", "bundle",
        "osax", "service", "xpc", "appex", "framework", "dylib", "so", "mdimporter", "wdgt",
    ]

    public static func openRefusal(path: String, isDirectory: Bool, isExecutable: Bool) -> String? {
        let ext = (path as NSString).pathExtension.lowercased()
        if ext == "app" { return "use open app for apps" }
        if scriptyExtensions.contains(ext) { return "that kind of file can run code, so I don't open it this way" }
        if !isDirectory, isExecutable { return "programs aren't opened this way" }
        return nil
    }

    public init?(_ raw: [String: Any]) {
        guard let k = Kind(rawValue: raw["action"] as? String ?? "") else { return nil }
        let target = Self.text(raw["target"]).trimmingCharacters(in: .whitespacesAndNewlines)
        var value = Self.text(raw["value"]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if k == .setVolume { value = Self.volume(value) }
        if [.openApp, .switchApp].contains(k), let url = Self.site(target) ?? (Self.isDomain(target) ? "https://" + target.lowercased() : nil) {
            self.kind = .openURL; self.target = url; self.value = ""; return
        }
        switch k {
        case .openApp, .quitApp, .switchApp:
            guard target.range(of: #"^[\p{L}\p{N} .&+'’()-]{1,60}$"#, options: .regularExpression) != nil else { return nil }
        case .openURL:
            guard let u = URL(string: target), ["http", "https"].contains(u.scheme?.lowercased() ?? ""), u.host != nil else { return nil }
        case .openDeeplink:
            guard target.count <= 500, let u = URL(string: target), let scheme = u.scheme?.lowercased(), Self.deeplinkSchemes.contains(scheme) else { return nil }
        case .openPath:
            guard (target.hasPrefix("~") || target.hasPrefix("/")), target.count <= 400, !target.contains(".."),
                  !Self.scriptyExtensions.contains((target as NSString).pathExtension.lowercased()) else { return nil }
        case .setVolume:
            guard value == "up" || value == "down" || (Int(value).map { (0...100).contains($0) } ?? false) else { return nil }
        case .darkMode:
            guard ["on", "off", "toggle"].contains(value) else { return nil }
        case .media:
            guard ["play_pause", "next", "previous"].contains(value) else { return nil }
        case .wifi:
            guard ["on", "off"].contains(value) else { return nil }
        case .typeText:
            guard !target.isEmpty, target.count <= 500 else { return nil }
        case .webSearch:
            guard !target.isEmpty, target.count <= 200, Self.searchURL(target, site: value.isEmpty ? "google" : value) != nil else { return nil }
            self.kind = k; self.target = target; self.value = value.isEmpty ? "google" : value; return
        case .findFile:
            guard !target.isEmpty, target.count <= 100, target.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\*?")) == nil else { return nil }
        case .playMusic, .playVideo:
            guard !target.isEmpty, target.count <= 120 else { return nil }
        case .playResult:
            guard let n = Int(value), (1...20).contains(n), target.count <= 120 else { return nil }
        case .openSettings:
            guard Self.settingsPages[target.lowercased()] != nil else { return nil }
            self.kind = k; self.target = target.lowercased(); self.value = value; return
        case .clipboardCopy, .newNote:
            guard !target.isEmpty, target.count <= 2000 else { return nil }
        case .mute, .unmute, .lockScreen, .screenshot:
            break
        case .moveWindow:
            guard target.lowercased() == "front" || target.range(of: #"^[\p{L}\p{N} .&+'’()-]{1,60}$"#, options: .regularExpression) != nil, WindowGeometry.placements.contains(value) else { return nil }
        case .setPreference:
            guard let p = Preference(rawValue: target.lowercased()), let v = p.normalize(Self.text(raw["value"])) else { return nil }
            self.kind = k; self.target = p.rawValue; self.value = v; return
        case .focus:
            guard ["on", "off"].contains(value) else { return nil }
        case .hideApp, .unhideApp:
            guard target.range(of: #"^[\p{L}\p{N} .&+'’()-]{1,60}$"#, options: .regularExpression) != nil else { return nil }
        }
        self.kind = k; self.target = target; self.value = value
    }

    static func volume(_ v: String) -> String {
        if let r = v.range(of: #"\d{1,3}"#, options: .regularExpression) { return String(v[r]) }
        if v.contains("up") || v.contains("louder") || v.contains("higher") { return "up" }
        if v.contains("down") || v.contains("quieter") || v.contains("lower") { return "down" }
        return v
    }

    static func text(_ any: Any?) -> String {
        switch any {
        case let s as String: return s
        case let n as NSNumber: return CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "on" : "off") : n.stringValue
        default: return ""
        }
    }

    public static func list(from raw: Any?) -> (actions: [MacAction], rejected: Int) {
        let items = raw as? [[String: Any]] ?? []
        let ok = items.compactMap(MacAction.init)
        return (Array(ok.prefix(8)), items.count - min(ok.count, 8))
    }

    public static func appleScriptString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") + "\""
    }

    public var summary: String {
        switch kind {
        case .openApp: return "open \(target)"
        case .quitApp: return "quit \(target)"
        case .switchApp: return "switch to \(target)"
        case .openURL: return "open \(URL(string: target)?.host ?? target)"
        case .openPath: return "open \((target as NSString).lastPathComponent)"
        case .setVolume: return value == "up" ? "volume up" : value == "down" ? "volume down" : "volume \(value)"
        case .mute: return "mute"
        case .unmute: return "unmute"
        case .darkMode: return "dark mode \(value)"
        case .media: return value.replacingOccurrences(of: "_", with: "/")
        case .wifi: return "Wi-Fi \(value)"
        case .lockScreen: return "lock the screen"
        case .screenshot: return "screenshot"
        case .typeText: return "type text"
        case .webSearch: return "search \(value) for \(target)"
        case .findFile: return "find \(target)"
        case .playMusic: return "play \(target)"
        case .playVideo: return "play \(target) on YouTube"
        case .playResult: return "play video \(value) of the results"
        case .openSettings: return "open \(target) settings"
        case .clipboardCopy: return "copy to clipboard"
        case .moveWindow: return "move \(target) \(value.replacingOccurrences(of: "_", with: " "))"
        case .setPreference: return "set \(Preference(rawValue: target)?.spokenName ?? target) to \(value)"
        case .focus: return "focus \(value)"
        case .hideApp: return "hide \(target)"
        case .unhideApp: return "show \(target)"
        case .newNote: return "make a note"
        case .openDeeplink: return "open \(URL(string: target)?.scheme ?? "app") link"
        }
    }
}
