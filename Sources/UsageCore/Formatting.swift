import Foundation

public enum Formatting {
    /// Compact token counts: 420, 12.3K, 1.2M, 3.4B.
    public static func tokens(_ n: Int) -> String {
        let d = Double(n)
        switch n {
        case ..<1_000: return "\(n)"
        case ..<1_000_000: return trim(d / 1_000) + "K"
        case ..<1_000_000_000: return trim(d / 1_000_000) + "M"
        default: return trim(d / 1_000_000_000) + "B"
        }
    }

    /// Notional dollars: $3.20, $0.84, $12.
    public static func dollars(_ v: Double) -> String {
        if v >= 100 { return "$" + String(format: "%.0f", v) }
        return "$" + String(format: "%.2f", v)
    }

    public static func percent(_ p: Double) -> String {
        String(format: "%.0f%%", p)
    }

    /// Compact countdown for the tight menu bar, e.g. "2h58m", "55m", "3d2h".
    public static func compactCountdown(to date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let secs = Int(date.timeIntervalSince(now))
        if secs <= 0 { return "0m" }
        let mins = secs / 60
        if mins < 60 { return "\(mins)m" }
        let hours = mins / 60
        if hours < 24 {
            let m = mins % 60
            return m == 0 ? "\(hours)h" : "\(hours)h\(m)m"
        }
        let days = hours / 24
        let h = hours % 24
        return h == 0 ? "\(days)d" : "\(days)d\(h)h"
    }

    /// Humanized reset countdown, e.g. "resets in 2h 40m", "resets in 3d",
    /// "resets soon". Returns "" if the date is missing.
    public static func reset(to date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let secs = date.timeIntervalSince(now)
        if secs <= 0 { return "resetting…" }
        let mins = Int(secs / 60)
        if mins < 1 { return "resets soon" }
        if mins < 60 { return "resets in \(mins)m" }
        let hours = mins / 60
        if hours < 24 {
            let rem = mins % 60
            return rem == 0 ? "resets in \(hours)h" : "resets in \(hours)h \(rem)m"
        }
        let days = hours / 24
        let remH = hours % 24
        return remH == 0 ? "resets in \(days)d" : "resets in \(days)d \(remH)h"
    }

    private static func trim(_ v: Double) -> String {
        // one decimal, but drop trailing ".0"
        let s = String(format: "%.1f", v)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
}
