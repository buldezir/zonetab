import AppKit
import ZoneTabCore

/// A translucent highlight over a zone: the drop target while Shift-dragging, and the zone preview while the
/// width slider in Settings is being dragged.
final class ZoneOverlayWindow {
    private static let inset: CGFloat = 6
    private var window: NSWindow?
    private var label: NSTextField?
    private var displayID: UInt32?

    /// - Parameter rect: the zone, in Quartz coordinates.
    func show(_ rect: CGRect, displayID: UInt32, label text: String? = nil) {
        // A transient window can stay attached to its old display's Space, so make a new one per display.
        if window == nil || self.displayID != displayID {
            window?.orderOut(nil)
            (window, label) = Self.makeWindow()
            self.displayID = displayID
        }
        guard let window else { return }
        label?.stringValue = text ?? ""
        label?.isHidden = text == nil
        let frame = Geometry.flip(rect, primaryMaxY: WindowInventory.primaryMaxY).insetBy(dx: Self.inset, dy: Self.inset)
        if window.frame != frame { window.setFrame(frame, display: true) }
        if !window.isVisible { window.orderFrontRegardless() }
    }

    func hide() {
        window?.orderOut(nil)
    }

    private static func makeWindow() -> (NSWindow, NSTextField) {
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

        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        window.contentView = view
        return (window, label)
    }
}

/// Shows every zone on every zoned display, labelled with its share and width.
final class ZonePreview {
    private var overlays: [ZoneOverlayWindow] = []

    func show(_ config: ZoneConfig) {
        var index = 0
        for display in WindowInventory.displays() {
            guard let zones = ZoneLayout.zones(for: display, config: config) else { continue }
            for zone in zones {
                if index == overlays.count { overlays.append(ZoneOverlayWindow()) }
                let share = Int((zone.rect.width / display.frame.width * 100).rounded())
                overlays[index].show(zone.rect, displayID: display.id, label: "\(share)%  ·  \(Int(zone.rect.width)) pt")
                index += 1
            }
        }
        for overlay in overlays[index...] { overlay.hide() }
    }

    func hide() {
        for overlay in overlays { overlay.hide() }
    }
}
