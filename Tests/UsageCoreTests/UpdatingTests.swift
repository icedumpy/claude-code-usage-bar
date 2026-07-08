import Testing
import Foundation
@testable import UsageCore

// MARK: version compare

@Test func isNewerComparesNumericComponents() {
    #expect(Updating.isNewer("1.10.0", than: "1.9.0"))     // 10 > 9, not string order
    #expect(Updating.isNewer("1.1.0", than: "1.0.9"))
    #expect(!Updating.isNewer("1.0.0", than: "1.0.0"))     // equal is not newer
    #expect(!Updating.isNewer("1.0.0", than: "1.0.1"))
    #expect(Updating.isNewer("2.0", than: "1.9.9"))        // ragged lengths
    #expect(Updating.isNewer("1.0.0", than: "0"))          // vs the unbundled ("0") fallback
}

@Test func isNewerDropsPrereleaseSuffix() {
    // "1.2.0-beta" must read as 1.2.0, not parse "0-beta" as 0.
    #expect(!Updating.isNewer("1.2.0-beta", than: "1.2.0"))
    #expect(Updating.isNewer("1.2.0", than: "1.2.0-beta") == false)  // equal core
    #expect(Updating.isNewer("1.3.0-rc1", than: "1.2.0"))
}

// MARK: install plan

@Test func planFallsBackToManualWhenParentNotWritable() {
    #expect(Updating.plan(parentWritable: true) == .selfUpdate)
    if case .manual = Updating.plan(parentWritable: false) {} else {
        Issue.record("expected manual fallback when parent dir isn't writable")
    }
}

// MARK: downloaded-bundle verification

private let expectedID = "com.pongporamat.claudeusagebar"

private func bundle(id: String? = "com.pongporamat.claudeusagebar",
                    version: String? = "1.2.0",
                    exec: Bool = true,
                    signed: Bool = true) -> Updating.DownloadedBundle {
    Updating.DownloadedBundle(bundleID: id, shortVersion: version,
                              hasExecutable: exec, codesignVerified: signed)
}

@Test func verifyAcceptsANewerWellFormedBundle() {
    #expect(Updating.verifyDownloaded(bundle(version: "1.2.0"),
                                      expectedBundleID: expectedID,
                                      runningVersion: "1.1.0") == .accept)
}

@Test func verifyAcceptsAnEqualVersionReinstall() {
    #expect(Updating.verifyDownloaded(bundle(version: "1.1.0"),
                                      expectedBundleID: expectedID,
                                      runningVersion: "1.1.0") == .accept)
}

@Test func verifyRejectsAStrictDowngrade() {
    if case .reject = Updating.verifyDownloaded(bundle(version: "1.0.0"),
                                                expectedBundleID: expectedID,
                                                runningVersion: "1.1.0") {} else {
        Issue.record("a downgrade must be rejected")
    }
}

@Test func verifyRejectsAWrongBundleID() {
    if case .reject = Updating.verifyDownloaded(bundle(id: "com.evil.app"),
                                                expectedBundleID: expectedID,
                                                runningVersion: "1.1.0") {} else {
        Issue.record("a different app must be rejected")
    }
}

@Test func verifyRejectsMissingExecutableOrSignatureOrVersion() {
    let running = "1.1.0"
    for bad in [bundle(exec: false), bundle(signed: false),
                bundle(version: nil), bundle(version: ""), bundle(id: nil)] {
        if case .accept = Updating.verifyDownloaded(bad, expectedBundleID: expectedID,
                                                    runningVersion: running) {
            Issue.record("expected reject for \(bad)")
        }
    }
}

// MARK: crash recovery

@Test func recoveryRestoresWhenTargetMissingButBackupPresent() {
    #expect(Updating.recovery(targetExists: false, backupExists: true) == .restoreBackup)
}

@Test func recoveryCleansUpAStaleBackup() {
    #expect(Updating.recovery(targetExists: true, backupExists: true) == .cleanupBackup)
}

@Test func recoveryDoesNothingInTheNormalCase() {
    #expect(Updating.recovery(targetExists: true, backupExists: false) == .none)
    #expect(Updating.recovery(targetExists: false, backupExists: false) == .none)
}

// MARK: swap paths

@Test func updatePathsAreSameVolumeSiblingsOfTheTarget() {
    let target = URL(fileURLWithPath: "/Applications/ClaudeUsageBar.app")
    let p = UpdatePaths.make(target: target)
    let parent = "/Applications"
    // Every scratch path shares the target's parent dir, so each rename is an
    // atomic same-volume move rather than a cross-volume copy.
    #expect(p.backup.deletingLastPathComponent().path == parent)
    #expect(p.stageDir.deletingLastPathComponent().path == parent)
    #expect(p.lock.deletingLastPathComponent().path == parent)
    // Hidden so they don't clutter /Applications if something is left behind.
    #expect(p.backup.lastPathComponent == ".ClaudeUsageBar.app.backup")
    #expect(p.stageDir.lastPathComponent == ".ClaudeUsageBar.app.update")
    #expect(p.lock.lastPathComponent == ".ClaudeUsageBar.app.update.lock")
}
