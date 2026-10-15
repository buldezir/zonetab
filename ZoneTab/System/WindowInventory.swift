import AppKit
import ZoneTabCore

struct InventorySnapshot {
    var displays: [DisplayInfo]
    /// On-screen windows in front-to-back order, followed by hidden apps' windows and, if asked for, full-screen
    /// windows on Spaces that aren't showing.
    var windows: [WindowInfo]
    var apps: [Int32: AppInfo]
    var frontmostPID: Int32?
    var ownPID: Int32
}

/// Reads displays, windows and running apps from the system. Window data comes from the WindowServer list, which
/// is fast, needs no Accessibility calls, and doesn't need Screen Recording (only window titles would).
final class WindowInventory {
    /// Most recently activated first.
    private var activationOrder: [pid_t] = []
    private var observer: NSObjectProtocol?

    init() {
        seedActivationOrder()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { self?.noteActivated(pid) }
        }
    }

    private func noteActivated(_ pid: pid_t) {
        activationOrder.removeAll { $0 == pid }
        activationOrder.insert(pid, at: 0)
    }

    private func seedActivationOrder() {
        var order: [pid_t] = []
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier { order.append(front) }
        for window in Self.windows(options: [.optionOnScreenOnly, .excludeDesktopElements]) where !order.contains(window.pid) {
            order.append(window.pid)
        }
        activationOrder = order
    }

    /// - Parameters:
    ///   - includeAllSpaces: every window on every Space, for the full-screen fallback list.
    ///   - includeFullScreen: full-screen windows on Spaces that aren't showing, marked `isFullScreen`.
    func snapshot(includeAllSpaces: Bool = false, includeFullScreen: Bool = false) -> InventorySnapshot {
        let ranks = Dictionary(activationOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        var apps: [Int32: AppInfo] = [:]
        for app in NSWorkspace.shared.runningApplications where !app.isTerminated {
            apps[app.processIdentifier] = AppInfo(
                pid: app.processIdentifier, bundleID: app.bundleIdentifier, name: app.localizedName ?? "?",
                isHidden: app.isHidden, isRegular: app.activationPolicy == .regular,
                activationRank: ranks[app.processIdentifier] ?? .max)
        }

        var windows = Self.windows(options: [.optionOnScreenOnly, .excludeDesktopElements])
        let hiddenPIDs = Set(apps.values.filter { $0.isHidden && $0.isRegular }.map(\.pid))
        if includeAllSpaces || !hiddenPIDs.isEmpty {
            let onScreen = Set(windows.map(\.id))
            windows += Self.windows(options: [.optionAll, .excludeDesktopElements]).filter {
                !onScreen.contains($0.id) && (includeAllSpaces || hiddenPIDs.contains($0.pid))
            }.map { var window = $0; window.isOnScreen = false; return window }
        }
        if includeFullScreen {
            let fullScreen = Self.fullScreenWindowIDs()
            for index in windows.indices where fullScreen.contains(windows[index].id) { windows[index].isFullScreen = true }
            let missing = fullScreen.subtracting(windows.map(\.id))
            windows += Self.windows(ids: Array(missing)).map {
                var window = $0
                window.isOnScreen = false
                window.isFullScreen = true
                return window
            }
        }

        return InventorySnapshot(displays: Self.displays(), windows: windows, apps: apps,
                                 frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                                 ownPID: getpid())
    }

    // MARK: - System queries

    nonisolated static func windows(options: CGWindowListOption) -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap(windowInfo(from:))
    }

    nonisolated static func window(id: CGWindowID) -> WindowInfo? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]] else { return nil }
        return list.first.flatMap(windowInfo(from:))
    }

    /// Descriptions of specific windows, wherever they are.
    nonisolated static func windows(ids: [CGWindowID]) -> [WindowInfo] {
        guard !ids.isEmpty else { return [] }
        var values: [UnsafeRawPointer?] = ids.map { UnsafeRawPointer(bitPattern: UInt($0)) }
        let array = values.withUnsafeMutableBufferPointer { CFArrayCreate(nil, $0.baseAddress, $0.count, nil) }
        guard let array, let list = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]] else { return [] }
        return list.compactMap(windowInfo(from:))
    }

    private nonisolated static func windowInfo(from entry: [String: Any]) -> WindowInfo? {
        guard let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
              let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
              let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else { return nil }
        return WindowInfo(id: id, pid: pid, bounds: bounds,
                          layer: (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
                          alpha: (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1,
                          isOnScreen: (entry[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false)
    }

    /// The primary display's height, for converting between Cocoa and Quartz coordinates.
    static var primaryMaxY: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    static var mouseLocation: CGPoint { Geometry.flip(NSEvent.mouseLocation, primaryMaxY: primaryMaxY) }

    static func displays() -> [DisplayInfo] {
        let primaryMaxY = primaryMaxY
        let dockAutohides = UserDefaults(suiteName: "com.apple.dock")?.bool(forKey: "autohide") ?? false
        return NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = number.uint32Value
            let frame = Geometry.flip(screen.frame, primaryMaxY: primaryMaxY)
            let visible = Geometry.flip(screen.visibleFrame, primaryMaxY: primaryMaxY)
            return DisplayInfo(id: id, uuid: uuid(of: id), frame: frame,
                               usableFrame: ZoneLayout.usableFrame(frame: frame, visibleFrame: visible, dockAutohides: dockAutohides))
        }
    }

    nonisolated static func uuid(of displayID: CGDirectDisplayID) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) else { return String(displayID) }
        return string as String
    }

    nonisolated static func managedDisplaySpaces() -> [[String: Any]] {
        CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]] ?? []
    }

    /// Windows that fill a full-screen Space, on every display. A Split View Space has one per side.
    nonisolated static func fullScreenWindowIDs() -> Set<CGWindowID> {
        var ids = Set<CGWindowID>()
        for display in managedDisplaySpaces() {
            for space in display["Spaces"] as? [[String: Any]] ?? [] where (space["type"] as? NSNumber)?.intValue == 4 {
                let tiles = (space["TileLayoutManager"] as? [String: Any])?["TileSpaces"] as? [[String: Any]] ?? []
                let tileIDs = tiles.compactMap { ($0["TileWindowID"] as? NSNumber)?.uint32Value }
                if !tileIDs.isEmpty {
                    ids.formUnion(tileIDs)
                } else if let id = (space["fs_wid"] as? NSNumber)?.uint32Value {
                    ids.insert(id)
                }
            }
        }
        return ids
    }

    /// Whether the given display is currently showing a full-screen Space.
    nonisolated static func isFullScreenSpaceActive(displayUUID: String) -> Bool {
        for display in managedDisplaySpaces() {
            let identifier = display["Display Identifier"] as? String
            guard identifier == "Main" || identifier?.caseInsensitiveCompare(displayUUID) == .orderedSame else { continue }
            let current = display["Current Space"] as? [String: Any]
            return (current?["type"] as? NSNumber)?.intValue == 4
        }
        return false
    }
}
