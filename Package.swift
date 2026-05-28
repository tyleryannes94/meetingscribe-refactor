// swift-tools-version:5.10
import PackageDescription

// Common Swift settings applied to every target. Enabling targeted strict
// concurrency surfaces actor-isolation and Sendable issues as warnings now,
// so we can fix them incrementally before the inevitable Swift 6 mode flip
// (where these become errors).
let commonSwiftSettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency=targeted")
]

let package = Package(
    name: "MeetingScribe",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MeetingScribe", targets: ["MeetingScribe"]),
        .executable(name: "ScribeCore", targets: ["ScribeCore"]),
        .executable(name: "MeetingScribeMCP", targets: ["MeetingScribeMCP"]),
        .executable(name: "NotionMCP", targets: ["NotionMCP"]),
        .library(name: "MeetingScribeShared", targets: ["MeetingScribeShared"]),
        // Pure-model "Second Brain" core, free of AppKit/SwiftUI so it can be
        // shared with a future iOS target.
        .library(name: "SecondBrainCore", targets: ["SecondBrainCore"]),
        // Consolidated vault library: merges SecondBrainCore + MeetingScribeShared
        // plus path helpers and Darwin IPC. Foundation + Combine only — no
        // AppKit/SwiftUI/UIKit — so it can be used from any target.
        .library(name: "VaultKit", targets: ["VaultKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        // Shared decode-only DTOs and JSON helpers — depended on by both
        // MCP servers and the main app so we don't carry three copies of
        // JSONValue or three drift-prone reimplementations of the
        // persisted model types.
        .target(
            name: "MeetingScribeShared",
            path: "Sources/MeetingScribeShared",
            swiftSettings: commonSwiftSettings
        ),
        // Dependency-free Second Brain models (Person, Encounter) plus the
        // store interface. No AppKit/SwiftUI/CloudKit imports, so this target
        // can be lifted wholesale into a future iOS app.
        .target(
            name: "SecondBrainCore",
            dependencies: [],
            path: "Sources/SecondBrainCore",
            swiftSettings: commonSwiftSettings
        ),
        // Consolidated vault library: merges SecondBrainCore + MeetingScribeShared
        // plus VaultPaths and DarwinNotifier. Foundation only — no AppKit/SwiftUI.
        .target(
            name: "VaultKit",
            dependencies: [],
            path: "Sources/VaultKit",
            swiftSettings: commonSwiftSettings
        ),
        .executableTarget(
            name: "MeetingScribe",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                "VaultKit"
            ],
            path: "Sources/MeetingScribe",
            swiftSettings: commonSwiftSettings
        ),
        .executableTarget(
            name: "ScribeCore",
            dependencies: ["VaultKit"],
            path: "Sources/ScribeCore",
            swiftSettings: commonSwiftSettings
        ),
        .executableTarget(
            name: "MeetingScribeMCP",
            dependencies: ["VaultKit"],
            path: "Sources/MeetingScribeMCP",
            swiftSettings: commonSwiftSettings
        ),
        .executableTarget(
            name: "NotionMCP",
            dependencies: ["VaultKit"],
            path: "Sources/NotionMCP",
            swiftSettings: commonSwiftSettings
        ),
        .testTarget(
            name: "MeetingScribeTests",
            dependencies: ["MeetingScribe", "MeetingScribeShared"],
            path: "Tests/MeetingScribeTests",
            swiftSettings: commonSwiftSettings
        )
    ]
)
