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

    @Published var alertsEnabled: Bool = (UserDefaults.standard.object(forKey: "alertsEnabled") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(alertsEnabled, forKey: "alertsEnabled") }
    }

    private let client: UsageFetching
    private let credentials: CredentialReading
    private let costEngine = CostEngine()
    private var timer: Timer?
    private var inFlight = false
    private var alertState = AlertState()
    private var failureStreak = 0
    private var backoffUntil: Date?

    init(client: UsageFetching,
         credentials: CredentialReading,
         refreshInterval: TimeInterval = 60) {
        self.client = client
        self.credentials = credentials
        self.refreshInterval = refreshInterval
    }

    /// Convenience production wiring. Reads the credential via `/usr/bin/security`,
    /// which accesses the item without a blocking keychain-ACL dialog (a freshly
    /// signed app is not in the item's trust list, so the Security-framework path
    /// would prompt on every poll).
    static func live(refreshInterval: TimeInterval = 60) -> UsageStore {
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
        // Manual refresh bypasses backoff.
        Task { await refresh(force: true) }
    }

    private func schedule() {
        timer?.invalidate()
        let t = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh(force: Bool = false) async {
        if inFlight { return }
        // Respect backoff after rate-limit/transient failures, unless the user
        // explicitly hit Refresh.
        if !force, let until = backoffUntil, Date() < until { return }
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
            failureStreak = 0
            backoffUntil = nil
            if alertsEnabled {
                let alerts = ThresholdAlerter.evaluate(limits: usage.limits, state: &alertState)
                alerts.forEach { NotificationManager.shared.fire($0) }
            }
        } catch UsageError.unauthorized, CredentialError.notFound {
            phase = .signedOut
            failureStreak = 0
            backoffUntil = nil
        } catch {
            // Keep last-known data visible; back off (exponential, capped at
            // 15 min) so repeated rate limits don't hammer the endpoint.
            phase = .error(Self.describe(error))
            failureStreak += 1
            backoffUntil = Date().addingTimeInterval(
                min(refreshInterval * pow(2, Double(failureStreak)), 900))
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

    private static func describe(_ error: Error) -> String {
        switch error {
        case UsageError.http(let code): return "Server error (\(code))"
        case UsageError.network: return "Network unavailable"
        case UsageError.decoding: return "Unexpected response"
        default: return "Temporary error"
        }
    }
}
