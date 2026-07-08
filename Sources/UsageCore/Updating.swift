import Foundation

/// Pure decision logic for the in-app updater, split out from the AppKit/Process
/// side effects so every branch that can brick an install is unit-tested. The
/// coordinator (`Updater` in the app target) gathers filesystem/codesign facts
/// and feeds them here; this file never touches the disk.
public enum Updating {
    /// Numeric-component version compare, e.g. isNewer("1.10.0", than: "1.9.0").
    /// A prerelease/build suffix ("-beta", "+build") is dropped before parsing.
    /// Shared by `UpdateChecker` (offer the banner) and `verifyDownloaded`
    /// (refuse to install an older bundle than we're running).
    public static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = numericComponents(a)
        let pb = numericComponents(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func numericComponents(_ v: String) -> [Int] {
        let core = v.prefix { $0 != "-" && $0 != "+" }
        return core.split(separator: ".").map { Int($0) ?? 0 }
    }

    // MARK: install location

    /// Whether we can swap the running bundle in place. Writing over the app in
    /// `/Applications` needs the parent dir to be writable; for many users it
    /// isn't without admin, so the manual path (open the release page) is a
    /// normal, expected outcome — not an error.
    public enum InstallPlan: Equatable {
        case selfUpdate
        case manual(reason: String)
    }

    public static func plan(parentWritable: Bool) -> InstallPlan {
        parentWritable
            ? .selfUpdate
            : .manual(reason: "Can’t write to the app’s folder — install the update manually.")
    }

    // MARK: downloaded-bundle verification

    /// Facts the coordinator reads off the extracted `.app` before we let it
    /// replace the running bundle. All gathered with side effects up in the app
    /// target; the accept/reject decision lives here so it's testable.
    public struct DownloadedBundle: Equatable {
        public let bundleID: String?
        public let shortVersion: String?
        public let hasExecutable: Bool
        public let codesignVerified: Bool

        public init(bundleID: String?, shortVersion: String?,
                    hasExecutable: Bool, codesignVerified: Bool) {
            self.bundleID = bundleID
            self.shortVersion = shortVersion
            self.hasExecutable = hasExecutable
            self.codesignVerified = codesignVerified
        }
    }

    public enum VerifyOutcome: Equatable {
        case accept
        case reject(String)
    }

    /// Refuse anything that isn't unmistakably a newer-or-equal build of *this*
    /// app with a loadable executable and a valid (even ad-hoc) signature. A
    /// strict downgrade is rejected so a swapped-out release asset can't push an
    /// older, possibly-vulnerable build in place.
    public static func verifyDownloaded(_ b: DownloadedBundle,
                                        expectedBundleID: String,
                                        runningVersion: String) -> VerifyOutcome {
        guard let id = b.bundleID else { return .reject("missing bundle identifier") }
        guard id == expectedBundleID else {
            return .reject("bundle identifier mismatch (\(id))")
        }
        guard let version = b.shortVersion, !version.isEmpty else {
            return .reject("missing version")
        }
        // Equal is allowed (a reinstall of the current version); only a strict
        // downgrade is refused.
        if isNewer(runningVersion, than: version) {
            return .reject("downloaded version \(version) is older than \(runningVersion)")
        }
        guard b.hasExecutable else { return .reject("no executable in bundle") }
        guard b.codesignVerified else { return .reject("code signature did not verify") }
        return .accept
    }

    // MARK: crash / power-loss recovery

    /// After a swap, the helper leaves the old bundle at `backup` until it has
    /// confirmed the new one launched. If the app dies mid-swap, the next launch
    /// reconciles from what's on disk.
    public enum RecoveryAction: Equatable {
        /// Swap was interrupted after the target was moved aside but before the
        /// new bundle took its place: put the old one back.
        case restoreBackup
        /// New bundle is in place but a stale backup was left behind: remove it.
        case cleanupBackup
        /// Nothing to do.
        case none
    }

    public static func recovery(targetExists: Bool, backupExists: Bool) -> RecoveryAction {
        switch (targetExists, backupExists) {
        case (false, true): return .restoreBackup
        case (true, true): return .cleanupBackup
        default: return .none
        }
    }
}

/// Deterministic on-disk locations for a swap, all siblings of the target so the
/// rename is a same-volume (atomic) move — never a cross-volume copy. Fixed
/// (non-PID) names so a crashed update's leftovers are found and reconciled on
/// the next launch. The interprocess lock guarantees only one swap uses them at
/// a time.
public struct UpdatePaths: Equatable {
    public let target: URL      // the running .app, e.g. /Applications/ClaudeUsageBar.app
    public let backup: URL      // old bundle parked here until the new one is confirmed
    public let stageDir: URL    // download + unpack happen here (same volume as target)
    public let lock: URL        // O_EXCL lock file guarding the swap

    public static func make(target: URL) -> UpdatePaths {
        let parent = target.deletingLastPathComponent()
        let name = target.lastPathComponent          // "ClaudeUsageBar.app"
        return UpdatePaths(
            target: target,
            backup: parent.appendingPathComponent(".\(name).backup"),
            stageDir: parent.appendingPathComponent(".\(name).update"),
            lock: parent.appendingPathComponent(".\(name).update.lock"))
    }
}
