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
        // OPTIMIZATION: Updated to latest stable versions
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.5.0"),  // Latest: 2.9.0
        .package(url: "https://github.com/kean/Pulse", from: "4.0.0"),  // Latest: 5.0.0
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0")  // Latest: 6.30.0
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

