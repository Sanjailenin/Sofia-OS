import AppKit
import SofiaCore

@MainActor
enum MacRunner {
    static func perform(_ actions: [MacAction]) async -> (failed: [String], notes: [String]) {
        var failed: [String] = [], notes: [String] = []
        for a in actions {
            do { if let note = try await run(a) { notes.append(note) } } catch { failed.append("\(a.summary): \(error.localizedDescription)") }
        }
        return (failed, notes)
    }

    struct Failure: LocalizedError { let errorDescription: String? ; init(_ s: String) { errorDescription = s } }

    @discardableResult
    private static func run(_ a: MacAction) async throws -> String? {
        switch a.kind {
        case .openApp:
            if let url = appURL(named: a.target) {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            } else if let site = MacAction.websiteURL(a.target) {
                guard NSWorkspace.shared.open(site) else { throw Failure("couldn't open the \(a.target) website") }
                return "There is no \(a.target) app, so its website is open in the browser."
            } else { throw Failure("no app called \(a.target)") }
        case .quitApp:
            let apps = running(named: a.target)
            guard !apps.isEmpty else { throw Failure("\(a.target) isn't open") }
            apps.forEach { $0.terminate() }
        case .switchApp:
            if let app = running(named: a.target).first { app.activate(options: [.activateAllWindows]) }
            else if let url = appURL(named: a.target) { _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) }
            else { throw Failure("no app called \(a.target)") }
        case .openURL, .openDeeplink:
            guard let u = URL(string: a.target) else { throw Failure("bad address") }
            NSWorkspace.shared.open(u)
        case .openPath:
            let path = URL(fileURLWithPath: (a.target as NSString).expandingTildeInPath).resolvingSymlinksInPath().path
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { throw Failure("not found") }
            if let why = MacAction.openRefusal(path: path, isDirectory: isDir.boolValue, isExecutable: FileManager.default.isExecutableFile(atPath: path)) { throw Failure(why) }
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .setVolume:
            let level = a.value == "up" ? "(output volume of (get volume settings)) + 10" : a.value == "down" ? "(output volume of (get volume settings)) - 10" : "\(Int(a.value) ?? 50)"
            try script("set volume output volume \(level)\nset volume without output muted")
        case .mute:
            try script("set volume with output muted")
        case .unmute:
            try script("set volume without output muted")
        case .darkMode:
            let to = a.value == "toggle" ? "not dark mode" : (a.value == "on" ? "true" : "false")
            try script("tell application \"System Events\" to tell appearance preferences to set dark mode to \(to)")
        case .media:
            let verb = ["play_pause": "playpause", "next": "next track", "previous": "previous track"][a.value] ?? "playpause"
            if isRunning("com.spotify.client") { try script("tell application \"Spotify\" to \(verb)") }
            else if isRunning("com.apple.Music") { try script("tell application \"Music\" to \(verb)") }
            else { mediaKey(["play_pause": 16, "next": 17, "previous": 18][a.value] ?? 16) }
        case .wifi:
            guard let dev = wifiDevice() else { throw Failure("no Wi-Fi hardware found") }
            try tool("/usr/sbin/networksetup", ["-setairportpower", dev, a.value])
        case .lockScreen:
            try tool("/usr/bin/pmset", ["displaysleepnow"])
        case .screenshot:
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            let out = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Sofia screenshot \(f.string(from: Date())).png").path
            try tool("/usr/sbin/screencapture", ["-x", out])
        case .typeText:
            if let why = ComputerGuard.refusal(bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier) { throw Failure(why) }
            try script("tell application \"System Events\" to keystroke \(MacAction.appleScriptString(a.target))")
        case .webSearch:
            guard let u = MacAction.searchURL(a.target, site: a.value) else { throw Failure("unknown search site") }
            NSWorkspace.shared.open(u)
        case .findFile:
            guard let hit = findFile(a.target) else { throw Failure("nothing called \(a.target) in your home folder") }
            NSWorkspace.shared.activateFileViewerSelecting([hit])
            return "Found \(hit.lastPathComponent) in \(hit.deletingLastPathComponent().lastPathComponent)."
        case .playMusic:
            var allowed = CharacterSet.urlQueryAllowed; allowed.remove(charactersIn: "&+=?#/:")
            let q = a.target.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            if a.value.contains("spotify"), appURL(named: "Spotify") != nil, let u = URL(string: "spotify:search:\(q)") {
                NSWorkspace.shared.open(u)
                return "Spotify is showing results for \(a.target); pick one to play."
            }
            if a.value.contains("apple"), let u = URL(string: "https://music.apple.com/search?term=\(q)") {
                NSWorkspace.shared.open(u)
                return "Apple Music is showing results for \(a.target)."
            }
            return try await playYouTube(a.target)
        case .playVideo:
            return try await playYouTube(a.target)
        case .playResult:
            let n = Int(a.value) ?? 1
            let front = frontBrowserURL()
            let page: URL? = front.flatMap { MacAction.isYouTubeResults($0.url) ? URL(string: $0.url) : nil } ?? (a.target.isEmpty ? nil : MacAction.searchURL(a.target, site: "youtube"))
            guard let page else { throw Failure("there is no YouTube results page open and no recent YouTube search") }
            let ids = MacAction.youTubeVideos(in: try await youTubePage(page))
            guard ids.count >= n, let watch = URL(string: "https://www.youtube.com/watch?v=\(ids[n - 1])") else { throw Failure("that page doesn't have \(n) videos") }
            if let front, MacAction.isYouTubeResults(front.url), (try? script(front.set(watch.absoluteString))) != nil { return "Playing video \(n) of the results." }
            NSWorkspace.shared.open(watch)
            return "Playing video \(n) of the results."
        case .openSettings:
            guard let id = MacAction.settingsPages[a.target], let u = URL(string: "x-apple.systempreferences:\(id)") else { throw Failure("unknown settings page") }
            NSWorkspace.shared.open(u)
        case .clipboardCopy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(a.target, forType: .string)
        case .moveWindow:
            return try WindowMover.move(app: a.target, placement: a.value)
        case .hideApp:
            let apps = running(named: a.target); guard !apps.isEmpty else { throw Failure("\(a.target) isn't open") }
            apps.forEach { $0.hide() }
        case .unhideApp:
            let apps = running(named: a.target); guard !apps.isEmpty else { throw Failure("\(a.target) isn't open") }
            apps.forEach { $0.unhide() }
        case .focus:
            let name = a.value == "on" ? "Sofia Focus On" : "Sofia Focus Off"
            do { try tool("/usr/bin/shortcuts", ["run", name]) }
            catch { throw Failure("there's no Shortcut called “\(name)” yet; make one in Shortcuts with the action Set Focus, and one called “Sofia Focus Off”") }
        case .setPreference:
            return Preferences.apply(key: a.target, value: a.value)
        case .newNote:
            let html = a.target.components(separatedBy: .newlines).map { line in
                "<div>" + line.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") + "</div>"
            }.joined()
            try script("tell application \"Notes\" to make new note with properties {body:\(MacAction.appleScriptString(html))}")
        }
        return nil
    }

    static func findFile(_ name: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var out = (try? tool("/usr/bin/mdfind", ["-onlyin", home, "-name", name])) ?? ""
        if out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let words = name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 2 }.prefix(6)
            guard !words.isEmpty else { return nil }
            let query = words.map { "kMDItemFSName == \"*\($0)*\"cd" }.joined(separator: " && ")
            out = (try? tool("/usr/bin/mdfind", ["-onlyin", home, query])) ?? ""
        }
        let want = name.lowercased()
        let hits = out.split(separator: "\n").map(String.init).filter { p in
            let rel = p.dropFirst(home.count)
            return !rel.hasPrefix("/Library") && !rel.contains("/.") && !rel.contains("/node_modules/")
        }.prefix(300)
        func used(_ p: String) -> Date { (try? URL(fileURLWithPath: p).resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate) ?? .distantPast }
        let exact = hits.filter { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased() == want }
        let pick = (exact.isEmpty ? Array(hits) : exact).max { used($0) < used($1) }
        return pick.map { URL(fileURLWithPath: $0) }
    }

    private static let appFolders = ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities",
                                     FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]

    static func appURL(named name: String) -> URL? {
        let want = name.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ".app", with: "")
        var partial: URL?
        for folder in appFolders {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: folder) else { continue }
            for item in items where item.hasSuffix(".app") {
                let base = item.dropLast(4).lowercased().replacingOccurrences(of: " ", with: "")
                let url = URL(fileURLWithPath: folder).appendingPathComponent(item)
                if base == want { return url }
                if partial == nil, base.hasPrefix(want), want.count >= 3 { partial = url }
            }
        }
        return partial
    }

    private static func running(named name: String) -> [NSRunningApplication] {
        let want = name.lowercased().replacingOccurrences(of: " ", with: "")
        return NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier != Bundle.main.bundleIdentifier &&
            ($0.localizedName ?? "").lowercased().replacingOccurrences(of: " ", with: "") == want
        }
    }

    static func youTubePage(_ url: URL) async throws -> String {
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        req.setValue("en", forHTTPHeaderField: "Accept-Language")
        let (data, _) = try await URLSession.shared.data(for: req)
        return String(decoding: data, as: UTF8.self)
    }

    struct BrowserTab { let url: String; let set: (String) -> String }

    static func frontBrowserURL() -> BrowserTab? {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return nil }
        let chromium = ["com.google.Chrome": "Google Chrome", "com.brave.Browser": "Brave Browser", "com.microsoft.edgemac": "Microsoft Edge", "company.thebrowser.Browser": "Arc"]
        if let app = chromium[id], let url = try? script("tell application \"\(app)\" to return URL of active tab of front window"), !url.isEmpty {
            return BrowserTab(url: url) { "tell application \"\(app)\" to set URL of active tab of front window to \(MacAction.appleScriptString($0))" }
        }
        if id == "com.apple.Safari", let url = try? script("tell application \"Safari\" to return URL of front document"), !url.isEmpty {
            return BrowserTab(url: url) { "tell application \"Safari\" to set URL of front document to \(MacAction.appleScriptString($0))" }
        }
        return nil
    }

    static func playYouTube(_ what: String) async throws -> String {
        guard let search = MacAction.searchURL(what, site: "youtube") else { throw Failure("couldn't search YouTube") }
        if let html = try? await youTubePage(search), let id = MacAction.firstYouTubeVideo(in: html), let watch = URL(string: "https://www.youtube.com/watch?v=\(id)") {
            NSWorkspace.shared.open(watch)
            return "Playing the top YouTube result for \(what)."
        }
        NSWorkspace.shared.open(search)
        return "Couldn't pick a video, so the YouTube results for \(what) are open."
    }

    static func mediaKey(_ key: Int32) {
        for down in [true, false] {
            let flags: Int = down ? 0xA00 : 0xB00
            let data1 = Int((key << 16) | Int32(flags))
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)), timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    private static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    @discardableResult
    nonisolated static func script(_ source: String) throws -> String {
        var err: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&err)
        if let err {
            let msg = err[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
            let code = err[NSAppleScript.errorNumber] as? Int ?? 0
            throw Failure(code == -1743 ? "needs permission in System Settings → Privacy & Security → Automation" : msg)
        }
        return result?.stringValue ?? ""
    }

    @discardableResult
    nonisolated static func tool(_ path: String, _ args: [String]) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let deadline = Date().addingTimeInterval(30)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if p.isRunning { p.terminate(); throw Failure("took too long") }
        let out = String(data: data, encoding: .utf8) ?? ""
        guard p.terminationStatus == 0 else { throw Failure(out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "failed" : String(out.prefix(120))) }
        return out
    }

    private static func wifiDevice() -> String? {
        guard let out = try? tool("/usr/sbin/networksetup", ["-listallhardwareports"]) else { return nil }
        let lines = out.components(separatedBy: "\n")
        for (i, l) in lines.enumerated() where l.contains("Wi-Fi") || l.contains("AirPort") {
            if i + 1 < lines.count, lines[i + 1].hasPrefix("Device: ") { return String(lines[i + 1].dropFirst(8)) }
        }
        return nil
    }

    nonisolated static func runTool(_ path: String, _ args: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) { try tool(path, args) }.value
    }
}
