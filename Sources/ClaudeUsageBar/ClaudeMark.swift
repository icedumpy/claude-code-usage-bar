import AppKit
import UsageCore

/// Loads the menu bar icon from three SVG files on disk — one per severity —
/// so the user can drop in their own colored artwork without rebuilding.
/// Files live in ~/Library/Application Support/ClaudeUsageBar/icons/:
///   normal.svg (green), warning.svg (yellow), critical.svg (red).
/// Missing files are seeded with the bundled Claude icon as a placeholder.
enum ClaudeMark {
    static let iconsDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        return base.appendingPathComponent("ClaudeUsageBar/icons", isDirectory: true)
    }()

    static let fileNames = ["normal.svg", "warning.svg", "critical.svg"]

    private static func fileName(for s: Severity) -> String {
        switch s {
        case .warning: return "warning.svg"
        case .severe, .critical: return "critical.svg"
        case .normal, .unknown: return "normal.svg"
        }
    }

    /// Create the icons folder and seed any missing file with a default icon.
    static func ensurePlaceholders() {
        try? FileManager.default.createDirectory(at: iconsDir, withIntermediateDirectories: true)
        for name in fileNames {
            let url = iconsDir.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) {
                try? defaultSVG(for: name).data(using: .utf8)?.write(to: url)
            }
        }
    }

    private static var cache: [String: (mtime: Date, image: NSImage)] = [:]

    /// The icon for a severity, loaded from its SVG file. Cached and reloaded
    /// automatically when the file changes (so editing the SVG takes effect).
    static func icon(for severity: Severity) -> NSImage? {
        let url = iconsDir.appendingPathComponent(fileName(for: severity))
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate) ?? .distantPast
        let key = url.path
        if let cached = cache[key], cached.mtime == mtime { return cached.image }
        guard let img = NSImage(contentsOf: url) else { return nil }
        img.size = NSSize(width: 18, height: 18)
        img.isTemplate = false   // keep the SVG's own colors
        cache[key] = (mtime, img)
        return img
    }

    /// Default icon for a severity file: a simple filled circle in the severity
    /// color. Original artwork (no third-party marks). Replace any of the files
    /// in the icons folder with your own SVG to customize.
    private static func defaultSVG(for fileName: String) -> String {
        let color: String
        switch fileName {
        case "warning.svg":  color = "#FF9800"   // amber
        case "critical.svg": color = "#F44336"   // red
        default:             color = "#4CAF50"   // green
        }
        return #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><circle cx="50" cy="50" r="44" fill="\#(color)"/></svg>"#
    }
}
