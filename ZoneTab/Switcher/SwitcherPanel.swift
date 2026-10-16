import AppKit
import SwiftUI
import ZoneTabCore

/// A panel that never becomes key, so the frontmost app keeps keyboard focus while the switcher is open.
private final class NonKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Takes every mouse event over the switcher, like the native one: pointing at an app selects it, clicking it
/// switches to it.
private final class SwitcherMouseView: NSView {
    /// The item at a point in this view's (top-left origin) coordinates.
    var itemAt: (CGPoint) -> Int? = { _ in nil }
    var onPoint: (Int) -> Void = { _ in }
    var onClick: (Int) -> Void = { _ in }
    /// Where the mouse was when the panel appeared. It only selects once it moves, so a panel that opens under a
    /// resting mouse keeps its selection.
    var restingLocation: CGPoint?
    private var pressed: Int?

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Always active: ZoneTab is never the active app while the switcher is open.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseMoved, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }

    override func mouseMoved(with event: NSEvent) {
        if let restingLocation {
            guard NSEvent.mouseLocation != restingLocation else { return }
            self.restingLocation = nil
        }
        if let index = item(at: event) { onPoint(index) }
    }

    override func mouseDown(with event: NSEvent) {
        restingLocation = nil
        pressed = item(at: event)
        if let pressed { onPoint(pressed) }
    }

    /// Like a button: the click counts if it's released over the app it started on.
    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil }
        if let pressed, item(at: event) == pressed { onClick(pressed) }
    }

    private func item(at event: NSEvent) -> Int? {
        itemAt(convert(event.locationInWindow, from: nil))
    }
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
    private let mouseView = SwitcherMouseView()

    /// The mouse moved onto the item at this index.
    var onPoint: (Int) -> Void {
        get { mouseView.onPoint }
        set { mouseView.onPoint = newValue }
    }

    /// The item at this index was clicked.
    var onClick: (Int) -> Void {
        get { mouseView.onClick }
        set { mouseView.onClick = newValue }
    }

    init() {
        hostingView = NSHostingView(rootView: SwitcherView(model: model))
        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.autoresizingMask = [.width, .height]
        mouseView.addSubview(hostingView)
        // The hosting view fills the mouse view from its top-left corner, so their coordinates are the view's.
        mouseView.itemAt = { [model] in model.item(at: $0) }
        panel = NonKeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = mouseView
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
        mouseView.restingLocation = NSEvent.mouseLocation
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

#if DEBUG
extension SwitcherPanel {
    var isVisible: Bool { panel.isVisible }

    /// Each item's tile on screen, in Quartz coordinates.
    var itemFramesOnScreen: [CGRect] {
        model.items.map { item in
            guard let frame = model.itemFrames[item.pid] else { return .null }
            let onScreen = panel.convertToScreen(mouseView.convert(frame, to: nil))
            return Geometry.flip(onScreen, primaryMaxY: WindowInventory.primaryMaxY)
        }
    }
}
#endif
