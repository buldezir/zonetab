import AppKit
import ZoneTabCore

/// The translucent highlight shown over the target zone while Shift-dragging a window.
final class ZoneOverlayWindow {
    private static let inset: CGFloat = 6
    private var window: NSWindow?
    private var displayID: UInt32?

    /// - Parameter rect: the zone, in Quartz coordinates.
    func show(_ rect: CGRect, displayID: UInt32) {
        // A transient window can stay attached to its old display's Space, so make a new one per display.
        if window == nil || self.displayID != displayID {
            window?.orderOut(nil)
            window = Self.makeWindow()
            self.displayID = displayID
        }
        guard let window else { return }
        let frame = Geometry.flip(rect, primaryMaxY: WindowInventory.primaryMaxY).insetBy(dx: Self.inset, dy: Self.inset)
        if window.frame != frame { window.setFrame(frame, display: true) }
        if !window.isVisible { window.orderFrontRegardless() }
    }

    func hide() {
        window?.orderOut(nil)
    }

    private static func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .modalPanel
        window.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false

        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 16
        view.layer?.cornerCurve = .continuous
        view.layer?.borderWidth = 3
        view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        view.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.75).cgColor
        window.contentView = view
        return window
    }
}
