import AppKit
import SofiaCore

@MainActor
enum Preferences {
    static func apply(key: String, value: String) -> String? {
        guard let p = Preference(rawValue: key), let v = p.normalize(value) else { return nil }
        let s = AppSettings.shared
        let on = v == "on"
        switch p {
        case .entrance: s.entrance = on
        case .clapSensitivity: s.clapSensitivity = v
        case .conversation: s.conversation = on
        case .nudges: s.nudges = on
        case .remoteAccess: s.remoteAccess = on
        }
        return "\(p.spokenName.prefix(1).uppercased() + p.spokenName.dropFirst()) is now \(v)."
    }
}

@MainActor
enum WindowMover {
    struct Failure: LocalizedError { let msg: String; init(_ m: String) { msg = m }; var errorDescription: String? { msg } }

    static func move(app name: String, placement: String) throws -> String {
        guard InputDriver.hasPermission else { throw Failure("Accessibility permission is off for Sofia") }
        let app: NSRunningApplication
        if name.lowercased() == "front" { guard let f = NSWorkspace.shared.frontmostApplication else { throw Failure("no app in front") }; app = f }
        else { guard let a = running(named: name).first else { throw Failure("\(name) isn't open") }; app = a }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        var w: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXFocusedWindowAttribute as CFString, &w) == .success || AXUIElementCopyAttributeValue(el, kAXMainWindowAttribute as CFString, &w) == .success, let win = w else { throw Failure("\(app.localizedName ?? name) has no window") }
        let window = win as! AXUIElement
        var p: CFTypeRef?, s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &p) == .success, AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &s) == .success else { throw Failure("couldn't read the window") }
        var pt = CGPoint.zero, sz = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &pt); AXValueGetValue(s as! AXValue, .cgSize, &sz)
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let displays = NSScreen.screens.map { sc -> WindowGeometry.Rect in
            let v = sc.visibleFrame
            return WindowGeometry.Rect(x: v.minX, y: primaryH - v.maxY, width: v.width, height: v.height)
        }
        let builtin = NSScreen.screens.firstIndex(where: { $0.safeAreaInsets.top > 0 || CGDisplayIsBuiltin(($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0) != 0 })
        guard let target = WindowGeometry.frame(for: placement, window: WindowGeometry.Rect(x: pt.x, y: pt.y, width: sz.width, height: sz.height), displays: displays, builtin: builtin) else {
            throw Failure(placement == "external" || placement == "next_display" || placement.hasPrefix("display:") ? "there's only one display" : "can't place it \(placement)")
        }
        var np = CGPoint(x: target.x, y: target.y), ns = CGSize(width: target.width, height: target.height)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &np)!)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &ns)!)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &np)!)
        app.activate(options: [])
        return "Moved \(app.localizedName ?? name) \(placement.replacingOccurrences(of: "_", with: " "))."
    }

    private static func running(named name: String) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && ($0.localizedName ?? "").lowercased() == name.lowercased() }
    }
}
