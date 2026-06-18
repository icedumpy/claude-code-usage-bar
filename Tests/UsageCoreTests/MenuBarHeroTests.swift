import Testing
import Foundation
@testable import UsageCore

private func row(_ kind: String, _ pct: Double, _ sev: Severity) -> LimitRow {
    LimitRow(id: kind, kind: kind, label: kind, percent: pct, severity: sev,
             resetsAt: nil, isActive: true, isHero: kind == "session", elapsedFraction: nil)
}

private func snapshot(_ rows: [LimitRow]) -> UsageSnapshot {
    UsageSnapshot(heroPercent: rows.first?.percent,
                  heroSeverity: rows.first?.severity ?? .normal,
                  heroLabel: nil, heroResetsAt: nil, limitRows: rows, models: [],
                  totalTokens: 0, totalCostUSD: 0, subscriptionType: nil,
                  generatedAt: Date(timeIntervalSince1970: 0))
}

@Test func autoPicksMostSevereOverHigherPercent() {
    let s = snapshot([row("session", 50, .normal),
                      row("weekly_all", 30, .warning),
                      row("weekly_scoped", 90, .normal)])
    // warning beats normal even though weekly_scoped has a higher percent.
    #expect(s.menuBarRow(for: .auto)?.kind == "weekly_all")
}

@Test func autoTieBreaksOnPercent() {
    let s = snapshot([row("session", 50, .normal), row("weekly_all", 80, .normal)])
    #expect(s.menuBarRow(for: .auto)?.kind == "weekly_all")
}

@Test func explicitChoiceSelectsByKind() {
    let s = snapshot([row("session", 50, .normal), row("weekly_all", 30, .warning)])
    #expect(s.menuBarRow(for: .session)?.kind == "session")
    #expect(s.menuBarRow(for: .weeklyAll)?.kind == "weekly_all")
}

@Test func missingKindReturnsNil() {
    let s = snapshot([row("session", 50, .normal)])
    #expect(s.menuBarRow(for: .weeklyScoped) == nil)
}
