import CoreGraphics
import Testing
@testable import ZoneTabCore

struct MouseFocusTests {
    let apps: [Int32: AppInfo] = [1: Fixtures.app(1), 2: Fixtures.app(2), 3: Fixtures.app(3, regular: false)]
    let inB = CGPoint(x: 3300, y: 800)
    let terminal = WindowInfo(id: 20, pid: 2, bounds: Fixtures.zoneB)

    func target(at point: CGPoint, _ windows: [WindowInfo], frontmost: Int32? = 3) -> MouseFocusTarget {
        MouseFocus.target(at: point, windows: windows, apps: apps, frontmostPID: frontmost, ownPID: 99)
    }

    @Test func picksTheTopmostWindowUnderTheMouse() {
        let browser = WindowInfo(id: 10, pid: 1, bounds: Fixtures.zoneA)
        let behind = WindowInfo(id: 21, pid: 2, bounds: Fixtures.lg.usableFrame)
        #expect(target(at: inB, [browser, terminal, behind]) == .window(terminal))
        #expect(target(at: CGPoint(x: 500, y: 800), [terminal, browser], frontmost: 2) == .window(browser))
    }

    @Test func theFocusedWindowNeedsNothing() {
        #expect(target(at: inB, [terminal], frontmost: 2) == .focused)
        // The frontmost app's other window, further back, does need focusing.
        let front = WindowInfo(id: 22, pid: 2, bounds: Fixtures.zoneA)
        #expect(target(at: inB, [front, terminal], frontmost: 2) == .window(terminal))
    }

    @Test func menusDockAndTheDesktopAreNotTargets() {
        let menu = WindowInfo(id: 30, pid: 1, bounds: CGRect(x: 3200, y: 700, width: 300, height: 400), layer: 101)
        #expect(target(at: inB, [menu, terminal]) == .none)
        let dock = WindowInfo(id: 31, pid: 50, bounds: CGRect(x: 1000, y: 1500, width: 2600, height: 120), layer: 20)
        #expect(target(at: CGPoint(x: 3300, y: 1550), [dock, terminal]) == .none)
        #expect(target(at: CGPoint(x: 3300, y: 10), [terminal]) == .none)
    }

    @Test func looksThroughBackgroundAppsOwnAndInvisibleWindows() {
        let overlay = WindowInfo(id: 40, pid: 3, bounds: Fixtures.lg.frame)
        let own = WindowInfo(id: 41, pid: 99, bounds: Fixtures.lg.frame)
        let invisible = WindowInfo(id: 42, pid: 1, bounds: Fixtures.lg.frame, alpha: 0)
        #expect(target(at: inB, [overlay, own, invisible, terminal]) == .window(terminal))
    }

    @Test func smallWindowsInFrontBlock() {
        let palette = WindowInfo(id: 50, pid: 1, bounds: CGRect(x: 3250, y: 750, width: 80, height: 80))
        #expect(target(at: inB, [palette, terminal]) == .none)
    }
}
