import AppKit
import IOKit.pwr_mgt
import SofiaCore

@MainActor
enum RemoteRunner {
    struct Outcome { var text: String; var file: URL? = nil; var isImage = false }
    static let downloadCap = 500 * 1024 * 1024

    static func run(_ command: RemoteCommand, settings: AppSettings) async -> Outcome {
        WakeLog.event("remote \(String("\(command)".prefix(while: { $0 != "(" })))")
        switch command {
        case .help: return Outcome(text: RemoteCommand.helpText)
        case .status: return Outcome(text: status())
        case .screenPeek: return await screenPeek()
        case .sendFile(let q): return await sendFile(q, settings: settings)
        case .listFiles(let q): return Outcome(text: await listFiles(q, settings: settings))
        case .download(let url): return await download(url)
        case .stopRemote, .startRemote: return Outcome(text: "")
        default:
            guard let action = command.macAction else { return Outcome(text: "I can't do that from here.") }
            let (failed, notes) = await MacRunner.perform([action])
            if let f = failed.first { return Outcome(text: "Couldn't: \(f)") }
            return Outcome(text: notes.first ?? "Done: \(action.summary).")
        }
    }

    static func status() -> String {
        let (pct, charging) = NudgeMonitor.battery()
        var parts = ["The Mac is on"]
        if let pct { parts.append("\(pct)%\(charging ? " charging" : " on battery")") }
        if let front = NSWorkspace.shared.frontmostApplication?.localizedName, !front.isEmpty { parts.append("\(front) in front") }
        let idle = Int(CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!))
        if idle >= 60 { parts.append("idle \(idle >= 3600 ? "\(idle / 3600) h" : "\(idle / 60) min")") }
        parts.append("\(Int(NudgeMonitor.diskFreeGB())) GB free")
        return parts.joined(separator: ", ") + "."
    }

    private static func roots(_ settings: AppSettings) -> [String] { FilePolicy.roots(from: settings.remoteRoots, home: FileManager.default.homeDirectoryForCurrentUser.path) }

