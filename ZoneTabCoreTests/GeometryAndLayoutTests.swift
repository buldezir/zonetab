import CoreGraphics
import Testing
@testable import ZoneTabCore

struct GeometryTests {
    @Test func flipIsItsOwnInverse() {
        let rect = CGRect(x: -1728, y: 200, width: 800, height: 600)
        let flipped = Geometry.flip(rect, primaryMaxY: 1620)
        #expect(flipped == CGRect(x: -1728, y: 820, width: 800, height: 600))
        #expect(Geometry.flip(flipped, primaryMaxY: 1620) == rect)
    }

    @Test func flipPoint() {
        #expect(Geometry.flip(CGPoint(x: 10, y: 0), primaryMaxY: 1620) == CGPoint(x: 10, y: 1620))
    }

    @Test func approximateEquality() {
        let a = CGRect(x: 0, y: 33, width: 2880, height: 1587)
        #expect(Geometry.approximatelyEqual(a, a.insetBy(dx: 1, dy: 1)))
        #expect(!Geometry.approximatelyEqual(a, a.insetBy(dx: 3, dy: 0)))
    }
}

struct ZoneLayoutTests {
    @Test func lgSplitsAt4KColumn() throws {
        let zones = try #require(ZoneLayout.zones(for: Fixtures.lg, side: .left))
        #expect(zones.map(\.kind) == [.primary, .secondary])
        #expect(zones[0].rect == CGRect(x: 0, y: 33, width: 2880, height: 1587))
        #expect(zones[1].rect == CGRect(x: 2880, y: 33, width: 960, height: 1587))
    }

    @Test func primaryOnTheRight() throws {
        let zones = try #require(ZoneLayout.zones(for: Fixtures.lg, side: .right))
        #expect(zones.map(\.kind) == [.secondary, .primary])
        #expect(zones[0].rect.width == 960)
        #expect(zones[1].rect == CGRect(x: 960, y: 33, width: 2880, height: 1587))
    }

    @Test(arguments: [
        (CGSize(width: 3440, height: 1440), 2560.0, 880.0),
        (CGSize(width: 5120, height: 1440), 2560.0, 2560.0),
        (CGSize(width: 2560, height: 1080), 1920.0, 640.0),
    ])
    func otherUltrawides(size: CGSize, primary: CGFloat, secondary: CGFloat) throws {
        let frame = CGRect(origin: .zero, size: size)
        let display = DisplayInfo(id: 9, uuid: "X", frame: frame, usableFrame: frame)
        let zones = try #require(ZoneLayout.zones(for: display, side: .left))
        #expect(zones[0].rect.width == primary)
        #expect(zones[1].rect.width == secondary)
    }

    @Test(arguments: [CGSize(width: 3840, height: 2160), CGSize(width: 1728, height: 1117), CGSize(width: 1080, height: 1920)])
    func regularDisplaysAreNotZoned(size: CGSize) {
        let frame = CGRect(origin: .zero, size: size)
        #expect(ZoneLayout.zones(for: DisplayInfo(id: 9, uuid: "X", frame: frame, usableFrame: frame), side: .left) == nil)
    }

    @Test func offsetDisplayKeepsItsOrigin() throws {
        let frame = CGRect(x: -3440, y: -200, width: 3440, height: 1440)
        let display = DisplayInfo(id: 3, uuid: "Y", frame: frame, usableFrame: frame)
        let zones = try #require(ZoneLayout.zones(for: display, side: .left))
        #expect(zones[0].rect == CGRect(x: -3440, y: -200, width: 2560, height: 1440))
        #expect(zones[1].rect == CGRect(x: -880, y: -200, width: 880, height: 1440))
    }

    @Test func autohiddenDockInsetIsIgnored() {
        let frame = CGRect(x: 0, y: 0, width: 3840, height: 1620)
        let visible = CGRect(x: 0, y: 33, width: 3840, height: 1583) // 4 pt reserved at the bottom
        #expect(ZoneLayout.usableFrame(frame: frame, visibleFrame: visible, dockAutohides: true)
            == CGRect(x: 0, y: 33, width: 3840, height: 1587))
        #expect(ZoneLayout.usableFrame(frame: frame, visibleFrame: visible, dockAutohides: false) == visible)
    }

    @Test func visibleDockIsKept() {
        let frame = CGRect(x: 0, y: 0, width: 3840, height: 1620)
        let visible = CGRect(x: 0, y: 33, width: 3840, height: 1517) // 70 pt Dock
        #expect(ZoneLayout.usableFrame(frame: frame, visibleFrame: visible, dockAutohides: true) == visible)
    }

    @Test func zoneAtX() {
        let zones = Fixtures.lgZones
        #expect(ZoneLayout.zone(atX: 100, in: zones)?.kind == .primary)
        #expect(ZoneLayout.zone(atX: 2879.5, in: zones)?.kind == .primary)
        #expect(ZoneLayout.zone(atX: 2880, in: zones)?.kind == .secondary)
        #expect(ZoneLayout.zone(atX: -50, in: zones)?.kind == .primary)
        #expect(ZoneLayout.zone(atX: 5000, in: zones)?.kind == .secondary)
    }
}
