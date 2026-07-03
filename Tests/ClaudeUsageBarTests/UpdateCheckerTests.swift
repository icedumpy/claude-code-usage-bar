import Testing
@testable import ClaudeUsageBar

struct UpdateCheckerTests {
    @Test func numericComparison() {
        #expect(UpdateChecker.isNewer("1.10.0", than: "1.9.0"))   // 10 > 9, not string order
        #expect(UpdateChecker.isNewer("1.0.0", than: "0"))        // vs the unbundled fallback
        #expect(!UpdateChecker.isNewer("1.9.0", than: "1.10.0"))
        #expect(!UpdateChecker.isNewer("1.2.0", than: "1.2.0"))   // equal is not newer
        #expect(UpdateChecker.isNewer("1.2.1", than: "1.2.0"))
    }

    /// A prerelease/build suffix must be ignored, not parsed into the numeric
    /// core (where "0-beta" would silently become 0).
    @Test func prereleaseSuffixIsIgnored() {
        #expect(!UpdateChecker.isNewer("1.2.0-beta", than: "1.2.0"))   // same version
        #expect(UpdateChecker.isNewer("1.3.0-rc.1", than: "1.2.0"))    // genuinely newer
        #expect(!UpdateChecker.isNewer("1.2.0+build42", than: "1.2.0"))
    }
}
