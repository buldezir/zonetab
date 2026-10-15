import AppKit
import SwiftUI
import ZoneTabCore

/// A panel that never becomes key, so the frontmost app keeps keyboard focus while the switcher is open.
private final class NonKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class SwitcherPanel {
    private static let maxIconSize: CGFloat = 80
    private static let minIconSize: CGFloat = 32
    /// Per-item width beyond the icon itself: tile padding plus spacing.
    private static let itemChrome: CGFloat = 22
    private static let panelChrome: CGFloat = 28
    private static let scopeMargin: CGFloat = 40

    private let model = SwitcherViewModel()
    private let panel: NonKeyPanel
    private let hostingView: NSHostingView<SwitcherView>

    init() {
        hostingView = NSHostingView(rootView: SwitcherView(model: model))
        hostingView.sizingOptions = [.intrinsicContentSize]
        panel = NonKeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = hostingView
        prerender()
    }

    /// The first SwiftUI render can take longer than the show delay; do it once up front.
    private func prerender() {
        let placeholder = NSWorkspace.shared.icon(for: .application)
        model.items = [SwitcherItem(pid: 0, name: " ", icon: placeholder, windowID: nil, isHidden: false)]
        hostingView.layoutSubtreeIfNeeded()
        _ = hostingView.fittingSize
        model.items = []
    }

    /// - Parameter scopeRect: the zone or display to centre on, in Quartz coordinates.
    func show(items: [SwitcherItem], selection: Int, in scopeRect: CGRect) {
        update(items: items, selection: selection, in: scopeRect)
        panel.orderFrontRegardless()
    }

    func update(items: [SwitcherItem], selection: Int, in scopeRect: CGRect) {
        let available = scopeRect.width - Self.scopeMargin - Self.panelChrome
        let fitting = available / CGFloat(max(items.count, 1)) - Self.itemChrome
        model.iconSize = min(Self.maxIconSize, max(Self.minIconSize, fitting.rounded(.down)))
        model.items = items
        model.selection = selection
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let scope = Geometry.flip(scopeRect, primaryMaxY: WindowInventory.primaryMaxY)
        let origin = CGPoint(x: (scope.midX - size.width / 2).rounded(), y: (scope.midY - size.height / 2).rounded())
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    func update(selection: Int) {
        model.selection = selection
    }

    func hide() {
        panel.orderOut(nil)
    }
}
