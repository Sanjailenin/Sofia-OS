import SwiftUI
import AppKit
import SofiaCore

enum Tok {
    enum Space { static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 18 }
    enum Radius { static let rest: CGFloat = 10, open: CGFloat = 26, shoulder: CGFloat = 12 }
    enum Size {
        static let minWidth: CGFloat = 420, wingsExtra: CGFloat = 310
        static let textRow: CGFloat = 50, bareRow: CGFloat = 6, flatIdleWidth: CGFloat = 110
        static let barWidth: CGFloat = 2.5, barGap: CGFloat = 3, barMax: CGFloat = 22, bars = 11
    }

    enum Ink {
        static let surface = Color.black
        static let paper = Color(hex: 0xf7f3ef)
        static let muted = Color(hex: 0xa99b96)
        static let crimson = Color(hex: 0xd31e43)
        static let brass = Color(hex: 0xe0b76c)
        static let danger = Color(hex: 0xf97c3d)
    }

    static let lamp = Color(hex: 0xd31e43)

    enum Text_ {
        static let label = Font.system(size: 12.5, weight: .semibold)
        static let heard = Font.system(size: 13, weight: .medium)
        static let tag = Font.system(size: 8, weight: .heavy)
        static let serifName = NSFont(name: "InstrumentSerif-Regular", size: 15) != nil ? "InstrumentSerif-Regular" : nil
        static var serif: Font { serifName.map { Font.custom($0, size: 16) } ?? Font.system(size: 15, weight: .regular, design: .serif) }
        static var serifUsed: String { serifName ?? "system serif (New York)" }
    }

    enum Motion {
        static let open = Animation.spring(response: 0.45, dampingFraction: 0.72)
        static let text = Animation.spring(response: 0.4, dampingFraction: 0.82)
        static let fade = Animation.easeInOut(duration: 0.15)
        static let slowPulse: Double = 2.4
        static func pick(_ a: Animation, reduce: Bool) -> Animation { reduce ? fade : a }
    }
}

extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255) }
}
