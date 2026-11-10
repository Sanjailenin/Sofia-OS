import AppKit
import ScreenCaptureKit
import SofiaCore

enum ScreenCapture {
    struct Shot { let base64: String; let mediaType: String; let scale: ScreenScale; var note: String = "" }
    struct Failure: LocalizedError { let errorDescription: String?; init(_ s: String) { errorDescription = s } }

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }
    @discardableResult static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    static func targetDisplay() -> (id: CGDirectDisplayID, bounds: CGRect, index: Int, count: Int) {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8); var n: UInt32 = 0
        CGGetActiveDisplayList(8, &ids, &n)
        let all = Array(ids.prefix(Int(n))).map { ($0, CGDisplayBounds($0)) }
        func pick(_ p: CGPoint?) -> (CGDirectDisplayID, CGRect)? { guard let p else { return nil }; return all.first(where: { $0.1.contains(p) }) }
        let main = (CGMainDisplayID(), CGDisplayBounds(CGMainDisplayID()))
        let chosen = pick(frontWindowCenter()) ?? pick(mouseGlobal()) ?? main
        let index = all.firstIndex(where: { $0.0 == chosen.0 }) ?? 0
        return (chosen.0, chosen.1, index + 1, max(1, all.count))
    }
    private static func frontWindowCenter() -> CGPoint? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        var w: CFTypeRef?; guard AXUIElementCopyAttributeValue(el, kAXFocusedWindowAttribute as CFString, &w) == .success, let win = w else { return nil }
        var p: CFTypeRef?, sz: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win as! AXUIElement, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(win as! AXUIElement, kAXSizeAttribute as CFString, &sz) == .success else { return nil }
        var pt = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &pt), AXValueGetValue(sz as! AXValue, .cgSize, &size) else { return nil }
        return CGPoint(x: pt.x + size.width / 2, y: pt.y + size.height / 2)
    }
    private static func mouseGlobal() -> CGPoint? {
        let m = NSEvent.mouseLocation
        let primaryH = CGDisplayBounds(CGMainDisplayID()).height
        return CGPoint(x: m.x, y: primaryH - m.y)
    }

    static func capture(regionInImage region: [Double]? = nil, scale current: ScreenScale? = nil) async throws -> Shot {
        guard #available(macOS 14.0, *) else { throw Failure("Screen capture needs macOS 14 or later") }
        guard hasPermission else { throw Failure("Screen Recording permission is off for Sofia") }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let target = current.map { (id: CGDirectDisplayID($0.displayID), bounds: CGRect(x: $0.originX, y: $0.originY, width: $0.displayWidth, height: $0.displayHeight), index: 0, count: 0) } ?? targetDisplay()
        guard let display = content.displays.first(where: { $0.displayID == target.id }) ?? content.displays.first else { throw Failure("No display found") }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let b = target.bounds
        let fit = ScreenScale(displayWidth: b.width, displayHeight: b.height, originX: b.minX, originY: b.minY, displayID: UInt32(target.id), maxWidth: 1024, maxHeight: 640)
        let config = SCStreamConfiguration()
        config.showsCursor = true
        if let region, region.count == 4, let s = current {
            let (x0, y0) = s.toLocal(min(region[0], region[2]), min(region[1], region[3]))
            let (x1, y1) = s.toLocal(max(region[0], region[2]), max(region[1], region[3]))
            let rect = CGRect(x: x0, y: y0, width: max(8, x1 - x0), height: max(8, y1 - y0))
            config.sourceRect = rect
            let z = ScreenScale(displayWidth: rect.width * 2, displayHeight: rect.height * 2)
            config.width = z.imageWidth; config.height = z.imageHeight
        } else {
            config.width = fit.imageWidth; config.height = fit.imageHeight
        }
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.75]) else { throw Failure("Couldn't encode the screenshot") }
        let kind = CGDisplayIsBuiltin(target.id) != 0 ? "built-in" : "external"
        let note = target.count > 1 ? "Display \(target.index) of \(target.count) (\(kind), \(Int(b.width))×\(Int(b.height))). Other displays aren't in this image; switch_app to an app on another display moves the view there." : ""
        return Shot(base64: jpeg.base64EncodedString(), mediaType: "image/jpeg", scale: fit, note: note)
    }
}
