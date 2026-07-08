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
}
