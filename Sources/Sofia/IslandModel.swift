import SwiftUI
import SofiaCore

final class IslandModel: ObservableObject {
    @Published var name = WakeWord.defaultName
    @Published var phase: Phase = .idle
    @Published var transcript = ""
    @Published var level: Float = 0
    @Published var demo = false
    @Published var reduceMotion = false
    @Published var wakeListening = false
    @Published var notchWidth: CGFloat = 0
    @Published var notchHeight: CGFloat = 32
    @Published var hasNotch = false

    var phaseName: String {
        switch phase {
        case .idle: return "idle"
        case .listening: return "listening"
        case .thinking: return "thinking"
        case .speaking: return "speaking"
        case .error(let m): return "problem: \(m)"
        }
    }
}
