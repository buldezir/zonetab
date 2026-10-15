import AppKit
import ZoneTabCore

/// Shift-drag a window to snap it into the zone under the cursor.
final class DragSnapper {
    private static let moveCheckInterval: TimeInterval = 0.03
    private static let snapDelay: Duration = .milliseconds(50)

    private struct Tracked {
        var pid: pid_t
        var windowID: CGWindowID
        var startBounds: CGRect
    }

    private let settings: Settings
    private let mover: WindowMover
    private let overlay = ZoneOverlayWindow()
    private var monitor: Any?

    private var resolvedThisDrag = false
    private var tracked: Tracked?
    private var isMoving = false
    private var lastMoveCheck = Date.distantPast
    private var target: (displayID: UInt32, zone: Zone)?

    init(settings: Settings, mover: WindowMover) {
        self.settings = settings
        self.mover = mover
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]) { [weak self] event in
            let type = event.type
            let shift = event.modifierFlags.contains(.shift)
            MainActor.assumeIsolated { self?.handle(type, shift: shift) }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        reset()
    }

    private func handle(_ type: NSEvent.EventType, shift: Bool) {
        switch type {
        case .leftMouseDown: reset()
        case .leftMouseDragged: dragged(shift: shift)
        case .leftMouseUp: released(shift: shift)
        case .flagsChanged: if isMoving { updateTarget(shift: shift) }
        default: break
        }
    }

    private func dragged(shift: Bool) {
        guard settings.zonesEnabled else { return }
        if !resolvedThisDrag {
            resolvedThisDrag = true
            tracked = Self.windowUnderCursor()
        }
        guard let tracked else { return }
        if !isMoving, Date().timeIntervalSince(lastMoveCheck) >= Self.moveCheckInterval {
            lastMoveCheck = Date()
            // A window move changes the origin but not the size; text selection or resizing doesn't qualify.
            if let current = WindowInventory.window(id: tracked.windowID)?.bounds,
               abs(current.width - tracked.startBounds.width) <= 1, abs(current.height - tracked.startBounds.height) <= 1,
               abs(current.minX - tracked.startBounds.minX) > 2 || abs(current.minY - tracked.startBounds.minY) > 2 {
                isMoving = true
            }
        }
        if isMoving { updateTarget(shift: shift) }
    }

    private func updateTarget(shift: Bool) {
        let mouse = WindowInventory.mouseLocation
        guard shift, settings.zonesEnabled,
              let display = ScopeResolver.display(at: mouse, in: WindowInventory.displays()),
              let zones = ZoneLayout.zones(for: display, config: settings.zoneConfig),
              let zone = ZoneLayout.zone(atX: mouse.x, in: zones) else {
            target = nil
            overlay.hide()
            return
        }
        target = (display.id, zone)
        overlay.show(zone.rect, displayID: display.id)
    }

    private func released(shift: Bool) {
        defer { reset() }
        overlay.hide()
        guard isMoving, shift, let tracked, let target else { return }
        let mover = mover
        Task {
            // Let the app finish its own drag handling before moving the window.
            try? await Task.sleep(for: Self.snapDelay)
            await mover.place(pid: tracked.pid, windowID: tracked.windowID, zone: target.zone.kind, displayID: target.displayID)
        }
    }

    private func reset() {
        resolvedThisDrag = false
        tracked = nil
        isMoving = false
        target = nil
        overlay.hide()
    }

    private static func windowUnderCursor() -> Tracked? {
        let mouse = WindowInventory.mouseLocation
        let ownPID = getpid()
        let window = WindowInventory.windows(options: [.optionOnScreenOnly, .excludeDesktopElements]).first {
            $0.pid != ownPID && $0.isCandidate && $0.bounds.contains(mouse)
        }
        return window.map { Tracked(pid: $0.pid, windowID: $0.id, startBounds: $0.bounds) }
    }
}
