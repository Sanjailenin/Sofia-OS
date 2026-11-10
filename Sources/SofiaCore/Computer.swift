import Foundation

public struct ScreenScale: Equatable {
    public let displayWidth: Double, displayHeight: Double, scale: Double
    public let originX: Double, originY: Double
    public let displayID: UInt32
    public init(displayWidth: Double, displayHeight: Double, originX: Double = 0, originY: Double = 0, displayID: UInt32 = 0, maxWidth: Double = 1280, maxHeight: Double = 800) {
        self.displayWidth = displayWidth; self.displayHeight = displayHeight
        self.originX = originX; self.originY = originY; self.displayID = displayID
        scale = min(1, maxWidth / displayWidth, maxHeight / displayHeight)
    }
    public var imageWidth: Int { Int((displayWidth * scale).rounded()) }
    public var imageHeight: Int { Int((displayHeight * scale).rounded()) }
    public func toDisplay(_ x: Double, _ y: Double) -> (Double, Double) {
        (originX + min(max(x / scale, 0), displayWidth - 1), originY + min(max(y / scale, 0), displayHeight - 1))
    }
    public func toLocal(_ x: Double, _ y: Double) -> (Double, Double) {
        (min(max(x / scale, 0), displayWidth - 1), min(max(y / scale, 0), displayHeight - 1))
    }
    public func toImage(_ x: Double, _ y: Double) -> (Int, Int) { (Int(((x - originX) * scale).rounded()), Int(((y - originY) * scale).rounded())) }
    public func contains(_ x: Double, _ y: Double) -> Bool { x >= originX && y >= originY && x < originX + displayWidth && y < originY + displayHeight }
}

public enum TypedText {
    public static let maxUnits = 16
    public static func chunks(_ text: String, maxUnits: Int = maxUnits) -> [[UInt16]] {
        var out: [[UInt16]] = [], current: [UInt16] = []
        for ch in text {
            let units = Array(String(ch).utf16)
            if !current.isEmpty, current.count + units.count > maxUnits { out.append(current); current = [] }
            current += units
        }
        if !current.isEmpty { out.append(current) }
        return out
    }
}

public enum KeyMap {
    public static let shift: UInt64 = 0x20000, control: UInt64 = 0x40000, option: UInt64 = 0x80000, command: UInt64 = 0x100000, fn: UInt64 = 0x800000

    static let modifiers: [String: UInt64] = [
        "shift": shift, "ctrl": control, "control": control, "alt": option, "option": option, "opt": option,
        "super": command, "cmd": command, "command": command, "meta": command, "win": command, "fn": fn,
    ]
    static let named: [String: UInt16] = [
        "return": 36, "enter": 36, "kp_enter": 76, "tab": 48, "space": 49, "backspace": 51, "delete": 51, "escape": 53, "esc": 53,
        "forwarddelete": 117, "home": 115, "end": 119, "pageup": 116, "page_up": 116, "pagedown": 121, "page_down": 121,
        "left": 123, "right": 124, "down": 125, "up": 126, "capslock": 57,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "minus": 27, "equal": 24, "plus": 24, "comma": 43, "period": 47, "slash": 44, "backslash": 42, "semicolon": 41, "apostrophe": 39,
        "bracketleft": 33, "bracketright": 30, "grave": 50,
    ]
    static let chars: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "`": 50,
    ]

    public static func parse(_ combo: String) -> (keyCode: UInt16, flags: UInt64)? {
        let parts = combo.split(separator: "+", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyPart = parts.last, !keyPart.isEmpty else { return nil }
        var flags: UInt64 = 0
        for m in parts.dropLast() { guard let f = modifiers[m.lowercased()] else { return nil }; flags |= f }
        let k = keyPart.lowercased()
        if let code = named[k] { return (code, flags) }
        if keyPart.count == 1, let ch = keyPart.first {
            if let code = chars[Character(ch.lowercased())] { return (code, flags | (ch.isUppercase ? shift : 0)) }
        }
        return nil
    }

    public static func modifierFlags(_ text: String?) -> UInt64? {
        guard let t = text?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return 0 }
        var f: UInt64 = 0
        for m in t.split(separator: "+") { guard let v = modifiers[m.trimmingCharacters(in: .whitespaces).lowercased()] else { return nil }; f |= v }
        return f
    }
}

public enum ComputerGuard {
    public static let passwordPrefixes = ["com.apple.keychainaccess", "com.apple.Passwords", "com.1password", "com.agilebits", "com.bitwarden", "com.lastpass", "com.dashlane", "org.keepassxc", "com.apple.systempreferences.password"]
    public static let commandPrefixes = ["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp", "com.mitchellh.ghostty", "net.kovidgoyal.kitty", "org.alacritty", "io.alacritty", "com.github.wez.wezterm", "co.zeit.hyper", "com.apple.ScriptEditor2", "com.apple.Automator", "com.apple.shortcuts", "com.apple.systempreferences", "com.apple.Settings"]
    public static var blockedBundlePrefixes: [String] { passwordPrefixes + commandPrefixes }

    public static func isBlocked(bundleID: String?) -> Bool { refusal(bundleID: bundleID) != nil }

    public static func refusal(bundleID: String?) -> String? {
        guard let b = bundleID?.lowercased() else { return nil }
        if passwordPrefixes.contains(where: { b.hasPrefix($0.lowercased()) }) { return "I don't touch password managers" }
        if commandPrefixes.contains(where: { b.hasPrefix($0.lowercased()) }) { return "I don't type or click in terminals, script editors, Shortcuts or System Settings; do that part yourself" }
        return nil
    }
}
