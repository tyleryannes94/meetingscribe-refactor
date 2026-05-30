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
        // Consolidated vault library: the single source of truth for shared
        // models, JSON helpers, path helpers, and Darwin IPC. Foundation +
        // Combine only — no AppKit/SwiftUI/UIKit — so it can be used from any
        // target. (Superseded the former MeetingScribeShared + SecondBrainCore
        // targets, which were byte-identical orphans imported by nothing.)
        .library(name: "VaultKit", targets: ["VaultKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        // Consolidated vault library: the shared models (Person, Encounter,
        // MeetingDTO…), JSONValue, SchemaEnvelope, the SecondBrainStore
        // interface, plus VaultPaths and DarwinNotifier. Foundation only — no
        // AppKit/SwiftUI — so it can be lifted into a future iOS app. This is
        // the single source of truth depended on by the app, the daemon, and
        // both MCP servers.
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
            exclude: [
                "PersonExtractionController.swift",
                "ActionItemBackfillController.swift",
                "MeetingPipelineController.swift",
                "Calendar/CalendarService.swift",
                "Calendar/CalendarStoreActor.swift"
            ],
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
            dependencies: ["MeetingScribe", "VaultKit"],
            path: "Tests/MeetingScribeTests",
            swiftSettings: commonSwiftSettings
        )
    ]
)
