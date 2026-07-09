import Foundation

/// The minimal, cross-device payload the Mac app publishes for the iPhone
/// Scriptable widget. Only computed display values — never the OAuth token, and
/// no usage history. Encoded as JSON and written to Scriptable's iCloud Drive
/// folder (see `ScriptableSyncWriter`); the widget reads and renders it.
///
/// `schema` lets the widget refuse an unknown future format instead of drawing
/// garbage. Bump it on any breaking field change.
public struct SyncSnapshot: Codable, Equatable, Sendable {
    public static let currentSchema = 1

    public let schema: Int
    /// Hero limit percent (0...100), or nil when unknown.
    public let heroPercent: Double?
    /// Hero limit label, e.g. "5-hour window". Empty if the snapshot has none.
    public let heroLabel: String
    /// Raw `Severity` value driving the widget tint: normal/warning/severe/
    /// critical/unknown.
    public let severity: String
    /// ISO-8601 reset time; the widget derives the countdown. Nil if unknown.
    public let resetsAt: String?
    /// Notional API-equivalent dollars for the cost window (the same figure the
    /// menu bar shows).
    public let weeklyUSD: Double
    /// ISO-8601 write time; drives the widget's "updated Xm ago" / staleness.
    public let updatedAt: String

    public init(schema: Int = SyncSnapshot.currentSchema,
                heroPercent: Double?,
                heroLabel: String,
                severity: String,
                resetsAt: String?,
                weeklyUSD: Double,
                updatedAt: String) {
        self.schema = schema
        self.heroPercent = heroPercent
        self.heroLabel = heroLabel
        self.severity = severity
        self.resetsAt = resetsAt
        self.weeklyUSD = weeklyUSD
        self.updatedAt = updatedAt
    }

    /// A stable key over the fields the widget actually *displays* (everything
    /// except `updatedAt`), so the Mac can skip re-publishing when the phone
    /// would render an identical card. Cutting that write churn is what lets
    /// iCloud push the file to the phone promptly instead of coalescing a stream
    /// of once-a-minute rewrites. weeklyUSD is bucketed to $10 so tiny cost ticks
    /// don't force a write every refresh; a consequence is that a small visible
    /// change in the widget's $ figure can lag until the next heartbeat (~5 min),
    /// which is an intentional freshness-for-churn tradeoff.
    public var displayKey: String {
        let pct = heroPercent.map { String(Int($0.rounded())) } ?? "-"
        let usd = Int((weeklyUSD / 10).rounded())
        return "\(pct)|\(heroLabel)|\(severity)|\(resetsAt ?? "")|\(usd)"
    }

    /// Build from the app's display snapshot. `heroRow` is the row that actually
    /// drives the menu bar (so the widget honors the user's hero choice); when
    /// nil, falls back to the snapshot's default hero fields.
    public static func from(snapshot: UsageSnapshot,
                            heroRow: LimitRow?,
                            now: Date = Date()) -> SyncSnapshot {
        let iso = ISO8601DateFormatter()
        let percent = heroRow?.percent ?? snapshot.heroPercent
        let label = heroRow?.label ?? snapshot.heroLabel ?? ""
        let severity = heroRow?.severity ?? snapshot.heroSeverity
        let resets = heroRow?.resetsAt ?? snapshot.heroResetsAt
        return SyncSnapshot(
            heroPercent: percent,
            heroLabel: label,
            severity: severity.rawValue,
            resetsAt: resets.map { iso.string(from: $0) },
            weeklyUSD: snapshot.totalCostUSD,
            updatedAt: iso.string(from: now))
    }
}
