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
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
