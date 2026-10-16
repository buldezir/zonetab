import AppKit
import ZoneTabCore

/// What happened to one window when a layout was applied.
nonisolated struct AppliedChange: Codable, Sendable {
    var change: FrameChange
    /// Where the window ended up; nil if it wasn't found, or is minimized or in full screen.
    var actual: CGRect?
}

/// Keeps the tiles of zoned displays across unplugging them. While a display is connected, its layout is recorded
/// every few seconds. Once it's gone, its tiled windows are maximized wherever macOS put them; when it's back, they
/// return to their zones.
///
/// The record has to be from before the unplug: by the time anything is notified, macOS has already moved the
/// windows. So recording stops as soon as the display configuration starts changing, and nothing is moved until it
/// has settled.
final class DisplayLayoutKeeper {
    private struct State: Codable, Equatable {
        var layouts: [String: DisplayLayout] = [:]
        /// Displays unplugged since their layout was recorded: their layout is kept as it was until they're back.
        var away: Set<String> = []
    }

    private enum Action { case maximize, restore }

    private let inventory: WindowInventory
    private let settings: Settings
    private var state: State
    private var isEnabled = false
    private var isObservingDisplays = false
    private var recordTimer: Timer?
    private var settleTimer: Timer?
    private var isChanging = false
    /// Recorded displays seen offline while the configuration was changing, even if they're back by the end.
    private var wentOffline: Set<String> = []
    /// Layouts being applied. Recording waits for them, so a half-moved layout isn't saved.
    private var applying = 0

    private static let recordInterval: TimeInterval = 3
    /// macOS keeps moving windows for a moment after a display comes or goes.
    private static let settleDelay: TimeInterval = 2
    private static let fileURL = URL.applicationSupportDirectory.appending(path: "ZoneTab/display-layouts.json")

