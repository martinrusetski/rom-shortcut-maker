// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// SwiftPM is the single build system for this app: `swift test` runs the
// headless logic suite, `swift build -c release` produces the shippable binary,
// and CI hand-assembles that binary into "Rom Shortcut Maker.app" (see the
// release workflow and make-dmg.sh). For a GUI dev loop, open this Package.swift
// directly in Xcode — no .xcodeproj required.
//
// The one target holds every source file, `@main` included, so the test target
// can `@testable import SteamShortcutConverter` and reach the whole codebase.
let package = Package(
    name: "SteamShortcutConverter",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "RomShortcutMaker",
            targets: ["SteamShortcutConverter"])
    ],
    dependencies: [
        // Sparkle powers in-app auto-updates. The framework is embedded into the
        // .app by hand (embed-sparkle.sh) using an @executable_path/../Frameworks
        // rpath, mirroring the layout Xcode would produce.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "SteamShortcutConverter",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "SteamShortcutConverter",
            exclude: [
                // Xcode-only build inputs; the release build generates its own
                // Info.plist and compiles Assets.xcassets with actool in CI.
                "Info.plist",
                "Assets.xcassets"
            ],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .unsafeFlags([
                    // Locate the embedded Sparkle.framework at runtime once the
                    // executable lives inside the .app bundle we assemble by hand.
                    "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"
                ])
            ]),
        .testTarget(
            name: "SteamShortcutConverterTests",
            dependencies: ["SteamShortcutConverter"],
            path: "SteamShortcutConverterTests",
            exclude: [
                "Fixtures/README.md"
            ])
    ]
)
