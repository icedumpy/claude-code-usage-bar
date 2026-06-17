import SwiftUI

/// Owns the store and starts polling at launch — `.task`/`.onAppear` on a
/// MenuBarExtra label do not fire reliably, so we drive it from the delegate.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore.live()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.start()
    }
}

struct ClaudeUsageBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            DropdownView(store: delegate.store)
        } label: {
            MenuBarLabelView(store: delegate.store)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar text. Observes the store so the number updates while closed.
struct MenuBarLabelView: View {
    @ObservedObject var store: UsageStore
    var body: some View {
        Text(store.menuBarText)
    }
}
