import AppKit
import ApplicationServices
import SofiaCore

@MainActor
enum AXTree {
    struct Failure: LocalizedError { let msg: String; init(_ m: String) { msg = m }; var errorDescription: String? { msg } }
    private static let maxNodes = 1500
    private static var last: [String: (AXUIElement, AXElement)] = [:]

    static func find(query: String, scale: ScreenScale) -> String {
        guard InputDriver.hasPermission else { return "Accessibility permission is off for Sofia." }
        guard let app = NSWorkspace.shared.frontmostApplication else { return "No app in front." }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        var windows: [AXUIElement] = []
        if let w = copy(appEl, kAXWindowsAttribute) as? [AXUIElement] { windows = w }
        if let focused = copy(appEl, kAXFocusedWindowAttribute) { windows.insert(focused as! AXUIElement, at: 0) }
        var out: [AXElement] = []; var seen = Set<String>(); var budget = maxNodes
        last = [:]
        for w in windows {
            walk(w, depth: 0, budget: &budget) { el, role, subrole in
                guard let name = AXElement.roleName(role, subrole: subrole), let frame = frame(of: el), frame.width > 2, frame.height > 2 else { return }
                let title = titleOf(el)
                if title.isEmpty && !["text field", "text area", "combo box"].contains(name) { return }
                let (x, y) = scale.toImage(frame.midX, frame.midY)
                let key = "\(name)|\(title)|\(x)|\(y)"
                guard seen.insert(key).inserted else { return }
                let id = "e\(out.count + 1)"
                let item = AXElement(id: id, role: name, title: title, x: x, y: y, editable: ["text field", "text area", "combo box"].contains(name))
                out.append(item); last[id] = (el, item)
            }
        }
        return AXElement.report(out, query: query)
    }

    static func press(id: String, text: String?, scale: ScreenScale) async throws -> String {
        guard let (el, item) = last[id] else { throw Failure("No element \(id); call find_elements again, the window may have changed.") }
        if let text, item.editable {
            AXUIElementSetAttributeValue(el, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            let r = AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, text as CFTypeRef)
            if r == .success { return "Set \(item.role) \"\(item.title)\" to the text." }
            _ = try await InputDriver.perform("left_click", ["coordinate": [item.x, item.y]], scale: scale)
            _ = try await InputDriver.perform("key", ["text": "super+a"], scale: scale)
            _ = try await InputDriver.perform("type", ["text": text], scale: scale)
            return "Typed into \(item.role) \"\(item.title)\" (the app didn't accept a direct value)."
        }
        let r = AXUIElementPerformAction(el, kAXPressAction as CFString)
        if r == .success { return "Pressed \(item.role) \"\(item.title)\"." }
        _ = try await InputDriver.perform("left_click", ["coordinate": [item.x, item.y]], scale: scale)
        return "Clicked \(item.role) \"\(item.title)\" at its centre (press wasn't accepted)."
    }

    private static func walk(_ el: AXUIElement, depth: Int, budget: inout Int, visit: (AXUIElement, String, String?) -> Void) {
        guard depth < 40, budget > 0 else { return }
        budget -= 1
        let role = copy(el, kAXRoleAttribute) as? String ?? ""
        let subrole = copy(el, kAXSubroleAttribute) as? String
        if role != "AXWindow" { visit(el, role, subrole) }
        guard role != "AXMenuBar", let kids = copy(el, kAXChildrenAttribute) as? [AXUIElement] else { return }
        for k in kids.prefix(200) { walk(k, depth: depth + 1, budget: &budget, visit: visit) }
    }

    private static func copy(_ el: AXUIElement, _ attr: String) -> AnyObject? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
    }
    private static func titleOf(_ el: AXUIElement) -> String {
        for a in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXPlaceholderValueAttribute, kAXHelpAttribute] {
            if let s = copy(el, a) as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty { return s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ") }
        }
        if let titleEl = copy(el, kAXTitleUIElementAttribute), CFGetTypeID(titleEl) == AXUIElementGetTypeID(), let s = copy(titleEl as! AXUIElement, kAXValueAttribute) as? String { return s }
        return ""
    }
    private static func frame(of el: AXUIElement) -> CGRect? {
        guard let p = copy(el, kAXPositionAttribute), let s = copy(el, kAXSizeAttribute) else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &pt), AXValueGetValue(s as! AXValue, .cgSize, &sz) else { return nil }
        return CGRect(origin: pt, size: sz)
    }
}
