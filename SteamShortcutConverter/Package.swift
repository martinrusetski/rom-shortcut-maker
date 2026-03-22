// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SteamShortcutConverter",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "SteamShortcutConverter",
            targets: ["SteamShortcutConverter"])
    ],
    dependencies: [
        // SwiftCheck for property-based testing (optional)
        // Uncomment to enable property-based testing:
        // .package(url: "https://github.com/typelift/SwiftCheck.git", from: "0.12.0")
    ],
    targets: [
        .target(
            name: "SteamShortcutConverter",
            dependencies: []),
        .testTarget(
            name: "SteamShortcutConverterTests",
            dependencies: [
                "SteamShortcutConverter",
                // Uncomment to enable property-based testing:
                // "SwiftCheck"
            ])
    ]
)
