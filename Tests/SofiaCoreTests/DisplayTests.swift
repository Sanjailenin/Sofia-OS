import Testing
@testable import SofiaCore

struct DisplayTests {
    let laptop = IslandPlacement.Screen(index: 0, x: 0, y: 0, width: 1512, height: 982, hasNotch: true, isMain: true)
    let external = IslandPlacement.Screen(index: 1, x: 1512, y: 200, width: 2560, height: 1440, hasNotch: false, isMain: false)

    @Test func followUsesTheScreenUnderTheMouse() {
        #expect(IslandPlacement.choose([laptop, external], mode: .follow, mouse: (2000, 800)) == external)
        #expect(IslandPlacement.choose([laptop, external], mode: .follow, mouse: (100, 100)) == laptop)
        #expect(IslandPlacement.choose([laptop, external], mode: .follow, mouse: nil) == laptop)
        #expect(IslandPlacement.choose([external], mode: .follow, mouse: (5000, 5000)) == external)
    }
    @Test func builtinAndMainModes() {
        #expect(IslandPlacement.choose([laptop, external], mode: .builtin, mouse: (2000, 800)) == laptop)
        var ext = external; ext.isMain = true; var lap = laptop; lap.isMain = false
        #expect(IslandPlacement.choose([lap, ext], mode: .main, mouse: (100, 100)) == ext)
        #expect(IslandPlacement.choose([ext], mode: .builtin, mouse: nil) == ext)
        #expect(IslandPlacement.choose([], mode: .follow, mouse: nil) == nil)
    }

    @Test func scaleMapsThroughTheDisplayOrigin() {
        let s = ScreenScale(displayWidth: 2560, displayHeight: 1440, originX: 1512, originY: -200, displayID: 7)
        #expect(s.scale == 0.5 && s.imageWidth == 1280 && s.imageHeight == 720)
        let (gx, gy) = s.toDisplay(640, 360)
        #expect(gx == 1512 + 1280 && gy == -200 + 720)
        #expect(s.toImage(gx, gy) == (640, 360))
        let (lx, ly) = s.toLocal(640, 360); #expect(lx == 1280 && ly == 720)
        #expect(s.contains(1600, 0) && !s.contains(100, 100) && !s.contains(1512 + 2560, 0))
        let (cx, cy) = s.toDisplay(-50, 99999); #expect(cx == 1512 && cy == -200 + 1439)
    }
    @Test func primaryDisplayIsUnchanged() {
        let s = ScreenScale(displayWidth: 1024, displayHeight: 640)
        let (x, y) = s.toDisplay(100, 50); #expect(x == 100 && y == 50)
        #expect(s.toImage(100, 50) == (100, 50))
    }
}
