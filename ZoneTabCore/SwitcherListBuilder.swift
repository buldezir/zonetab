import CoreGraphics

public struct SwitcherEntry: Sendable, Equatable, Codable {
    public var pid: Int32
    /// The window to bring forward when this entry is chosen.
    public var windowID: UInt32?
    public var isHidden: Bool

    public init(pid: Int32, windowID: UInt32?, isHidden: Bool = false) {
        self.pid = pid
        self.windowID = windowID
        self.isHidden = isHidden
    }
}

public struct SwitcherList: Sendable, Equatable, Codable {
    public var entries: [SwitcherEntry]
    /// Where the selection starts, or nil when there is nothing to switch to.
    public var initialSelection: Int?

    public init(entries: [SwitcherEntry], initialSelection: Int?) {
        self.entries = entries
        self.initialSelection = initialSelection
    }
}

public enum SwitcherListBuilder {
    /// Apps with a window in `scope`, most recently used first.
    ///
    /// - Parameter windows: front-to-back z-order, as CGWindowList returns it. Off-screen windows are only used
    ///   for hidden apps (their windows keep their last frame).
    public static func build(windows: [WindowInfo], apps: [Int32: AppInfo], frontmostPID: Int32?, ownPID: Int32,
                             scope: Scope, displays: [DisplayInfo], config: ZoneConfig) -> SwitcherList {
        func eligible(_ pid: Int32) -> AppInfo? {
            guard pid != ownPID, let app = apps[pid], app.isRegular else { return nil }
            return app
        }

        // Visible windows: z-order is the most-recently-used order, so the first in-scope window per app wins.
        var entries: [SwitcherEntry] = []
        var listed = Set<Int32>()
        var topmostWindow: [Int32: UInt32] = [:]
        for window in windows where window.isOnScreen && window.isCandidate {
            guard let app = eligible(window.pid), !app.isHidden else { continue }
            if topmostWindow[window.pid] == nil { topmostWindow[window.pid] = window.id }
            guard !listed.contains(window.pid),
                  ScopeResolver.contains(scope, windowBounds: window.bounds, displays: displays, config: config) else { continue }
            listed.insert(window.pid)
            entries.append(SwitcherEntry(pid: window.pid, windowID: window.id))
        }

        // Hidden apps go last, by activation order.
        var hidden: [(rank: Int, entry: SwitcherEntry)] = []
        for window in windows where !window.isOnScreen && window.isCandidate {
            guard let app = eligible(window.pid), app.isHidden, !listed.contains(window.pid),
                  ScopeResolver.contains(scope, windowBounds: window.bounds, displays: displays, config: config) else { continue }
            listed.insert(window.pid)
            hidden.append((app.activationRank, SwitcherEntry(pid: window.pid, windowID: window.id, isHidden: true)))
        }
        entries += hidden.sorted { $0.rank < $1.rank }.map(\.entry)

        // The first entry is "where you are now" only if it's the frontmost app's frontmost window.
        let firstIsCurrent = entries.first.map {
            $0.pid == frontmostPID && !$0.isHidden && $0.windowID == topmostWindow[$0.pid]
        } ?? false
        return SwitcherList(entries: entries, initialSelection: initialSelection(count: entries.count, firstIsCurrent: firstIsCurrent))
    }

    /// Used when the cursor's display shows a full-screen Space, where scoping would leave only one app:
    /// every regular app that has a window anywhere, by activation order.
    ///
    /// - Parameter windows: windows on all Spaces; on-screen ones are preferred as the target.
    public static func buildFallback(windows: [WindowInfo], apps: [Int32: AppInfo], frontmostPID: Int32?,
                                     ownPID: Int32) -> SwitcherList {
        var target: [Int32: UInt32] = [:]
        for window in windows where window.isCandidate && window.isOnScreen && target[window.pid] == nil {
            target[window.pid] = window.id
        }
        for window in windows where window.isCandidate && target[window.pid] == nil {
            target[window.pid] = window.id
        }
        let entries = apps.values
            .filter { $0.pid != ownPID && $0.isRegular && target[$0.pid] != nil }
            .sorted { ($0.activationRank, $0.pid) < ($1.activationRank, $1.pid) }
            .map { SwitcherEntry(pid: $0.pid, windowID: target[$0.pid], isHidden: $0.isHidden) }
        let firstIsCurrent = entries.first?.pid == frontmostPID
        return SwitcherList(entries: entries, initialSelection: initialSelection(count: entries.count, firstIsCurrent: firstIsCurrent))
    }

    private static func initialSelection(count: Int, firstIsCurrent: Bool) -> Int? {
        if count == 0 { return nil }
        if firstIsCurrent { return count > 1 ? 1 : nil }
        return 0
    }
}
