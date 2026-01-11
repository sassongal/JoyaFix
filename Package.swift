// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JoyaFix",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "JoyaFix", targets: ["JoyaFix"])
    ],
    dependencies: [
        // Updated to latest stable versions (2026-01-09)
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),  // Updated from 2.5.0 (latest: 2.8.1)
        .package(url: "https://github.com/kean/Pulse", from: "4.0.0"),  // Keep 4.x (5.0 has breaking changes)
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.3")  // Updated from 6.0.0 (latest: 6.29.3)
    ],
    targets: [
        .executableTarget(
            name: "JoyaFix",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Pulse", package: "Pulse"),
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/JoyaFix", // הנתיב המעודכן לאחר המעבר
            exclude: ["Resources/Info.plist"],
            resources: [
                .process("Resources/en.lproj"),
                .process("Resources/he.lproj"),
                .process("Resources/FLATLOGO.png"),
                .process("Resources/success.wav"),
                .process("Resources/JoyaFix.icns"),
                .process("Resources/JoyaFix.iconset")
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

