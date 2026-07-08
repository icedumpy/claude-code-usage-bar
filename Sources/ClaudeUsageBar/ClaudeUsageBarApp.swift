import SwiftUI

/// Owns the store and starts polling at launch — `.task`/`.onAppear` on a
/// MenuBarExtra label do not fire reliably, so we drive it from the delegate.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore.live()
    let updater = Updater()

    func applicationDidFinishLaunching(_ notification: Notification) {
        ClaudeMark.ensurePlaceholders()
        NotificationManager.shared.requestAuthorization()
        // Reconcile any interrupted self-update before anything else touches disk.
        updater.reconcileAtLaunch()
        store.start()
        // Re-attach the pinned panel if it was left open last session.
        if store.isPinned { PinnedPanelController.shared.show(store: store) }
    }
}

struct ClaudeUsageBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            DropdownView(store: delegate.store, updater: delegate.updater)
        } label: {
            MenuBarLabelView(store: delegate.store)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar label: the Claude sunburst tinted by severity, plus the percent.
/// Observes the store so both update while the dropdown is closed.
struct MenuBarLabelView: View {
    @ObservedObject var store: UsageStore
    var body: some View {
        HStack(spacing: 3) {
            if let icon = ClaudeMark.icon(for: store.menuBarSeverity) {
                Image(nsImage: icon).renderingMode(.original)
            }
            Text(store.menuBarCountdown.isEmpty
                 ? store.menuBarText
                 : "\(store.menuBarText) · \(store.menuBarCountdown)")
        }
    }
}
