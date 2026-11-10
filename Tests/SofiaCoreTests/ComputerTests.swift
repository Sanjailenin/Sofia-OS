import Foundation
import Testing
@testable import SofiaCore

@Suite struct ComputerTests {
    @Test func keysAndCombos() {
        #expect(KeyMap.parse("Return")! == (36, 0))
        #expect(KeyMap.parse("super+space")! == (49, KeyMap.command))
        #expect(KeyMap.parse("ctrl+shift+Tab")! == (48, KeyMap.control | KeyMap.shift))
        #expect(KeyMap.parse("super+c")! == (8, KeyMap.command))
        #expect(KeyMap.parse("A")! == (0, KeyMap.shift))
        #expect(KeyMap.parse("cmd+alt+Escape")! == (53, KeyMap.command | KeyMap.option))
        #expect(KeyMap.parse("F5")! == (96, 0))
        #expect(KeyMap.parse("hyper+x") == nil)
        #expect(KeyMap.parse("superduper") == nil)
        #expect(KeyMap.parse("") == nil)
    }

    @Test func coordinatesMapBackToTheScreen() {
        let s = ScreenScale(displayWidth: 1512, displayHeight: 982)
        #expect(s.imageWidth <= 1280 && s.imageHeight <= 800)
        let (x, y) = s.toDisplay(Double(s.imageWidth) / 2, Double(s.imageHeight) / 2)
        #expect(abs(x - 756) < 1 && abs(y - 491) < 1)
        let (cx, cy) = s.toDisplay(99_999, -50)
        #expect(cx == 1511 && cy == 0)
        #expect(ScreenScale(displayWidth: 1024, displayHeight: 640).scale == 1)
    }

    @Test func typedTextKeepsCharactersWhole() {
        #expect(TypedText.chunks("") == [])
        #expect(TypedText.chunks("hello") == [Array("hello".utf16)])
        let long = String(repeating: "a", count: 40)
        #expect(TypedText.chunks(long).map(\.count) == [16, 16, 8])
        let s = String(repeating: "x", count: 15) + "😀"
        let c = TypedText.chunks(s)
        #expect(c.count == 2 && c[0].count == 15 && c[1] == Array("😀".utf16))
        #expect(TypedText.chunks("🇩🇪", maxUnits: 2) == [Array("🇩🇪".utf16)])
    }

    @Test func modifierNamesForClicks() {
        #expect(KeyMap.modifierFlags(nil) == 0 && KeyMap.modifierFlags("  ") == 0)
        #expect(KeyMap.modifierFlags("shift") == KeyMap.shift)
        #expect(KeyMap.modifierFlags("super+shift") == KeyMap.command | KeyMap.shift)
        #expect(KeyMap.modifierFlags("hyper") == nil)
    }

    @Test func secretAppsAreOffLimits() {
        for b in ["com.apple.keychainaccess", "com.1password.1password", "com.bitwarden.desktop", "com.apple.Passwords"] { #expect(ComputerGuard.isBlocked(bundleID: b), "\(b)") }
        for b in ["com.spotify.client", "com.apple.Safari", nil] { #expect(!ComputerGuard.isBlocked(bundleID: b)) }
    }

}
