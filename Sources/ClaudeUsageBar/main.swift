import Foundation

// `--probe` runs a one-shot headless fetch (for verification / CLI use);
// otherwise launch the SwiftUI menu bar app.
if CommandLine.arguments.contains("--probe") {
    exit(Probe.run())
} else {
    ClaudeUsageBarApp.main()
}
