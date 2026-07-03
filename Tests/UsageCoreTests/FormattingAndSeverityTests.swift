import Testing
import Foundation
@testable import UsageCore

struct FormattingAndSeverityTests {
    @Test func dollarsGroupsThousands() {
        #expect(Formatting.dollars(1612.4) == "$1,612")
        #expect(Formatting.dollars(999.5) == "$1,000")
        #expect(Formatting.dollars(112.0) == "$112")
        #expect(Formatting.dollars(3.204) == "$3.20")
        #expect(Formatting.dollars(0.845) == "$0.84")
    }

    @Test func compactCountdownBuckets() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func at(_ secs: TimeInterval) -> String {
            Formatting.compactCountdown(to: now.addingTimeInterval(secs), now: now)
        }
        #expect(at(-10) == "0m")
        #expect(at(55 * 60) == "55m")
        #expect(at(2 * 3600 + 58 * 60) == "2h58m")
        #expect(at(3 * 3600) == "3h")
        #expect(at(3 * 24 * 3600 + 2 * 3600) == "3d2h")
        #expect(Formatting.compactCountdown(to: nil, now: now) == "")
    }

    /// One ordering everywhere: unknown loses to every real severity, so a
    /// limit the API couldn't classify never outranks a known-normal one.
    @Test func unknownSeverityAlwaysLoses() {
        let real: [Severity] = [.normal, .warning, .severe, .critical]
        for s in real {
            #expect(Severity.unknown.rank < s.rank)
        }
        #expect(Severity.normal.rank < Severity.warning.rank)
        #expect(Severity.warning.rank < Severity.severe.rank)
        #expect(Severity.severe.rank < Severity.critical.rank)
    }
}
