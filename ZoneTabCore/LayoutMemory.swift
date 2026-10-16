import CoreGraphics

/// Where a window sat on a zoned display.
public enum SavedPlacement: Sendable, Equatable, Codable {
    case zone(ZoneKind)
    /// Filling all zones.
    case display
    /// Not tiled: its frame relative to the display's top-left corner, so it survives the display moving in the
    /// arrangement.
    case frame(CGRect)
}

public struct SavedWindow: Sendable, Equatable, Codable {
    public var id: UInt32
    public var pid: Int32
    /// Checked together with the pid, which a different process may have after a restart.
    public var bundleID: String?
    public var placement: SavedPlacement

    public init(id: UInt32, pid: Int32, bundleID: String?, placement: SavedPlacement) {
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
        self.placement = placement
    }
}

/// The windows on one zoned display, front to back, as they were the last time it was connected.
public struct DisplayLayout: Sendable, Equatable, Codable {
    public var displayUUID: String
    public var windows: [SavedWindow]

    public init(displayUUID: String, windows: [SavedWindow]) {
        self.displayUUID = displayUUID
        self.windows = windows
    }
}

/// A frame to give a window.
public struct FrameChange: Sendable, Equatable, Codable {
    public var windowID: UInt32
    public var pid: Int32
    public var frame: CGRect
    /// The usable frame of the display the window goes to: a window that refuses the size is kept inside it.
    public var bounds: CGRect

    public init(windowID: UInt32, pid: Int32, frame: CGRect, bounds: CGRect) {
        self.windowID = windowID
        self.pid = pid
        self.frame = frame
        self.bounds = bounds
    }
}

/// What to do once the display configuration has settled after a change.
public struct DisplayChangeActions: Sendable, Equatable {
    /// Recorded displays that are gone: their windows are maximized wherever they ended up.
    public var maximize: [String]
    /// Recorded displays that are connected and get their layout back.
    public var restore: [String]

    public init(maximize: [String], restore: [String]) {
        self.maximize = maximize
        self.restore = restore
    }
}

/// Keeps a zoned display's tiles across unplugging it: record its layout while it's connected, maximize its tiled
/// windows wherever they end up once it's gone, and put them back when it returns.
public enum LayoutMemory {
    /// Every normal window on `display`, on any Space: tiled ones by what they fill, the rest by their frame.
    /// Full-screen windows are left out; they move with their Space.
    ///
    /// - Parameter windows: front-to-back, with `isFullScreen` set.
    public static func record(display: DisplayInfo, displays: [DisplayInfo], windows: [WindowInfo], apps: [Int32: AppInfo],
                              ownPID: Int32, config: ZoneConfig) -> DisplayLayout? {
        guard let zones = ZoneLayout.zones(for: display, config: config) else { return nil }
        var saved: [SavedWindow] = []
        var seen = Set<UInt32>()
        for window in windows where window.isCandidate && !window.isFullScreen && !seen.contains(window.id) {
            guard window.pid != ownPID, let app = apps[window.pid], app.isRegular,
                  ScopeResolver.display(for: window.bounds, in: displays)?.id == display.id else { continue }
            seen.insert(window.id)
            let placement: SavedPlacement
            switch ScopeResolver.tiledPlacement(of: window.bounds, in: zones) {
            case .zone(let kind): placement = .zone(kind)
            case nil: placement = .frame(window.bounds.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY))
            default: placement = .display
            }
            saved.append(SavedWindow(id: window.id, pid: window.pid, bundleID: app.bundleID, placement: placement))
        }
        return DisplayLayout(displayUUID: display.uuid, windows: saved)
    }

    /// After the display is gone: tiled windows fill the display they ended up on; untiled windows are only pulled
    /// inside it if they no longer fit.
    public static func maximizeChanges(for layout: DisplayLayout, displays: [DisplayInfo], windows: [WindowInfo],
                                       apps: [Int32: AppInfo]) -> [FrameChange] {
        let current = windowsByID(windows)
        return layout.windows.compactMap { saved in
            guard let window = alive(saved, current, apps),
                  let display = ScopeResolver.display(for: window.bounds, in: displays) ?? displays.first else { return nil }
            let usable = display.usableFrame
            let frame: CGRect
            switch saved.placement {
            case .zone, .display: frame = usable
            case .frame: frame = fit(window.bounds, in: usable)
            }
            return change(window, frame, usable)
        }
    }

    /// Back on the display: tiled windows return to their zone (with the current zone settings), untiled ones to
    /// their old frame.
    public static func restoreChanges(for layout: DisplayLayout, on display: DisplayInfo, windows: [WindowInfo],
                                      apps: [Int32: AppInfo], config: ZoneConfig) -> [FrameChange] {
        let current = windowsByID(windows)
        let zones = ZoneLayout.zones(for: display, config: config)
        let usable = display.usableFrame
        return layout.windows.compactMap { saved in
            guard let window = alive(saved, current, apps) else { return nil }
            let frame: CGRect
            switch saved.placement {
            case .zone(let kind):
                guard let rect = zones?.first(where: { $0.kind == kind })?.rect else { return nil }
                frame = rect
            case .display:
                frame = usable
            case .frame(let relative):
                frame = fit(relative.offsetBy(dx: display.frame.minX, dy: display.frame.minY), in: usable)
            }
            return change(window, frame, usable)
        }
    }

    /// - Parameters:
    ///   - recorded: displays with a recorded layout.
    ///   - away: displays already handled as unplugged.
    ///   - wentOffline: recorded displays seen offline during the change, even if they're back by now.
    ///   - online: displays connected now.
    ///   - rearranged: whether displays came, went or moved. macOS moves windows around on every display then:
    ///     closing the lid piles the laptop's windows onto the others, opening it may move some back. So every
    ///     connected display gets its layout back, not only one that was unplugged.
    public static func actions(recorded: Set<String>, away: Set<String>, wentOffline: Set<String>, online: Set<String>,
                               rearranged: Bool) -> DisplayChangeActions {
        DisplayChangeActions(
            maximize: recorded.subtracting(online).subtracting(away).sorted(),
            restore: recorded.intersection(online).filter { rearranged || away.contains($0) || wentOffline.contains($0) }.sorted())
    }

    /// `frame`, shrunk to fit `bounds` if it's bigger, and moved inside them.
    public static func fit(_ frame: CGRect, in bounds: CGRect) -> CGRect {
        let size = CGSize(width: min(frame.width, bounds.width), height: min(frame.height, bounds.height))
        return CGRect(x: min(max(frame.minX, bounds.minX), bounds.maxX - size.width),
                      y: min(max(frame.minY, bounds.minY), bounds.maxY - size.height),
                      width: size.width, height: size.height)
    }

    private static func windowsByID(_ windows: [WindowInfo]) -> [UInt32: WindowInfo] {
        Dictionary(windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The saved window, if it's still open in the same app and not in full screen now.
    private static func alive(_ saved: SavedWindow, _ current: [UInt32: WindowInfo], _ apps: [Int32: AppInfo]) -> WindowInfo? {
        guard let window = current[saved.id], window.pid == saved.pid, !window.isFullScreen,
              let app = apps[saved.pid], app.bundleID == saved.bundleID else { return nil }
        return window
    }

    /// nil when the window is already there.
    private static func change(_ window: WindowInfo, _ frame: CGRect, _ bounds: CGRect) -> FrameChange? {
        Geometry.approximatelyEqual(window.bounds, frame) ? nil
            : FrameChange(windowID: window.id, pid: window.pid, frame: frame, bounds: bounds)
    }
}
