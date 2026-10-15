import Carbon.HIToolbox
import Combine
import Foundation
import ZoneTabCore

enum ShortcutAction: String, CaseIterable, Codable, Identifiable {
    case fill, left, right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: "Fill zone / maximize"
        case .left: "Move to left zone (or half)"
        case .right: "Move to right zone (or half)"
        }
    }

    var defaultCombo: KeyCombo {
        switch self {
        case .fill: KeyCombo(keyCode: kVK_Return, modifiers: KeyCombo.hyper)
        case .left: KeyCombo(keyCode: kVK_LeftArrow, modifiers: KeyCombo.hyper)
        case .right: KeyCombo(keyCode: kVK_RightArrow, modifiers: KeyCombo.hyper)
        }
    }

    var command: TileCommand {
        switch self {
        case .fill: .fill
        case .left: .left
        case .right: .right
        }
    }
}

/// User preferences, persisted in UserDefaults. `objectWillChange` drives both SwiftUI and the app's reaction
/// to changes (re-registering shortcuts, toggling the native switcher).
final class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    @Published var zonesEnabled: Bool {
        didSet { defaults.set(zonesEnabled, forKey: Keys.zonesEnabled) }
    }

    @Published var replaceCommandTab: Bool {
        didSet { defaults.set(replaceCommandTab, forKey: Keys.replaceCommandTab) }
    }

    @Published var primarySide: ZoneSide {
        didSet { defaults.set(primarySide.rawValue, forKey: Keys.primarySide) }
    }

    @Published private(set) var shortcuts: [ShortcutAction: KeyCombo] {
        didSet {
            let stored = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
            defaults.set(try? JSONEncoder().encode(stored), forKey: Keys.shortcuts)
        }
    }

    private enum Keys {
        static let zonesEnabled = "zonesEnabled"
        static let replaceCommandTab = "replaceCommandTab"
        static let primarySide = "primarySide"
        static let shortcuts = "shortcuts"
    }

    private init() {
        defaults.register(defaults: [Keys.zonesEnabled: true, Keys.replaceCommandTab: true, Keys.primarySide: ZoneSide.left.rawValue])
        zonesEnabled = defaults.bool(forKey: Keys.zonesEnabled)
        replaceCommandTab = defaults.bool(forKey: Keys.replaceCommandTab)
        primarySide = ZoneSide(rawValue: defaults.string(forKey: Keys.primarySide) ?? "") ?? .left
        var shortcuts = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultCombo) })
        if let data = defaults.data(forKey: Keys.shortcuts),
           let stored = try? JSONDecoder().decode([String: KeyCombo].self, from: data) {
            for (key, combo) in stored { if let action = ShortcutAction(rawValue: key) { shortcuts[action] = combo } }
        }
        self.shortcuts = shortcuts
    }

    func shortcut(for action: ShortcutAction) -> KeyCombo {
        shortcuts[action] ?? action.defaultCombo
    }

    func setShortcut(_ combo: KeyCombo, for action: ShortcutAction) {
        shortcuts[action] = combo
    }

    func resetShortcut(_ action: ShortcutAction) {
        shortcuts[action] = action.defaultCombo
    }
}
