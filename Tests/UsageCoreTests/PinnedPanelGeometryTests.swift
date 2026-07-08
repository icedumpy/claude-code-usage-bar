import Testing
import Foundation
@testable import UsageCore

@Test func clampWidthStaysInBounds() {
    #expect(PinnedPanelGeometry.clampWidth(10) == PinnedPanelGeometry.minWidth)
    #expect(PinnedPanelGeometry.clampWidth(9000) == PinnedPanelGeometry.maxWidth)
    #expect(PinnedPanelGeometry.clampWidth(PinnedPanelGeometry.defaultWidth) == PinnedPanelGeometry.defaultWidth)
}

@Test func clampedOnScreenSlidesAWiderPanelInFromTheRightEdge() {
    // Failure mode Codex flagged: a panel anchored at the right edge that grows
    // wider must slide left to stay fully visible, not spill off-screen.
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let grown = CGRect(x: 1200, y: 700, width: 400, height: 160)  // maxX 1600 > 1440
    let result = PinnedPanelGeometry.clampedOnScreen(grown, visible: visible)
    #expect(result.size == grown.size)
    #expect(result.maxX == visible.maxX)   // right edge pinned on-screen
    #expect(result.minX == visible.maxX - grown.width)
}

@Test func clampOpacityStaysInBounds() {
    #expect(PinnedPanelGeometry.clampOpacity(0.0) == PinnedPanelGeometry.minOpacity)
    #expect(PinnedPanelGeometry.clampOpacity(2.0) == PinnedPanelGeometry.maxOpacity)
    #expect(PinnedPanelGeometry.clampOpacity(0.7) == 0.7)
}

@Test func onScreenFrameKeepsVisibleFrame() {
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let saved = CGRect(x: 100, y: 100, width: 300, height: 160)
    #expect(PinnedPanelGeometry.onScreenFrame(saved: saved, visible: visible) == saved)
}

@Test func onScreenFrameRecentersOffscreenFrame() {
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
    // Saved frame entirely off to the right (a disconnected monitor).
    let saved = CGRect(x: 5000, y: 4000, width: 300, height: 160)
    let result = PinnedPanelGeometry.onScreenFrame(saved: saved, visible: visible)
    #expect(result.size == saved.size)
    #expect(result.midX == visible.midX)
    #expect(result.midY == visible.midY)
}

@Test func clampedOnScreenPullsOverhangingTopBackIn() {
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
    // Top edge above the screen (the spawn bug: grew upward off the top).
    let frame = CGRect(x: 1300, y: 850, width: 300, height: 160)
    let result = PinnedPanelGeometry.clampedOnScreen(frame, visible: visible)
    #expect(result.size == frame.size)
    #expect(result.maxY == visible.maxY)   // top pinned to the visible top
    #expect(result.maxX == visible.maxX)   // right pinned to the visible right
}

@Test func clampedOnScreenLeavesFullyVisibleFrameAlone() {
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let frame = CGRect(x: 200, y: 200, width: 300, height: 160)
    #expect(PinnedPanelGeometry.clampedOnScreen(frame, visible: visible) == frame)
}
