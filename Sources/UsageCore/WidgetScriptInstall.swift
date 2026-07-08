import Foundation

/// Decides whether the Mac app may write (or refresh) the Scriptable widget
/// script `ClaudeUsage.js` it drops into Scriptable's iCloud folder — so a
/// first-time user never has to paste ~200 lines into Scriptable by hand. Pure
/// and unit-tested; the writer supplies the existing file's contents and the
/// fresh body, this file never touches the disk.
public enum WidgetScriptInstall {
    /// Bump whenever `scriptable/usage-widget.js` changes so already-installed
    /// copies that still carry our marker get refreshed on the next sync.
    public static let currentVersion = 1

    /// Leading marker line stamped onto scripts we manage. The trailing note is
    /// the opt-out: a user who wants to hand-edit the script deletes this line,
    /// and we then treat it as their own and never overwrite it.
    public static func markerLine(version: Int = currentVersion) -> String {
        "// managed:ClaudeUsage:v\(version) — ClaudeUsageBar keeps this script "
            + "up to date. Delete THIS line to keep your own edits."
    }

    /// The body with our marker prepended, ready to write.
    public static func stamped(_ body: String, version: Int = currentVersion) -> String {
        markerLine(version: version) + "\n" + body
    }

    /// Version parsed from a managed script, or nil when the text isn't ours
    /// (user-authored, or hand-pasted without the marker). Scans a small leading
    /// window rather than only line 1: Scriptable prepends its own
    /// "// Variables used by Scriptable" header when the user opens the script,
    /// which would otherwise push our marker down and make us misread an updated
    /// script as user-owned.
    public static func managedVersion(of existing: String) -> Int? {
        // Scan a generous leading window (not just line 1) so Scriptable's
        // prepended "// Variables used by Scriptable" header — however much it
        // grows — never pushes our marker out of view and makes us misread a
        // managed script as user-owned.
        let head = existing.prefix(4096)
        guard let range = head.range(of: "managed:ClaudeUsage:v") else { return nil }
        let digits = head[range.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }

    public enum Action: Equatable {
        /// No file yet, or one of ours at an older version: (over)write it.
        case install
        /// Our marker, already at this version or newer: leave it.
        case skipUpToDate
        /// A file without our marker — a user's own script: never clobber it.
        case skipUserOwned
    }

    /// `existing` is the current `ClaudeUsage.js` contents, or nil if absent.
    public static func decide(existing: String?,
                              currentVersion: Int = currentVersion) -> Action {
        guard let existing else { return .install }
        guard let version = managedVersion(of: existing) else { return .skipUserOwned }
        return version < currentVersion ? .install : .skipUpToDate
    }
}
