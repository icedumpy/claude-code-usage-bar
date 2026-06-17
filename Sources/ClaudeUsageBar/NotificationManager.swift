import Foundation
import UserNotifications
import UsageCore

/// Posts local macOS notifications for threshold crossings. Failures (e.g. the
/// user declined permission) are silently ignored — alerts are best-effort.
final class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func fire(_ alert: ThresholdAlert) {
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
