import Testing
import Foundation
@testable import UsageCore

@Suite struct SessionNotificationTests {
    @Test func roundTripsThroughURL() {
        let original = SessionNotification(
            repo: "claude-code-usage-bar",
            topic: "Fix the login bug",
            message: "Claude is waiting for your input",
            activateBundleID: "com.apple.Terminal")

        let url = SessionNotificationLink.url(for: original)
        let parsed = SessionNotificationLink.parse(url)

        #expect(parsed == original)
    }

    @Test func parsesWithoutBundleID() {
        let url = URL(string: "claudeusagebar://session-notify?repo=my-repo&message=hello")!
        let parsed = SessionNotificationLink.parse(url)

        #expect(parsed?.repo == "my-repo")
        #expect(parsed?.message == "hello")
        #expect(parsed?.topic == "hello")   // falls back to message when topic is absent
        #expect(parsed?.activateBundleID == nil)
    }

    @Test func decodesPercentEncodedValues() {
        let url = URL(string: "claudeusagebar://session-notify?repo=my%20repo&topic=fix%20%26%20ship&message=needs%20input")!
        let parsed = SessionNotificationLink.parse(url)

        #expect(parsed?.repo == "my repo")
        #expect(parsed?.topic == "fix & ship")
        #expect(parsed?.message == "needs input")
    }

    @Test func rejectsUnrelatedURLs() {
        #expect(SessionNotificationLink.parse(URL(string: "https://example.com")!) == nil)
        #expect(SessionNotificationLink.parse(URL(string: "claudeusagebar://other-host?repo=x&message=y")!) == nil)
        #expect(SessionNotificationLink.parse(URL(string: "claudeusagebar://session-notify?topic=only-topic")!) == nil)
    }
}
