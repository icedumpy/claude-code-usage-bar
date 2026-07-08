import Testing
import Foundation
@testable import UsageCore

/// Covers the iPhone-widget sync payload: the display-snapshot mapping and the
/// best-effort file writer.
struct SyncSnapshotTests {
    let now = ISO8601DateParser.parse("2026-06-16T10:00:00Z")!
    let reset = ISO8601DateParser.parse("2026-06-16T12:00:00Z")!

    private func snapshot(heroPercent: Double? = 42) -> UsageSnapshot {
        UsageSnapshot(
            heroPercent: heroPercent, heroSeverity: .normal,
            heroLabel: "5-hour window", heroResetsAt: reset,
            limitRows: [], models: [], totalTokens: 0,
            totalCostUSD: 1612.4, subscriptionType: "max", generatedAt: now)
    }

    @Test func mapsSnapshotDefaultHeroWhenRowNil() {
        let s = SyncSnapshot.from(snapshot: snapshot(), heroRow: nil, now: now)
        #expect(s.schema == SyncSnapshot.currentSchema)
        #expect(s.heroPercent == 42)
        #expect(s.heroLabel == "5-hour window")
        #expect(s.severity == "normal")
        #expect(s.weeklyUSD == 1612.4)
        #expect(s.resetsAt == "2026-06-16T12:00:00Z")
        #expect(s.updatedAt == "2026-06-16T10:00:00Z")
    }

    @Test func heroRowOverridesSnapshotDefaults() {
        // The widget must honor the user's hero choice, not just the session
        // default baked into the snapshot.
        let row = LimitRow(id: "weekly_all#", kind: "weekly_all", label: "Weekly (all)",
                           percent: 88, severity: .severe, resetsAt: reset,
                           isActive: true, isHero: true, elapsedFraction: 0.5)
        let s = SyncSnapshot.from(snapshot: snapshot(), heroRow: row, now: now)
        #expect(s.heroPercent == 88)
        #expect(s.heroLabel == "Weekly (all)")
        #expect(s.severity == "severe")
    }

    @Test func encodeRoundTrips() throws {
        let s = SyncSnapshot.from(snapshot: snapshot(), heroRow: nil, now: now)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(SyncSnapshot.self, from: data)
        #expect(back == s)
    }

    @Test func writerWritesAndRoundTrips() throws {
        let dir = try makeTempDir("sync-write")
        let writer = ScriptableSyncWriter(directory: dir)
        let s = SyncSnapshot.from(snapshot: snapshot(), heroRow: nil, now: now)

        #expect(writer.write(s) == true)
        let file = dir.appendingPathComponent(ScriptableSyncWriter.fileName)
        let back = try JSONDecoder().decode(SyncSnapshot.self, from: Data(contentsOf: file))
        #expect(back == s)
    }

    @Test func writerSkipsWhenFolderAbsent() {
        // Scriptable not installed / not yet synced: no folder, silent skip, and
        // we must not create the folder (a fake dir wouldn't sync anyway).
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sync-absent-\(UUID().uuidString)", isDirectory: true)
        let writer = ScriptableSyncWriter(directory: dir)
        #expect(writer.write(SyncSnapshot.from(snapshot: snapshot(), heroRow: nil, now: now)) == false)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func writerOverwritesExisting() throws {
        let dir = try makeTempDir("sync-over")
        let writer = ScriptableSyncWriter(directory: dir)
        writer.write(SyncSnapshot.from(snapshot: snapshot(heroPercent: 10), heroRow: nil, now: now))
        writer.write(SyncSnapshot.from(snapshot: snapshot(heroPercent: 90), heroRow: nil, now: now))
        let file = dir.appendingPathComponent(ScriptableSyncWriter.fileName)
        let back = try JSONDecoder().decode(SyncSnapshot.self, from: Data(contentsOf: file))
        #expect(back.heroPercent == 90)
    }

    private func makeTempDir(_ tag: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(tag)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
