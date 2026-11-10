import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import SofiaCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = Controller()
    private var panel: NotchPanel!
    private var statusItem: NSStatusItem!
    private var hotKeys: [HotKey] = []
    private var settingsWindow: NSWindow?
    private var standbyItem: NSMenuItem?
    private var talkItem: NSMenuItem?
    private var quitItem: NSMenuItem?
    private var setupWindow: NSWindow?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Kokoro.shared.warm()
        panel = NotchPanel(model: controller.model) { [weak self] in self?.controller.escapePressed() }
        controller.panel = panel
        panel.orderFrontRegardless()

        for (key, action) in [(UInt32(kVK_Space), 0), (UInt32(kVK_ANSI_S), 0), (UInt32(kVK_ANSI_D), 1)] {
            if let hk = HotKey(keyCode: key, modifiers: UInt32(controlKey | optionKey), handler: { [weak self] in action == 0 ? self?.controller.hotkeyPressed() : self?.controller.dictationPressed() }) { hotKeys.append(hk) }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let name = AppSettings.shared.assistantName
        statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: name)
        let menu = NSMenu()
        talkItem = menu.addItem(withTitle: "Talk to \(name) (⌃⌥S)", action: #selector(talk), keyEquivalent: "")
        talkItem?.target = self
        standbyItem = menu.addItem(withTitle: "Go off (until I wake her)", action: #selector(toggleStandby), keyEquivalent: "")
        standbyItem?.target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        quitItem = menu.addItem(withTitle: "Quit \(name)", action: #selector(quit), keyEquivalent: "q")
        quitItem?.target = self
        statusItem.menu = menu

        AppSettings.shared.$standby.receive(on: DispatchQueue.main).sink { [weak self] off in MainActor.assumeIsolated {
            let n = AppSettings.shared.assistantName
            self?.standbyItem?.title = off ? "Wake \(n)" : "Go off (until I wake her)"
            self?.statusItem.button?.image = NSImage(systemSymbolName: off ? "waveform.slash" : "waveform", accessibilityDescription: off ? "\(n) is off" : n)
        } }.store(in: &bag)
        AppSettings.shared.$assistantName.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] n in MainActor.assumeIsolated {
            self?.talkItem?.title = "Talk to \(n) (⌃⌥S)"; self?.quitItem?.title = "Quit \(n)"; self?.settingsWindow?.title = n; self?.controller.model.name = n
            if !AppSettings.shared.standby { self?.standbyItem?.title = "Go off (until I wake her)" } else { self?.standbyItem?.title = "Wake \(n)" }
        } }.store(in: &bag)

        NotificationCenter.default.addObserver(forName: .sofiaEntrance, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.controller.previewEntrance() } }
        NotificationCenter.default.addObserver(forName: .sofiaTelegramChanged, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.controller.phone.start() } }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.panel.reposition(model: self?.controller.model) } }

        if !AppSettings.shared.setupDone { openSetup() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.controller.startBackground() }
    }

    @objc func talk() { controller.hotkeyPressed() }
    @objc func toggleStandby() { if AppSettings.shared.standby { controller.wakeFromStandby() } else { AppSettings.shared.standby = true } }
    @objc func quit() { NSApp.terminate(nil) }
    func openSetup() {
        if setupWindow == nil {
            let view = SetupView(settings: AppSettings.shared) { [weak self] in self?.setupWindow?.close(); self?.setupWindow = nil; AppSettings.shared.setupDone = true }
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 620), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Welcome"
            w.contentView = NSHostingView(rootView: view)
            w.isReleasedWhenClosed = false
            w.center()
            setupWindow = w
        }
        setupWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: AppSettings.shared, pairingCode: { [weak self] in self?.controller.phone.pairingCode ?? "" })
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 700), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = AppSettings.shared.assistantName
            w.contentView = NSHostingView(rootView: view)
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

if CommandLine.arguments.contains("--status") {
    let status = "Screen Recording: \(CGPreflightScreenCaptureAccess() ? "on" : "off")\nAccessibility: \(AXIsProcessTrusted() ? "on" : "off")\n"
    print(status, terminator: "")
    let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Sofia")
    try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    try? status.write(to: logs.appendingPathComponent("status.txt"), atomically: true, encoding: .utf8)
    exit(0)
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
