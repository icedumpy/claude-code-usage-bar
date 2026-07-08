import Foundation

/// Publishes a `SyncSnapshot` to Scriptable's iCloud Drive folder so the iPhone
/// widget can read it. Best-effort by design: the write only happens if the
/// Scriptable folder already exists (i.e. the user installed Scriptable and it
/// synced to this Mac). A missing folder or any IO error is a silent skip — a
/// sync failure must never disrupt a usage refresh.
///
/// The Mac app is not sandboxed, so it can write a plain file into the user's
/// iCloud Drive with no entitlement; the system's iCloud daemon syncs it to the
/// phone. Nothing here needs a paid Apple Developer account.
public struct ScriptableSyncWriter: Sendable {
    public static let fileName = "usage.json"
    public static let scriptFileName = "ClaudeUsage.js"

    /// Scriptable's iCloud Drive Documents folder on macOS. The container id
    /// `iCloud~dk~simonbs~Scriptable` is Scriptable's, and its `Documents` dir
    /// is exactly what `FileManager.iCloud()` exposes to widget scripts.
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents",
                isDirectory: true)
    }

    public let directory: URL

    public init(directory: URL = ScriptableSyncWriter.defaultDirectory) {
        self.directory = directory
    }

    /// Write the snapshot as `usage.json`. Returns true if written, false if
    /// skipped (folder absent) or on any IO/encode error. Never throws.
    ///
    /// The write is wrapped in `NSFileCoordinator` because the target lives in
    /// another app's iCloud container: a bare `Data.write(.atomic)` renames a
    /// temp file underneath the iCloud daemon and can race its upload/tracking.
    /// Coordinated writing lets the daemon hold off and pick up the replacement
    /// cleanly. `.atomic` inside the coordinated accessor still guarantees the
    /// widget never sees a half-written file.
    ///
    /// We deliberately do NOT create the folder: a hand-made directory outside a
    /// real iCloud container wouldn't sync, so its absence is the correct signal
    /// that there's no phone to sync to yet.
    @discardableResult
    public func write(_ snapshot: SyncSnapshot) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir),
              isDir.boolValue else {
            return false
        }
        let data: Data
        do {
            data = try JSONEncoder().encode(snapshot)
        } catch {
            return false
        }

        let target = directory.appendingPathComponent(Self.fileName)
        var coordinatorError: NSError?
        var wrote = false
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing,
                                       error: &coordinatorError) { url in
            wrote = (try? data.write(to: url, options: .atomic)) != nil
        }
        return wrote && coordinatorError == nil
    }

    public enum ScriptInstallOutcome: Equatable {
        case installed          // wrote/refreshed our managed ClaudeUsage.js
        case upToDate           // our marker already current — nothing to do
        case userOwned          // a script without our marker — left untouched
        case folderMissing      // Scriptable's iCloud folder not synced yet
        case failed             // present but the write itself errored
    }

    /// Install (or refresh) the widget script so the user doesn't paste it by
    /// hand. `body` is the raw `usage-widget.js` shipped in the app bundle; we
    /// stamp a version marker on it. Never clobbers a user-edited script (one
    /// without our marker). Same folder-absent = silent skip contract as
    /// `write`: a missing Scriptable folder just means "no phone yet".
    @discardableResult
    public func installScript(_ body: String) -> ScriptInstallOutcome {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
            return .folderMissing
        }
        let target = directory.appendingPathComponent(Self.scriptFileName)
        // An iCloud file that hasn't downloaded yet shows up as a hidden
        // ".<name>.icloud" placeholder rather than the real file.
        let placeholder = directory.appendingPathComponent(".\(Self.scriptFileName).icloud")
        let targetExists = fm.fileExists(atPath: target.path)
        let placeholderExists = fm.fileExists(atPath: placeholder.path)

        // Only write when we're SURE nothing is there. If a file (or its
        // not-yet-downloaded placeholder) exists but we can't read/decode it,
        // treat it as the user's own and never clobber it — a read failure must
        // not be mistaken for "no file", which would overwrite a real script.
        if targetExists || placeholderExists {
            guard targetExists, let existing = try? String(contentsOf: target, encoding: .utf8) else {
                return .userOwned
            }
            switch WidgetScriptInstall.decide(existing: existing) {
            case .skipUpToDate: return .upToDate
            case .skipUserOwned: return .userOwned
            case .install: return writeScript(body, to: target)
            }
        }
        return writeScript(body, to: target)
    }

    private func writeScript(_ body: String, to target: URL) -> ScriptInstallOutcome {
        guard let data = WidgetScriptInstall.stamped(body).data(using: .utf8) else {
            return .failed
        }
        var coordinatorError: NSError?
        var wrote = false
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing,
                                       error: &coordinatorError) { url in
            wrote = (try? data.write(to: url, options: .atomic)) != nil
        }
        return (wrote && coordinatorError == nil) ? .installed : .failed
    }
}
