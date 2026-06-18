import CoreGraphics

/// Pure geometry/bounds logic for the pinned PiP panel, split out from the
/// AppKit window code so it can be unit-tested. No UIKit/AppKit here.
public enum PinnedPanelGeometry {
    public static let minScale: Double = 0.8
    public static let maxScale: Double = 1.6
    public static let minOpacity: Double = 0.1
    public static let maxOpacity: Double = 1.0

    public static func clampScale(_ s: Double) -> Double {
        min(maxScale, max(minScale, s))
    }

    public static func clampOpacity(_ o: Double) -> Double {
        min(maxOpacity, max(minOpacity, o))
    }

    /// Keep a saved frame on screen: if it no longer intersects the visible
    /// area (e.g. a monitor was unplugged), re-center it (keeping its size) in
    /// the visible frame; otherwise return it unchanged.
    public static func onScreenFrame(saved: CGRect, visible: CGRect) -> CGRect {
        guard !visible.intersects(saved) else { return saved }
        return CGRect(x: visible.midX - saved.width / 2,
                      y: visible.midY - saved.height / 2,
                      width: saved.width,
                      height: saved.height)
    }

    /// Nudge a partially off-screen frame fully inside `visible` (keeping its
    /// size). If the frame is larger than `visible`, it pins to the top-left.
    /// Coordinates are AppKit-style (y increases upward).
    public static func clampedOnScreen(_ frame: CGRect, visible: CGRect) -> CGRect {
        var f = frame
        if f.maxX > visible.maxX { f.origin.x = visible.maxX - f.width }
        if f.minX < visible.minX { f.origin.x = visible.minX }
        if f.maxY > visible.maxY { f.origin.y = visible.maxY - f.height }
        if f.minY < visible.minY { f.origin.y = visible.minY }
        return f
    }
}
