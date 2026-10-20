import AppKit
import ZoneTabCore

/// "Focus follows the mouse between zones": when the mouse moves into another zone (or display), the window under
/// it comes to the front and gets focus, as if it had been clicked. Moving around inside a zone changes nothing, and
/// neither does coming into a zone while using the keyboard.
final class FocusFollower {
    /// How long the mouse has to stay in a zone before its window is focused, so passing through one doesn't.
    private static let dwell: TimeInterval = 0.1
    /// If the mouse entered the zone over the menu bar, say, the window is focused once the mouse reaches it.
    /// Until then, the window list is read at most this often.
    private static let retryInterval: Duration = .milliseconds(50)

    private struct Region: Equatable {
        var displayID: UInt32
        var zone: ZoneKind?
    }

    private let inventory: WindowInventory
    private let settings: Settings
    /// Holds off while true (the switcher is open, and the mouse is pointing at apps in it).
    var isSuspended: () -> Bool = { false }

    private var monitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var displays: [DisplayInfo] = []
    private var region: Region?
    /// The mouse entered `region` and its window hasn't been focused yet.
    private var pending = false
    /// When the mouse entered `region`, in system uptime like the event source's clock.
    private var enteredAt: TimeInterval = 0
    private var dwellTimer: Timer?
    private var lastAttempt = ContinuousClock.now
    private var focusTask: Task<Void, Never>?

    init(inventory: WindowInventory, settings: Settings) {
        self.inventory = inventory
        self.settings = settings
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != (monitor != nil) else { return }
        guard enabled else {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
            screenObserver = nil
            reset()
            return
        }
        displays = WindowInventory.displays()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.displays = WindowInventory.displays()
                self?.reset()
            }
        }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            let moved = event.type == .mouseMoved
            MainActor.assumeIsolated { moved ? self?.mouseMoved() : self?.cancel() }
        }
    }

    /// Something else is taking focus (a click, the switcher): drop what was about to happen.
    func cancel() {
        pending = false
        dwellTimer?.invalidate()
        dwellTimer = nil
        focusTask?.cancel()
        focusTask = nil
    }

    private func reset() {
        cancel()
        region = nil
    }

    private func mouseMoved() {
        guard let region = region(at: WindowInventory.mouseLocation) else { return }
        guard !isSuspended() else {
            self.region = region
            cancel()
            return
        }
        if region != self.region {
            // The first position seen is only where the mouse starts.
            let entered = self.region != nil
            self.region = region
            cancel()
            guard entered else { return }
            pending = true
            enteredAt = ProcessInfo.processInfo.systemUptime
            dwellTimer = Timer.scheduledTimer(withTimeInterval: Self.dwell, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.dwellTimer = nil
                    self?.focusWindowUnderMouse()
                }
            }
        } else if pending, dwellTimer == nil, ContinuousClock.now - lastAttempt >= Self.retryInterval {
            focusWindowUnderMouse()
        }
    }

    /// A key is held, or one was pressed or released since the mouse entered the zone: the keystrokes are meant for
    /// the focused window, so the focus stays there. Caps Lock stays down while it's on, so it doesn't count as held.
    private var isKeyboardInUse: Bool {
        let state = CGEventSourceStateID.combinedSessionState
        let sinceEntered = ProcessInfo.processInfo.systemUptime - enteredAt
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        if types.contains(where: { CGEventSource.secondsSinceLastEventType(state, eventType: $0) < sinceEntered }) { return true }
        return (0..<128).contains { $0 != Self.capsLock && CGEventSource.keyState(state, key: $0) }
    }

    private static let capsLock: CGKeyCode = 57

    private func region(at point: CGPoint) -> Region? {
        ScopeResolver.scope(at: point, displays: displays, zonesEnabled: settings.zonesEnabled, config: settings.zoneConfig)
            .map { Region(displayID: $0.displayID, zone: $0.zone) }
    }

    private func focusWindowUnderMouse() {
        lastAttempt = .now
        let point = WindowInventory.mouseLocation
        guard pending else { return }
        guard !isSuspended(), !isKeyboardInUse else { return cancel() }
        guard NSEvent.pressedMouseButtons == 0, region(at: point) == region else { return }
        let snapshot = inventory.snapshot()
        switch MouseFocus.target(at: point, windows: snapshot.windows, apps: snapshot.apps, frontmostPID: snapshot.frontmostPID,
                                 ownPID: snapshot.ownPID) {
        case .none:
            break
        case .focused:
            pending = false
        case .window(let window):
            pending = false
            Log.tiling.debug("Focusing window \(window.id) under the mouse")
            focusTask = Task.detached(priority: .userInitiated) {
                await WindowFocuser.focus(pid: window.pid, windowID: window.id, unhide: false)
            }
        }
    }
}
