import AppKit
import SwiftUI

final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: Settings

    init(settings: Settings) {
        self.settings = settings
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: settings))
            let window = NSWindow(contentViewController: hosting)
            window.title = "ZoneTab Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // A menu-bar app isn't active by default; without this the window opens behind everything.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
