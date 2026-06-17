import SwiftUI
import UsageCore

/// Maps API severity to a menu bar emoji dot (keeps color in the menu bar, which
/// otherwise renders SwiftUI labels monochrome) and a panel accent color.
enum SeverityStyle {
    static func dot(_ s: Severity) -> String {
        switch s {
        case .normal: return "🟢"
        case .warning: return "🟡"
        case .severe, .critical: return "🔴"
        case .unknown: return "⚪️"
        }
    }

    static func color(_ s: Severity) -> Color {
        switch s {
        case .normal: return .green
        case .warning: return .yellow
        case .severe, .critical: return .red
        case .unknown: return .secondary
        }
    }
}
