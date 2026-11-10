import Foundation

public enum WindowGeometry {
    public struct Rect: Equatable {
        public var x: Double, y: Double, width: Double, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
        public var midX: Double { x + width / 2 }
        public var midY: Double { y + height / 2 }
        public func contains(_ px: Double, _ py: Double) -> Bool { px >= x && px < x + width && py >= y && py < y + height }
    }
    public static let placements: Set<String> = ["left", "right", "full", "center", "next_display", "laptop", "external", "display:1", "display:2", "display:3"]

    public static func frame(for placement: String, window w: Rect, displays: [Rect], builtin: Int?) -> Rect? {
        guard !displays.isEmpty else { return nil }
        let cur = displays.firstIndex(where: { $0.contains(w.midX, w.midY) }) ?? 0
        let d = displays[cur]
        switch placement {
        case "left": return Rect(x: d.x, y: d.y, width: d.width / 2, height: d.height)
        case "right": return Rect(x: d.x + d.width / 2, y: d.y, width: d.width / 2, height: d.height)
        case "full": return d
        case "center":
            let ww = min(w.width, d.width), hh = min(w.height, d.height)
            return Rect(x: d.x + (d.width - ww) / 2, y: d.y + (d.height - hh) / 2, width: ww, height: hh)
        case "next_display":
            guard displays.count > 1 else { return nil }
            return moved(w, from: d, to: displays[(cur + 1) % displays.count])
        case "laptop":
            guard let b = builtin else { return nil }
            return moved(w, from: d, to: displays[b])
        case "external":
            guard let e = displays.indices.first(where: { $0 != builtin }) else { return nil }
            return moved(w, from: d, to: displays[e])
        default:
            if placement.hasPrefix("display:"), let n = Int(placement.dropFirst(8)), n >= 1, n <= displays.count { return moved(w, from: d, to: displays[n - 1]) }
            return nil
        }
    }

    static func moved(_ w: Rect, from a: Rect, to b: Rect) -> Rect {
        let fx = a.width > 0 ? (w.x - a.x) / a.width : 0, fy = a.height > 0 ? (w.y - a.y) / a.height : 0
        let width = min(w.width * b.width / max(1, a.width), b.width), height = min(w.height * b.height / max(1, a.height), b.height)
        let x = min(max(b.x + fx * b.width, b.x), b.x + b.width - width)
        let y = min(max(b.y + fy * b.height, b.y), b.y + b.height - height)
        return Rect(x: x, y: y, width: width, height: height)
    }
}

public enum Preference: String, CaseIterable, Sendable {
    case entrance, clapSensitivity = "clap_sensitivity", conversation, nudges, remoteAccess = "remote_access"

    public func normalize(_ raw: String) -> String? {
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch self {
        case .entrance, .conversation, .nudges, .remoteAccess:
            if ["on", "yes", "true", "enable", "enabled"].contains(v) { return "on" }
            if ["off", "no", "false", "disable", "disabled"].contains(v) { return "off" }
            return nil
        case .clapSensitivity:
            return ["low", "normal", "high"].contains(v) ? v : nil
        }
    }

    public var spokenName: String {
        switch self {
        case .entrance: return "the entrance"
        case .clapSensitivity: return "clap sensitivity"
        case .conversation: return "conversation mode"
        case .nudges: return "nudges"
        case .remoteAccess: return "remote access"
        }
    }
}

public struct NudgeRules {
    public struct Facts: Equatable {
        public var batteryPercent: Int?
        public var charging: Bool
        public var diskFreeGB: Double
        public var online: Bool
        public var eventWithinHour: Bool
        public init(batteryPercent: Int?, charging: Bool, diskFreeGB: Double, online: Bool, eventWithinHour: Bool) {
            self.batteryPercent = batteryPercent; self.charging = charging; self.diskFreeGB = diskFreeGB; self.online = online; self.eventWithinHour = eventWithinHour
        }
    }
    public struct Memory: Equatable {
        public var lastBattery = Date.distantPast
        public var lastDisk = Date.distantPast
        public var offlineSince: Date?
        public var saidOffline = false
        public init() {}
    }
    public static let batteryCooldown: TimeInterval = 30 * 60
    public static let diskCooldown: TimeInterval = 24 * 3600
    public static let offlineAfter: TimeInterval = 2 * 60

    public static func evaluate(_ f: Facts, now: Date, memory: inout Memory) -> [String] {
        var out: [String] = []
        if let b = f.batteryPercent, !f.charging, now.timeIntervalSince(memory.lastBattery) > batteryCooldown {
            if b < 20 { out.append("Battery is at \(b) percent; plug in when you can."); memory.lastBattery = now }
            else if b < 35 && f.eventWithinHour { out.append("Battery is at \(b) percent and you have a meeting within the hour; worth plugging in."); memory.lastBattery = now }
        }
        if f.diskFreeGB < 10, now.timeIntervalSince(memory.lastDisk) > diskCooldown {
            out.append("Your disk has \(Int(f.diskFreeGB.rounded())) gigabytes left."); memory.lastDisk = now
        }
        if !f.online {
            if memory.offlineSince == nil { memory.offlineSince = now }
            if let since = memory.offlineSince, !memory.saidOffline, now.timeIntervalSince(since) >= offlineAfter { out.append("You've been offline for two minutes."); memory.saidOffline = true }
        } else {
            if memory.saidOffline { out.append("You're back online.") }
            memory.offlineSince = nil; memory.saidOffline = false
        }
        return out
    }
}

public enum Dictation {
    public static func clean(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = t.first else { return "" }
        t = first.uppercased() + t.dropFirst()
        if let last = t.last, !".!?,;:".contains(last) { t += "." }
        return t
    }
}
