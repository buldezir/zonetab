import CoreGraphics

/// A physical display, in Quartz coordinates.
public struct DisplayInfo: Sendable, Equatable, Codable {
    public var id: UInt32
    public var uuid: String
    /// Full display bounds.
    public var frame: CGRect
    /// Area windows may occupy: the visible frame (no menu bar, no visible Dock).
    public var usableFrame: CGRect

    public init(id: UInt32, uuid: String, frame: CGRect, usableFrame: CGRect) {
        self.id = id
        self.uuid = uuid
        self.frame = frame
        self.usableFrame = usableFrame
    }
}

/// Which side of an ultrawide display holds the 16:9 zone.
public enum ZoneSide: String, Sendable, Codable, CaseIterable {
    case left, right
}

public enum ZoneKind: String, Sendable, Codable {
    /// The 16:9 zone at full display height ("4K display").
    case primary
    /// The remaining width.
    case secondary
}

public struct Zone: Sendable, Equatable, Codable {
    public var kind: ZoneKind
    public var rect: CGRect

    public init(kind: ZoneKind, rect: CGRect) {
        self.kind = kind
        self.rect = rect
    }
}

public enum ZoneLayout {
    /// Displays at least this wide relative to their height get zones (21:9 is ~2.37, 16:10 is 1.6).
    public static let minimumAspectRatio: CGFloat = 2.2
    public static let primaryAspectRatio: CGFloat = 16.0 / 9.0
    /// An auto-hidden Dock still trims a few points off `visibleFrame`; insets up to this size are ignored.
    public static let autohiddenDockInset: CGFloat = 5

    public static func isZoned(_ frame: CGRect) -> Bool {
        frame.height > 0 && frame.width / frame.height >= minimumAspectRatio
    }

    /// The usable frame for a display: `visibleFrame`, minus the sliver an auto-hidden Dock reserves.
    /// All rects are in Quartz coordinates, so the bottom edge is `maxY`.
    public static func usableFrame(frame: CGRect, visibleFrame: CGRect, dockAutohides: Bool) -> CGRect {
        guard dockAutohides else { return visibleFrame }
        var minX = visibleFrame.minX
        var maxX = visibleFrame.maxX
        var maxY = visibleFrame.maxY
        if minX - frame.minX > 0, minX - frame.minX <= autohiddenDockInset { minX = frame.minX }
        if frame.maxX - maxX > 0, frame.maxX - maxX <= autohiddenDockInset { maxX = frame.maxX }
        if frame.maxY - maxY > 0, frame.maxY - maxY <= autohiddenDockInset { maxY = frame.maxY }
        return CGRect(x: minX, y: visibleFrame.minY, width: maxX - minX, height: maxY - visibleFrame.minY)
    }

    /// Width of the 16:9 zone: 16:9 of the full display height, so on a 5K2K panel the split sits at exactly
    /// 3840 physical pixels.
    public static func primaryWidth(for frame: CGRect) -> CGFloat {
        (frame.height * primaryAspectRatio).rounded()
    }

    /// Zones for a display, ordered left to right, or nil if the display isn't wide enough.
    public static func zones(for display: DisplayInfo, side: ZoneSide) -> [Zone]? {
        let frame = display.frame
        let usable = display.usableFrame
        guard isZoned(frame) else { return nil }
        let width = primaryWidth(for: frame)
        let splitX = side == .left ? frame.minX + width : frame.maxX - width
        guard splitX > usable.minX, splitX < usable.maxX else { return nil }
        let left = CGRect(x: usable.minX, y: usable.minY, width: splitX - usable.minX, height: usable.height)
        let right = CGRect(x: splitX, y: usable.minY, width: usable.maxX - splitX, height: usable.height)
        switch side {
        case .left: return [Zone(kind: .primary, rect: left), Zone(kind: .secondary, rect: right)]
        case .right: return [Zone(kind: .secondary, rect: left), Zone(kind: .primary, rect: right)]
        }
    }

    /// The zone whose horizontal range contains `x`; points beyond either end map to the nearest zone.
    public static func zone(atX x: CGFloat, in zones: [Zone]) -> Zone? {
        guard let first = zones.first, let last = zones.last else { return nil }
        if x < first.rect.minX { return first }
        if x >= last.rect.maxX { return last }
        return zones.first { x >= $0.rect.minX && x < $0.rect.maxX } ?? last
    }
}