    static func find(_ query: String, settings: AppSettings, limit: Int = 10) async -> [URL] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.hasPrefix("/") || q.hasPrefix("~") {
            let p = ((q as NSString).expandingTildeInPath as NSString).standardizingPath
            return FileManager.default.fileExists(atPath: p) ? [URL(fileURLWithPath: p)] : []
        }
        let words = q.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 2 }.prefix(6)
        guard !words.isEmpty else { return [] }
        var args: [String] = []
        for r in roots(settings) { args += ["-onlyin", r] }
        args.append(words.map { "kMDItemFSName == \"*\($0)*\"cd" }.joined(separator: " && ") + " && kMDItemContentTypeTree != \"public.folder\"")
        let out = (try? await MacRunner.runTool("/usr/bin/mdfind", args)) ?? ""
        let urls = out.split(separator: "\n").map { URL(fileURLWithPath: String($0)).resolvingSymlinksInPath() }
            .filter { u in (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        let dated = urls.map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        return dated.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    static func describe(_ u: URL) -> String {
        let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short
        return "\(u.lastPathComponent) (\(FilePolicy.sizeText(v?.fileSize ?? 0)), \(u.deletingLastPathComponent().lastPathComponent), \(v?.contentModificationDate.map(f.string) ?? "?"))"
    }

    static func listFiles(_ query: String, settings: AppSettings) async -> String {
        let hits = await find(query, settings: settings)
        if hits.isEmpty { return "Nothing called “\(query)” in the folders I may send from (\(roots(settings).map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")))." }
        return "\(hits.count) match\(hits.count == 1 ? "" : "es"):\n" + hits.enumerated().map { "\($0.offset + 1). \(describe($0.element))" }.joined(separator: "\n")
    }

    static func sendFile(_ query: String, settings: AppSettings) async -> Outcome {
        let hits = await find(query, settings: settings)
        guard let file = hits.first else { return Outcome(text: "Nothing called “\(query)” in the folders I may send from.") }
        if hits.count > 1, !query.hasPrefix("/"), !query.hasPrefix("~") {
            let exact = hits.filter { $0.lastPathComponent.lowercased() == query.lowercased() || $0.deletingPathExtension().lastPathComponent.lowercased() == query.lowercased() }
            if exact.count != 1, Set(hits.map(\.lastPathComponent)).count > 1 {
                return Outcome(text: "Several files match; which one?\n" + hits.prefix(5).enumerated().map { "\($0.offset + 1). \(describe($0.element))" }.joined(separator: "\n"))
            }
        }
        let resolved = file.resolvingSymlinksInPath().path
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if let why = FilePolicy.refusal(forResolved: resolved, roots: roots(settings), size: size) { return Outcome(text: "Not sending that: \(why).") }
        if let h = FileHandle(forReadingAtPath: resolved), FilePolicy.looksSecret(h.readData(ofLength: 400)) { return Outcome(text: "Not sending that: it looks like it holds a key or a secret.") }
        return Outcome(text: "Here's \(describe(file)).", file: file)
    }

    static func screenPeek() async -> Outcome {
        do {
            let shot = try await ScreenCapture.capture()
            guard let data = Data(base64Encoded: shot.base64) else { return Outcome(text: "Couldn't capture the screen.") }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("sofia-screen-\(Int(Date().timeIntervalSince1970)).jpg")
            try data.write(to: tmp, options: .atomic)
            return Outcome(text: shot.note.isEmpty ? "Your screen right now." : shot.note, file: tmp, isImage: true)
        } catch { return Outcome(text: "Couldn't capture the screen: \(error.localizedDescription)") }
    }

    static func download(_ url: URL) async -> Outcome {
        guard url.scheme == "https" else { return Outcome(text: "Only https links.") }
        do {
            let (tmp, resp) = try await URLSession.shared.download(from: url)
            defer { try? FileManager.default.removeItem(at: tmp) }
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return Outcome(text: "The server answered \((resp as? HTTPURLResponse)?.statusCode ?? 0).") }
            let size = (try? tmp.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size > 0, size <= downloadCap else { return Outcome(text: size == 0 ? "The download was empty." : "The file is over 500 MB.") }
            var name = (resp.suggestedFilename ?? url.lastPathComponent).replacingOccurrences(of: "/", with: "_").trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { name = "download" }
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            var dest = downloads.appendingPathComponent(name)
            var n = 2
            while FileManager.default.fileExists(atPath: dest.path) { dest = downloads.appendingPathComponent("\((name as NSString).deletingPathExtension) \(n).\((name as NSString).pathExtension)"); n += 1 }
            try FileManager.default.moveItem(at: tmp, to: dest)
            var marked = dest
            var values = URLResourceValues()
            values.quarantineProperties = [kLSQuarantineAgentNameKey as String: "Sofia", kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String, kLSQuarantineDataURLKey as String: url.absoluteString]
            do { try marked.setResourceValues(values) } catch { try? FileManager.default.removeItem(at: dest); return Outcome(text: "Couldn't mark the download as coming from the internet, so I deleted it.") }
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dest.path)
            return Outcome(text: "Saved \(dest.lastPathComponent) (\(FilePolicy.sizeText(size))) to Downloads.")
        } catch { return Outcome(text: "Couldn't download: \(error.localizedDescription)") }
    }
}

@MainActor
final class KeepAwake {
    private var assertion: IOPMAssertionID = 0
    private var timer: Timer?
    private(set) var holding = false
    var enabled = false { didSet { apply() } }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in self?.apply() } }
        apply()
    }
    private func apply() {
        let battery = NudgeMonitor.battery()
        let want = enabled && (battery.1 || battery.0 == nil)
        if want && !holding {
            if IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Sofia: reachable from your phone" as CFString, &assertion) == kIOReturnSuccess { holding = true }
        } else if !want && holding {
            IOPMAssertionRelease(assertion); holding = false
        }
    }
}
