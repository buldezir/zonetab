import CoreGraphics
import Testing
@testable import ZoneTabCore

struct ScopeResolverTests {
    let displays = [Fixtures.lg, Fixtures.laptop]

    @Test func centreDecidesTheZone() {
        let window = CGRect(x: 100, y: 100, width: 800, height: 600)
        #expect(ScopeResolver.zoneMemberships(of: window, in: Fixtures.lgZones) == [.primary])
        let narrow = CGRect(x: 3000, y: 100, width: 600, height: 600)
        #expect(ScopeResolver.zoneMemberships(of: narrow, in: Fixtures.lgZones) == [.secondary])
    }

    @Test func fullDisplayWindowIsInBothZones() {
        #expect(ScopeResolver.zoneMemberships(of: Fixtures.lg.usableFrame, in: Fixtures.lgZones) == [.primary, .secondary])
    }

    @Test func straddlingWindowStaysInItsCentreZone() {
        // Centre at x=2000 (zone A); covers only 120 of zone B's 960 pt.
        let window = CGRect(x: 1000, y: 33, width: 2000, height: 1587)
        #expect(ScopeResolver.zoneMemberships(of: window, in: Fixtures.lgZones) == [.primary])
    }

    @Test func scopeFollowsTheCursor() {
        let a = ScopeResolver.scope(at: CGPoint(x: 500, y: 500), displays: displays, zonesEnabled: true, config: ZoneConfig(side: .left))
        #expect(a == Scope(displayID: 1, zone: .primary, rect: Fixtures.zoneA))
        let b = ScopeResolver.scope(at: CGPoint(x: 3500, y: 500), displays: displays, zonesEnabled: true, config: ZoneConfig(side: .left))
        #expect(b?.zone == .secondary)
        let laptop = ScopeResolver.scope(at: CGPoint(x: 4000, y: 500), displays: displays, zonesEnabled: true, config: ZoneConfig(side: .left))
        #expect(laptop == Scope(displayID: 2, zone: nil, rect: Fixtures.laptop.usableFrame))
    }

    @Test func scopeFollowsConfiguredWidth() {
        // At 60% the split is at x=2304, so x=2500 is in the secondary zone.
        let config = ZoneConfig(side: .left, width: .fraction(0.6))
        let scope = ScopeResolver.scope(at: CGPoint(x: 2500, y: 500), displays: displays, zonesEnabled: true, config: config)
        #expect(scope == Scope(displayID: 1, zone: .secondary, rect: CGRect(x: 2304, y: 33, width: 1536, height: 1587)))
        // Centre at x=2550: past the 60% split (2304) but before the 16:9 split (2880).
        let window = CGRect(x: 2350, y: 33, width: 400, height: 1000)
        #expect(ScopeResolver.contains(scope!, windowBounds: window, displays: displays, config: config))
        #expect(!ScopeResolver.contains(scope!, windowBounds: window, displays: displays, config: ZoneConfig()))
    }

    @Test func zonesOffMeansWholeDisplay() {
        let scope = ScopeResolver.scope(at: CGPoint(x: 3500, y: 500), displays: displays, zonesEnabled: false, config: ZoneConfig(side: .left))
        #expect(scope == Scope(displayID: 1, zone: nil, rect: Fixtures.lg.usableFrame))
    }

    @Test func windowsOnOtherDisplaysAreOutOfScope() {
        let scope = Scope(displayID: 1, zone: nil, rect: Fixtures.lg.usableFrame)
        #expect(ScopeResolver.contains(scope, windowBounds: CGRect(x: 100, y: 100, width: 500, height: 500), displays: displays, config: ZoneConfig(side: .left)))
        #expect(!ScopeResolver.contains(scope, windowBounds: CGRect(x: 4000, y: 100, width: 500, height: 500), displays: displays, config: ZoneConfig(side: .left)))
        // Mostly on the laptop: belongs to the laptop.
        #expect(!ScopeResolver.contains(scope, windowBounds: CGRect(x: 3700, y: 100, width: 1000, height: 500), displays: displays, config: ZoneConfig(side: .left)))
    }

    @Test func pointBetweenDisplaysPicksNearest() {
        // Below the laptop (183 pt away) and right of the LG (660 pt away).
        #expect(ScopeResolver.display(at: CGPoint(x: 4500, y: 1300), in: displays)?.id == 2)
        #expect(ScopeResolver.display(at: CGPoint(x: 4000, y: 1500), in: displays)?.id == 1)
    }
}