    init(inventory: WindowInventory, settings: Settings) {
        self.inventory = inventory
        self.settings = settings
        state = (try? Data(contentsOf: Self.fileURL)).flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        settleTimer?.invalidate()
        recordTimer?.invalidate()
        isChanging = false
        wentOffline.removeAll()
        guard enabled else {
            // Turned back on later, a display that is connected by then shouldn't get an old layout back.
            state.away.removeAll()
            save()
            return
        }
        if !isObservingDisplays {
            isObservingDisplays = true
            CGDisplayRegisterReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
        }
        // Displays unplugged while ZoneTab wasn't running get their tiles back when they return, or now if they
        // already have.
        let online = WindowInventory.onlineDisplayUUIDs()
        state.away.formUnion(Set(state.layouts.keys).subtracting(online))
        if !state.away.isDisjoint(with: online) {
            isChanging = true
            scheduleSettle()
        }
        recordTimer = Timer.scheduledTimer(withTimeInterval: Self.recordInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.record() }
        }
        record()
    }

    /// After ZoneTab tiles a window, so that unplugging right away still finds it in its new place.
    func recordSoon() {
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            record()
        }
    }

    private func record() {
        guard isEnabled, !isChanging, applying == 0 else { return }
        let snapshot = inventory.snapshot(includeAllSpaces: true, includeFullScreen: true)
        // Asked after the window list was read: a display that is still online now was online when the list was
        // taken, so its windows hadn't been moved off it yet.
        let online = WindowInventory.onlineDisplayUUIDs()
        var layouts = state.layouts
        for display in snapshot.displays where online.contains(display.uuid) && !state.away.contains(display.uuid) {
            layouts[display.uuid] = LayoutMemory.record(display: display, displays: snapshot.displays, windows: snapshot.windows,
                                                        apps: snapshot.apps, ownPID: snapshot.ownPID, config: settings.zoneConfig)
        }
        guard layouts != state.layouts else { return }
        state.layouts = layouts
        save()
    }

    // MARK: - Display changes

    /// Called before and after every display change.
    fileprivate func displaysChanging() {
        guard isEnabled else { return }
        isChanging = true
        wentOffline.formUnion(Set(state.layouts.keys).subtracting(WindowInventory.onlineDisplayUUIDs()))
        scheduleSettle()
    }

    private func scheduleSettle() {
        settleTimer?.invalidate()
        settleTimer = Timer.scheduledTimer(withTimeInterval: Self.settleDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.settle() }
        }
    }

    private func settle() {
        let displays = WindowInventory.displays()
        // With no display at all (lid closed, nothing plugged in) there is nowhere to put windows yet.
        guard !displays.isEmpty else { return }
        isChanging = false
        let online = Set(displays.map(\.uuid))
        let before = state
        for uuid in state.layouts.keys.sorted() {
            if !online.contains(uuid) {
                guard state.away.insert(uuid).inserted else { continue }
                Log.tiling.info("Display \(uuid, privacy: .public) unplugged: maximizing its windows")
                apply(.maximize, to: uuid)
            } else if state.away.remove(uuid) != nil || wentOffline.contains(uuid) {
                Log.tiling.info("Display \(uuid, privacy: .public) is back: restoring its tiles")
                apply(.restore, to: uuid)
            }
        }
        wentOffline.removeAll()
        if state != before { save() }
    }

    // MARK: - Moving windows

    /// - Parameter pids: only move these apps' windows (for testing).
    @discardableResult
    private func apply(_ action: Action, to uuid: String, pids: Set<pid_t>? = nil) -> Task<[AppliedChange], Never> {
        let layout = state.layouts[uuid]
        applying += 1
        return Task {
            defer { applying -= 1 }
            guard let layout else { return [] }
            var applied: [AppliedChange] = []
            // macOS may still be moving windows after the first pass, so look once more a little later.
            for pass in 0..<2 {
                if pass > 0 { try? await Task.sleep(for: .seconds(Self.settleDelay)) }
                let changes = changes(action, layout).filter { pids?.contains($0.pid) ?? true }
                guard !changes.isEmpty else { break }
                applied += await Task.detached(priority: .userInitiated) { Self.perform(changes) }.value
            }
            let moved = applied.filter { $0.actual != nil }.count
            Log.tiling.info("\(action == .maximize ? "Maximized" : "Restored", privacy: .public) \(moved) of \(applied.count) window frames")
            return applied
        }
    }

    private func changes(_ action: Action, _ layout: DisplayLayout) -> [FrameChange] {
        let snapshot = inventory.snapshot(includeAllSpaces: true, includeFullScreen: true)
        switch action {
        case .maximize:
            return LayoutMemory.maximizeChanges(for: layout, displays: snapshot.displays, windows: snapshot.windows, apps: snapshot.apps)
        case .restore:
            guard let display = snapshot.displays.first(where: { $0.uuid == layout.displayUUID }) else { return [] }
            return LayoutMemory.restoreChanges(for: layout, on: display, windows: snapshot.windows, apps: snapshot.apps,
                                               config: settings.zoneConfig)
        }
    }

    private nonisolated static func perform(_ changes: [FrameChange]) -> [AppliedChange] {
        var applied: [AppliedChange] = []
        for (pid, changes) in Dictionary(grouping: changes, by: \.pid) {
            let windows = AXWindow.windowsOnAnySpace(pid: pid, ids: Set(changes.map(\.windowID)))
            for change in changes {
                guard let window = windows[change.windowID], !window.isMinimized, !window.isFullScreen else {
                    applied.append(AppliedChange(change: change, actual: nil))
                    continue
                }
                applied.append(AppliedChange(change: change, actual: window.setFrame(change.frame, within: change.bounds)))
            }
        }
        return applied
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: Self.fileURL, options: .atomic)
        } catch {
            Log.tiling.error("Saving display layouts failed: \(error.localizedDescription)")
        }
    }
}

/// Called on the main thread, once before (`kCGDisplayBeginConfigurationFlag`) and once after each display's change.
private nonisolated func displayReconfigured(_: CGDirectDisplayID, _: CGDisplayChangeSummaryFlags, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let keeper = Unmanaged<DisplayLayoutKeeper>.fromOpaque(context).takeUnretainedValue()
    DispatchQueue.main.async { MainActor.assumeIsolated { keeper.displaysChanging() } }
}

#if DEBUG
extension DisplayLayoutKeeper {
    struct DebugResult: Encodable {
        var layout: DisplayLayout?
        var away: [String]
        var applied: [AppliedChange]
    }

    /// `save` records now. `disconnect` acts as if the display had been unplugged (maximizing on the display itself
    /// while it's still there) and keeps its layout until `restore`, which acts as if it were plugged back in.
    func debug(_ action: String, uuid: String, pids: Set<pid_t>?) async -> DebugResult {
        var applied: [AppliedChange] = []
        switch action {
        case "save":
            record()
        case "disconnect":
            state.away.insert(uuid)
            applied = await apply(.maximize, to: uuid, pids: pids).value
        case "restore":
            state.away.remove(uuid)
            applied = await apply(.restore, to: uuid, pids: pids).value
        default:
            break
        }
        save()
        return DebugResult(layout: state.layouts[uuid], away: state.away.sorted(), applied: applied)
    }
}
#endif
