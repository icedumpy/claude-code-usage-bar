import Foundation
import UsageCore

/// Headless verification: fetch live usage + cost and print the snapshot the
/// menu bar would show. Reads the token via `security` to avoid a GUI prompt.
enum Probe {
    static func run() -> Int32 {
        let creds = ShellCredentialProvider()
        let client = UsageClient(credentials: creds)
        let sem = DispatchSemaphore(value: 0)
        var exitCode: Int32 = 0

        Task {
            defer { sem.signal() }
            do {
                let usage = try await client.fetch()
                let since = usage.weeklyWindowStart
                    ?? Date().addingTimeInterval(-7 * 24 * 60 * 60)
                let breakdown = CostEngine().breakdown(since: since)
                let snap = UsageSnapshot.make(usage: usage,
                                              breakdown: breakdown,
                                              credentials: try? creds.read())
                printSnapshot(snap)
            } catch {
                FileHandle.standardError.write(Data("probe failed: \(error)\n".utf8))
                exitCode = 1
            }
        }
        sem.wait()
        return exitCode
    }

    private static func printSnapshot(_ snap: UsageSnapshot) {
        print("=== Claude Usage (live) ===")
        if let p = snap.heroPercent {
            print("MENU BAR: \(SeverityStyle.dot(snap.heroSeverity)) \(Formatting.percent(p))  [\(snap.heroLabel ?? "")]")
        }
        print("")
        for row in snap.limitRows {
            let mark = row.isHero ? " (now)" : ""
            print(String(format: "  %-18@ %4@   %@%@",
                         row.label as NSString,
                         Formatting.percent(row.percent) as NSString,
                         Formatting.reset(to: row.resetsAt) as NSString,
                         mark as NSString))
        }
        if !snap.models.isEmpty {
            print("\n  This week — by model:")
            for m in snap.models {
                print(String(format: "    %-14@ %8@ tok   %@",
                             m.displayName as NSString,
                             Formatting.tokens(m.tokens.total) as NSString,
                             Formatting.dollars(m.costUSD) as NSString))
            }
            print(String(format: "    %-14@ %8@ tok   %@",
                         "Total" as NSString,
                         Formatting.tokens(snap.totalTokens) as NSString,
                         Formatting.dollars(snap.totalCostUSD) as NSString))
        }
        if let sub = snap.subscriptionType { print("\n  Plan: \(sub)") }
    }
}
