import SwiftUI
import UsageCore

/// Maps API severity to UI styling: an emoji dot (used by the `--probe` CLI
/// output) and the accent color used for the dropdown's limit bars.
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
