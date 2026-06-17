import AppKit
import SwiftUI

/// Lazily creates and shows the Settings window. A menu-bar-only (LSUIElement)
/// app can't rely on the standard Settings scene on macOS 13, so we host the
/// SwiftUI form in an NSWindow we manage ourselves.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(store: UsageStore) {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(store: store))
            let w = NSWindow(contentViewController: hosting)
            w.title = "Claude Usage Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            // Place it clear of the top-right menu bar dropdown (left-of-center).
            if let vf = NSScreen.main?.visibleFrame {
                w.setFrameOrigin(NSPoint(x: vf.minX + 100,
                                         y: vf.midY - w.frame.height / 2))
            } else {
                w.center()
            }
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
