// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// This package exists for HEADLESS testing of the app's logic (`swift test`).
// The shippable macOS app is built from SteamShortcutConverter.xcodeproj.
//
// The library target compiles the same source files as the app target, EXCEPT
// `SteamShortcutConverterApp.swift` (the `@main` entry point), which can only be
// compiled in an executable context. Everything the tests touch — parsers,
// filters, generators, managers, view models — lives in this library, so the
// suite runs without launching the GUI.
let package = Package(
    name: "SteamShortcutConverter",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "SteamShortcutConverter",
            targets: ["SteamShortcutConverter"])
    ],
    targets: [
        .target(
            name: "SteamShortcutConverter",
            path: "SteamShortcutConverter",
            exclude: [
                "SteamShortcutConverterApp.swift"
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
