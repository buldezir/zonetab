import CoreGraphics

public enum TileCommand: String, Sendable, Codable, CaseIterable {
    /// Fill the window's zone; again → whole display; again → back to the zone. Maximize on unzoned displays.
    case fill
    /// Left zone, or left half on unzoned displays.
    case left
    /// Right zone, or right half on unzoned displays.
    case right
}

public enum Placement: Sendable, Equatable, Codable {
    case zone(ZoneKind)
    case display
    case leftHalf
    case rightHalf
}

/// What ZoneTab last did to a window, keyed by window id in the app.
public struct TileMemory: Sendable, Equatable, Codable {
    public var placement: Placement
    /// The frame the window actually ended up with (apps may round the requested size).
    public var frame: CGRect
    /// The zone a window filled before it was expanded to the whole display.
    public var zoneBeforeDisplay: ZoneKind?

    public init(placement: Placement, frame: CGRect, zoneBeforeDisplay: ZoneKind? = nil) {
        self.placement = placement
        self.frame = frame
        self.zoneBeforeDisplay = zoneBeforeDisplay
    }
}

public struct TilePlan: Sendable, Equatable, Codable {
    public var placement: Placement
    public var frame: CGRect
    public var zoneBeforeDisplay: ZoneKind?

    public init(placement: Placement, frame: CGRect, zoneBeforeDisplay: ZoneKind? = nil) {
        self.placement = placement
        self.frame = frame
        self.zoneBeforeDisplay = zoneBeforeDisplay
    }
}

public enum TileActions {
    /// - Parameters:
    ///   - usable: the usable frame of the window's display.
    ///   - zones: that display's zones, or nil when the display isn't zoned or zones are off.
    ///   - memory: what ZoneTab last did to this window, if anything.
    ///   - cursorZone: the zone under the cursor, if the cursor is on the window's display.
    public static func plan(_ command: TileCommand, windowFrame: CGRect, usable: CGRect, zones: [Zone]?,
                            memory: TileMemory?, cursorZone: ZoneKind?) -> TilePlan {
        guard let zones, let leftZone = zones.first, let rightZone = zones.last else {
            return planUnzoned(command, usable: usable)
        }
        switch command {
        case .left:
            return TilePlan(placement: .zone(leftZone.kind), frame: leftZone.rect)
        case .right:
            return TilePlan(placement: .zone(rightZone.kind), frame: rightZone.rect)
        case .fill:
            switch currentPlacement(windowFrame: windowFrame, usable: usable, zones: zones, memory: memory) {
            case .zone(let kind):
                return TilePlan(placement: .display, frame: usable, zoneBeforeDisplay: kind)
            case .display:
                let kind = memory?.zoneBeforeDisplay ?? cursorZone ?? centreZone(of: windowFrame, in: zones).kind
                return TilePlan(placement: .zone(kind), frame: rect(of: kind, in: zones))
            case .leftHalf, .rightHalf, nil:
                let zone = centreZone(of: windowFrame, in: zones)
                return TilePlan(placement: .zone(zone.kind), frame: zone.rect)
            }
        }
    }

    /// Where the window currently is: what ZoneTab last put it at (if it hasn't moved since), or a zone/display
    /// it exactly fills.
    public static func currentPlacement(windowFrame: CGRect, usable: CGRect, zones: [Zone], memory: TileMemory?) -> Placement? {
        if let memory, Geometry.approximatelyEqual(memory.frame, windowFrame) { return memory.placement }
        if let zone = zones.first(where: { Geometry.approximatelyEqual($0.rect, windowFrame) }) { return .zone(zone.kind) }
        if Geometry.approximatelyEqual(usable, windowFrame) { return .display }
        return nil
    }

    private static func planUnzoned(_ command: TileCommand, usable: CGRect) -> TilePlan {
        let leftWidth = (usable.width / 2).rounded(.down)
        switch command {
        case .fill:
            return TilePlan(placement: .display, frame: usable)
        case .left:
            return TilePlan(placement: .leftHalf,
                            frame: CGRect(x: usable.minX, y: usable.minY, width: leftWidth, height: usable.height))
        case .right:
            return TilePlan(placement: .rightHalf,
                            frame: CGRect(x: usable.minX + leftWidth, y: usable.minY,
                                          width: usable.width - leftWidth, height: usable.height))
        }
    }

    private static func centreZone(of windowFrame: CGRect, in zones: [Zone]) -> Zone {
        ZoneLayout.zone(atX: windowFrame.midX, in: zones) ?? zones[0]
    }

    private static func rect(of kind: ZoneKind, in zones: [Zone]) -> CGRect {
        (zones.first { $0.kind == kind } ?? zones[0]).rect
    }
}
