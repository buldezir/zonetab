import CoreGraphics
import Testing
@testable import ZoneTabCore

struct TileActionsTests {
    let usable = Fixtures.lg.usableFrame
    let zones = Fixtures.lgZones
    let smallWindow = CGRect(x: 200, y: 200, width: 900, height: 700)

    func plan(_ command: TileCommand, _ frame: CGRect, zones: [Zone]? = Fixtures.lgZones, memory: TileMemory? = nil,
              cursor: ZoneKind? = nil) -> TilePlan {
        TileActions.plan(command, windowFrame: frame, usable: usable, zones: zones, memory: memory, cursorZone: cursor)
    }

    @Test func arrowsMoveToZones() {
        #expect(plan(.left, smallWindow) == TilePlan(placement: .zone(.primary), frame: Fixtures.zoneA))
        #expect(plan(.right, smallWindow) == TilePlan(placement: .zone(.secondary), frame: Fixtures.zoneB))
    }

    @Test func arrowsFollowScreenSidesWhenPrimaryIsRight() {
        let flipped = ZoneLayout.zones(for: Fixtures.lg, config: ZoneConfig(side: .right))!
        #expect(plan(.left, smallWindow, zones: flipped).placement == .zone(.secondary))
        #expect(plan(.right, smallWindow, zones: flipped).placement == .zone(.primary))
    }

    @Test func fillCyclesZoneDisplayZone() {
        let window = CGRect(x: 3000, y: 100, width: 500, height: 500) // centre in zone B
        let first = plan(.fill, window)
        #expect(first == TilePlan(placement: .zone(.secondary), frame: Fixtures.zoneB))

        let memory1 = TileMemory(placement: first.placement, frame: first.frame)
        let second = plan(.fill, first.frame, memory: memory1, cursor: .primary)
        #expect(second == TilePlan(placement: .display, frame: usable, zoneBeforeDisplay: .secondary))

        let memory2 = TileMemory(placement: second.placement, frame: second.frame, zoneBeforeDisplay: second.zoneBeforeDisplay)
        let third = plan(.fill, second.frame, memory: memory2, cursor: .primary)
        #expect(third == TilePlan(placement: .zone(.secondary), frame: Fixtures.zoneB))
    }

    @Test func fillUsesReadBackFrameFromMemory() {
        // Terminal-like apps round the size; memory holds the frame they actually took.
        let actual = CGRect(x: 0, y: 33, width: 2875, height: 1580)
        let memory = TileMemory(placement: .zone(.primary), frame: actual)
        #expect(plan(.fill, actual, memory: memory).placement == .display)
    }

    @Test func movedWindowForgetsMemory() {
        let memory = TileMemory(placement: .zone(.primary), frame: Fixtures.zoneA)
        #expect(plan(.fill, smallWindow, memory: memory).placement == .zone(.primary))
    }

    @Test func windowAlreadyFillingAZoneExpands() {
        #expect(plan(.fill, Fixtures.zoneA).placement == .display)
    }

    @Test func displayWithoutMemoryReturnsToCursorZone() {
        #expect(plan(.fill, usable, cursor: .secondary) == TilePlan(placement: .zone(.secondary), frame: Fixtures.zoneB))
        #expect(plan(.fill, usable).placement == .zone(.primary)) // centre of the display is in zone A
    }

    @Test func unzonedDisplayUsesHalvesAndMaximize() {
        #expect(plan(.fill, smallWindow, zones: nil) == TilePlan(placement: .display, frame: usable))
        #expect(plan(.left, smallWindow, zones: nil) == TilePlan(placement: .leftHalf, frame: CGRect(x: 0, y: 33, width: 1920, height: 1587)))
        #expect(plan(.right, smallWindow, zones: nil) == TilePlan(placement: .rightHalf, frame: CGRect(x: 1920, y: 33, width: 1920, height: 1587)))
    }
}
