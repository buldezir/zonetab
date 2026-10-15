import ApplicationServices
import CoreGraphics
import Foundation

/// An Accessibility window element. AX calls block until the target app answers, so this type is nonisolated and
/// meant to be used off the main thread.
nonisolated struct AXWindow: @unchecked Sendable {
    let element: AXUIElement
    let pid: pid_t

    static let messagingTimeout: Float = 0.25

    static func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        return app
    }

    /// The app's focused window, or its first window.
    static func focusedWindow(pid: pid_t) -> AXWindow? {
        let app = application(pid)
        if let window = element(app, kAXFocusedWindowAttribute) { return AXWindow(element: window, pid: pid) }
        return windows(pid: pid).first
    }

    /// Windows on the current Space.
    static func windows(pid: pid_t) -> [AXWindow] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application(pid), kAXWindowsAttribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement] else { return [] }
        return elements.map { AXWindow(element: $0, pid: pid) }
    }

    static func window(pid: pid_t, id: CGWindowID) -> AXWindow? {
        windows(pid: pid).first { $0.windowID == id }
    }

    /// Like `window(pid:id:)`, but also finds windows on other Spaces, which `kAXWindowsAttribute` leaves out.
    /// Element ids are small and handed out in order, so the window is among the first few thousand.
    static func windowOnAnySpace(pid: pid_t, id: CGWindowID) -> AXWindow? {
        if let window = window(pid: pid, id: id) { return window }
        var token = Data(count: 20)
        withUnsafeBytes(of: pid) { token.replaceSubrange(0..<4, with: $0) }
        withUnsafeBytes(of: UInt32(0x636f_636f)) { token.replaceSubrange(8..<12, with: $0) }
        for elementID in UInt64(0)..<searchLimit {
            withUnsafeBytes(of: elementID) { token.replaceSubrange(12..<20, with: $0) }
            guard let element = _AXUIElementCreateWithRemoteToken(token as CFData) else { continue }
            let window = AXWindow(element: element, pid: pid)
            if window.windowID == id { return window }
        }
        return nil
    }

    private static let searchLimit: UInt64 = 5000

    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    /// Quartz coordinates, like CGWindowList.
    var frame: CGRect? {
        guard let position = pointValue(kAXPositionAttribute), let size = sizeValue(kAXSizeAttribute) else { return nil }
        return CGRect(origin: position, size: size)
    }

    var isFullScreen: Bool { boolValue("AXFullScreen") ?? false }

    func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    /// Moves and resizes the window to `target`, then reads back where it actually went. If the app refuses the
    /// size (minimum size, fixed-size windows), the window is centred on `target` and kept inside `bounds`.
    @discardableResult
    func setFrame(_ target: CGRect, within bounds: CGRect) -> CGRect? {
        // AXEnhancedUserInterface (set by e.g. VoiceOver or Chromium) makes apps animate and fight frame changes.
        let app = Self.application(pid)
        let enhanced = Self.boolValue(app, "AXEnhancedUserInterface") ?? false
        if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
        defer { if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) } }

        // Size first so a move across displays isn't clamped by the old display, then size again because macOS
        // may have shrunk the window to fit where it was.
        setSize(target.size)
        setPosition(target.origin)
        setSize(target.size)

        guard let actual = frame else { return nil }
        if abs(actual.width - target.width) <= 1, abs(actual.height - target.height) <= 1 { return actual }

        var origin = CGPoint(x: target.midX - actual.width / 2,
                             y: actual.height >= target.height ? target.minY : target.midY - actual.height / 2)
        origin.x = min(max(origin.x, bounds.minX), max(bounds.minX, bounds.maxX - actual.width))
        origin.y = min(max(origin.y, bounds.minY), max(bounds.minY, bounds.maxY - actual.height))
        setPosition(origin)
        return frame
    }

    // MARK: - Attribute helpers

    private func setSize(_ size: CGSize) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
    }

    private func setPosition(_ point: CGPoint) {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    private func pointValue(_ attribute: String) -> CGPoint? {
        guard let value = Self.axValue(element, attribute) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    private func sizeValue(_ attribute: String) -> CGSize? {
        guard let value = Self.axValue(element, attribute) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    private func boolValue(_ attribute: String) -> Bool? {
        Self.boolValue(element, attribute)
    }

    private static func boolValue(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
