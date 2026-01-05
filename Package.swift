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
        .package(url: "https://github.com/kean/Pulse", from: "4.0.0"),
        // SwiftLint for code style
        .package(url: "https://github.com/realm/SwiftLint", from: "0.55.1"),
        // GRDB for SQLite database (replaces UserDefaults for history storage)
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0")
    ],
    targets: [
        .executableTarget(
            name: "JoyaFix",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Pulse", package: "Pulse"),
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/JoyaFix",
            exclude: [
                "Resources/Info.plist"
            ],
            resources: [
                .process("Resources/en.lproj"),
                .process("Resources/he.lproj"),
                .process("Resources/FLATLOGO.png"),
                .process("Resources/success.wav")
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices")
            ],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLint")
            ]
        ),
        .testTarget(
            name: "JoyaFixTests",
            dependencies: ["JoyaFix"],
            path: "Tests/JoyaFixTests"
        )
    ]
)

