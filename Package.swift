// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "JoyaFix",
    platforms: [
        .macOS(.v11)
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
            path: "Sources/JoyaFix",
            resources: [
                .process("Resources")
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

