import Foundation
import Combine
import UsageCore

/// Polls the usage API + cost engine on an interval and publishes one phase.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var phase: AppPhase = .loading
    @Published private(set) var lastSnapshot: UsageSnapshot?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
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
            // Hop to the main actor explicitly — compiler-verified, no reliance
            // on which thread the timer callback happens to run on.
            Task { @MainActor in self?.refreshNow() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() async {
        if inFlight { return }
        inFlight = true
        isRefreshing = true
        // Always advance the "checked" time so a manual Refresh is visibly
        // responsive even when the fetch fails (e.g. a transient rate limit).
        defer { inFlight = false; isRefreshing = false; lastUpdated = Date() }

        do {
            let usage = try await client.fetch()
            // Best-effort: only used for the subscription badge. A failure here
            // is not the signed-out signal — that comes from fetch() throwing.
            let creds = try? credentials.read()
            let since = usage.weeklyWindowStart
                ?? Date().addingTimeInterval(-7 * 24 * 60 * 60)
            // CostEngine is an actor: file IO + caching run off the main actor.
            let breakdown = await costEngine.breakdown(since: since)
            let snapshot = UsageSnapshot.make(usage: usage,
                                              breakdown: breakdown,
                                              credentials: creds)
            lastSnapshot = snapshot
            phase = .ok(snapshot)
        } catch UsageError.unauthorized, CredentialError.notFound {
            phase = .signedOut
        } catch {
            // Keep the last good snapshot visible; the transient failure is not
            // surfaced as a scary banner — we just keep showing last-known data.
            phase = .error(Self.describe(error))
        }
        Self.debugLog(menuBarText)
    }

    /// Appends the current menu bar text to a log file when CLAUDE_USAGE_LOG is
    /// set. Used only for headless verification of the running GUI app.
    private static let logFormatter = ISO8601DateFormatter()

    private static func debugLog(_ text: String) {
        guard let path = ProcessInfo.processInfo.environment["CLAUDE_USAGE_LOG"] else { return }
        let line = "\(logFormatter.string(from: Date())) \(text)\n"
        if let data = line.data(using: .utf8) {
            if let h = FileHandle(forWritingAtPath: path) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    /// Percent text for the menu bar (no emoji — the tinted Claude mark carries
    /// the color). "…" while loading, "!" when signed out.
    var menuBarPercent: String {
        switch phase {
        case .loading:
            return "…"
        case .ok(let snap):
            return snap.heroPercent.map { Formatting.percent($0) } ?? "—"
        case .signedOut:
            return "!"
        case .error:
            return lastSnapshot?.heroPercent.map { Formatting.percent($0) } ?? "!"
        }
    }

    /// Severity driving the Claude mark's tint.
    var menuBarSeverity: Severity {
        switch phase {
        case .ok(let snap): return snap.heroSeverity
        case .error: return lastSnapshot?.heroSeverity ?? .unknown
        case .loading, .signedOut: return .unknown
        }
    }

    /// The string shown in the menu bar (emoji dot + percent, or a warning).
    /// Retained for the debug log.
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
