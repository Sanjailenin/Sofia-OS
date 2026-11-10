import Foundation

public enum IslandPlacement {
    public enum Mode: String, CaseIterable, Sendable { case follow, builtin, main }

    public struct Screen: Equatable {
        public var index: Int
        public var x: Double, y: Double, width: Double, height: Double
        public var hasNotch: Bool
        public var isMain: Bool
        public init(index: Int, x: Double, y: Double, width: Double, height: Double, hasNotch: Bool, isMain: Bool) {
            self.index = index; self.x = x; self.y = y; self.width = width; self.height = height; self.hasNotch = hasNotch; self.isMain = isMain
        }
        public func contains(_ px: Double, _ py: Double) -> Bool { px >= x && px < x + width && py >= y && py < y + height }
    }

    public static func choose(_ screens: [Screen], mode: Mode, mouse: (Double, Double)?) -> Screen? {
        guard !screens.isEmpty else { return nil }
        let builtin = screens.first(where: { $0.hasNotch })
        let main = screens.first(where: { $0.isMain }) ?? screens[0]
        switch mode {
        case .builtin: return builtin ?? main
        case .main: return main
        case .follow:
            if let (mx, my) = mouse, let under = screens.first(where: { $0.contains(mx, my) }) { return under }
            return builtin ?? main
        }
    }
}
