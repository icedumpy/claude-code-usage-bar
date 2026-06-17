import Foundation

/// One alert to surface when a limit crosses a usage threshold.
public struct ThresholdAlert: Sendable, Equatable {
    public let limitId: String
    public let threshold: Int
    public let title: String
    public let body: String
}

/// Remembers the highest threshold already notified per limit, so alerts fire
/// once per crossing rather than every poll.
public struct AlertState: Sendable, Equatable {
    public var fired: [String: Int]
    public init(fired: [String: Int] = [:]) { self.fired = fired }
}

/// Pure threshold-crossing logic (unit tested). Fires when a limit rises past a
/// threshold; resets once the limit drops back below all thresholds (e.g. after
/// a window reset) so it can alert again next cycle.
public enum ThresholdAlerter {
    public static let thresholds = [80, 95]

    public static func evaluate(limits: [Limit], state: inout AlertState) -> [ThresholdAlert] {
        var alerts: [ThresholdAlert] = []
        for limit in limits {
            let id = "\(limit.kind)#\(limit.modelName ?? "")"
            let pct = Int(limit.percent.rounded())
            guard let crossed = thresholds.filter({ pct >= $0 }).max() else {
                state.fired[id] = nil   // back below all thresholds — allow re-alert
                continue
            }
            let already = state.fired[id] ?? 0
            if crossed > already {
                alerts.append(ThresholdAlert(
                    limitId: id,
                    threshold: crossed,
                    title: "Claude usage at \(crossed)%",
                    body: "\(limit.displayLabel) is at \(pct)%."))
                state.fired[id] = crossed
            }
        }
        return alerts
    }
}
