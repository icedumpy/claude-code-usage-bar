import AppKit
import SwiftUI
import UsageCore

/// Owns the floating picture-in-picture panel. Chromeless, always-on-top,
/// visible on every Space and over fullscreen apps, never steals focus. Mirrors
/// SettingsWindowController's "host a SwiftUI view in a panel we manage" pattern
/// since a menu-bar-only (LSUIElement) app can't lean on SwiftUI scenes here.
@MainActor
final class PinnedPanelController: NSObject, NSWindowDelegate {
    static let shared = PinnedPanelController()
    private var panel: NSPanel?

    private let originXKey = "pinOriginX"
    private let originYKey = "pinOriginY"

    func show(store: UsageStore) {
        let p = panel ?? makePanel(store: store)
        panel = p
        // Order front first so the panel has laid out (valid size + screen)
        // before we read its frame to restore/correct the origin.
        p.orderFrontRegardless()
        positionOnScreen(p)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel(store: UsageStore) -> NSPanel {
        let hosting = NSHostingController(rootView: PinnedPanelView(store: store))
        hosting.sizingOptions = [.preferredContentSize]   // auto-size to content

        let p = FloatingPanel(contentViewController: hosting)
        p.styleMask = [.borderless, .nonactivatingPanel]
        p.acceptsMouseMovedEvents = true
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = true
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.delegate = self
        return p
    }

    /// Place the panel at its saved origin (or the top-right on first run),
    /// keeping it fully on screen. Forces the content size first, because the
    /// SwiftUI auto-size hasn't settled right after `orderFront`, and a
    /// zero-height frame would otherwise be positioned off the top of the screen.
    private func positionOnScreen(_ p: NSPanel) {
        if let v = p.contentViewController?.view {
            v.layoutSubtreeIfNeeded()
            p.setContentSize(v.fittingSize)
        }
        guard let visible = (p.screen ?? NSScreen.main)?.visibleFrame else { return }

        let size = p.frame.size
        let d = UserDefaults.standard
        let target: CGRect
        if d.object(forKey: originXKey) != nil {
            target = CGRect(x: d.double(forKey: originXKey), y: d.double(forKey: originYKey),
                            width: size.width, height: size.height)
        } else {
            target = CGRect(x: visible.maxX - size.width - 16,
                            y: visible.maxY - size.height - 16,
                            width: size.width, height: size.height)
        }
        // Re-center if it's totally off (monitor gone), then nudge any partial
        // overhang fully on screen.
        let recovered = PinnedPanelGeometry.onScreenFrame(saved: target, visible: visible)
        let onScreen = PinnedPanelGeometry.clampedOnScreen(recovered, visible: visible)
        p.setFrame(onScreen, display: true)
    }

    /// As the panel auto-sizes (content/zoom changes) keep it fully on screen,
    /// so growing taller never pushes the top under the menu bar / off-screen.
    @MainActor func windowDidResize(_ notification: Notification) {
        guard let w = notification.object as? NSWindow,
              let visible = (w.screen ?? NSScreen.main)?.visibleFrame else { return }
        let clamped = PinnedPanelGeometry.clampedOnScreen(w.frame, visible: visible)
        if clamped != w.frame { w.setFrame(clamped, display: true) }
    }

    @MainActor func windowDidMove(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        let d = UserDefaults.standard
        d.set(Double(w.frame.origin.x), forKey: originXKey)
        d.set(Double(w.frame.origin.y), forKey: originYKey)
    }
}

/// Borderless panels default `canBecomeKey` to false, which would swallow the
/// hover tracking and the button/drag events the PiP relies on. Allow it to
/// become key — it stays a nonactivating panel, so it never activates the app
/// or steals focus from what the user is doing.
private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
