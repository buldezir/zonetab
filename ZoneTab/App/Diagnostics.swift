#if DEBUG
import AppKit
import ZoneTabCore

/// Debug-build hooks for checking behaviour from a terminal. Use `open -g` so the frontmost app doesn't change:
///
///     open -g "zonetab://dump"                       # state at the mouse
///     open -g "zonetab://dump?x=3500&y=800"           # state at a point (Quartz coordinates)
///     open -g "zonetab://tile?action=left&bundle=com.apple.TextEdit"
///
/// Output goes to ~/Library/Application Support/ZoneTab/{diagnostics,tile-result}.json.
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
                .map { ScopeResolver.zoneMemberships(of: window.bounds, in: $0).sorted { $0.rawValue < $1.rawValue } } ?? []
            return WindowDump(app: name(window.pid), window: window, displayID: display?.id, zones: zones)
        }
        return Dump(
            generatedAt: Date(), running: app.isRunning, accessibilityTrusted: Permissions.isAccessibilityTrusted,
            zonesEnabled: settings.zonesEnabled, replaceCommandTab: settings.replaceCommandTab, zoneConfig: config,
            point: point, frontmostPID: snapshot.frontmostPID, scope: query?.scope,
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
