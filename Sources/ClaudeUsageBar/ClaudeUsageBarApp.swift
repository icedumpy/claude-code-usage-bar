import SwiftUI

struct ClaudeUsageBarApp: App {
    @StateObject private var store = UsageStore.live()

    var body: some Scene {
        MenuBarExtra {
            DropdownView(store: store)
        } label: {
            // Emoji dot keeps its color in the menu bar; `.task` starts polling
            // at launch so the number updates even while the dropdown is closed.
            Text(store.menuBarText)
                .task { store.start() }
        }
        .menuBarExtraStyle(.window)
    }
}
