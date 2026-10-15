import CoreGraphics

/// The part of the screen the switcher lists apps for: a whole display, or one zone of it.
public struct Scope: Sendable, Equatable, Codable {
    public var displayID: UInt32
    /// nil when the scope is the whole display.
    public var zone: ZoneKind?
    /// The zone rect, or the display's usable frame.
    public var rect: CGRect

    public init(displayID: UInt32, zone: ZoneKind?, rect: CGRect) {
        self.displayID = displayID
        self.zone = zone
        self.rect = rect
    }
}

public enum ScopeResolver {
    /// A window belongs to any zone it covers at least this much of, in addition to the zone holding its centre.
    public static let zoneCoverageThreshold: CGFloat = 0.5
    /// A window counts as tiled when it covers at least this share of a zone's width and height.
    public static let tiledCoverage: CGFloat = 0.9

    /// The display containing `point`, or the nearest one if the point is in a gap between displays.
    public static func display(at point: CGPoint, in displays: [DisplayInfo]) -> DisplayInfo? {
        if let hit = displays.first(where: { $0.frame.contains(point) }) { return hit }
        return displays.min { distance(point, $0.frame) < distance(point, $1.frame) }
    }

    /// The display a window is on: the one with the largest intersection, or nil if it's off every display.
    public static func display(for windowBounds: CGRect, in displays: [DisplayInfo]) -> DisplayInfo? {
        let best = displays.max {
            Geometry.intersectionArea(windowBounds, $0.frame) < Geometry.intersectionArea(windowBounds, $1.frame)
        }
        guard let best, Geometry.intersectionArea(windowBounds, best.frame) > 0 else { return nil }
        return best
    }

    /// Zones a window belongs to: the zone holding its centre, plus any zone it covers at least half of.
    /// A window spanning the whole display therefore belongs to every zone.
    public static func zoneMemberships(of windowBounds: CGRect, in zones: [Zone]) -> Set<ZoneKind> {
        var result = Set<ZoneKind>()
        if let centre = ZoneLayout.zone(atX: windowBounds.midX, in: zones) { result.insert(centre.kind) }
        for zone in zones {
            let zoneArea = Geometry.area(zone.rect)
            guard zoneArea > 0 else { continue }
            if Geometry.intersectionArea(windowBounds, zone.rect) / zoneArea >= zoneCoverageThreshold {
                result.insert(zone.kind)
            }
        }
        return result
    }

    /// The scope at the cursor: its zone when zones are on and the display is zoned, otherwise its display.
    public static func scope(at point: CGPoint, displays: [DisplayInfo], zonesEnabled: Bool, config: ZoneConfig) -> Scope? {
        guard let display = display(at: point, in: displays) else { return nil }
        if zonesEnabled, let zones = ZoneLayout.zones(for: display, config: config),
           let zone = ZoneLayout.zone(atX: point.x, in: zones) {
            return Scope(displayID: display.id, zone: zone.kind, rect: zone.rect)
        }
        return Scope(displayID: display.id, zone: nil, rect: display.usableFrame)
    }

    /// Whether a window fills a zone, or all zones together. Apps that resize in steps (terminals) stop a little
    /// short of a zone's edges, so this isn't an exact match.
    public static func isTiled(_ windowBounds: CGRect, in zones: [Zone]) -> Bool {
        guard let first = zones.first else { return false }
        let all = zones.dropFirst().reduce(first.rect) { $0.union($1.rect) }
        return (zones.map(\.rect) + [all]).contains { rect in
            let overlap = windowBounds.intersection(rect)
            return !overlap.isNull && overlap.width >= rect.width * tiledCoverage && overlap.height >= rect.height * tiledCoverage
        }
    }

    /// - Parameter untiledInEveryZone: windows that don't fill a zone (settings windows, dialogs, anything sized
    ///   by hand) belong to every zone of their display rather than to the zone they happen to sit in.
    public static func contains(_ scope: Scope, windowBounds: CGRect, displays: [DisplayInfo], config: ZoneConfig,
                                untiledInEveryZone: Bool = false) -> Bool {
        guard let display = display(for: windowBounds, in: displays), display.id == scope.displayID else { return false }
        guard let zoneKind = scope.zone else { return true }
        guard let zones = ZoneLayout.zones(for: display, config: config) else { return true }
        if untiledInEveryZone, !isTiled(windowBounds, in: zones) { return true }
        return zoneMemberships(of: windowBounds, in: zones).contains(zoneKind)
    }

    private static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
