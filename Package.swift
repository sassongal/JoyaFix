// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "JoyaFix",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "JoyaFix",
            targets: ["JoyaFix"]
        )
    ],
    dependencies: [
        // Sparkle for app updates
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.5.0"),
        // Pulse for network logging
        .package(url: "https://github.com/kean/Pulse", from: "4.0.0")
    ],
    targets: [
        .executableTarget(
            name: "JoyaFix",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Pulse", package: "Pulse")
            ],
            path: ".",
            exclude: [
                "build.sh",
                "run.sh",
                "test.sh",
                "migrate_to_spm.sh",
                "Tests",
                "JoyaFix.app",
                ".build",
                "build",
                "DEBUG.md",
                "EXECUTION_PLAN.md",
                "GAP_ANALYSIS.md",
                "HOTKEY_SYSTEM.md",
                "OPTIMIZATION.md",
                "README.md",
                "SOUND_SETUP.md",
                "SPM_MIGRATION.md",
                "UI_UPGRADE.md",
                "version.json",
                "Package.swift",
                "Package.resolved"
            ],
            resources: [
                .process("en.lproj"),
                .process("he.lproj"),
                .process("FLATLOGO.png"),
                .process("success.wav")
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices")
            ]
        ),
        .testTarget(
            name: "JoyaFixTests",
            dependencies: ["JoyaFix"],
            path: "Tests/JoyaFixTests"
        )
    ]
)

