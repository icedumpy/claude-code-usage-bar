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
    @Published private(set) var updateInfo: UpdateInfo?
    @Published var refreshInterval: TimeInterval {
        didSet { Defaults.set("refreshInterval", refreshInterval); schedule() }
    }

    @Published var alertsEnabled = Defaults.value("alertsEnabled", true) {
        didSet { Defaults.set("alertsEnabled", alertsEnabled) }
    }
    @Published var showCountdown = Defaults.value("showCountdown", false) {
        didSet { Defaults.set("showCountdown", showCountdown) }
    }
    @Published var warnThreshold = Defaults.value("warnThreshold", 80) {
        didSet { Defaults.set("warnThreshold", warnThreshold) }
    }
    @Published var critThreshold = Defaults.value("critThreshold", 95) {
        didSet { Defaults.set("critThreshold", critThreshold) }
    }
    @Published var vizStyle = Defaults.raw("vizStyle", VisualizationStyle.bars) {
        didSet { Defaults.setRaw("vizStyle", vizStyle) }
    }

    // Pinned PiP panel preferences (see PinnedPanelController/View).
    @Published var isPinned = Defaults.value("isPinned", false) {
        didSet { Defaults.set("isPinned", isPinned) }
    }
    @Published var pinOpacity = PinnedPanelGeometry.clampOpacity(Defaults.value("pinOpacity", 0.95)) {
        didSet { Defaults.set("pinOpacity", pinOpacity) }
    }
    @Published var pinWidth = PinnedPanelGeometry.clampWidth(UsageStore.initialPinWidth()) {
        didSet { Defaults.set("pinWidth", pinWidth) }
    }
    @Published var pinShowWeekly = Defaults.value("pinShowWeekly", true) {
        didSet { Defaults.set("pinShowWeekly", pinShowWeekly) }
    }
    @Published var pinShowModels = Defaults.value("pinShowModels", false) {
        didSet { Defaults.set("pinShowModels", pinShowModels) }
    }

    // Menu bar display preferences.
    @Published var menuBarDisplay = Defaults.raw("menuBarDisplay", MenuBarDisplay.percent) {
        didSet { Defaults.setRaw("menuBarDisplay", menuBarDisplay) }
    }
    @Published var heroChoice = Defaults.raw("heroChoice", HeroLimitChoice.session) {
        didSet { Defaults.setRaw("heroChoice", heroChoice) }
    }

    /// Opt-in: publish a compact snapshot to Scriptable's iCloud folder for an
    /// iPhone widget. Off by default so the app never writes to a user's iCloud
    /// unless they ask — even if Scriptable happens to be installed.
    @Published var syncToWidget = Defaults.value("syncToWidget", false) {
        didSet { Defaults.set("syncToWidget", syncToWidget) }
    }

    private let client: UsageFetching
    private let credentials: CredentialReading
    private let costEngine: CostEngine
    private let syncWriter: ScriptableSyncWriter
    private var timer: Timer?
    private var updateCheckTask: Task<Void, Never>?
    private var inFlight = false
    private var alertState = AlertState()
    private var failureStreak = 0
    private var backoffUntil: Date?

    init(client: UsageFetching,
         credentials: CredentialReading,
         refreshInterval: TimeInterval? = nil,
         costEngine: CostEngine = CostEngine(),
         syncWriter: ScriptableSyncWriter = ScriptableSyncWriter()) {
        self.client = client
        self.credentials = credentials
        self.costEngine = costEngine
        self.syncWriter = syncWriter
        // didSet does not fire during init, so the stored value isn't rewritten.
        self.refreshInterval = refreshInterval
            ?? Defaults.value("refreshInterval", TimeInterval(60))
    }

    /// Initial pinned-panel width. Prefers a saved `pinWidth`; otherwise
    /// migrates a pre-width `pinScale` (the old uniform-zoom factor) once so an
    /// existing user's panel keeps roughly its former size, falling back to the
    /// default width on a clean install.
    private static func initialPinWidth() -> Double {
        let d = UserDefaults.standard
        if d.object(forKey: "pinWidth") != nil { return Defaults.value("pinWidth", PinnedPanelGeometry.defaultWidth) }
        if let scale = d.object(forKey: "pinScale") as? Double { return PinnedPanelGeometry.defaultWidth * scale }
        return PinnedPanelGeometry.defaultWidth
    }

    /// Convenience production wiring. Reads the credential via `/usr/bin/security`,
    /// which accesses the item without a blocking keychain-ACL dialog (a freshly
    /// signed app is not in the item's trust list, so the Security-framework path
    /// would prompt on every poll).
    static func live() -> UsageStore {
        let creds = ShellCredentialProvider()
        return UsageStore(client: UsageClient(credentials: creds),
                          credentials: creds)
    }

    func start() {
        refreshNow()
        schedule()
        // Re-check daily, not just at launch: a menu bar app can stay running
        // for weeks, so a one-shot check would miss every release after startup.
        updateCheckTask?.cancel()
        updateCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                let info = await UpdateChecker.check()
                guard let self, !Task.isCancelled else { return }
                self.updateInfo = info
                try? await Task.sleep(for: .seconds(24 * 60 * 60))
            }
        }
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
        // Let the system coalesce wakeups — exact firing doesn't matter here.
        t.tolerance = refreshInterval * 0.1
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
            // Publish a compact snapshot for the iPhone Scriptable widget, only
            // if the user opted in. Best-effort and off the main actor: heroRow
            // reflects the user's hero choice, and a failed/skipped write never
            // affects the refresh.
            if syncToWidget {
                let syncSnap = SyncSnapshot.from(snapshot: snapshot, heroRow: heroRow)
                let writer = syncWriter
                Task.detached { writer.write(syncSnap) }
            }
            if alertsEnabled {
                let alerts = ThresholdAlerter.evaluate(limits: usage.limits, state: &alertState,
                                                       thresholds: [warnThreshold, critThreshold])
                alerts.forEach { NotificationManager.shared.fire($0) }
            }
        } catch UsageError.unauthorized, CredentialError.notFound, CredentialError.malformed {
            // .malformed means the keychain item exists but is unreadable — like
            // a missing token, that needs the user to sign in again, not retries.
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

    /// Snapshot worth displaying right now (last-known stays visible on error).
    private var displaySnapshot: UsageSnapshot? {
        switch phase {
        case .ok(let s): return s
        case .error: return lastSnapshot
        case .loading, .signedOut: return nil
        }
    }

    /// The menu-bar limit chosen by `heroChoice` (falls back to the snapshot's
    /// session-based hero if that limit isn't present).
    private var heroRow: LimitRow? { displaySnapshot?.menuBarRow(for: heroChoice) }

    /// Id of the row the views should badge as "now" — the same limit the menu
    /// bar is driven by, so the dropdown and pinned panel never disagree with it.
    var heroRowID: String? {
        heroRow?.id ?? displaySnapshot?.limitRows.first(where: { $0.isHero })?.id
    }

    /// Menu bar text (no emoji — the tinted Claude mark carries the color):
    /// percent, dollars, or both, per `menuBarDisplay`. "…" loading, "!" signed
    /// out, "?" an error with no data to fall back on (distinct from "!" so a
    /// user's screenshot tells "sign in" apart from "fetch failed").
    var menuBarText: String {
        switch phase {
        case .loading: return "…"
        case .signedOut: return "!"
        case .ok, .error: break
        }
        guard let snap = displaySnapshot else { return "?" }
        let pct = heroRow?.percent ?? snap.heroPercent
        let pctStr = pct.map { Formatting.percent($0) } ?? "—"
        // totalCostUSD is baked into the snapshot, so over an error it shows the
        // last-known value — same staleness as the rest of the row.
        let dollarStr = Formatting.dollars(snap.totalCostUSD)
        switch menuBarDisplay {
        case .percent: return pctStr
        case .dollars: return dollarStr
        case .both: return "\(pctStr) · \(dollarStr)"
        }
    }

    /// Severity driving the Claude mark's tint.
    var menuBarSeverity: Severity {
        guard let snap = displaySnapshot else { return .unknown }
        return heroRow?.severity ?? snap.heroSeverity
    }

    /// Compact reset countdown shown next to the text when enabled.
    var menuBarCountdown: String {
        guard showCountdown, let snap = displaySnapshot else { return "" }
        let pct = heroRow?.percent ?? snap.heroPercent
        guard pct != nil else { return "" }
        // Falls back to the session window's reset (snap.heroResetsAt) if the
        // chosen limit is absent.
        return Formatting.compactCountdown(to: heroRow?.resetsAt ?? snap.heroResetsAt)
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

/// How the dropdown draws each limit row: the classic stacked capsule bars,
/// or the rabbit-vs-turtle race track. User-selectable in Settings.
enum VisualizationStyle: String, CaseIterable, Identifiable {
    case bars
    case race

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bars: return "Bars"
        case .race: return "Rabbit & turtle"
        }
    }
}

/// What the menu bar shows: the limit percentage, the week's dollar value, or
/// both. Dollars are the notional API-equivalent value, not real spend.
enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case percent
    case dollars
    case both

    var id: String { rawValue }

    var label: String {
        switch self {
        case .percent: return "Percent"
        case .dollars: return "Dollars"
        case .both: return "Both"
        }
    }
}
