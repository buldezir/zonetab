import ServiceManagement
import SwiftUI
import ZoneTabCore

struct SettingsView: View {
    @ObservedObject var settings: Settings
    let preview: ZonePreview
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted

    var body: some View {
        Form {
            Section {
                Toggle("Zones on ultrawide displays", isOn: $settings.zonesEnabled)
                ZoneControls(settings: settings, preview: preview)
                    .disabled(!settings.zonesEnabled)
            } header: {
                Text("Zones")
            } footer: {
                Text("Displays 21:9 or wider get a main zone and a second zone with the rest of the width. By default the main zone is 16:9 at full height: on a 5K2K display, exactly a 4K-sized column. Windows keep their size until you snap them again. With zones off, everything works per display.")
            }

            Section {
                Toggle("Replace ⌘⇥ with ZoneTab's switcher", isOn: $settings.replaceCommandTab)
                Toggle(isOn: $settings.includeUntiledWindows) {
                    Text("Always include untiled windows")
                    Text("Floating windows, such as settings and dialogs, and full-screen apps are listed from anywhere on their display, not only from their zone.")
                }
                .disabled(!settings.replaceCommandTab)
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

/// Main zone position and width. While the slider is dragged, the zones are previewed on screen.
private struct ZoneControls: View {
    @ObservedObject var settings: Settings
    let preview: ZonePreview
    @State private var isDraggingWidth = false
    @State private var flashTask: Task<Void, Never>?

    /// The first zoned display, which the 16:9 stop and the size readout refer to.
    private var referenceDisplay: (name: String, frame: CGRect)? {
        NSScreen.screens.first { ZoneLayout.isZoned($0.frame) }.map { ($0.localizedName, $0.frame) }
    }

    private var sixteenByNinePercent: Double {
        referenceDisplay.map { ZoneLayout.fraction(for: $0.frame, width: .sixteenByNine) * 100 } ?? 75
    }

    /// Values within a step of 16:9 snap to it, so the "4K" width is easy to get back to.
    private var widthPercent: Binding<Double> {
        Binding(
            get: { settings.zoneWidthPercent ?? sixteenByNinePercent },
            set: { value in settings.zoneWidthPercent = abs(value - sixteenByNinePercent) < 1 ? nil : value })
    }

    private var readout: String {
        let width = settings.zoneConfig.width
        let percent = Int((ZoneLayout.fraction(for: referenceDisplay?.frame ?? .zero, width: width) * 100).rounded())
        var text = "\(percent)%"
        if let display = referenceDisplay {
            let main = Int(ZoneLayout.primaryWidth(for: display.frame, width: width))
            text += " · \(main) + \(Int(display.frame.width) - main) pt on \(display.name)"
        }
        return settings.zoneWidthPercent == nil ? text + " · 16:9 (4K)" : text
    }

    var body: some View {
        Picker("Main zone position", selection: $settings.primarySide) {
            Text("Left").tag(ZoneSide.left)
            Text("Right").tag(ZoneSide.right)
        }
        .onChange(of: settings.primarySide) { flashPreview() }

        LabeledContent("Main zone width") {
            Slider(value: widthPercent, in: ZoneLayout.fractionRange.lowerBound * 100...ZoneLayout.fractionRange.upperBound * 100,
                   step: 1) { editing in
                isDraggingWidth = editing
                if editing { showPreview() } else { preview.hide() }
            }
            .frame(width: 220)
        }
        .onChange(of: settings.zoneWidthPercent) { if isDraggingWidth { showPreview() } }

        HStack {
            Text(readout)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer()
            Button("Use 16:9 (4K)") {
                settings.zoneWidthPercent = nil
                flashPreview()
            }
            .disabled(settings.zoneWidthPercent == nil)
        }
    }

    private func showPreview() {
        flashTask?.cancel()
        preview.show(settings.zoneConfig)
    }

    /// Shows the zones briefly after a change made with a click rather than a drag.
    private func flashPreview() {
        showPreview()
        flashTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, !isDraggingWidth else { return }
            preview.hide()
        }
    }
}
