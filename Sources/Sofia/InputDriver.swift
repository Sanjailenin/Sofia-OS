import AppKit
import CoreGraphics
import SofiaCore

enum InputDriver {
    struct Failure: LocalizedError { let errorDescription: String?; init(_ s: String) { errorDescription = s } }

    static var hasPermission: Bool { AXIsProcessTrusted() }
    static func requestPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    private static let src = CGEventSource(stateID: .combinedSessionState)

    static func perform(_ name: String, _ input: [String: Any], scale: ScreenScale) async throws -> String {
        guard hasPermission else { throw Failure("Accessibility permission is off for Sofia") }
        func point(_ key: String = "coordinate") throws -> CGPoint? {
            guard let c = input[key] as? [Any] else { return nil }
            guard c.count == 2, let x = (c[0] as? NSNumber)?.doubleValue, let y = (c[1] as? NSNumber)?.doubleValue else { throw Failure("bad \(key)") }
            let (dx, dy) = scale.toDisplay(x, y); return CGPoint(x: dx, y: dy)
        }
        let takesModifiers = ["left_click", "right_click", "middle_click", "double_click", "triple_click", "left_click_drag", "scroll"].contains(name)
        guard let mods = takesModifiers ? KeyMap.modifierFlags(input["text"] as? String) : 0 else { throw Failure("unknown modifier \(input["text"] as? String ?? "")") }
        switch name {
        case "left_click", "right_click", "middle_click", "double_click", "triple_click":
            let p = try point() ?? currentPoint()
            let count = name == "double_click" ? 2 : name == "triple_click" ? 3 : 1
            let button: CGMouseButton = name == "right_click" ? .right : name == "middle_click" ? .center : .left
            move(to: p); try await pause(0.05)
            for i in 1...count { click(button, at: p, clickState: i, flags: mods) }
        case "mouse_move":
            guard let p = try point() else { throw Failure("coordinate is required") }
            move(to: p)
        case "left_click_drag":
            guard let from = try point("start_coordinate"), let to = try point() else { throw Failure("start_coordinate and coordinate are required") }
            move(to: from); try await pause(0.05)
            post(.leftMouseDown, at: from, button: .left, flags: mods)
            for i in 1...12 {
                let t = Double(i) / 12
                post(.leftMouseDragged, at: CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t), button: .left, flags: mods)
                try await pause(0.015)
            }
            post(.leftMouseUp, at: to, button: .left, flags: mods)
        case "left_mouse_down": post(.leftMouseDown, at: currentPoint(), button: .left, flags: mods)
        case "left_mouse_up": post(.leftMouseUp, at: currentPoint(), button: .left, flags: mods)
        case "cursor_position":
            let p = currentPoint(); let (x, y) = scale.toImage(p.x, p.y)
            return "X=\(x), Y=\(y)"
        case "scroll":
            if let p = try point() { move(to: p); try await pause(0.03) }
            let amount = Int32(max(1, min(30, (input["scroll_amount"] as? NSNumber)?.intValue ?? 3)))
            let dir = input["scroll_direction"] as? String ?? "down"
            let (dy, dx): (Int32, Int32) = dir == "up" ? (amount, 0) : dir == "down" ? (-amount, 0) : dir == "left" ? (0, amount) : (0, -amount)
            guard let e = CGEvent(scrollWheelEvent2Source: src, units: .line, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else { throw Failure("scroll failed") }
            e.flags = CGEventFlags(rawValue: mods); e.post(tap: .cghidEventTap)
        case "type":
            guard let text = input["text"] as? String, !text.isEmpty else { throw Failure("text is required") }
            try await type(text)
        case "key":
            guard let combo = input["text"] as? String, let k = KeyMap.parse(combo) else { throw Failure("unknown key \(input["text"] as? String ?? "")") }
            let times = max(1, min(100, (input["repeat"] as? NSNumber)?.intValue ?? 1))
            for _ in 0..<times { press(k.keyCode, flags: k.flags); try await pause(0.02) }
        case "hold_key":
            guard let combo = input["text"] as? String, let k = KeyMap.parse(combo) else { throw Failure("unknown key") }
            let secs = min(10, max(0, (input["duration"] as? NSNumber)?.doubleValue ?? 0.5))
            key(k.keyCode, down: true, flags: k.flags); try await pause(secs); key(k.keyCode, down: false, flags: k.flags)
        case "wait":
            try await pause(min(30, max(0, (input["duration"] as? NSNumber)?.doubleValue ?? 1)))
        default:
            throw Failure("\(name) isn't supported on this Mac")
        }
        return "OK"
    }

    static func currentPoint() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }
    private static func move(to p: CGPoint) { post(.mouseMoved, at: p, button: .left, flags: 0) }

    private static func click(_ button: CGMouseButton, at p: CGPoint, clickState: Int, flags: UInt64) {
        let (down, up): (CGEventType, CGEventType) = button == .right ? (.rightMouseDown, .rightMouseUp) : button == .center ? (.otherMouseDown, .otherMouseUp) : (.leftMouseDown, .leftMouseUp)
        for t in [down, up] {
            guard let e = CGEvent(mouseEventSource: src, mouseType: t, mouseCursorPosition: p, mouseButton: button) else { continue }
            e.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
            e.flags = CGEventFlags(rawValue: flags); e.post(tap: .cghidEventTap)
        }
    }

    private static func post(_ type: CGEventType, at p: CGPoint, button: CGMouseButton, flags: UInt64) {
        guard let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return }
        e.flags = CGEventFlags(rawValue: flags); e.post(tap: .cghidEventTap)
    }

    private static func key(_ code: UInt16, down: Bool, flags: UInt64) {
        guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down) else { return }
        e.flags = CGEventFlags(rawValue: flags); e.post(tap: .cghidEventTap)
    }
    private static func press(_ code: UInt16, flags: UInt64) { key(code, down: true, flags: flags); key(code, down: false, flags: flags) }

    private static func type(_ text: String) async throws {
        for chunk in TypedText.chunks(text) {
            try Task.checkCancellation()
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down) else { continue }
                chunk.withUnsafeBufferPointer { e.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: $0.baseAddress) }
                e.post(tap: .cghidEventTap)
            }
            try await pause(0.012)
        }
    }

    private static func pause(_ s: Double) async throws { try await Task.sleep(nanoseconds: UInt64(s * 1e9)) }
}
