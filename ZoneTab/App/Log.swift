import os

/// `log stream --predicate 'subsystem == "dev.sasha.zonetab"' --level debug`
nonisolated enum Log {
    static let app = Logger(subsystem: "dev.sasha.zonetab", category: "app")
    static let switcher = Logger(subsystem: "dev.sasha.zonetab", category: "switcher")
    static let tiling = Logger(subsystem: "dev.sasha.zonetab", category: "tiling")
    static let hotkeys = Logger(subsystem: "dev.sasha.zonetab", category: "hotkeys")
}
