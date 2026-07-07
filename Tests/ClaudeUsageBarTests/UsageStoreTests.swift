import Testing
import Foundation
import UsageCore
@testable import ClaudeUsageBar

// Minimal /api/oauth/usage response: a session limit (the default hero) plus a
// weekly one. Percents stay below the default 80/95 alert thresholds so refresh
// never reaches the notification path inside the test runner.
private let usageJSON = """
{"limits":[
  {"kind":"session","group":"session","percent":42,"severity":"normal","resets_at":"2026-06-17T07:40:00+00:00","scope":null,"is_active":true},
  {"kind":"weekly_all","group":"weekly","percent":50,"severity":"normal","resets_at":"2026-06-21T08:00:00+00:00","scope":null,"is_active":false}
]}
"""

private func fixtureResponse() throws -> UsageResponse {
    try UsageResponse.decoder().decode(UsageResponse.self, from: Data(usageJSON.utf8))
}

/// Scriptable UsageFetching double. `result` is swapped mid-test to drive the
/// store through success/failure transitions; `fetchCount` observes backoff.
private final class MockClient: UsageFetching, @unchecked Sendable {
    var result: Result<UsageResponse, Error>
    private(set) var fetchCount = 0

    init(_ result: Result<UsageResponse, Error>) { self.result = result }

    func fetch() async throws -> UsageResponse {
        fetchCount += 1
        return try result.get()
    }
}

private struct MockCredentials: CredentialReading {
    func read() throws -> Credentials {
        Credentials(accessToken: "test-token", subscriptionType: "max")
    }
}

/// Store wired to mocks, with the cost engine pointed at an empty temp dir so
/// refresh never scans the machine's real transcripts.
@MainActor
private func makeStore(client: MockClient) -> UsageStore {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("usage-store-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let store = UsageStore(client: client,
                           credentials: MockCredentials(),
                           refreshInterval: 60,
                           costEngine: CostEngine(projectsDir: tmp))
    store.alertsEnabled = false
    return store
}

struct UsageStoreTests {
    @Test @MainActor func successPublishesSnapshotAndPercent() async throws {
        let store = makeStore(client: MockClient(.success(try fixtureResponse())))
        await store.refresh(force: true)

        guard case .ok(let snap) = store.phase else {
            Issue.record("expected .ok, got \(store.phase)")
            return
        }
        #expect(snap.limitRows.count == 2)
        store.menuBarDisplay = .percent
        store.heroChoice = .session
        #expect(store.menuBarText == "42%")
    }

    @Test @MainActor func heroRowFollowsHeroChoice() async throws {
        let store = makeStore(client: MockClient(.success(try fixtureResponse())))
        await store.refresh(force: true)
        store.menuBarDisplay = .percent

        store.heroChoice = .weeklyAll
        #expect(store.menuBarText == "50%")
        #expect(store.heroRowID?.hasPrefix("weekly_all#") == true)

        store.heroChoice = .session
        #expect(store.menuBarText == "42%")
        #expect(store.heroRowID?.hasPrefix("session#") == true)
    }

    @Test @MainActor func unauthorizedBecomesSignedOut() async {
        let store = makeStore(client: MockClient(.failure(UsageError.unauthorized)))
        await store.refresh(force: true)
        #expect(store.phase == .signedOut)
        #expect(store.menuBarText == "!")
    }

    @Test @MainActor func malformedCredentialBecomesSignedOutNotError() async {
        // A corrupt keychain blob needs the user to sign in again — it must not
        // land in the transient-error branch and retry forever.
        let store = makeStore(client: MockClient(.failure(CredentialError.malformed)))
        await store.refresh(force: true)
        #expect(store.phase == .signedOut)
    }

    @Test @MainActor func transientErrorKeepsLastSnapshotAndBacksOff() async throws {
        let client = MockClient(.success(try fixtureResponse()))
        let store = makeStore(client: client)
        await store.refresh(force: true)
        #expect(store.lastSnapshot != nil)

        client.result = .failure(UsageError.http(500))
        await store.refresh(force: true)
        #expect(store.phase == .error("Server error (500)"))
        #expect(store.lastSnapshot != nil)          // last-known stays visible
        store.menuBarDisplay = .percent
        #expect(store.menuBarText == "42%")         // ...including in the menu bar

        // Backoff: a scheduled (non-forced) refresh right after a failure is a
        // no-op, while a manual refresh still goes through.
        let before = client.fetchCount
        await store.refresh(force: false)
        #expect(client.fetchCount == before)
        await store.refresh(force: true)
        #expect(client.fetchCount == before + 1)
    }

    @Test @MainActor func errorWithNoDataShowsDistinctGlyph() async {
        // First-ever fetch fails: no lastSnapshot to fall back on. The menu bar
        // shows "?" (fetch failed), which must stay distinct from "!" (signed out).
        let store = makeStore(client: MockClient(.failure(UsageError.http(500))))
        await store.refresh(force: true)
        #expect(store.phase == .error("Server error (500)"))
        #expect(store.menuBarText == "?")
    }

    @Test @MainActor func refreshIntervalPersistsAcrossStores() async throws {
        defer { UserDefaults.standard.removeObject(forKey: "refreshInterval") }
        let first = makeStore(client: MockClient(.failure(UsageError.network)))
        first.refreshInterval = 300

        // A store created without an explicit interval picks up the saved one.
        let second = UsageStore(client: MockClient(.failure(UsageError.network)),
                                credentials: MockCredentials())
        #expect(second.refreshInterval == 300)
    }

    @Test @MainActor func widgetSyncWritesFileOnlyWhenOptedIn() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-gate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(ScriptableSyncWriter.fileName)

        func store(sync: Bool) throws -> UsageStore {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("cost-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            let s = UsageStore(client: MockClient(.success(try fixtureResponse())),
                               credentials: MockCredentials(),
                               refreshInterval: 60,
                               costEngine: CostEngine(projectsDir: tmp),
                               syncWriter: ScriptableSyncWriter(directory: dir))
            s.alertsEnabled = false
            s.syncToWidget = sync
            return s
        }

        // Opted out: a successful refresh writes nothing.
        let optedOut = try store(sync: false)
        await optedOut.refresh(force: true)
        try? await Task.sleep(for: .milliseconds(150))
        #expect(!FileManager.default.fileExists(atPath: file.path))

        // Opted in: the widget file appears. The write is off-main
        // (Task.detached), so poll briefly for it.
        let optedIn = try store(sync: true)
        await optedIn.refresh(force: true)
        var wrote = false
        for _ in 0..<50 where !wrote {
            if FileManager.default.fileExists(atPath: file.path) { wrote = true; break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(wrote)
    }
}
