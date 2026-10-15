import CoreGraphics

/// One entry from the WindowServer's window list.
public struct WindowInfo: Sendable, Equatable, Codable {
    public var id: UInt32
    public var pid: Int32
    /// Quartz coordinates.
    public var bounds: CGRect
    public var layer: Int
    public var alpha: Double
    public var isOnScreen: Bool
    /// The window fills a full-screen Space (alone, or as one side of Split View).
    public var isFullScreen: Bool

    public init(id: UInt32, pid: Int32, bounds: CGRect, layer: Int = 0, alpha: Double = 1, isOnScreen: Bool = true,
                isFullScreen: Bool = false) {
        self.id = id
        self.pid = pid
        self.bounds = bounds
        self.layer = layer
        self.alpha = alpha
        self.isOnScreen = isOnScreen
        self.isFullScreen = isFullScreen
    }

    public static let minimumSize = CGSize(width: 100, height: 50)

    /// Normal app windows: the standard window layer, visible, and big enough to not be a utility sliver.
    public var isCandidate: Bool {
        layer == 0 && alpha > 0 && bounds.width >= Self.minimumSize.width && bounds.height >= Self.minimumSize.height
    }
}

public struct AppInfo: Sendable, Equatable, Codable {
    public var pid: Int32
    public var bundleID: String?
    public var name: String
    public var isHidden: Bool
    /// `NSApplication.ActivationPolicy.regular`: the apps native ⌘⇥ shows.
    public var isRegular: Bool
    /// 0 = most recently activated.
    public var activationRank: Int

    public init(pid: Int32, bundleID: String? = nil, name: String, isHidden: Bool = false, isRegular: Bool = true,
                activationRank: Int = .max) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
        self.isHidden = isHidden
        self.isRegular = isRegular
        self.activationRank = activationRank
    }
}
