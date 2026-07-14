import Foundation

/// A Claude Code session event (needs input, needs permission, ...) relayed
/// from the `session-notify.sh` hook script into the app.
public struct SessionNotification: Sendable, Equatable {
    public let repo: String
    public let topic: String
    public let message: String
    /// Bundle ID of the terminal app hosting the Claude Code session, if the
    /// hook script could detect one — used to bring that app forward when
    /// the notification is clicked, instead of whatever fired the alert.
    public let activateBundleID: String?

    public init(repo: String, topic: String, message: String, activateBundleID: String?) {
        self.repo = repo
        self.topic = topic
        self.message = message
        self.activateBundleID = activateBundleID
    }
}

/// Builds/parses the `claudeusagebar://session-notify` link the hook script
/// hands off to the app via `open`.
public enum SessionNotificationLink {
    public static let scheme = "claudeusagebar"
    public static let host = "session-notify"

    public static func parse(_ url: URL) -> SessionNotification? {
        guard url.scheme == scheme, url.host == host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        var values: [String: String] = [:]
        for item in components.queryItems ?? [] where item.value != nil {
            values[item.name] = item.value
        }
        guard let repo = values["repo"], let message = values["message"] else { return nil }
        return SessionNotification(
            repo: repo,
            topic: values["topic"] ?? message,
            message: message,
            activateBundleID: values["bundleId"])
    }

    /// Round-trip helper (used by tests, and available to callers that want
    /// to build a link rather than shell out).
    public static func url(for notification: SessionNotification) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        var items = [
            URLQueryItem(name: "repo", value: notification.repo),
            URLQueryItem(name: "topic", value: notification.topic),
            URLQueryItem(name: "message", value: notification.message),
        ]
        if let bundleID = notification.activateBundleID {
            items.append(URLQueryItem(name: "bundleId", value: bundleID))
        }
        components.queryItems = items
        return components.url!
    }
}
