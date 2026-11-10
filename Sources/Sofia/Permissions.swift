import AppKit
import AVFoundation
import Speech
import EventKit
import SwiftUI

enum Permission: String, CaseIterable, Identifiable {
    case microphone, speech, accessibility, screen, calendar, automation
    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .speech: return "Speech Recognition"
        case .accessibility: return "Accessibility"
        case .screen: return "Screen Recording"
        case .calendar: return "Calendars"
        case .automation: return "Automation (System Events)"
        }
    }

    var why: String {
        switch self {
        case .microphone: return "to hear “Hey <name>”, claps and what you ask"
        case .speech: return "to understand you, on this Mac only"
        case .accessibility: return "to click, type and move windows when you ask"
        case .screen: return "for screen tasks and screenshots you ask for"
        case .calendar: return "to stay quiet during meetings (optional)"
        case .automation: return "to control music, dark mode and typing"
        }
    }

    var pane: String {
        switch self {
        case .microphone: return "Privacy_Microphone"
        case .speech: return "Privacy_SpeechRecognition"
        case .accessibility: return "Privacy_Accessibility"
        case .screen: return "Privacy_ScreenCapture"
        case .calendar: return "Privacy_Calendars"
        case .automation: return "Privacy_Automation"
        }
    }

    var tccService: String {
        switch self {
        case .microphone: return "Microphone"
        case .speech: return "SpeechRecognition"
        case .accessibility: return "Accessibility"
        case .screen: return "ScreenCapture"
        case .calendar: return "Calendar"
        case .automation: return "AppleEvents"
        }
    }

    var needsRestart: Bool { self == .screen }

    var granted: Bool {
        switch self {
        case .microphone: return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .speech: return SFSpeechRecognizer.authorizationStatus() == .authorized
        case .accessibility: return AXIsProcessTrusted()
        case .screen: return CGPreflightScreenCaptureAccess()
        case .calendar:
            let s = EKEventStore.authorizationStatus(for: .event)
            if #available(macOS 14.0, *) { return s == .fullAccess }
            return s.rawValue == 3
        case .automation: return Self.automationStatus(ask: false) == noErr
        }
    }

    static func automationStatus(ask: Bool) -> OSStatus {
        let id = "com.apple.systemevents"
        if NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return OSStatus(procNotFound) }
            let config = NSWorkspace.OpenConfiguration(); config.activates = false; config.addsToRecentItems = false
            let done = DispatchSemaphore(value: 0)
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in done.signal() }
            _ = done.wait(timeout: .now() + 3)
        }
        var target = AEAddressDesc()
        let bytes = Array(id.utf8)
        guard AECreateDesc(typeApplicationBundleID, bytes, bytes.count, &target) == noErr else { return OSStatus(procNotFound) }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, ask)
    }

    func request(_ done: @escaping () -> Void) {
        switch self {
        case .microphone: AVCaptureDevice.requestAccess(for: .audio) { _ in DispatchQueue.main.async(execute: done) }
        case .speech: SFSpeechRecognizer.requestAuthorization { _ in DispatchQueue.main.async(execute: done) }
        case .accessibility:
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            DispatchQueue.main.async(execute: done)
        case .screen:
            _ = CGRequestScreenCaptureAccess()
            DispatchQueue.main.async(execute: done)
        case .calendar:
            let store = EKEventStore()
            if #available(macOS 14.0, *) { store.requestFullAccessToEvents { _, _ in DispatchQueue.main.async(execute: done) } }
            else { store.requestAccess(to: .event) { _, _ in DispatchQueue.main.async(execute: done) } }
        case .automation:
            DispatchQueue.global(qos: .userInitiated).async { _ = Self.automationStatus(ask: true); DispatchQueue.main.async(execute: done) }
        }
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }

    func reset() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", tccService, Bundle.main.bundleIdentifier ?? "dev.sofia.app"]
        try? p.run(); p.waitUntilExit()
    }
}

@MainActor
final class PermissionState: ObservableObject {
    @Published var granted: [Permission: Bool] = [:]
    @Published var asking = false
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }
    deinit { timer?.invalidate() }

    func refresh() {
        let quick = Permission.allCases.filter { $0 != .automation }
        var g = granted
        for p in quick { g[p] = p.granted }
        granted = g
        DispatchQueue.global(qos: .utility).async {
            let a = Permission.automation.granted
            DispatchQueue.main.async { [weak self] in self?.granted[.automation] = a }
        }
    }

    var missing: [Permission] { Permission.allCases.filter { granted[$0] != true } }

    func askAll() {
        guard !asking else { return }
        asking = true
        var queue = missing
        func next() {
            guard !queue.isEmpty else { asking = false; refresh(); return }
            let p = queue.removeFirst()
            p.request { [weak self] in self?.refresh(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { next() } }
        }
        next()
    }

    func reset(_ p: Permission) { p.reset(); p.request { [weak self] in self?.refresh() } }
}

struct PermissionsView: View {
    @StateObject private var state = PermissionState()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Permission.allCases) { p in
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: state.granted[p] == true ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(state.granted[p] == true ? .green : .orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.title).font(.callout)
                        Text(p.why).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if state.granted[p] != true {
                        Button("Allow") { p.request { state.refresh() }; if p == .accessibility || p == .screen { p.openSettings() } }
                        Button("Reset") { state.reset(p) }.help("Use when Sofia is switched on in System Settings but this still says not allowed (an entry from an older version).")
                    }
                }
            }
            HStack {
                Button(state.asking ? "Asking…" : "Allow everything") { state.askAll() }.disabled(state.asking || state.missing.isEmpty)
                Spacer()
                Text(state.missing.isEmpty ? "All set." : "\(state.missing.count) still to allow.").font(.caption).foregroundStyle(.secondary)
            }
            if state.granted[.screen] != true {
                Text("Screen Recording only takes effect after Sofia is quit and opened again.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
