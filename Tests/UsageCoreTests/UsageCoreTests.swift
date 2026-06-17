import Testing
import Foundation
@testable import UsageCore

// The real /api/oauth/usage response captured during the spike.
private let usageFixture = """
{"five_hour":{"utilization":5.0,"resets_at":"2026-06-17T07:40:00.211046+00:00"},
 "seven_day":{"utilization":14.0,"resets_at":"2026-06-21T08:00:00.211077+00:00"},
 "seven_day_oauth_apps":null,"seven_day_opus":null,
 "seven_day_sonnet":{"utilization":17.0,"resets_at":"2026-06-21T08:00:00.211090+00:00"},
 "extra_usage":{"is_enabled":false},
 "limits":[
   {"kind":"session","group":"session","percent":5,"severity":"normal","resets_at":"2026-06-17T07:40:00.211046+00:00","scope":null,"is_active":false},
   {"kind":"weekly_all","group":"weekly","percent":14,"severity":"normal","resets_at":"2026-06-21T08:00:00.211077+00:00","scope":null,"is_active":false},
   {"kind":"weekly_scoped","group":"weekly","percent":17,"severity":"warning","resets_at":"2026-06-21T08:00:00.211090+00:00","scope":{"model":{"id":null,"display_name":"Sonnet"},"surface":null},"is_active":true}
 ],
 "spend":{"used":{"amount_minor":0,"currency":"USD","exponent":2},"percent":0,"enabled":false}}
"""

private func decodeFixture() throws -> UsageResponse {
    try UsageResponse.decoder().decode(UsageResponse.self, from: Data(usageFixture.utf8))
}

@Suite struct UsageDecodingTests {
    @Test func decodesLimitsAndWindows() throws {
        let u = try decodeFixture()
        #expect(u.limits.count == 3)
        #expect(u.fiveHour?.utilization == 5.0)
        #expect(u.sevenDaySonnet?.utilization == 17.0)
        #expect(u.sevenDayOpus == nil)
        #expect(u.fiveHour?.resetsAt != nil)
    }

    @Test func heroIsHighestPercent() throws {
        let hero = try #require(try decodeFixture().heroLimit)
        #expect(hero.percent == 17)
        #expect(hero.modelName == "Sonnet")
        #expect(hero.severity == .warning)
        #expect(hero.displayLabel == "Weekly · Sonnet")
    }

    @Test func weeklyWindowStartIsResetMinusSevenDays() throws {
        let u = try decodeFixture()
        let start = try #require(u.weeklyWindowStart)
        let reset = try #require(u.sevenDay?.resetsAt)
        #expect(abs(reset.timeIntervalSince(start) - 7 * 24 * 60 * 60) < 1)
    }

    @Test func severityUnknownFallback() throws {
        let json = #"{"limits":[{"kind":"session","group":"session","percent":3,"severity":"bananas","is_active":true}]}"#
        let u = try UsageResponse.decoder().decode(UsageResponse.self, from: Data(json.utf8))
        #expect(u.limits.first?.severity == .unknown)
    }
}

@Suite struct CostEngineTests {
    let weekStart = ISO8601DateParser.parse("2026-06-14T00:00:00Z")!
    let now = ISO8601DateParser.parse("2026-06-17T12:00:00Z")!

    func line(uuid: String, ts: String, model: String, inp: Int, out: Int, cw: Int = 0, cr: Int = 0) -> String {
        """
        {"uuid":"\(uuid)","timestamp":"\(ts)","type":"assistant","message":{"model":"\(model)","usage":{"input_tokens":\(inp),"output_tokens":\(out),"cache_creation_input_tokens":\(cw),"cache_read_input_tokens":\(cr)}}}
        """
    }

    @Test func aggregatesByModelWithinWindow() {
        let lines = [
            line(uuid: "a", ts: "2026-06-15T10:00:00Z", model: "claude-opus-4-8", inp: 100, out: 50),
            line(uuid: "b", ts: "2026-06-16T10:00:00Z", model: "claude-opus-4-8", inp: 100, out: 50),
            line(uuid: "c", ts: "2026-06-16T11:00:00Z", model: "claude-sonnet-4-6", inp: 200, out: 10),
        ]
        let t = CostEngine.aggregate(lines: lines, since: weekStart, now: now)
        #expect(t["claude-opus-4-8"]?.input == 200)
        #expect(t["claude-opus-4-8"]?.output == 100)
        #expect(t["claude-sonnet-4-6"]?.input == 200)
    }

