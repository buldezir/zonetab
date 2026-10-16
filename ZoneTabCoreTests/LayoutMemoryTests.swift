import CoreGraphics
import Testing
@testable import ZoneTabCore

struct LayoutMemoryTests {
    let config = ZoneConfig(side: .left)
    let floating = CGRect(x: 1000, y: 400, width: 700, height: 500)
    var apps: [Int32: AppInfo] {
        [1: AppInfo(pid: 1, bundleID: "one", name: "One"), 2: AppInfo(pid: 2, bundleID: "two", name: "Two"),
         3: AppInfo(pid: 3, bundleID: "three", name: "Three")]
    }

    /// The LG, unplugged: only the laptop is left, now the primary display at the origin.
    let laptopAlone = DisplayInfo(id: 2, uuid: "Laptop", frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                                  usableFrame: CGRect(x: 0, y: 38, width: 1728, height: 1079))

    func record(_ windows: [WindowInfo], apps: [Int32: AppInfo]? = nil) -> DisplayLayout? {
        LayoutMemory.record(display: Fixtures.lg, displays: [Fixtures.lg, Fixtures.laptop], windows: windows,
                            apps: apps ?? self.apps, ownPID: 99, config: config)
    }

    @Test func recordsTilesAndFloatingFrames() {
        let layout = record([
            WindowInfo(id: 10, pid: 1, bounds: Fixtures.zoneA),
            WindowInfo(id: 11, pid: 2, bounds: CGRect(x: 2880, y: 33, width: 953, height: 1572)), // a terminal's steps
            WindowInfo(id: 12, pid: 3, bounds: Fixtures.lg.usableFrame, isOnScreen: false), // another Space
            WindowInfo(id: 13, pid: 3, bounds: floating),
        ])
        #expect(layout == DisplayLayout(displayUUID: "LG", windows: [
            SavedWindow(id: 10, pid: 1, bundleID: "one", placement: .zone(.primary)),
            SavedWindow(id: 11, pid: 2, bundleID: "two", placement: .zone(.secondary)),
            SavedWindow(id: 12, pid: 3, bundleID: "three", placement: .display),
            SavedWindow(id: 13, pid: 3, bundleID: "three", placement: .frame(floating)),
        ]))
    }

    @Test func leavesOutOtherDisplaysFullScreenAndNonAppWindows() {
        let layout = record([
            WindowInfo(id: 10, pid: 1, bounds: Fixtures.laptop.usableFrame),
            WindowInfo(id: 11, pid: 1, bounds: Fixtures.lg.frame, isOnScreen: false, isFullScreen: true),
            WindowInfo(id: 12, pid: 1, bounds: Fixtures.zoneA, layer: 3),
            WindowInfo(id: 13, pid: 99, bounds: Fixtures.zoneA),
            WindowInfo(id: 14, pid: 4, bounds: Fixtures.zoneA), // not a running app
        ])
        #expect(layout?.windows == [])
    }

    @Test func unzonedDisplaysHaveNoLayout() {
        #expect(LayoutMemory.record(display: Fixtures.laptop, displays: [Fixtures.lg, Fixtures.laptop], windows: [],
                                    apps: apps, ownPID: 99, config: config) == nil)
    }

    @Test func floatingFramesAreRelativeToTheDisplay() {
        let right = DisplayInfo(id: 1, uuid: "LG", frame: CGRect(x: 1728, y: 0, width: 3840, height: 1620),
                                usableFrame: CGRect(x: 1728, y: 33, width: 3840, height: 1587))
        let layout = LayoutMemory.record(display: right, displays: [right], windows: [
            WindowInfo(id: 10, pid: 1, bounds: floating.offsetBy(dx: 1728, dy: 0)),
        ], apps: apps, ownPID: 99, config: config)
        #expect(layout?.windows.first?.placement == .frame(floating))
    }

    @Test func unpluggedTilesFillTheDisplayTheyEndUpOn() {
        let layout = DisplayLayout(displayUUID: "LG", windows: [
            SavedWindow(id: 10, pid: 1, bundleID: "one", placement: .zone(.primary)),
            SavedWindow(id: 11, pid: 2, bundleID: "two", placement: .display),
            SavedWindow(id: 12, pid: 3, bundleID: "three", placement: .frame(floating)),
            SavedWindow(id: 13, pid: 3, bundleID: "three", placement: .frame(CGRect(x: 0, y: 33, width: 2000, height: 1587))),
        ])
        // Where macOS left them: squeezed onto the laptop, partly off it.
        let now = [
            WindowInfo(id: 10, pid: 1, bounds: CGRect(x: 0, y: 38, width: 1728, height: 1079)),
            WindowInfo(id: 11, pid: 2, bounds: CGRect(x: 100, y: 200, width: 1600, height: 900)),
            WindowInfo(id: 12, pid: 3, bounds: CGRect(x: 300, y: 300, width: 700, height: 500)),
            WindowInfo(id: 13, pid: 3, bounds: CGRect(x: 0, y: 38, width: 2000, height: 1079)),
        ]
        let changes = LayoutMemory.maximizeChanges(for: layout, displays: [laptopAlone], windows: now, apps: apps)
        let usable = laptopAlone.usableFrame
        #expect(changes == [
            FrameChange(windowID: 11, pid: 2, frame: usable, bounds: usable),
            FrameChange(windowID: 13, pid: 3, frame: CGRect(x: 0, y: 38, width: 1728, height: 1079), bounds: usable),
        ])
    }

    @Test func pluggedBackTilesReturnToTheirZones() {
        let layout = DisplayLayout(displayUUID: "LG", windows: [
            SavedWindow(id: 10, pid: 1, bundleID: "one", placement: .zone(.primary)),
            SavedWindow(id: 11, pid: 2, bundleID: "two", placement: .zone(.secondary)),
            SavedWindow(id: 12, pid: 3, bundleID: "three", placement: .display),
            SavedWindow(id: 13, pid: 3, bundleID: "three", placement: .frame(floating)),
        ])
        let laptopFrame = Fixtures.laptop.usableFrame
        let now = [10, 11, 12, 13].map { WindowInfo(id: $0, pid: $0 == 10 ? 1 : $0 == 11 ? 2 : 3, bounds: laptopFrame) }
        let changes = LayoutMemory.restoreChanges(for: layout, on: Fixtures.lg, windows: now, apps: apps, config: config)
        let usable = Fixtures.lg.usableFrame
        #expect(changes.map(\.frame) == [Fixtures.zoneA, Fixtures.zoneB, usable, floating])
        #expect(changes.allSatisfy { $0.bounds == usable })
    }

    @Test func restoreUsesTheCurrentZoneWidth() {
        let layout = DisplayLayout(displayUUID: "LG", windows: [SavedWindow(id: 10, pid: 1, bundleID: "one", placement: .zone(.secondary))])
        let now = [WindowInfo(id: 10, pid: 1, bounds: Fixtures.laptop.usableFrame)]
        let changes = LayoutMemory.restoreChanges(for: layout, on: Fixtures.lg, windows: now, apps: apps,
                                                  config: ZoneConfig(side: .left, width: .fraction(0.6)))
        #expect(changes.first?.frame == CGRect(x: 2304, y: 33, width: 1536, height: 1587))
    }

    @Test func skipsClosedReusedFullScreenAndAlreadyPlacedWindows() {
        let layout = DisplayLayout(displayUUID: "LG", windows: [
            SavedWindow(id: 10, pid: 1, bundleID: "one", placement: .zone(.primary)), // closed
            SavedWindow(id: 11, pid: 2, bundleID: "two", placement: .zone(.primary)), // id reused by another app
            SavedWindow(id: 12, pid: 3, bundleID: "old", placement: .zone(.primary)), // pid reused after a restart
            SavedWindow(id: 13, pid: 3, bundleID: "three", placement: .zone(.primary)), // full screen now
            SavedWindow(id: 14, pid: 3, bundleID: "three", placement: .zone(.secondary)), // already there
        ])
        let now = [
            WindowInfo(id: 11, pid: 1, bounds: floating),
            WindowInfo(id: 12, pid: 3, bounds: floating),
            WindowInfo(id: 13, pid: 3, bounds: Fixtures.lg.frame, isOnScreen: false, isFullScreen: true),
            WindowInfo(id: 14, pid: 3, bounds: CGRect(x: 2881, y: 33, width: 958, height: 1586)),
        ]
        #expect(LayoutMemory.restoreChanges(for: layout, on: Fixtures.lg, windows: now, apps: apps, config: config) == [])
        #expect(LayoutMemory.maximizeChanges(for: layout, displays: [Fixtures.lg], windows: now, apps: apps).map(\.windowID) == [14])
    }

    @Test func windowsLeftOffEveryDisplayGoToTheFirst() {
        let layout = DisplayLayout(displayUUID: "LG", windows: [SavedWindow(id: 10, pid: 1, bundleID: "one", placement: .zone(.primary))])
        let now = [WindowInfo(id: 10, pid: 1, bounds: CGRect(x: 5000, y: 0, width: 800, height: 600))]
        let changes = LayoutMemory.maximizeChanges(for: layout, displays: [laptopAlone], windows: now, apps: apps)
        #expect(changes.first?.frame == laptopAlone.usableFrame)
    }

    func actions(away: Set<String> = [], wentOffline: Set<String> = [], online: Set<String>, rearranged: Bool) -> DisplayChangeActions {
        LayoutMemory.actions(recorded: ["LG"], away: away, wentOffline: wentOffline, online: online, rearranged: rearranged)
    }

    @Test func unpluggingMaximizesOnce() {
        #expect(actions(wentOffline: ["LG"], online: ["Laptop"], rearranged: true) == DisplayChangeActions(maximize: ["LG"], restore: []))
        // Opening the lid on the laptop later, the LG is still away: nothing more to do.
        #expect(actions(away: ["LG"], online: ["Laptop"], rearranged: true) == DisplayChangeActions(maximize: [], restore: []))
    }

    @Test func pluggingBackInRestores() {
        #expect(actions(away: ["LG"], online: ["LG", "Laptop"], rearranged: true) == DisplayChangeActions(maximize: [], restore: ["LG"]))
        // Plugged back in with the lid closed: the configuration is the same as before it went away.
        #expect(actions(away: ["LG"], online: ["LG"], rearranged: false) == DisplayChangeActions(maximize: [], restore: ["LG"]))
    }

    @Test func briefDropOutRestores() {
        #expect(actions(wentOffline: ["LG"], online: ["LG"], rearranged: false) == DisplayChangeActions(maximize: [], restore: ["LG"]))
    }

    @Test func lidClosingOrOpeningRestores() {
        // The laptop's display goes offline (lid closed) or comes back (lid opened); the LG stays connected.
        #expect(actions(online: ["LG"], rearranged: true) == DisplayChangeActions(maximize: [], restore: ["LG"]))
        #expect(actions(online: ["LG", "Laptop"], rearranged: true) == DisplayChangeActions(maximize: [], restore: ["LG"]))
    }

    @Test func changesThatMoveNothingDoNothing() {
        #expect(actions(online: ["LG"], rearranged: false) == DisplayChangeActions(maximize: [], restore: []))
    }

    @Test func fitShrinksAndMovesInside() {
        let bounds = CGRect(x: 0, y: 38, width: 1728, height: 1079)
        #expect(LayoutMemory.fit(CGRect(x: 1500, y: 0, width: 600, height: 400), in: bounds) == CGRect(x: 1128, y: 38, width: 600, height: 400))
        #expect(LayoutMemory.fit(CGRect(x: -100, y: 500, width: 3000, height: 2000), in: bounds) == bounds)
        #expect(LayoutMemory.fit(floating, in: bounds) == floating)
    }
}
