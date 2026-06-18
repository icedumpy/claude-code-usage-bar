import Foundation

/// One rate-limit row for the dropdown.
public struct LimitRow: Identifiable, Sendable, Equatable {
    public let id: String
    /// Raw limit kind: "session", "weekly_all", "weekly_scoped", etc.
    public let kind: String
    public let label: String
    public let percent: Double
    public let severity: Severity
    public let resetsAt: Date?
    public let isActive: Bool
    public let isHero: Bool
    /// Fraction (0...1) of this limit's window that has elapsed — the "time"
    /// racing against `percent`.
    public let elapsedFraction: Double?
}

/// The merged, UI-ready view of everything. Built by `make` (pure), published
/// by the app's polling store.
public struct UsageSnapshot: Sendable, Equatable {
    public let heroPercent: Double?
    public let heroSeverity: Severity
    public let heroLabel: String?
    public let heroResetsAt: Date?
    public let limitRows: [LimitRow]
    public let models: [ModelUsage]
    public let totalTokens: Int
    public let totalCostUSD: Double
    public let subscriptionType: String?
    public let generatedAt: Date

    public static func make(usage: UsageResponse,
                            breakdown: [ModelUsage],
                            credentials: Credentials? = nil,
                            now: Date = Date()) -> UsageSnapshot {
        // The menu bar shows the 5-hour window; weekly limits live in the
        // dropdown. Fall back to the highest limit only if there's no session row.
        let hero = usage.sessionLimit ?? usage.heroLimit

        // Order rows: session first, then weekly-all, then scoped models.
        let order: (Limit) -> Int = { l in
            switch l.kind {
            case "session": return 0
            case "weekly_all": return 1
            case "weekly_scoped": return 2
            default: return 3
            }
        }
        func elapsed(_ l: Limit) -> Double? {
            guard let rs = l.resetsAt else { return nil }
            let windowSecs: Double = (l.kind == "session") ? 5 * 3600 : 7 * 24 * 3600
            return max(0, min(1, 1 - rs.timeIntervalSince(now) / windowSecs))
        }
        let rows: [LimitRow] = usage.limits
            .sorted { order($0) < order($1) }
            .map { l in
                LimitRow(
                    // resetsAt keeps the id unique even if the API returns two
                    // limits with the same kind+model (else ForEach misbehaves).
                    id: "\(l.kind)#\(l.modelName ?? "")#\(l.resetsAt?.timeIntervalSince1970 ?? 0)",
                    kind: l.kind,
                    label: l.displayLabel,
                    percent: l.percent,
                    severity: l.severity,
                    resetsAt: l.resetsAt,
                    isActive: l.isActive,
                    isHero: hero.map { isSameLimit($0, l) } ?? false,
                    elapsedFraction: elapsed(l))
            }

        let totalTokens = breakdown.reduce(0) { $0 + $1.tokens.total }
        let totalCost = breakdown.reduce(0.0) { $0 + $1.costUSD }

        return UsageSnapshot(
            heroPercent: hero?.percent,
            heroSeverity: hero?.severity ?? .normal,
            heroLabel: hero?.displayLabel,
            heroResetsAt: hero?.resetsAt,
            limitRows: rows,
            models: breakdown,
            totalTokens: totalTokens,
            totalCostUSD: totalCost,
            subscriptionType: credentials?.subscriptionType,
            generatedAt: now)
    }

    private static func isSameLimit(_ a: Limit, _ b: Limit) -> Bool {
        a.kind == b.kind && a.modelName == b.modelName && a.percent == b.percent
    }
}

/// Which rate-limit window drives the menu bar's number, color, and countdown.
public enum HeroLimitChoice: String, CaseIterable, Sendable, Identifiable {
    case auto, session, weeklyAll, weeklyScoped

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .auto: return "Auto (most severe)"
        case .session: return "5-hour window"
        case .weeklyAll: return "Weekly (all)"
        case .weeklyScoped: return "Weekly (per-model)"
        }
    }
}

public extension UsageSnapshot {
    /// The limit row that should drive the menu bar for the given choice.
    /// `.auto` picks whichever limit is most severe, then highest percent.
    /// Returns nil if no matching limit exists (caller falls back to hero*).
    func menuBarRow(for choice: HeroLimitChoice) -> LimitRow? {
        // Narrow to a pool of rows, then pick the most severe (then
        // highest-percent). So a kind with several rows — e.g. multiple
        // weekly_scoped model tiers — surfaces its worst one, not an arbitrary
        // first match.
        let pool: [LimitRow]
        switch choice {
        case .auto:         pool = limitRows
        case .session:      pool = limitRows.filter { $0.kind == "session" }
        case .weeklyAll:    pool = limitRows.filter { $0.kind == "weekly_all" }
        case .weeklyScoped: pool = limitRows.filter { $0.kind == "weekly_scoped" }
        }
        return pool.max {
            (Self.severityRank($0.severity), $0.percent)
                < (Self.severityRank($1.severity), $1.percent)
        }
    }

    private static func severityRank(_ s: Severity) -> Int {
        switch s {
        case .unknown: return -1   // unknown always loses to any real severity
        case .normal: return 0
        case .warning: return 1
        case .severe: return 2
        case .critical: return 3
        }
    }
}

/// App lifecycle phase, surfaced to the menu bar.
public enum AppPhase: Sendable, Equatable {
    case loading
    case ok(UsageSnapshot)
    case signedOut          // no/expired token — open Claude Code to re-auth
    case error(String)      // transient network/server error; last snapshot may persist
}
