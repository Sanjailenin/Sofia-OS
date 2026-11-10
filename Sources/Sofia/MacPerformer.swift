import AppKit
import SofiaCore

struct MacPerformer: ActionPerformer {
    let settings: AppSettings
    let progressSink: @Sendable (String) -> Void

    func perform(_ action: MacAction) async -> ActionOutcome {
        let (failed, notes) = await MacRunner.perform([action])
        if let f = failed.first { return .failed(f) }
        return .done(notes.first ?? "")
    }

    func computerTask(_ goal: String, progress: @escaping @Sendable (String) -> Void) async -> String {
        guard await MainActor.run(body: { settings.allowComputer }) else { return "Using the screen, mouse and keyboard is switched off in Settings." }
        let access = await MainActor.run { () -> (input: Bool, screen: Bool) in
            let input = InputDriver.hasPermission, screen = ScreenCapture.hasPermission
            if !input { InputDriver.requestPermission() }
            if !screen { ScreenCapture.requestPermission() }
            return (input, screen)
        }
        guard access.input else { return "I need Accessibility permission to use the mouse and keyboard. In System Settings, Privacy and Security, Accessibility, turn Sofia on. If it already looks on, an update made it stale: select Sofia, click minus, add it again with plus, then ask me again." }
        guard access.screen else { return "I need Screen Recording permission to see the screen. In System Settings, Privacy and Security, Screen and System Audio Recording, turn Sofia on. If it already looks on, remove Sofia with minus and add it again with plus. Then quit and reopen me and ask again." }
        let provider = await MainActor.run { settings.visionProvider }
        WakeLog.event("computer task")
        return await ComputerLoop.run(goal: goal, host: MacComputerHost(), provider: provider) { p in progress(p); progressSink(p) }
    }
}

struct MacComputerHost: ComputerHost {
    private static var lastScale = ScreenScale(displayWidth: 1, displayHeight: 1)

    static func checkFront() async throws {
        let id = await MainActor.run { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
        if let why = ComputerGuard.refusal(bundleID: id) { throw InputDriver.Failure(why) }
    }

    func screenshot() async throws -> Screenshot {
        let shot = try await ScreenCapture.capture()
        await MainActor.run { Self.lastScale = shot.scale }
        return Screenshot(base64: shot.base64, width: shot.scale.imageWidth, height: shot.scale.imageHeight, note: shot.note)
    }
    func click(x: Int, y: Int, double: Bool, right: Bool) async throws {
        try await Self.checkFront()
        let scale = await MainActor.run { Self.lastScale }
        _ = try await InputDriver.perform(right ? "right_click" : double ? "double_click" : "left_click", ["coordinate": [x, y]], scale: scale)
    }
    func type(_ text: String) async throws {
        try await Self.checkFront()
        let scale = await MainActor.run { Self.lastScale }
        _ = try await InputDriver.perform("type", ["text": text], scale: scale)
    }
    func key(_ combo: String) async throws {
        try await Self.checkFront()
        let scale = await MainActor.run { Self.lastScale }
        _ = try await InputDriver.perform("key", ["text": combo], scale: scale)
    }
    func scroll(x: Int, y: Int, direction: String, amount: Int) async throws {
        try await Self.checkFront()
        let scale = await MainActor.run { Self.lastScale }
        _ = try await InputDriver.perform("scroll", ["coordinate": [x, y], "scroll_direction": direction, "scroll_amount": amount], scale: scale)
    }
    func findElements(_ query: String) async throws -> String {
        let scale = await MainActor.run { Self.lastScale }
        return await MainActor.run { AXTree.find(query: query, scale: scale) }
    }
    func pressElement(_ id: String, text: String?) async throws -> String {
        try await Self.checkFront()
        let scale = await MainActor.run { Self.lastScale }
        return try await AXTree.press(id: id, text: text, scale: scale)
    }
}
