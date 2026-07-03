// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeUsageBar",
    platforms: [.macOS(.v13)],
    targets: [
        // UI-free data layer + models. Fully unit-tested.
        .target(
            name: "UsageCore",
            path: "Sources/UsageCore"
        ),
        // SwiftUI menu bar app. Thin layer over UsageCore.
        .executableTarget(
            name: "ClaudeUsageBar",
            dependencies: ["UsageCore"],
            path: "Sources/ClaudeUsageBar"
        ),
        .testTarget(
            name: "UsageCoreTests",
            dependencies: ["UsageCore"],
            path: "Tests/UsageCoreTests"
        ),
        .testTarget(
            name: "ClaudeUsageBarTests",
            dependencies: ["ClaudeUsageBar"],
            path: "Tests/ClaudeUsageBarTests"
        ),
    ]
)
