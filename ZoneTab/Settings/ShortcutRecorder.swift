import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click, then press a key combination. Esc cancels. All global shortcuts are paused while recording so the
/// combination reaches the recorder instead of triggering ZoneTab.
struct ShortcutRecorder: View {
    let action: ShortcutAction
    @ObservedObject var settings: Settings
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        LabeledContent(action.title) {
            HStack(spacing: 6) {
                Button(isRecording ? "Type shortcut…" : settings.shortcut(for: action).displayString) {
                    isRecording ? stopRecording() : startRecording()
                }
                .frame(minWidth: 110)
                Button {
                    settings.resetShortcut(action)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset to \(action.defaultCombo.displayString)")
                .disabled(settings.shortcut(for: action) == action.defaultCombo)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        HotKeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape, KeyCombo(event: event).modifiers == 0 {
                stopRecording()
                return nil
            }
            let combo = KeyCombo(event: event)
            guard combo.hasRequiredModifier else {
                NSSound.beep()
                return nil
            }
            settings.setShortcut(combo, for: action)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        HotKeyCenter.shared.resume()
    }
}
