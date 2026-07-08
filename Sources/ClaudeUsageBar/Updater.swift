import AppKit
import Foundation
import UsageCore

/// Drives the one-click "Update & Relaunch" flow: download the latest release
/// zip, verify it, and hand off to a detached shell helper that swaps the
/// running bundle in place and relaunches. The bricking-risk decisions live in
/// `UsageCore.Updating` (pure, unit-tested); this type only performs the side
/// effects — download, `ditto`, `codesign --verify`, spawn helper — and reports
/// state to the banner.
///
/// Safety model (all per Codex review):
/// - Stage + swap happen on the *same volume* as the target so each move is an
///   atomic rename, never a cross-volume copy.
/// - An O_EXCL lock file guards the swap; the button is disabled while working.
/// - The old bundle is parked at a backup path and only deleted once the new one
///   is in place; the helper restores it on any failure.
/// - A status file is written for the *next* launch to read, since the app is
///   dead during the swap and can't report failures itself.
@MainActor
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle
        case working(String)     // shown on the button while busy
        case failed(String)      // surfaced in the banner; keeps the manual link
    }

    @Published private(set) var state: State = .idle

    var isBusy: Bool { if case .working = state { return true }; return false }

    private let bundleID = "com.pongporamat.claudeusagebar"
    private let assetURL = URL(string:
        "https://github.com/icedumpy/claude-code-usage-bar/releases/latest/download/ClaudeUsageBar.zip")!

    // MARK: launch-time reconciliation

    /// Reconcile leftovers from a prior update: restore a bundle that was moved
    /// aside but not replaced (interrupted swap), clean a stale backup, remove a
    /// stale lock / staging dir, and surface any failure the helper recorded.
    /// Safe to call unconditionally at launch — no-ops when there's nothing to do.
    func reconcileAtLaunch() {
        guard let target = runningBundleURL() else { return }
        let paths = UpdatePaths.make(target: target)
        let fm = FileManager.default

        switch Updating.recovery(targetExists: fm.fileExists(atPath: paths.target.path),
                                 backupExists: fm.fileExists(atPath: paths.backup.path)) {
        case .restoreBackup:
            try? fm.moveItem(at: paths.backup, to: paths.target)
        case .cleanupBackup:
            try? fm.removeItem(at: paths.backup)
        case .none:
            break
        }
        // A fresh launch means no swap is mid-flight, so any lock / staging dir
        // is stale.
        try? fm.removeItem(at: paths.lock)
        try? fm.removeItem(at: paths.stageDir)

        surfaceLastStatus()
    }

    private func surfaceLastStatus() {
        let url = statusFileURL()
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        if obj["ok"] as? Bool == false {
            let msg = (obj["message"] as? String) ?? "Update failed."
            state = .failed("Update failed: \(msg)")
        }
    }

    // MARK: the update flow

    /// Kick off the update. `releasePage` is the fallback the banner already
    /// used — opened whenever we can't (or shouldn't) self-update.
    func updateAndRelaunch(releasePage: URL) {
        guard !isBusy else { return }

        guard let target = runningBundleURL(), target.pathExtension == "app" else {
            // Running unpackaged (e.g. `swift run`) — nothing to swap.
            openReleasePage(releasePage, note: "Open the release page to update.")
            return
        }
        let parent = target.deletingLastPathComponent()
        if case .manual(let reason) = Updating.plan(
            parentWritable: FileManager.default.isWritableFile(atPath: parent.path)) {
            openReleasePage(releasePage, note: reason)
            return
        }

        let paths = UpdatePaths.make(target: target)
        guard acquireLock(paths.lock) else {
            state = .failed("An update is already in progress.")
            return
        }

        state = .working("Downloading…")
        Task {
            do {
                try await runUpdate(paths: paths, running: currentVersion())
                // On success runUpdate spawns the helper and terminates the app;
                // control does not return here.
            } catch {
                releaseLock(paths.lock)
                try? FileManager.default.removeItem(at: paths.stageDir)
                state = .failed("Update failed: \(error.localizedDescription). "
                                + "You can still update from the release page.")
            }
        }
    }

    private func runUpdate(paths: UpdatePaths, running: String) async throws {
        let fm = FileManager.default
        try? fm.removeItem(at: paths.stageDir)
        try fm.createDirectory(at: paths.stageDir, withIntermediateDirectories: true)

        // Download the zip (URLSession downloads carry no quarantine flag).
        let (tmp, resp) = try await URLSession.shared.download(from: assetURL)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdaterError("download failed (HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1))")
        }
        let zip = paths.stageDir.appendingPathComponent("release.zip")
        try? fm.removeItem(at: zip)
        try fm.moveItem(at: tmp, to: zip)

        // Unpack on the target's volume so the final rename is atomic.
        await MainActor.run { self.state = .working("Verifying…") }
        let extracted = paths.stageDir.appendingPathComponent("extracted")
        try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, extracted.path])

        guard let newApp = topLevelApp(in: extracted) else {
            throw UpdaterError("no app bundle in the download")
        }
        let facts = bundleFacts(at: newApp)
        if case .reject(let why) = Updating.verifyDownloaded(
            facts, expectedBundleID: bundleID, runningVersion: running) {
            throw UpdaterError("verification failed — \(why)")
        }

        // Hand off to the detached helper and quit so it can swap us out.
        await MainActor.run { self.state = .working("Installing…") }
        try spawnHelper(paths: paths, newApp: newApp,
                        version: facts.shortVersion ?? running)
        NSApp.terminate(nil)
    }

    // MARK: helper

    /// Write and launch the swap helper detached, then return. The helper waits
    /// for our PID to exit before touching the bundle. Paths are passed as
    /// environment variables (not interpolated into the script) so spaces in
    /// paths can't break or inject into the shell.
    private func spawnHelper(paths: UpdatePaths, newApp: URL, version: String) throws {
        let scriptURL = paths.stageDir.appendingPathComponent("swap.sh")
        try Self.helperScript.write(to: scriptURL, atomically: true, encoding: .utf8)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptURL.path]
        var env = ProcessInfo.processInfo.environment
        env["CUB_PID"] = String(ProcessInfo.processInfo.processIdentifier)
        env["CUB_TARGET"] = paths.target.path
        env["CUB_BACKUP"] = paths.backup.path
        env["CUB_NEWAPP"] = newApp.path
        env["CUB_STAGEDIR"] = paths.stageDir.path
        env["CUB_LOCK"] = paths.lock.path
        env["CUB_STATUS"] = statusFileURL().path
        env["CUB_VERSION"] = version
        task.environment = env
        try task.run()   // detached: not waited on; survives our termination
    }

    /// Bash helper. Reads everything from the environment. Atomic same-volume
    /// renames; restores the old bundle on any failure; records status for the
    /// next launch; relaunches.
    private static let helperScript = """
    #!/bin/bash
    # ClaudeUsageBar self-update swap helper. Do not run directly.
    set -u

    log() { echo "[cub-updater] $*" >&2; }

    write_status() { printf '%s' "$1" > "$CUB_STATUS" 2>/dev/null; }

    relaunch_and_exit() { open "$CUB_TARGET" 2>/dev/null; rm -f "$CUB_LOCK" 2>/dev/null; exit "$1"; }

    fail() {
      log "FAILED: $1"
      # If we parked the old bundle and the target is now empty, put it back so
      # the user is never left without an app.
      if [ ! -e "$CUB_TARGET" ] && [ -e "$CUB_BACKUP" ]; then
        mv "$CUB_BACKUP" "$CUB_TARGET" 2>/dev/null
      fi
      write_status "{\\"ok\\":false,\\"message\\":\\"$1\\"}"
      relaunch_and_exit 1
    }

    # Wait for the old app to fully exit (up to ~30s), then confirm the process
    # is really gone (guards against PID reuse racing the swap).
    for _ in $(seq 1 60); do kill -0 "$CUB_PID" 2>/dev/null || break; sleep 0.5; done
    if kill -0 "$CUB_PID" 2>/dev/null; then fail "old app did not quit"; fi

    # Park the current bundle, then move the new one into place — both are on the
    # same volume, so each mv is an atomic rename.
    rm -rf "$CUB_BACKUP" 2>/dev/null
    mv "$CUB_TARGET" "$CUB_BACKUP" 2>/dev/null || fail "could not move current app aside"
    mv "$CUB_NEWAPP" "$CUB_TARGET" 2>/dev/null || fail "could not install new app"

    xattr -dr com.apple.quarantine "$CUB_TARGET" 2>/dev/null || true

    # Success: drop the backup + staging, record it, relaunch.
    rm -rf "$CUB_BACKUP" "$CUB_STAGEDIR" 2>/dev/null
    write_status "{\\"ok\\":true,\\"version\\":\\"$CUB_VERSION\\"}"
    relaunch_and_exit 0
    """

    // MARK: fact gathering (side effects; decisions live in Updating)

    private func bundleFacts(at app: URL) -> Updating.DownloadedBundle {
        let info = app.appendingPathComponent("Contents/Info.plist")
        let plist = NSDictionary(contentsOf: info)
        let id = plist?["CFBundleIdentifier"] as? String
        let version = plist?["CFBundleShortVersionString"] as? String
        let execName = plist?["CFBundleExecutable"] as? String
        let hasExec: Bool = {
            guard let execName else { return false }
            let exec = app.appendingPathComponent("Contents/MacOS/\(execName)")
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: exec.path, isDirectory: &isDir) && !isDir.boolValue
        }()
        let signed = (try? run("/usr/bin/codesign",
                               ["--verify", "--deep", "--strict", app.path])) != nil
        return Updating.DownloadedBundle(bundleID: id, shortVersion: version,
                                         hasExecutable: hasExec, codesignVerified: signed)
    }

    /// The immediate `.app` child of `dir` (top level only — a nested app buried
    /// deeper is not what a legit release archive looks like, and Codex flagged
    /// a recursive search as spoofable).
    private func topLevelApp(in dir: URL) -> URL? {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        return items.first { $0.pathExtension == "app" }
    }

    // MARK: helpers

    private func runningBundleURL() -> URL? { Bundle.main.bundleURL }

    private func currentVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private func statusFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeUsageBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("last-update-status.json")
    }

    private func acquireLock(_ url: URL) -> Bool {
        let fd = open(url.path, O_CREAT | O_EXCL | O_WRONLY, 0o644)
        guard fd >= 0 else { return false }
        close(fd)
        return true
    }

    private func releaseLock(_ url: URL) { try? FileManager.default.removeItem(at: url) }

    private func openReleasePage(_ url: URL, note: String) {
        state = .failed(note)
        NSWorkspace.shared.open(url)
    }

    /// Run a tool, throwing if it exits non-zero. Used for `ditto` / `codesign`.
    private func run(_ launchPath: String, _ args: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = args
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw UpdaterError("\((launchPath as NSString).lastPathComponent) exited \(task.terminationStatus)")
        }
    }
}

private struct UpdaterError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
