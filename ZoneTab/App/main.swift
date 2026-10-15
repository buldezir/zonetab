import AppKit

// Helper modes run before AppKit starts.
let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--watchdog"), index + 1 < arguments.count, let parent = pid_t(arguments[index + 1]) {
    NativeSwitcherGuard.runWatchdog(parentPID: parent)
}
if arguments.contains("--restore-native-cmd-tab") {
    NativeSwitcherGuard.setNativeSwitcherEnabled(true)
    exit(0)
}

let appDelegate = AppDelegate()
let application = NSApplication.shared
application.delegate = appDelegate
application.run()
