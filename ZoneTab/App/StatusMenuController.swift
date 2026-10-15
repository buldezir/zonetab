import AppKit
import ZoneTabCore

final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private weak var app: AppDelegate?

    init(app: AppDelegate) {
        self.app = app
        super.init()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        refresh()
    }

    func refresh() {
        let zonesOn = app?.settings.zonesEnabled ?? true
        let symbol = Permissions.isAccessibilityTrusted ? (zonesOn ? "rectangle.split.2x1" : "rectangle") : "exclamationmark.triangle"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "ZoneTab")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let settings = app?.settings else { return }

        if !Permissions.isAccessibilityTrusted {
            menu.addItem(item("Grant Accessibility Access…", #selector(openAccessibility)))
            menu.addItem(.separator())
        }

        menu.addItem(item("Zones", #selector(toggleZones), state: settings.zonesEnabled))
        for side in ZoneSide.allCases {
            let title = side == .left ? "Main Zone on Left" : "Main Zone on Right"
            let sideItem = item(title, #selector(chooseSide(_:)), state: settings.primarySide == side)
            sideItem.indentationLevel = 1
            sideItem.representedObject = side.rawValue
            sideItem.isEnabled = settings.zonesEnabled
            menu.addItem(sideItem)
        }
        menu.addItem(item("Replace ⌘⇥ App Switcher", #selector(toggleSwitcher), state: settings.replaceCommandTab))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Quit ZoneTab", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, state: Bool? = nil, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let state { item.state = state ? .on : .off }
        return item
    }

    @objc private func toggleZones() { app?.settings.zonesEnabled.toggle() }
    @objc private func toggleSwitcher() { app?.settings.replaceCommandTab.toggle() }
    @objc private func openAccessibility() { Permissions.openAccessibilitySettings() }
    @objc private func openSettings() { app?.showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func chooseSide(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let side = ZoneSide(rawValue: raw) else { return }
        app?.settings.primarySide = side
    }
}
