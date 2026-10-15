import AppKit

/// Reports when ⌘ is released while the switcher is open.
///
/// A global flagsChanged monitor gives instant notice; a fast poll of the live modifier state covers the cases
/// where no event arrives (secure input, events delivered to our own windows, a lost release).
final class ModifierWatcher {
    private var monitor: Any?
    private var timer: Timer?
    private var onRelease: (() -> Void)?

    static var isCommandDown: Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand)
    }

    func start(onRelease: @escaping () -> Void) {
        stop()
        self.onRelease = onRelease
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let commandDown = event.modifierFlags.contains(.command)
            MainActor.assumeIsolated {
                if !commandDown { self?.fire() }
            }
        }
        let timer = Timer(timeInterval: 0.008, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if !Self.isCommandDown { self?.fire() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        timer?.invalidate()
        timer = nil
        onRelease = nil
    }

    private func fire() {
        guard let onRelease else { return }
        stop()
        onRelease()
    }
}
