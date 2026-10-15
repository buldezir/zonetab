import Carbon.HIToolbox

/// Global shortcuts via Carbon `RegisterEventHotKey`. They work without an event tap and still fire while a
/// password field has secure input on.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private struct Registration {
        var combo: KeyCombo
        var ref: EventHotKeyRef?
        var action: () -> Void
    }

    private static let signature: OSType = 0x5A54_4142 // "ZTAB"
    private var eventHandler: EventHandlerRef?
    private var registrations: [UInt32: Registration] = [:]
    /// While the shortcut recorder is open, nothing is registered so it can capture any combination.
    private(set) var isSuspended = false

    private init() {}

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetEventDispatcherTarget(), hotKeyEventHandler, 1, &spec, nil, &eventHandler)
        if status != noErr { Log.hotkeys.error("InstallEventHandler failed: \(status)") }
    }

    /// Registers (or replaces) the shortcut with this id. Returns false if macOS refused the combination.
    @discardableResult
    func register(id: UInt32, combo: KeyCombo, action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        unregister(id: id)
        var registration = Registration(combo: combo, ref: nil, action: action)
        var ok = true
        if !isSuspended {
            registration.ref = Self.registerWithSystem(id: id, combo: combo)
            ok = registration.ref != nil
        }
        registrations[id] = registration
        return ok
    }

    func unregister(id: UInt32) {
        if let ref = registrations[id]?.ref { UnregisterEventHotKey(ref) }
        registrations[id] = nil
    }

    func unregister(ids: some Sequence<UInt32>) {
        for id in ids { unregister(id: id) }
    }

    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        for (id, registration) in registrations {
            if let ref = registration.ref { UnregisterEventHotKey(ref) }
            registrations[id]?.ref = nil
        }
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        for (id, registration) in registrations {
            registrations[id]?.ref = Self.registerWithSystem(id: id, combo: registration.combo)
        }
    }

    fileprivate func handlePress(id: UInt32) {
        registrations[id]?.action()
    }

    private static func registerWithSystem(id: UInt32, combo: KeyCombo) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, EventHotKeyID(signature: signature, id: id),
                                         GetEventDispatcherTarget(), 0, &ref)
        if status != noErr {
            Log.hotkeys.error("RegisterEventHotKey \(combo.displayString) (id \(id)) failed: \(status)")
            return nil
        }
        return ref
    }
}

/// Carbon delivers hot key events on the main thread.
private nonisolated func hotKeyEventHandler(_: EventHandlerCallRef?, _ event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }
    let id = hotKeyID.id
    MainActor.assumeIsolated { HotKeyCenter.shared.handlePress(id: id) }
    return noErr
}
