import CoreGraphics

/// Everything in ZoneTabCore uses Quartz coordinates: origin at the top-left of the primary display, y grows down.
/// That is what CGWindowList and the Accessibility API use. AppKit (NSScreen, NSEvent.mouseLocation, NSWindow)
/// uses Cocoa coordinates: origin at the bottom-left of the primary display, y grows up.
public enum Geometry {
    /// Converts a rect between Cocoa and Quartz coordinates. The conversion is its own inverse.
    /// `primaryMaxY` is `NSScreen.screens[0].frame.maxY` (the primary display's height).
    public static func flip(_ rect: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryMaxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Converts a point between Cocoa and Quartz coordinates. The conversion is its own inverse.
    public static func flip(_ point: CGPoint, primaryMaxY: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryMaxY - point.y)
    }

    /// Whether two rects are equal within `tolerance` points on every edge.
    public static func approximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.maxX - b.maxX) <= tolerance && abs(a.maxY - b.maxY) <= tolerance
    }

    public static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull || rect.isEmpty ? 0 : rect.width * rect.height
    }

    public static func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        area(a.intersection(b))
    }
}
