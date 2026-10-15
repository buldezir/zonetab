import ServiceManagement
import SwiftUI
import ZoneTabCore

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted

    var body: some View {
        Form {
            Section {
                Toggle("Zones on ultrawide displays", isOn: $settings.zonesEnabled)
                Picker("4K zone position", selection: $settings.primarySide) {
                    Text("Left").tag(ZoneSide.left)
                    Text("Right").tag(ZoneSide.right)
                }
                .disabled(!settings.zonesEnabled)
            } header: {
                Text("Zones")
            } footer: {
                Text("Displays 21:9 or wider get a 16:9 zone at full height (a 4K-sized column) and a second zone with the rest. With zones off, everything works per display.")
            }

            Section {
                Toggle("Replace ⌘⇥ with ZoneTab's switcher", isOn: $settings.replaceCommandTab)
            } header: {
                Text("App switcher")
            } footer: {
                Text("Lists only apps with a window in the zone (or display) under the mouse. Hold ⌘ and use ⇥, ⇧⇥ or arrows; ⌘Q quits and ⌘H hides the selected app; ⌘⎋ cancels.")
            }

            Section("Window shortcuts") {
                ForEach(ShortcutAction.allCases) { action in
                    ShortcutRecorder(action: action, settings: settings)
                }
                LabeledContent("Snap to zone", value: "Hold ⇧ while dragging a window")
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchAtLoginError {
                    Text(launchAtLoginError).foregroundStyle(.red).font(.caption)
                }
                LabeledContent("Accessibility access") {
                    if accessibilityTrusted {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Open System Settings…") { Permissions.openAccessibilitySettings() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            accessibilityTrusted = Permissions.isAccessibilityTrusted
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
