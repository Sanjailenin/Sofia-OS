import AppKit
import SwiftUI
import SofiaCore

final class NotchPanel: NSPanel {
    static let panelSize = NSSize(width: 680, height: 150)

    init(model: IslandModel, onTap: @escaping () -> Void) {
        super.init(contentRect: NSRect(origin: .zero, size: Self.panelSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false; hidesOnDeactivate = false; isReleasedWhenClosed = false
        ignoresMouseEvents = true
        let host = NSHostingView(rootView: IslandView(model: model, onTap: onTap))
        host.layer?.backgroundColor = .clear
        contentView = host
        reposition(model: model)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func reposition(model: IslandModel?) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let described = screens.enumerated().map { i, s in IslandPlacement.Screen(index: i, x: s.frame.minX, y: s.frame.minY, width: s.frame.width, height: s.frame.height, hasNotch: s.safeAreaInsets.top > 0, isMain: s == NSScreen.main) }
        let mode = IslandPlacement.Mode(rawValue: AppSettings.shared.islandScreen) ?? .follow
        let m = NSEvent.mouseLocation
        let pick = IslandPlacement.choose(described, mode: mode, mouse: (Double(m.x), Double(m.y))) ?? described[0]
        let screen = screens[pick.index]
        var notchW: CGFloat = 0, notchH: CGFloat = 32, has = false
        if screen.safeAreaInsets.top > 0, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            notchW = screen.frame.width - l.width - r.width
            notchH = screen.safeAreaInsets.top
            has = true
        } else {
            notchH = max(32, NSStatusBar.system.thickness + 8)
        }
        if let model { model.notchWidth = notchW; model.notchHeight = notchH; model.hasNotch = has }
        let f = screen.frame
        setFrame(NSRect(x: f.midX - Self.panelSize.width / 2, y: f.maxY - Self.panelSize.height, width: Self.panelSize.width, height: Self.panelSize.height), display: true)
    }
}