    @Test func excludesOutsideWindowAndFuture() {
        let lines = [
            line(uuid: "old", ts: "2026-06-01T10:00:00Z", model: "claude-opus-4-8", inp: 999, out: 999),
            line(uuid: "future", ts: "2026-06-20T10:00:00Z", model: "claude-opus-4-8", inp: 999, out: 999),
            line(uuid: "ok", ts: "2026-06-15T10:00:00Z", model: "claude-opus-4-8", inp: 10, out: 5),
        ]
        let t = CostEngine.aggregate(lines: lines, since: weekStart, now: now)
        #expect(t["claude-opus-4-8"]?.input == 10)
    }

    @Test func dedupesByUUID() {
        let l = line(uuid: "dup", ts: "2026-06-15T10:00:00Z", model: "claude-opus-4-8", inp: 100, out: 50)
        let t = CostEngine.aggregate(lines: [l, l, l], since: weekStart, now: now)
        #expect(t["claude-opus-4-8"]?.input == 100)
    }

    @Test func skipsSyntheticAndMalformed() {
        let lines = [
            line(uuid: "s", ts: "2026-06-15T10:00:00Z", model: "<synthetic>", inp: 100, out: 50),
            "this is not json",
            "{}",
            line(uuid: "ok", ts: "2026-06-15T10:00:00Z", model: "claude-opus-4-8", inp: 7, out: 3),
        ]
        let t = CostEngine.aggregate(lines: lines, since: weekStart, now: now)
        #expect(t["<synthetic>"] == nil)
        #expect(t.count == 1)
        #expect(t["claude-opus-4-8"]?.output == 3)
    }

    @Test func makeRowsSkipsUnpricedAndSortsByCost() {
        let tallies: [String: TokenCounts] = [
            "claude-opus-4-8": TokenCounts(input: 1_000_000, output: 0),
            "claude-sonnet-4-6": TokenCounts(input: 1_000_000, output: 0),
            "mystery-model": TokenCounts(input: 1_000_000, output: 0),
        ]
        let rows = CostEngine.makeRows(from: tallies)
        #expect(rows.count == 2)
        #expect(rows.first?.modelID == "claude-opus-4-8")
        #expect(abs((rows.first?.costUSD ?? 0) - 15) < 0.001)
    }
}

@Suite struct PriceTableTests {
    @Test func opusCost() throws {
        let price = try #require(PriceTable.price(forModelID: "claude-opus-4-8"))
        let c = PriceTable.cost(price: price, tokens: TokenCounts(input: 1_000_000, output: 1_000_000))
        #expect(abs(c - 90) < 0.001)
    }

    @Test func displayNames() {
        #expect(PriceTable.displayName(forModelID: "claude-opus-4-8") == "Opus 4.8")
        #expect(PriceTable.displayName(forModelID: "claude-sonnet-4-6") == "Sonnet 4.6")
        // Trailing date group is ignored.
        #expect(PriceTable.displayName(forModelID: "claude-haiku-4-5-20251001") == "Haiku 4.5")
        #expect(PriceTable.displayName(forModelID: "claude-opus-4-5-20251001") == "Opus 4.5")
    }

    @Test func unknownModelHasNoPrice() {
        #expect(PriceTable.price(forModelID: "gpt-4o") == nil)
    }
}

@Suite struct FormattingTests {
    @Test func tokens() {
        #expect(Formatting.tokens(420) == "420")
        #expect(Formatting.tokens(12_300) == "12.3K")
        #expect(Formatting.tokens(1_200_000) == "1.2M")
        #expect(Formatting.tokens(2_000_000) == "2M")
    }

    @Test func dollars() {
        #expect(Formatting.dollars(3.2) == "$3.20")
        #expect(Formatting.dollars(120) == "$120")
    }

