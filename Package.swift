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
        .library(name: "GlanceAntigravity", targets: ["GlanceAntigravity"]),
        .library(name: "GlanceCodex", targets: ["GlanceCodex"]),
        .library(name: "GlanceDevin", targets: ["GlanceDevin"]),
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
        .target(name: "GlanceAntigravity", dependencies: ["GlanceCore"]),
        .target(name: "GlanceCodex", dependencies: ["GlanceCore"]),
        .target(name: "GlanceDevin", dependencies: ["GlanceCore"]),
        .executableTarget(
            name: "GlanceApp",
            dependencies: [
                "GlanceCore",
                "GlanceOpenCode",
                "GlanceClaude",
                "GlanceAntigravity",
                "GlanceCodex",
                "GlanceDevin",
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
            dependencies: ["GlanceApp", "GlanceCore", "GlanceOpenCode", "GlanceDevin", "GlanceAntigravity"]
        ),
        .testTarget(
            name: "GlanceClaudeTests",
            dependencies: ["GlanceClaude", "GlanceCore"]
        ),
        .testTarget(
            name: "GlanceAntigravityTests",
            dependencies: ["GlanceAntigravity", "GlanceCore"]
        ),
        .testTarget(
            name: "GlanceCodexTests",
            dependencies: ["GlanceCodex", "GlanceCore"]
        ),
        .testTarget(
            name: "GlanceDevinTests",
            dependencies: ["GlanceDevin", "GlanceCore"]
        ),
    ]
)
