import Foundation

/// Severity reported by the API for a limit. Drives the menu bar color.
public enum Severity: String, Decodable, Sendable {
    case normal
    case warning
    case critical
    case severe
    case unknown

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? "unknown"
        self = Severity(rawValue: raw) ?? .unknown
    }

    /// Worst-wins ordering so the hero color reflects the most urgent limit.
    public var rank: Int {
        switch self {
        case .normal: return 0
        case .unknown: return 1
        case .warning: return 2
        case .severe: return 3
        case .critical: return 4
        }
    }
}

/// A single rate-limit window summary (used for per-model lookups and fallback).
public struct Window: Decodable, Sendable {
    public let utilization: Double
    public let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

/// Model reference inside a scoped limit (e.g. the weekly Opus/Sonnet limit).
public struct ModelRef: Decodable, Sendable {
    public let id: String?
    public let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

public struct Scope: Decodable, Sendable {
    public let model: ModelRef?
}

/// One entry from the `limits` array — the primary source for the menu bar.
public struct Limit: Decodable, Sendable {
    public let kind: String       // "session" | "weekly_all" | "weekly_scoped"
    public let group: String      // "session" | "weekly"
    public let percent: Double
    public let severity: Severity
    public let resetsAt: Date?
    public let scope: Scope?
    public let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case kind, group, percent, severity, scope
        case resetsAt = "resets_at"
        case isActive = "is_active"
    }

    /// Human label, e.g. "5-hour window", "Weekly (all)", "Weekly · Opus".
    public var displayLabel: String {
        switch kind {
        case "session":
            return "5-hour window"
        case "weekly_all":
            return "Weekly (all)"
        case "weekly_scoped":
            if let m = scope?.model?.displayName { return "Weekly · \(m)" }
            return "Weekly (scoped)"
        default:
            if let m = scope?.model?.displayName { return "\(kind) · \(m)" }
            return kind
        }
    }

    public var modelName: String? { scope?.model?.displayName }
}

/// Decoded `GET /api/oauth/usage` response.
public struct UsageResponse: Decodable, Sendable {
    public let limits: [Limit]
    public let fiveHour: Window?
    public let sevenDay: Window?
    public let sevenDayOpus: Window?
    public let sevenDaySonnet: Window?

    enum CodingKeys: String, CodingKey {
        case limits
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
    }

    /// The hero limit: highest current-usage-vs-limit percentage.
    /// Ties broken by severity, then by the active flag.
    public var heroLimit: Limit? {
        limits.max { a, b in
            if a.percent != b.percent { return a.percent < b.percent }
            if a.severity.rank != b.severity.rank { return a.severity.rank < b.severity.rank }
            return (a.isActive ? 1 : 0) < (b.isActive ? 1 : 0)
        }
    }

    /// The 5-hour (session) limit — what the menu bar shows by default. Weekly
    /// limits are still available in the dropdown.
    public var sessionLimit: Limit? {
        limits.first { $0.kind == "session" || $0.group == "session" }
    }

    /// Start of the current weekly window, derived from the weekly reset time.
    /// Cost breakdown is scoped to this so the dropdown tells one coherent story.
    public var weeklyWindowStart: Date? {
        let reset = sevenDay?.resetsAt
            ?? limits.first(where: { $0.kind == "weekly_all" })?.resetsAt
        guard let reset else { return nil }
        return reset.addingTimeInterval(-7 * 24 * 60 * 60)
    }

    /// Decoder configured for the API's ISO8601-with-fractional-seconds dates.
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = ISO8601DateParser.parse(s) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Unparseable date: \(s)"))
        }
        return d
    }
}

/// Lenient ISO8601 parser that accepts fractional seconds and timezone offsets.
public enum ISO8601DateParser {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func parse(_ s: String) -> Date? {
        withFraction.date(from: s) ?? plain.date(from: s)
    }
}
