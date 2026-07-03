import Foundation
import UserNotifications
import UsageCore

/// Posts local macOS notifications for threshold crossings. Failures (e.g. the
/// user declined permission) are silently ignored — alerts are best-effort.
final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    /// UNUserNotificationCenter traps in a non-bundled process (e.g. a bare
    /// `swift run` / `.build/release` binary), so alerts only work in the .app.
    private let available = Bundle.main.bundleIdentifier != nil

    func requestAuthorization() {
        guard available else { return }
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
}
