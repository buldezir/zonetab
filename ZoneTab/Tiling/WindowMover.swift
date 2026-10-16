import AppKit
import ZoneTabCore

struct TileOutcome: Codable {
    var pid: Int32
    var windowID: UInt32?
    var before: CGRect
    var plan: TilePlan
    /// Where the window actually ended up (apps may round or refuse the requested size).
    var actual: CGRect?
}

/// Runs tiling commands. Accessibility work happens off the main thread; the per-window toggle memory lives here.
final class WindowMover {
    private let settings: Settings
    private var memory: [CGWindowID: TileMemory] = [:]
    /// Called after a window was tiled.
    var onMove: (() -> Void)?

    init(settings: Settings) {
        self.settings = settings
    }

    /// Applies a command to the focused window of `pid` (default: the frontmost app).
    @discardableResult
    func perform(_ command: TileCommand, pid: pid_t? = nil) async -> TileOutcome? {
        guard let pid = pid ?? NSWorkspace.shared.frontmostApplication?.processIdentifier, pid != getpid() else { return nil }
        let displays = WindowInventory.displays()
        let zonesEnabled = settings.zonesEnabled
        let config = settings.zoneConfig
        let mouse = WindowInventory.mouseLocation
        let memory = self.memory

        let outcome = await Task.detached(priority: .userInitiated) { () -> TileOutcome? in
            guard let window = AXWindow.focusedWindow(pid: pid), !window.isFullScreen, let frame = window.frame,
                  let display = ScopeResolver.display(for: frame, in: displays) ?? ScopeResolver.display(at: mouse, in: displays)
            else { return nil }
            let zones = zonesEnabled ? ZoneLayout.zones(for: display, config: config) : nil
            let cursorZone = display.frame.contains(mouse) ? zones.flatMap { ZoneLayout.zone(atX: mouse.x, in: $0)?.kind } : nil
            let windowID = window.windowID
            let plan = TileActions.plan(command, windowFrame: frame, usable: display.usableFrame, zones: zones,
                                        memory: windowID.flatMap { memory[$0] }, cursorZone: cursorZone)
            let actual = window.setFrame(plan.frame, within: display.usableFrame)
            return TileOutcome(pid: pid, windowID: windowID, before: frame, plan: plan, actual: actual)
        }.value

        remember(outcome)
        if let outcome {
            Log.tiling.debug("\(command.rawValue): \(String(describing: outcome.plan.placement)) → \(String(describing: outcome.actual))")
        }
        return outcome
    }

    /// Puts a specific window into a zone (used by drag-to-zone).
    @discardableResult
    func place(pid: pid_t, windowID: CGWindowID, zone kind: ZoneKind, displayID: UInt32) async -> TileOutcome? {
        guard let display = WindowInventory.displays().first(where: { $0.id == displayID }),
              let zone = ZoneLayout.zones(for: display, config: settings.zoneConfig)?.first(where: { $0.kind == kind }) else { return nil }
        let outcome = await Task.detached(priority: .userInitiated) { () -> TileOutcome? in
            guard let window = AXWindow.window(pid: pid, id: windowID), !window.isFullScreen, let frame = window.frame else { return nil }
            let actual = window.setFrame(zone.rect, within: display.usableFrame)
            return TileOutcome(pid: pid, windowID: windowID, before: frame,
                               plan: TilePlan(placement: .zone(kind), frame: zone.rect), actual: actual)
        }.value
        remember(outcome)
        return outcome
    }

    /// Display layout changed: remembered placements no longer mean anything.
    func reset() {
        memory.removeAll()
    }

    private func remember(_ outcome: TileOutcome?) {
        guard let outcome, let windowID = outcome.windowID else { return }
        memory[windowID] = TileMemory(placement: outcome.plan.placement, frame: outcome.actual ?? outcome.plan.frame,
                                      zoneBeforeDisplay: outcome.plan.zoneBeforeDisplay)
        onMove?()
    }
}
