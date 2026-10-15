import CoreGraphics
import Testing
@testable import ZoneTabCore

struct SwitcherListBuilderTests {
    let displays = [Fixtures.lg, Fixtures.laptop]
    let ownPID: Int32 = 999
    var zoneA: Scope { Scope(displayID: 1, zone: .primary, rect: Fixtures.zoneA) }
    var zoneB: Scope { Scope(displayID: 1, zone: .secondary, rect: Fixtures.zoneB) }

    func inA(_ id: UInt32, _ pid: Int32) -> WindowInfo { WindowInfo(id: id, pid: pid, bounds: Fixtures.zoneA) }
    func inB(_ id: UInt32, _ pid: Int32) -> WindowInfo { WindowInfo(id: id, pid: pid, bounds: Fixtures.zoneB) }

    func build(_ windows: [WindowInfo], apps: [AppInfo], frontmost: Int32?, scope: Scope) -> SwitcherList {
        SwitcherListBuilder.build(windows: windows, apps: Dictionary(uniqueKeysWithValues: apps.map { ($0.pid, $0) }),
                                  frontmostPID: frontmost, ownPID: ownPID, scope: scope, displays: displays, side: .left)
    }

    @Test func listsOnlyAppsInTheZoneInZOrder() {
        let windows = [inA(10, 1), inB(20, 2), inA(11, 3), inA(12, 1), inB(21, 4)]
        let list = build(windows, apps: [1, 2, 3, 4].map { Fixtures.app($0) }, frontmost: 1, scope: zoneA)
        #expect(list.entries == [SwitcherEntry(pid: 1, windowID: 10), SwitcherEntry(pid: 3, windowID: 11)])
        #expect(list.initialSelection == 1)
    }

    @Test func frontmostAppElsewhereStartsAtFirstEntry() {
        // Cursor in zone B; the focused app (1) is in zone A.
        let windows = [inA(10, 1), inB(20, 2), inB(21, 4)]
        let list = build(windows, apps: [1, 2, 4].map { Fixtures.app($0) }, frontmost: 1, scope: zoneB)
        #expect(list.entries.map(\.pid) == [2, 4])
        #expect(list.initialSelection == 0)
    }

    @Test func appWithWindowsInBothZonesTargetsTheZonesWindow() {
        // App 1 is focused in zone A but also has a window in zone B.
        let windows = [inA(10, 1), inB(20, 2), inB(11, 1)]
        let list = build(windows, apps: [1, 2].map { Fixtures.app($0) }, frontmost: 1, scope: zoneB)
        #expect(list.entries == [SwitcherEntry(pid: 2, windowID: 20), SwitcherEntry(pid: 1, windowID: 11)])
        #expect(list.initialSelection == 0)
    }

    @Test func onlyTheCurrentAppMeansNothingToSwitchTo() {
        let list = build([inA(10, 1)], apps: [Fixtures.app(1)], frontmost: 1, scope: zoneA)
        #expect(list.entries.count == 1)
        #expect(list.initialSelection == nil)
    }

    @Test func singleOtherAppIsSelected() {
        let list = build([inA(10, 1)], apps: [Fixtures.app(1)], frontmost: 7, scope: zoneA)
        #expect(list.initialSelection == 0)
    }

    @Test func emptyScope() {
        let list = build([inB(20, 2)], apps: [Fixtures.app(2)], frontmost: 2, scope: zoneA)
        #expect(list.entries.isEmpty)
        #expect(list.initialSelection == nil)
    }

    @Test func skipsOwnAccessoryTinyAndOverlayWindows() {
        let windows = [
            inA(1, ownPID),
            inA(2, 5),                                                               // accessory app
            WindowInfo(id: 3, pid: 6, bounds: CGRect(x: 10, y: 40, width: 80, height: 40)), // too small
            WindowInfo(id: 4, pid: 7, bounds: Fixtures.zoneA, layer: 25),          // status/overlay layer
            WindowInfo(id: 5, pid: 8, bounds: Fixtures.zoneA, alpha: 0),           // invisible
            inA(6, 9),
        ]
        let apps = [Fixtures.app(ownPID), Fixtures.app(5, regular: false), Fixtures.app(6), Fixtures.app(7), Fixtures.app(8), Fixtures.app(9)]
        let list = build(windows, apps: apps, frontmost: nil, scope: zoneA)
        #expect(list.entries.map(\.pid) == [9])
    }

    @Test func hiddenAppsComeLastByActivationOrder() {
        let windows = [
            inA(10, 1),
            WindowInfo(id: 30, pid: 3, bounds: Fixtures.zoneA, isOnScreen: false),
            WindowInfo(id: 40, pid: 4, bounds: Fixtures.zoneA, isOnScreen: false),
            WindowInfo(id: 50, pid: 5, bounds: Fixtures.zoneB, isOnScreen: false),
        ]
        let apps = [Fixtures.app(1, rank: 0), Fixtures.app(3, rank: 5, hidden: true),
                    Fixtures.app(4, rank: 2, hidden: true), Fixtures.app(5, rank: 1, hidden: true)]
        let list = build(windows, apps: apps, frontmost: 1, scope: zoneA)
        #expect(list.entries == [
            SwitcherEntry(pid: 1, windowID: 10),
            SwitcherEntry(pid: 4, windowID: 40, isHidden: true),
            SwitcherEntry(pid: 3, windowID: 30, isHidden: true),
        ])
        #expect(list.initialSelection == 1)
    }

    @Test func offScreenWindowsOfVisibleAppsAreIgnored() {
        // Minimized or on another Space: not listed in v1.
        let windows = [WindowInfo(id: 10, pid: 1, bounds: Fixtures.zoneA, isOnScreen: false)]
        #expect(build(windows, apps: [Fixtures.app(1)], frontmost: nil, scope: zoneA).entries.isEmpty)
    }

    @Test func displayScopeIncludesBothZones() {
        let scope = Scope(displayID: 1, zone: nil, rect: Fixtures.lg.usableFrame)
        let windows = [inA(10, 1), inB(20, 2), WindowInfo(id: 30, pid: 3, bounds: CGRect(x: 4000, y: 0, width: 800, height: 600))]
        let list = build(windows, apps: [1, 2, 3].map { Fixtures.app($0) }, frontmost: 1, scope: scope)
        #expect(list.entries.map(\.pid) == [1, 2])
    }

    @Test func fallbackListsEveryAppByActivation() {
        let windows = [
            WindowInfo(id: 10, pid: 1, bounds: Fixtures.lg.frame),
            WindowInfo(id: 20, pid: 2, bounds: Fixtures.zoneA, isOnScreen: false),
            WindowInfo(id: 30, pid: 3, bounds: Fixtures.zoneB, isOnScreen: false),
        ]
        let apps = [Fixtures.app(1, rank: 0), Fixtures.app(2, rank: 2), Fixtures.app(3, rank: 1), Fixtures.app(4, rank: 3)]
        let list = SwitcherListBuilder.buildFallback(windows: windows, apps: Dictionary(uniqueKeysWithValues: apps.map { ($0.pid, $0) }),
                                                     frontmostPID: 1, ownPID: ownPID)
        #expect(list.entries.map(\.pid) == [1, 3, 2])
        #expect(list.entries.map(\.windowID) == [10, 30, 20])
        #expect(list.initialSelection == 1)
    }
}
