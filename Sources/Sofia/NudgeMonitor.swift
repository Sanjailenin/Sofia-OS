import Foundation
import IOKit.ps
import Network
import SofiaCore

@MainActor
final class NudgeMonitor {
    var onNudge: ((String) -> Void)?
    var eventWithinHour: () -> Bool = { false }
    private var memory = NudgeRules.Memory()
    private var timer: Timer?
    private let path = NWPathMonitor()
    private var online = true

    init() {
        path.pathUpdateHandler = { [weak self] p in Task { @MainActor in self?.online = p.status == .satisfied } }
        path.start(queue: DispatchQueue(label: "sofia.nudges.path"))
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in Task { @MainActor in self?.check() } }
        Task { @MainActor in try? await Task.sleep(nanoseconds: 20_000_000_000); self.check() }
    }
    func stop() { timer?.invalidate(); timer = nil }

    func check() {
        let (pct, charging) = Self.battery()
        let facts = NudgeRules.Facts(batteryPercent: pct, charging: charging, diskFreeGB: Self.diskFreeGB(), online: online, eventWithinHour: eventWithinHour())
        for line in NudgeRules.evaluate(facts, now: Date(), memory: &memory) { onNudge?(line) }
    }

    static func battery() -> (Int?, Bool) {
        guard let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let list = IOPSCopyPowerSourcesList(snap)?.takeRetainedValue() as? [CFTypeRef] else { return (nil, false) }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(snap, ps)?.takeUnretainedValue() as? [String: Any], d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let cap = d[kIOPSCurrentCapacityKey] as? Int ?? 0, max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let charging = (d[kIOPSIsChargingKey] as? Bool ?? false) || (d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
            return (max > 0 ? Int(Double(cap) * 100 / Double(max)) : cap, charging)
        }
        return (nil, false)
    }
    static func diskFreeGB() -> Double {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let v = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Double(v?.volumeAvailableCapacityForImportantUsage ?? 0) / 1e9
    }
}