    @Test func reset() {
        let now = ISO8601DateParser.parse("2026-06-17T12:00:00Z")!
        #expect(Formatting.reset(to: now.addingTimeInterval(160 * 60), now: now) == "resets in 2h 40m")
        #expect(Formatting.reset(to: now.addingTimeInterval(3 * 86400), now: now) == "resets in 3d")
        #expect(Formatting.reset(to: now.addingTimeInterval(30), now: now) == "resets soon")
        #expect(Formatting.reset(to: nil, now: now) == "")
    }
}

@Suite struct CredentialTests {
    @Test func parsesNestedShape() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"tok123","refreshToken":"ref456","subscriptionType":"max","rateLimitTier":"tier_x"}}"#
        let c = try Credentials.parse(Data(json.utf8))
        #expect(c.accessToken == "tok123")
        #expect(c.refreshToken == "ref456")
        #expect(c.subscriptionType == "max")
    }

    @Test func malformedThrows() {
        #expect(throws: (any Error).self) {
            try Credentials.parse(Data("{}".utf8))
        }
    }
}

@Suite struct SnapshotTests {
    @Test func makeBuildsHeroAndTotals() throws {
        let fixture = """
        {"limits":[
          {"kind":"session","group":"session","percent":5,"severity":"normal","resets_at":"2026-06-17T07:40:00Z","scope":null,"is_active":false},
          {"kind":"weekly_scoped","group":"weekly","percent":40,"severity":"warning","resets_at":"2026-06-21T08:00:00Z","scope":{"model":{"display_name":"Opus"}},"is_active":true}
        ],"seven_day":{"utilization":40,"resets_at":"2026-06-21T08:00:00Z"}}
        """
        let u = try UsageResponse.decoder().decode(UsageResponse.self, from: Data(fixture.utf8))
        let breakdown = CostEngine.makeRows(from: ["claude-opus-4-8": TokenCounts(input: 1_000_000, output: 0)])
        let snap = UsageSnapshot.make(usage: u, breakdown: breakdown)

        // Menu bar shows the 5-hour (session) limit, not the higher weekly one.
        #expect(snap.heroPercent == 5)
        #expect(snap.heroSeverity == .normal)
        #expect(snap.heroLabel == "5-hour window")
        #expect(snap.limitRows.count == 2)
        #expect(snap.limitRows.first { $0.isHero }?.label == "5-hour window")
        #expect(abs(snap.totalCostUSD - 15) < 0.001)
        #expect(snap.totalTokens == 1_000_000)
    }
}

@Suite struct ThresholdAlerterTests {
    func sessionLimits(_ pct: Int) throws -> [Limit] {
        let json = #"{"limits":[{"kind":"session","group":"session","percent":\#(pct),"severity":"normal","is_active":true}]}"#
        return try UsageResponse.decoder().decode(UsageResponse.self, from: Data(json.utf8)).limits
    }

    @Test func firesOnceWhenCrossing80() throws {
        var state = AlertState()
        #expect(ThresholdAlerter.evaluate(limits: try sessionLimits(79), state: &state).isEmpty)
        let a = ThresholdAlerter.evaluate(limits: try sessionLimits(82), state: &state)
        #expect(a.count == 1)
        #expect(a.first?.threshold == 80)
        // does not re-fire while still in the same band
        #expect(ThresholdAlerter.evaluate(limits: try sessionLimits(85), state: &state).isEmpty)
    }

    @Test func escalatesTo95() throws {
        var state = AlertState()
        _ = ThresholdAlerter.evaluate(limits: try sessionLimits(82), state: &state)
        let a = ThresholdAlerter.evaluate(limits: try sessionLimits(96), state: &state)
        #expect(a.first?.threshold == 95)
    }

    @Test func resetsAfterDropBelow() throws {
        var state = AlertState()
        _ = ThresholdAlerter.evaluate(limits: try sessionLimits(96), state: &state)
        // window reset drops it below all thresholds
        #expect(ThresholdAlerter.evaluate(limits: try sessionLimits(5), state: &state).isEmpty)
        // and it can alert again afterwards
        let a = ThresholdAlerter.evaluate(limits: try sessionLimits(82), state: &state)
        #expect(a.first?.threshold == 80)
    }
}
