import Foundation

/// One rate-limit row for the dropdown.
public struct LimitRow: Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let percent: Double
    public let severity: Severity
    public let resetsAt: Date?
    public let isActive: Bool
    public let isHero: Bool
}

/// The merged, UI-ready view of everything. Built by `make` (pure), published
/// by the app's polling store.
public struct UsageSnapshot: Sendable, Equatable {
    public let heroPercent: Double?
    public let heroSeverity: Severity
    public let heroLabel: String?
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
        let rows: [LimitRow] = usage.limits
            .sorted { order($0) < order($1) }
            .map { l in
                LimitRow(
                    // resetsAt keeps the id unique even if the API returns two
                    // limits with the same kind+model (else ForEach misbehaves).
                    id: "\(l.kind)#\(l.modelName ?? "")#\(l.resetsAt?.timeIntervalSince1970 ?? 0)",
                    label: l.displayLabel,
                    percent: l.percent,
                    severity: l.severity,
                    resetsAt: l.resetsAt,
                    isActive: l.isActive,
                    isHero: hero.map { isSameLimit($0, l) } ?? false)
            }

        let totalTokens = breakdown.reduce(0) { $0 + $1.tokens.total }
        let totalCost = breakdown.reduce(0.0) { $0 + $1.costUSD }

        return UsageSnapshot(
            heroPercent: hero?.percent,
            heroSeverity: hero?.severity ?? .normal,
            heroLabel: hero?.displayLabel,
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

/// App lifecycle phase, surfaced to the menu bar.
public enum AppPhase: Sendable, Equatable {
    case loading
    case ok(UsageSnapshot)
    case signedOut          // no/expired token — open Claude Code to re-auth
    case error(String)      // transient network/server error; last snapshot may persist
}
