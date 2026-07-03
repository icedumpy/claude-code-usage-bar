import Foundation

struct UpdateInfo: Equatable, Sendable {
    let version: String   // e.g. "1.1.0"
    let url: String       // release page to open
}

/// Lightweight update check: asks the public GitHub Releases API for the latest
/// version and compares it to the running build. No dependency, no auto-install
/// — the dropdown shows a one-click link to the release page when newer.
enum UpdateChecker {
    static let repo = "icedumpy/claude-code-usage-bar"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static func check() async -> UpdateInfo? {
        // A bare `swift run` / `.build/release` binary has no bundle version, so
        // `currentVersion` is "0" and every release would look newer. Only the
        // packaged .app should surface an update banner.
        guard Bundle.main.infoDictionary?["CFBundleShortVersionString"] != nil else { return nil }
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String
        else { return nil }

        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard isNewer(latest, than: currentVersion) else { return nil }

        let page = (obj["html_url"] as? String) ?? "https://github.com/\(repo)/releases/latest"
        return UpdateInfo(version: latest, url: page)
    }

    /// Numeric component comparison, e.g. isNewer("1.10.0", than: "1.9.0") == true.
    /// A prerelease/build suffix is dropped before parsing, so "1.2.0-beta" is
    /// read as 1.2.0 rather than parsing its last component "0-beta" as 0.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = numericComponents(a)
        let pb = numericComponents(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Splits a semver-ish string into its numeric components, ignoring any
    /// "-prerelease" or "+build" suffix (per SemVer, those start at the first
    /// "-" or "+").
    private static func numericComponents(_ v: String) -> [Int] {
        let core = v.prefix { $0 != "-" && $0 != "+" }
        return core.split(separator: ".").map { Int($0) ?? 0 }
    }
}
