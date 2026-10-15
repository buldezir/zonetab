import AppKit

/// Turns the system ⌘⇥ / ⌘⇧⇥ switcher off while ZoneTab provides its own, and makes sure it comes back.
///
/// The symbolic hot key state is global and survives the process, so it is restored on normal quit and by a
/// watchdog process that outlives crashes, `kill -9` and Xcode's Stop button.
nonisolated enum NativeSwitcherGuard {
    private static let symbolicHotKeys: [Int32] = [1, 2]

    static func setNativeSwitcherEnabled(_ enabled: Bool) {
        for hotKey in symbolicHotKeys {
            let error = CGSSetSymbolicHotKeyEnabled(hotKey, enabled)
            if error != .success { Log.hotkeys.error("CGSSetSymbolicHotKeyEnabled(\(hotKey), \(enabled)) failed: \(error.rawValue)") }
        }
    }

    /// Launches `ZoneTab --watchdog <our pid>`.
    static func spawnWatchdog() {
        guard let executable = Bundle.main.executableURL else { return }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--watchdog", String(getpid())]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            Log.app.info("Watchdog started, pid \(process.processIdentifier)")
        } catch {
            Log.app.error("Could not start watchdog: \(error.localizedDescription)")
        }
    }

    /// Waits for `parentPID` to exit, then restores the native switcher unless another ZoneTab has taken over.
    static func runWatchdog(parentPID: pid_t) -> Never {
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        signal(SIGHUP, SIG_IGN)
        let source = DispatchSource.makeProcessSource(identifier: parentPID, eventMask: .exit, queue: .main)
        source.setEventHandler { finishWatchdog(parentPID: parentPID) }
        source.resume()
        if kill(parentPID, 0) != 0, errno == ESRCH { finishWatchdog(parentPID: parentPID) }
        dispatchMain()
    }

    private static func finishWatchdog(parentPID: pid_t) -> Never {
        // Give a relaunched instance a moment to register before deciding nobody needs the switcher off.
        usleep(500_000)
        let bundleID = Bundle.main.bundleIdentifier ?? "dev.sasha.zonetab"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter {
            $0.processIdentifier != parentPID && $0.processIdentifier != getpid() && !$0.isTerminated
        }
        if others.isEmpty { setNativeSwitcherEnabled(true) }
        exit(0)
    }
}
