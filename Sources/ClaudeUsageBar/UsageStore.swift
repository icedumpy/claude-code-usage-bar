import Foundation
import Combine
import UsageCore

/// Polls the usage API + cost engine on an interval and publishes one phase.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var phase: AppPhase = .loading
    @Published private(set) var lastSnapshot: UsageSnapshot?
    @Published private(set) var lastUpdated: Date?
    @Published var refreshInterval: TimeInterval {
        didSet { schedule() }
    }

    private let client: UsageFetching
    private let credentials: CredentialReading
    private let costEngine = CostEngine()
    private var timer: Timer?
    private var inFlight = false

    init(client: UsageFetching,
         credentials: CredentialReading,
         refreshInterval: TimeInterval = 30) {
        self.client = client
        self.credentials = credentials
        self.refreshInterval = refreshInterval
    }

    /// Convenience production wiring. Reads the credential via `/usr/bin/security`,
    /// which accesses the item without a blocking keychain-ACL dialog (a freshly
    /// signed app is not in the item's trust list, so the Security-framework path
    /// would prompt on every poll).
    static func live(refreshInterval: TimeInterval = 30) -> UsageStore {
        let creds = ShellCredentialProvider()
        return UsageStore(client: UsageClient(credentials: creds),
                          credentials: creds,
                          refreshInterval: refreshInterval)
    }

    func start() {
        refreshNow()
        schedule()
    }

    func refreshNow() {
        Task { await refresh() }
    }

    private func schedule() {
        timer?.invalidate()
        let t = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshNow() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() async {
        if inFlight { return }
        inFlight = true
        defer { inFlight = false }

        do {
            let usage = try await client.fetch()
            let creds = try? credentials.read()
            let since = usage.weeklyWindowStart
                ?? Date().addingTimeInterval(-7 * 24 * 60 * 60)
            // CostEngine is an actor: file IO + caching run off the main actor.
            let breakdown = await costEngine.breakdown(since: since)
            let snapshot = UsageSnapshot.make(usage: usage,
                                              breakdown: breakdown,
                                              credentials: creds)
            lastSnapshot = snapshot
            lastUpdated = Date()
            phase = .ok(snapshot)
        } catch UsageError.unauthorized, CredentialError.notFound {
            phase = .signedOut
        } catch {
            // Keep the last good snapshot visible; flag the transient failure.
            phase = .error(Self.describe(error))
        }
        Self.debugLog(menuBarText)
    }

    /// Appends the current menu bar text to a log file when CLAUDE_USAGE_LOG is
    /// set. Used only for headless verification of the running GUI app.
    private static func debugLog(_ text: String) {
        guard let path = ProcessInfo.processInfo.environment["CLAUDE_USAGE_LOG"] else { return }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(text)\n"
        if let data = line.data(using: .utf8) {
            if let h = FileHandle(forWritingAtPath: path) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    /// The string shown in the menu bar (emoji dot + percent, or a warning).
    var menuBarText: String {
        switch phase {
        case .loading:
            return "…"
        case .ok(let snap):
            if let p = snap.heroPercent {
                return "\(SeverityStyle.dot(snap.heroSeverity)) \(Formatting.percent(p))"
            }
            return "🟢 —"
        case .signedOut:
            return "⚠️"
        case .error:
            // fall back to last known good number if we have one
            if let snap = lastSnapshot, let p = snap.heroPercent {
                return "\(SeverityStyle.dot(snap.heroSeverity)) \(Formatting.percent(p))"
            }
            return "⚠️"
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case UsageError.http(let code): return "Server error (\(code))"
        case UsageError.network: return "Network unavailable"
        case UsageError.decoding: return "Unexpected response"
        default: return "Temporary error"
        }
    }
}
