import AppKit

/// SkyLight (WindowServer) functions that are not exported by any public framework, looked up at runtime so a
/// future macOS that drops them degrades to public APIs instead of failing to launch.
private nonisolated enum SkyLight {
    typealias SetFrontProcessWithOptions = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    typealias PostEventRecordTo = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError

    nonisolated(unsafe) private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    static let setFrontProcessWithOptions: SetFrontProcessWithOptions? = symbol("_SLPSSetFrontProcessWithOptions")
    static let postEventRecordTo: PostEventRecordTo? = symbol("SLPSPostEventRecordTo")

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }
}

/// Brings one specific window to the front and gives it keyboard focus, without raising the app's other windows
/// (which may be sitting in the other zone).
nonisolated enum WindowFocuser {
    /// Raise only the given window, not every window of the app.
    private static let userGeneratedFront: UInt32 = 0x200

    static func focus(pid: pid_t, windowID: CGWindowID?, unhide: Bool) async {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }
        if unhide { app.unhide() }
        guard let windowID else {
            app.activate()
            return
        }
        bringForward(pid: pid, windowID: windowID, app: app)

        // Some apps re-order their windows right after activation; check once and repeat if we lost.
        try? await Task.sleep(for: .milliseconds(150))
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
            Log.switcher.debug("Focus retry for pid \(pid) window \(windowID)")
            bringForward(pid: pid, windowID: windowID, app: app)
        }
    }

    private static func bringForward(pid: pid_t, windowID: CGWindowID, app: NSRunningApplication) {
        var psn = ProcessSerialNumber()
        if let setFront = SkyLight.setFrontProcessWithOptions, let post = SkyLight.postEventRecordTo,
           ZTGetProcessForPID(pid, &psn) == noErr {
            _ = setFront(&psn, windowID, userGeneratedFront)
            makeKeyWindow(&psn, windowID: windowID, post: post)
        } else {
            app.activate()
        }
        AXWindow.window(pid: pid, id: windowID)?.raise()
    }

    /// Posts the synthetic event record WindowServer uses to make a window key. Layout as used by AltTab on
    /// macOS 14.7.4+: a 0x100-byte buffer (smaller buffers crash the target), a far-off click location so no app
    /// treats it as a real click, and the window id at 0x3c.
    private static func makeKeyWindow(_ psn: inout ProcessSerialNumber, windowID: CGWindowID, post: SkyLight.PostEventRecordTo) {
        var bytes = [UInt8](repeating: 0, count: 0x100)
        bytes[0x04] = 0xf8
        bytes[0x08] = 0x01
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: CGPoint(x: 300_000, y: 300_000)) { bytes.replaceSubrange(0x20..<0x30, with: $0) }
        withUnsafeBytes(of: windowID) { bytes.replaceSubrange(0x3c..<0x40, with: $0) }
        _ = bytes.withUnsafeMutableBufferPointer { buffer in post(&psn, buffer.baseAddress!) }
    }
}
