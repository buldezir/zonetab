import CoreGraphics
@testable import ZoneTabCore

enum Fixtures {
    /// LG 5K2K at "looks like" 3840×1620, menu bar 33 pt, Dock hidden.
    static let lg = DisplayInfo(id: 1, uuid: "LG", frame: CGRect(x: 0, y: 0, width: 3840, height: 1620),
                                usableFrame: CGRect(x: 0, y: 33, width: 3840, height: 1587))
    /// A 16:10 laptop panel to the right of the LG.
    static let laptop = DisplayInfo(id: 2, uuid: "Laptop", frame: CGRect(x: 3840, y: 0, width: 1728, height: 1117),
                                    usableFrame: CGRect(x: 3840, y: 0, width: 1728, height: 1117))

    static let lgZones = ZoneLayout.zones(for: lg, config: ZoneConfig(side: .left))!
    static var zoneA: CGRect { lgZones[0].rect }
    static var zoneB: CGRect { lgZones[1].rect }

    static func app(_ pid: Int32, rank: Int = 0, hidden: Bool = false, regular: Bool = true) -> AppInfo {
        AppInfo(pid: pid, name: "App\(pid)", isHidden: hidden, isRegular: regular, activationRank: rank)
    }
}
