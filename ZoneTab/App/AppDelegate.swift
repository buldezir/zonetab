import AppKit
import Combine
import ZoneTabCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings.shared
    private(set) lazy var inventory = WindowInventory()
    private(set) lazy var mover = WindowMover(settings: settings)
    private(set) lazy var layoutKeeper = DisplayLayoutKeeper(inventory: inventory, settings: settings)
    private lazy var switcher = SwitcherController(inventory: inventory, settings: settings)
    private lazy var dragSnapper = DragSnapper(settings: settings, mover: mover)
    private lazy var settingsWindow = SettingsWindowController(settings: settings)
    private var statusMenu: StatusMenuController?

    private var featuresStarted = false
    private var nativeSwitcherDisabled = false
    private var appliedShortcuts: [ShortcutAction: KeyCombo] = [:]
    private var appliedReplaceCommandTab: Bool?
    private var appliedZones: ZoneConfig?
    private var trustTimer: Timer?
    private var settingsSubscription: AnyCancellable?
    private var observers: [NSObjectProtocol] = []

    private static func tileHotKeyID(_ action: ShortcutAction) -> UInt32 {
        10 + UInt32(ShortcutAction.allCases.firstIndex(of: action) ?? 0)
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        if anotherInstanceIsRunning() {
            Log.app.info("ZoneTab is already running; exiting")
            exit(0)
        }
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)
        statusMenu = StatusMenuController(app: self)
        NativeSwitcherGuard.spawnWatchdog()
        observeSystem()

        settingsSubscription = settings.objectWillChange.sink { [weak self] in
            // objectWillChange fires before the new value is stored.
            DispatchQueue.main.async { self?.applySettings() }
        }

        if Permissions.isAccessibilityTrusted {
            startFeatures()
        } else {
            Permissions.promptForAccessibility()
            waitForAccessibility()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if nativeSwitcherDisabled { NativeSwitcherGuard.setNativeSwitcherEnabled(true) }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        #if DEBUG
        for url in urls { Diagnostics.handle(url, app: self) }
        #endif
    }

    private func anotherInstanceIsRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains {
            $0.processIdentifier != getpid() && !$0.isTerminated && $0.activationPolicy != .prohibited
        }
    }

    private func waitForAccessibility() {
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard Permissions.isAccessibilityTrusted else { return }
                self?.trustTimer?.invalidate()
                self?.trustTimer = nil
                Log.app.info("Accessibility access granted")
                self?.startFeatures()
            }
        }
    }

    var isRunning: Bool { featuresStarted }

    private func startFeatures() {
        guard !featuresStarted else { return }
        featuresStarted = true
        mover.onMove = { [weak self] in self?.layoutKeeper.recordSoon() }
        applySettings()
        dragSnapper.start()
    }

    // MARK: - Settings

    /// Reacts to settings changes. Only what actually changed is re-applied: the zone width slider fires this
    /// on every step.
    func applySettings() {
        statusMenu?.refresh()
        guard featuresStarted else { return }

        for action in ShortcutAction.allCases where appliedShortcuts[action] != settings.shortcut(for: action) {
            let combo = settings.shortcut(for: action)
            let command = action.command
            HotKeyCenter.shared.register(id: Self.tileHotKeyID(action), combo: combo) { [weak self] in
                self?.tile(command)
            }
            appliedShortcuts[action] = combo
        }

        if appliedReplaceCommandTab != settings.replaceCommandTab {
            appliedReplaceCommandTab = settings.replaceCommandTab
            if settings.replaceCommandTab {
                if !nativeSwitcherDisabled { disableNativeSwitcher() }
                switcher.registerShortcuts()
            } else {
                switcher.unregisterShortcuts()
                if nativeSwitcherDisabled {
                    NativeSwitcherGuard.setNativeSwitcherEnabled(true)
                    nativeSwitcherDisabled = false
                }
            }
        }

        // Remembered placements refer to the old zone geometry.
        let zones = settings.zonesEnabled ? settings.zoneConfig : nil
        if zones != appliedZones {
            appliedZones = zones
            mover.reset()
        }
        layoutKeeper.setEnabled(settings.zonesEnabled && settings.keepTilesWhenUnplugged)
    }

    private func disableNativeSwitcher() {
        NativeSwitcherGuard.setNativeSwitcherEnabled(false)
        nativeSwitcherDisabled = true
        // A previous instance's watchdog may restore the native switcher just after we start; apply again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.nativeSwitcherDisabled else { return }
            NativeSwitcherGuard.setNativeSwitcherEnabled(false)
        }
    }

    private func tile(_ command: TileCommand) {
        Task { await mover.perform(command) }
    }

    func showSettings() {
        settingsWindow.show()
    }

    // MARK: - System events

    private func observeSystem() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.switcher.cancel()
                self?.mover.reset()
            }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.switcher.cancel()
                    if self.nativeSwitcherDisabled { NativeSwitcherGuard.setNativeSwitcherEnabled(false) }
                }
            })
        }
    }
}
