import CoreGraphics

/// What's under the mouse, for focusing it when the mouse moves into another zone.
public enum MouseFocusTarget: Sendable, Equatable {
    /// A normal app window that isn't focused yet.
    case window(WindowInfo)
    /// The window under the mouse is already the focused one.
    case focused
    /// Nothing to focus: the desktop, or something other than a normal window (the menu bar, a menu, the Dock).
    case none
}

public enum MouseFocus {
    /// The topmost window at `point`.
    ///
    /// - Parameter windows: on-screen windows, front-to-back.
    public static func target(at point: CGPoint, windows: [WindowInfo], apps: [Int32: AppInfo], frontmostPID: Int32?,
                              ownPID: Int32) -> MouseFocusTarget {
        for window in windows where window.isOnScreen && window.alpha > 0 && window.pid != ownPID && window.bounds.contains(point) {
            // Background apps' windows at the normal level are mostly invisible overlays: look through them.
            if window.layer == 0, apps[window.pid]?.isRegular != true { continue }
            // Anything else in front (a menu, the Dock, a tooltip) is what the mouse is on.
            guard window.isCandidate else { return .none }
            // An app's front window is its focused one.
            let front = windows.first { $0.pid == window.pid && $0.isOnScreen && $0.isCandidate }
            return window.pid == frontmostPID && front?.id == window.id ? .focused : .window(window)
        }
        return .none
    }
}
