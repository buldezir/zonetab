#if DEBUG
import AppKit
import ZoneTabCore

/// Debug-build hooks for checking behaviour from a terminal. Use `open -g` so the frontmost app doesn't change:
///
///     open -g "zonetab://dump"                       # state at the mouse
///     open -g "zonetab://dump?x=3500&y=800"           # state at a point (Quartz coordinates)
///     open -g "zonetab://tile?action=left&bundle=com.apple.TextEdit"
///     open -g "zonetab://fullscreen?bundle=com.apple.TextEdit&on=1"   # focused window enters (on=0: leaves) full screen
///     open -g "zonetab://focus?wid=1234"                               # switch to a window, as the switcher does
///     open -g "zonetab://layout?action=save|disconnect|restore&bundle=com.apple.TextEdit"
///     open -g "zonetab://switcher"                                     # the ⌘⇥ session: selection, items on screen
///     open -g "zonetab://focusfollows?on=1"                            # turn "Focus follows the mouse" on (on=0: off)
///
/// `layout` acts on the first zoned display (or `uuid=`); `disconnect` and `restore` act as if it had been unplugged
/// and plugged back in, moving only `bundle`'s windows if given.
///
/// Output goes to ~/Library/Application Support/ZoneTab/: diagnostics.json and
/// {tile,fullscreen,focus,layout,switcher,focusfollows}-result.json.
enum Diagnostics {
    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "ZoneTab", directoryHint: .isDirectory)
    }

    static func handle(_ url: URL, app: AppDelegate) {
        let query = Dictionary(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map { ($0.name, $0.value ?? "") } ?? [],
                               uniquingKeysWith: { _, last in last })
        switch url.host() {
        case "dump":
            var point = WindowInventory.mouseLocation
            if let x = query["x"].flatMap(Double.init), let y = query["y"].flatMap(Double.init) { point = CGPoint(x: x, y: y) }
            write(dump(at: point, app: app), to: "diagnostics.json")
        case "fullscreen":
            guard let bundleID = query["bundle"],
                  let target = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
            let pid = target.processIdentifier
            let on = query["on"] != "0"
            Task.detached {
                fullScreenElement = AXWindow.focusedWindow(pid: pid)?.element ?? fullScreenElement
                guard let element = fullScreenElement else { return }
                let error = AXUIElementSetAttributeValue(element, "AXFullScreen" as CFString, on ? kCFBooleanTrue : kCFBooleanFalse)
                try? await Task.sleep(for: .seconds(1.5))
                await write(["error": "\(error.rawValue)", "spaces": currentSpaces()], to: "fullscreen-result.json")
            }
        case "focus":
            guard let wid = query["wid"].flatMap(UInt32.init), let window = WindowInventory.windows(ids: [wid]).first else { return }
            Task.detached {
                await WindowFocuser.focus(pid: window.pid, windowID: wid, unhide: false)
                try? await Task.sleep(for: .seconds(1.5))
                let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
                await write(["targetPID": "\(window.pid)", "frontmostPID": "\(frontmost ?? 0)",
                             "onScreen": "\(WindowInventory.window(id: wid)?.isOnScreen ?? false)",
                             "spaces": currentSpaces()], to: "focus-result.json")
            }
        case "layout":
            guard let uuid = query["uuid"] ?? WindowInventory.displays().first(where: { ZoneLayout.isZoned($0.frame) })?.uuid else {
                write(["error": "no zoned display"], to: "layout-result.json")
                return
            }
            let pids = query["bundle"].map { bundleID in
                Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map(\.processIdentifier))
            }
            Task {
                let result = await app.layoutKeeper.debug(query["action"] ?? "save", uuid: uuid, pids: pids)
                write(result, to: "layout-result.json")
            }
        case "switcher":
            write(app.switcher.debugState, to: "switcher-result.json")
        case "focusfollows":
            let previous = app.settings.focusFollowsMouse
            app.settings.focusFollowsMouse = query["on"] != "0"
            write(["previous": previous], to: "focusfollows-result.json")
        case "tile":
            guard let command = query["action"].flatMap(TileCommand.init(rawValue:)),
                  let bundleID = query["bundle"],
                  let target = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
                write(["error": "usage: zonetab://tile?action=fill|left|right&bundle=<bundle id>"], to: "tile-result.json")
                return
            }
            Task {
                let outcome = await app.mover.perform(command, pid: target.processIdentifier)
                write(TileResult(command: command.rawValue, bundleID: bundleID, outcome: outcome), to: "tile-result.json")
            }
        default:
            write(["error": "unknown command \(url.absoluteString)"], to: "diagnostics.json")
        }
    }

    nonisolated(unsafe) private static var fullScreenElement: AXUIElement?

    /// Per display: the current Space's type and full-screen window, e.g. "type 4 fs_wid 123".
    private nonisolated static func currentSpaces() -> String {
        WindowInventory.managedDisplaySpaces().map { display in
            let current = display["Current Space"] as? [String: Any]
            return "\(display["Display Identifier"] ?? "?"): type \(current?["type"] ?? "?") fs_wid \(current?["fs_wid"] ?? "-")"
        }.joined(separator: "; ")
    }

    private struct TileResult: Encodable {
        var command: String
        var bundleID: String
        var outcome: TileOutcome?
    }

    private struct DisplayDump: Encodable {
        var display: DisplayInfo
        var zones: [Zone]?
        var fullScreenSpace: Bool
    }

    private struct WindowDump: Encodable {
        var app: String
        var window: WindowInfo
        var displayID: UInt32?
        var zones: [ZoneKind]
        /// nil on displays without zones.
        var tiled: Bool?
    }

    private struct EntryDump: Encodable {
        var app: String
        var entry: SwitcherEntry
    }

    private struct Dump: Encodable {
        var generatedAt: Date
        var running: Bool
        var accessibilityTrusted: Bool
        var zonesEnabled: Bool
        var replaceCommandTab: Bool
        var zoneConfig: ZoneConfig
        var includeUntiledWindows: Bool
        var point: CGPoint
        var frontmostPID: Int32?
        var scope: Scope?
        var fullScreenFallback: Bool
        var displays: [DisplayDump]
        var windows: [WindowDump]
        var switcher: [EntryDump]
        var initialSelection: Int?
    }

    private static func dump(at point: CGPoint, app: AppDelegate) -> Dump {
        let settings = app.settings
        let config = settings.zoneConfig
        let query = SwitcherController.query(inventory: app.inventory, settings: settings, at: point)
        let snapshot = query?.snapshot ?? app.inventory.snapshot()
        let list = query?.list
        func name(_ pid: Int32) -> String { snapshot.apps[pid]?.name ?? "pid \(pid)" }

        let windows = snapshot.windows.filter(\.isCandidate).map { window -> WindowDump in
            let display = ScopeResolver.display(for: window.bounds, in: snapshot.displays)
            let zones = display.flatMap { ZoneLayout.zones(for: $0, config: config) }
            let memberships = zones.map { ScopeResolver.zoneMemberships(of: window.bounds, in: $0).sorted { $0.rawValue < $1.rawValue } }
            return WindowDump(app: name(window.pid), window: window, displayID: display?.id, zones: memberships ?? [],
                              tiled: zones.map { ScopeResolver.isTiled(window.bounds, in: $0) })
        }
        return Dump(
            generatedAt: Date(), running: app.isRunning, accessibilityTrusted: Permissions.isAccessibilityTrusted,
            zonesEnabled: settings.zonesEnabled, replaceCommandTab: settings.replaceCommandTab, zoneConfig: config,
            includeUntiledWindows: settings.includeUntiledWindows, point: point, frontmostPID: snapshot.frontmostPID, scope: query?.scope,
            fullScreenFallback: query?.isFullScreenFallback ?? false,
            displays: snapshot.displays.map {
                DisplayDump(display: $0, zones: ZoneLayout.zones(for: $0, config: config),
                            fullScreenSpace: WindowInventory.isFullScreenSpaceActive(displayUUID: $0.uuid))
            },
            windows: windows,
            switcher: list?.entries.map { EntryDump(app: name($0.pid), entry: $0) } ?? [],
            initialSelection: list?.initialSelection)
    }

    private static func write(_ value: some Encodable, to fileName: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder.encode(value).write(to: directory.appending(path: fileName), options: .atomic)
        } catch {
            Log.app.error("Diagnostics write failed: \(error.localizedDescription)")
        }
    }
}
#endif
