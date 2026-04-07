// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Glance",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "GlanceCore", targets: ["GlanceCore"]),
        .library(name: "GlanceOpenCode", targets: ["GlanceOpenCode"]),
        .library(name: "GlanceClaude", targets: ["GlanceClaude"]),
        .library(name: "GlanceGemini", targets: ["GlanceGemini"]),
        .library(name: "GlanceCodex", targets: ["GlanceCodex"]),
        .executable(name: "GlanceApp", targets: ["GlanceApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
    ],
    targets: [
        .target(name: "GlanceCore"),
        .target(
            name: "GlanceOpenCode",
            dependencies: ["GlanceCore"],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .target(name: "GlanceClaude", dependencies: ["GlanceCore"]),
        .target(name: "GlanceGemini", dependencies: ["GlanceCore"]),
        .target(name: "GlanceCodex", dependencies: ["GlanceCore"]),
        .executableTarget(
            name: "GlanceApp",
            dependencies: [
                "GlanceCore",
                "GlanceOpenCode",
                "GlanceClaude",
                "GlanceGemini",
                "GlanceCodex",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "GlanceCoreTests",
            dependencies: ["GlanceCore"]
        ),
        .testTarget(
            name: "GlanceOpenCodeTests",
            dependencies: ["GlanceOpenCode", "GlanceCore"]
        ),
        .testTarget(
            name: "GlanceAppTests",
            dependencies: ["GlanceApp", "GlanceCore", "GlanceOpenCode"]
        ),
        .testTarget(
            name: "GlanceClaudeTests",
            dependencies: ["GlanceClaude", "GlanceCore"]
        ),
        .testTarget(
            name: "GlanceGeminiTests",
            dependencies: ["GlanceGemini", "GlanceCore"]
        ),
        .testTarget(
            name: "GlanceCodexTests",
            dependencies: ["GlanceCodex", "GlanceCore"]
        ),
    ]
)
