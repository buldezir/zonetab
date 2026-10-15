import AppKit
import Carbon.HIToolbox
import ZoneTabCore

struct SwitcherItem: Identifiable, Equatable {
    var id: pid_t { pid }
    let pid: pid_t
    let name: String
    let icon: NSImage
    let windowID: CGWindowID?
    var isHidden: Bool
}

/// The ⌘⇥ session: idle → pending (panel not shown yet) → shown → commit or cancel.
final class SwitcherController {
    private enum HotKeyID {
        static let next: UInt32 = 1
        static let previous: UInt32 = 2
        static let session: ClosedRange<UInt32> = 100...199
    }

    /// Releasing ⌘ before this delay switches without ever showing the panel, like the native switcher.
    private static let showDelay: Duration = .milliseconds(80)

    private let inventory: WindowInventory
    private let settings: Settings
    private let panel = SwitcherPanel()
    private let modifierWatcher = ModifierWatcher()
    private var terminationObserver: NSObjectProtocol?

    private var items: [SwitcherItem] = []
    private var selection = 0
    private var scopeRect: CGRect = .zero
    private var isActive = false
    private var showTask: Task<Void, Never>?

    init(inventory: WindowInventory, settings: Settings) {
        self.inventory = inventory
        self.settings = settings
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated { self?.appTerminated(pid) }
        }
    }

    // MARK: - Shortcuts

    func registerShortcuts() {
        let center = HotKeyCenter.shared
        center.register(id: HotKeyID.next, combo: KeyCombo(keyCode: kVK_Tab, modifiers: KeyCombo.command)) { [weak self] in
            self?.step(1)
        }
        center.register(id: HotKeyID.previous, combo: KeyCombo(keyCode: kVK_Tab, modifiers: KeyCombo.command | KeyCombo.shift)) { [weak self] in
            self?.step(-1)
        }
    }

    func unregisterShortcuts() {
        cancel()
        HotKeyCenter.shared.unregister(ids: [HotKeyID.next, HotKeyID.previous])
    }

    /// Keys that only exist while the switcher is open. ⌘ is held, so they are ⌘-combinations, which also keeps
    /// them away from the frontmost app (⌘Q would otherwise quit it).
    private func registerSessionKeys() {
        let command = KeyCombo.command
        let shift = KeyCombo.shift
        let bindings: [(Int, () -> Void)] = [
            (kVK_LeftArrow, { [weak self] in self?.step(-1) }),
            (kVK_RightArrow, { [weak self] in self?.step(1) }),
            (kVK_UpArrow, { [weak self] in self?.step(-1) }),
            (kVK_DownArrow, { [weak self] in self?.step(1) }),
            (kVK_Return, { [weak self] in self?.commit() }),
            (kVK_ANSI_KeypadEnter, { [weak self] in self?.commit() }),
            (kVK_Escape, { [weak self] in self?.cancel() }),
            (kVK_ANSI_Q, { [weak self] in self?.quitSelected() }),
            (kVK_ANSI_H, { [weak self] in self?.hideSelected() }),
        ]
        var id = HotKeyID.session.lowerBound
        for (keyCode, action) in bindings {
            for modifiers in [command, command | shift] {
                HotKeyCenter.shared.register(id: id, combo: KeyCombo(keyCode: keyCode, modifiers: modifiers), action: action)
                id += 1
            }
        }
    }

    private func unregisterSessionKeys() {
        HotKeyCenter.shared.unregister(ids: HotKeyID.session)
    }

    // MARK: - Session

    private func step(_ delta: Int) {
        if isActive {
            guard !items.isEmpty else { return }
            selection = (selection + delta + items.count) % items.count
            panel.update(selection: selection)
        } else {
            begin(forward: delta > 0)
        }
        // A hot key and the ⌘ release can arrive out of order; never leave the switcher waiting for a release
        // that already happened.
        if isActive, !ModifierWatcher.isCommandDown { commit() }
    }

    struct Query {
        var scope: Scope
        var list: SwitcherList
        var snapshot: InventorySnapshot
        /// The cursor's display shows a full-screen Space, so every app is listed instead of the scope's.
        var isFullScreenFallback: Bool
    }

    /// What ⌘⇥ lists for a cursor position (Quartz coordinates). Also used by the debug diagnostics.
    static func query(inventory: WindowInventory, settings: Settings, at point: CGPoint) -> Query? {
        let snapshot = inventory.snapshot()
        guard let scope = ScopeResolver.scope(at: point, displays: snapshot.displays,
                                              zonesEnabled: settings.zonesEnabled, side: settings.primarySide) else { return nil }
        let displayUUID = snapshot.displays.first { $0.id == scope.displayID }?.uuid ?? ""
        if WindowInventory.isFullScreenSpaceActive(displayUUID: displayUUID) {
            let all = inventory.snapshot(includeAllSpaces: true)
            let list = SwitcherListBuilder.buildFallback(windows: all.windows, apps: all.apps,
                                                         frontmostPID: all.frontmostPID, ownPID: all.ownPID)
            return Query(scope: scope, list: list, snapshot: all, isFullScreenFallback: true)
        }
        let list = SwitcherListBuilder.build(windows: snapshot.windows, apps: snapshot.apps, frontmostPID: snapshot.frontmostPID,
                                             ownPID: snapshot.ownPID, scope: scope, displays: snapshot.displays,
                                             side: settings.primarySide)
        return Query(scope: scope, list: list, snapshot: snapshot, isFullScreenFallback: false)
    }

    private func begin(forward: Bool) {
        guard let query = Self.query(inventory: inventory, settings: settings, at: WindowInventory.mouseLocation) else { return }
        let list = query.list
        let scope = query.scope

        let entries = list.entries.compactMap { entry -> SwitcherItem? in
            guard let app = NSRunningApplication(processIdentifier: entry.pid), !app.isTerminated else { return nil }
            let icon = app.icon ?? NSWorkspace.shared.icon(for: .application)
            return SwitcherItem(pid: entry.pid, name: app.localizedName ?? "?", icon: icon,
                                windowID: entry.windowID, isHidden: entry.isHidden)
        }
        guard let initial = list.initialSelection, entries.count == list.entries.count else {
            Log.switcher.debug("Nothing to switch to (\(list.entries.count) entries)")
            return
        }

        items = entries
        selection = forward ? initial : entries.count - 1
        scopeRect = scope.rect
        isActive = true
        registerSessionKeys()
        modifierWatcher.start { [weak self] in self?.commit() }
        showTask = Task { [weak self] in
            try? await Task.sleep(for: Self.showDelay)
            guard let self, self.isActive, !Task.isCancelled else { return }
            self.panel.show(items: self.items, selection: self.selection, in: self.scopeRect)
        }
    }

    private func commit() {
        guard isActive, items.indices.contains(selection) else { return cancel() }
        let item = items[selection]
        end()
        Log.switcher.debug("Switching to \(item.name) window \(item.windowID ?? 0)")
        Task.detached(priority: .userInitiated) {
            await WindowFocuser.focus(pid: item.pid, windowID: item.windowID, unhide: item.isHidden)
        }
    }

    func cancel() {
        guard isActive else { return }
        end()
    }

    private func end() {
        isActive = false
        showTask?.cancel()
        showTask = nil
        modifierWatcher.stop()
        unregisterSessionKeys()
        panel.hide()
        items = []
    }

    private func quitSelected() {
        guard isActive, items.indices.contains(selection) else { return }
        NSRunningApplication(processIdentifier: items[selection].pid)?.terminate()
        // The entry disappears when the app actually exits (appTerminated).
    }

    private func hideSelected() {
        guard isActive, items.indices.contains(selection) else { return }
        NSRunningApplication(processIdentifier: items[selection].pid)?.hide()
        items[selection].isHidden = true
        panel.update(items: items, selection: selection, in: scopeRect)
    }

    private func appTerminated(_ pid: pid_t) {
        guard isActive, let index = items.firstIndex(where: { $0.pid == pid }) else { return }
        items.remove(at: index)
        if items.isEmpty { return cancel() }
        if selection > index || selection >= items.count { selection = max(0, selection - 1) }
        panel.update(items: items, selection: selection, in: scopeRect)
    }
}
