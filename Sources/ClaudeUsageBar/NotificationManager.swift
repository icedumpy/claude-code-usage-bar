import AppKit
import Foundation
import UserNotifications
import UsageCore

/// Posts local macOS notifications for threshold crossings and relayed
/// Claude Code session events. Failures (e.g. the user declined permission)
/// are silently ignored — alerts are best-effort.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private override init() { super.init() }

    /// UNUserNotificationCenter traps in a non-bundled process (e.g. a bare
    /// `swift run` / `.build/release` binary), so alerts only work in the .app.
    private let available = Bundle.main.bundleIdentifier != nil
    private let activateBundleIDKey = "activateBundleID"

    func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func fire(_ alert: ThresholdAlert) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "\(alert.limitId)#\(alert.threshold)",
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Fires a notification for a Claude Code session event relayed by
    /// `scripts/session-notify.sh`. Unlike a raw `osascript -e 'display
    /// notification'`, this is attributed to ClaudeUsageBar itself, so
    /// clicking it runs our delegate below instead of activating Script
    /// Editor.
    func fireSession(_ notification: SessionNotification) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = notification.repo
        content.subtitle = notification.topic
        content.body = notification.message
        content.sound = .default
        if let bundleID = notification.activateBundleID {
            content.userInfo[activateBundleIDKey] = bundleID
        }
        let request = UNNotificationRequest(
            identifier: "session-\(UUID().uuidString)",
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Show the banner even if the app were somehow frontmost (it never is —
    /// LSUIElement — but macOS suppresses banners for the frontmost app by
    /// default, so this is cheap insurance).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 willPresent notification: UNNotification,
                                 withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Clicking a session notification activates the terminal app that
    /// hosted the session, so you land back where Claude is waiting rather
    /// than on whatever app happened to be frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 didReceive response: UNNotificationResponse,
                                 withCompletionHandler completionHandler: @escaping () -> Void) {
        if let bundleID = response.notification.request.content.userInfo[activateBundleIDKey] as? String,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.open(appURL)
        }
        completionHandler()
    }
}
