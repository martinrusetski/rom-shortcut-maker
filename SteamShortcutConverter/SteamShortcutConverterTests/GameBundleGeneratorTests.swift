//
//  GameBundleGeneratorTests.swift
//  SteamShortcutConverterTests
//
//  Tests for the ROM-pipeline bundle path: template expansion, single-escaping,
//  bundle structure, and bundle-ID uniqueness.
//

import XCTest
@testable import SteamShortcutConverter

final class GameBundleGeneratorTests: XCTestCase {

    var generator: DefaultAppBundleGenerator!
    var tempDirectory: URL!

    override func setUpWithError() throws {
        generator = DefaultAppBundleGenerator()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GameBundleTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        generator = nil
        tempDirectory = nil
    }

    // MARK: - Template expansion

    func testStandaloneArgumentExpansion() throws {
        let command = try generator.buildLaunchCommand(
            emulator: URL(fileURLWithPath: "/Applications/Snes9x/bin/snes9x"),
            launchArguments: ["{romPath}"],
            rom: URL(fileURLWithPath: "/ROMs/game.sfc"),
            core: nil
        )
        XCTAssertEqual(command, "'/Applications/Snes9x/bin/snes9x' '/ROMs/game.sfc'")
    }

    func testRetroArchArgumentExpansion() throws {
        // Non-.app CLI binary path keeps the direct-exec form.
        let command = try generator.buildLaunchCommand(
            emulator: URL(fileURLWithPath: "/Applications/RetroArch/bin/retroarch"),
            launchArguments: ["-L", "{corePath}", "{romPath}"],
            rom: URL(fileURLWithPath: "/ROMs/game.sfc"),
            core: URL(fileURLWithPath: "/cores/snes9x_libretro.dylib")
        )
        XCTAssertEqual(
            command,
            "'/Applications/RetroArch/bin/retroarch' '-L' '/cores/snes9x_libretro.dylib' '/ROMs/game.sfc'"
        )
    }

    // MARK: - .app emulators launch via LaunchServices (open -a)

    func testAppBundleLaunchesViaOpen() throws {
        // A real .app emulator must be launched through `open -a` so it gets its
        // own app identity, not by exec'ing the inner Mach-O from our bundle.
        let command = try generator.buildLaunchCommand(
            emulator: URL(fileURLWithPath: "/Applications/RetroArch.app"),
            launchArguments: ["-L", "{corePath}", "{romPath}"],
            rom: URL(fileURLWithPath: "/ROMs/Crazy Taxi 2.chd"),
            core: URL(fileURLWithPath: "/cores/flycast_libretro.dylib")
        )
        XCTAssertEqual(
            command,
            "'/usr/bin/open' '-a' '/Applications/RetroArch.app' '--args' '-L' '/cores/flycast_libretro.dylib' '/ROMs/Crazy Taxi 2.chd'"
        )
    }

    func testAppBundleWithBarePositionalRom() throws {
        let command = try generator.buildLaunchCommand(
            emulator: URL(fileURLWithPath: "/Applications/Cemu.app"),
            launchArguments: ["-g", "{romPath}"],
            rom: URL(fileURLWithPath: "/ROMs/BOTW.wua"),
            core: nil
        )
        XCTAssertEqual(
            command,
            "'/usr/bin/open' '-a' '/Applications/Cemu.app' '--args' '-g' '/ROMs/BOTW.wua'"
        )
    }

    func testPointerFileContentsBecomeOneSafelyQuotedArgument() throws {
        let reference = tempDirectory.appendingPathComponent("Sonic Mania.ps4")
        try "CUSA07010\n".write(to: reference, atomically: true, encoding: .utf8)

        let command = try generator.buildLaunchCommand(
            emulator: URL(fileURLWithPath: "/Applications/shadPS4QtLauncher.app"),
            launchArguments: ["-d", "-g", "{romContents}"],
            rom: reference,
            core: nil
        )
        XCTAssertEqual(
            command,
            "'/usr/bin/open' '-a' '/Applications/shadPS4QtLauncher.app' '--args' '-d' '-g' 'CUSA07010'"
        )
    }

    // MARK: - Single-escaping correctness (exercised through a real shell)

    func testShellQuotingSurvivesNastyPaths() throws {
        let nastyPaths = [
            "/tmp/a b c.sfc",
            "/tmp/price $HOME.sfc",
            "/tmp/back`tick`.sfc",
            "/tmp/quote\".sfc",
            "/tmp/it's mine.sfc",
            "/tmp/all $x `y` \"z\" 's.sfc"
        ]
        for path in nastyPaths {
            let quoted = DefaultAppBundleGenerator.shellQuote(path)
            let echoed = try runBash("printf '%s' \(quoted)")
            XCTAssertEqual(echoed, path, "shell quoting failed for \(path)")
        }
    }

    private func runBash(_ script: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Bundle structure on disk

    func testGeneratesBundleStructure() async throws {
        let game = ResolvedGameBundle(
            bundleName: "Chrono Trigger",
            bundleIdentifier: "com.romshortcutmaker.chrono-trigger",
            displayName: "Chrono Trigger",
            executablePath: URL(fileURLWithPath: "/Applications/Snes9x/bin/snes9x"),
            launchArguments: ["{romPath}"],
            romPath: URL(fileURLWithPath: "/ROMs/Chrono Trigger.sfc"),
            outputDirectory: tempDirectory
        )
        let bundleURL = try await generator.generateAppBundle(for: game)

        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        let scriptURL = bundleURL.appendingPathComponent("Contents/MacOS/launch.sh")
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: scriptURL.path))

        let iconURL = bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconURL.path))
        XCTAssertEqual(String(data: try Data(contentsOf: iconURL).prefix(4), encoding: .ascii), "icns")

        let plist = try String(contentsOf: plistURL, encoding: .utf8)
        XCTAssertTrue(plist.contains("com.romshortcutmaker.chrono-trigger"))
        XCTAssertTrue(plist.contains("CFBundleIconFile"))
        XCTAssertTrue(plist.contains("AppIcon"))

        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        XCTAssertTrue(script.contains("'/Applications/Snes9x/bin/snes9x'"))
        XCTAssertTrue(script.contains("'/ROMs/Chrono Trigger.sfc'"))

        let attrs = try FileManager.default.attributesOfItem(atPath: scriptURL.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(perms & 0o777, 0o755)
    }

    // MARK: - .app executable resolution

    func testResolveExecutableFromAppBundle() throws {
        let app = tempDirectory.appendingPathComponent("Snes9x.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleExecutable": "snes9x-qt"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))

        let resolved = generator.resolveExecutable(app)
        XCTAssertEqual(resolved.lastPathComponent, "snes9x-qt")
        XCTAssertTrue(resolved.path.hasSuffix("Snes9x.app/Contents/MacOS/snes9x-qt"))
    }

    func testResolveExecutablePassesThroughNonApp() {
        let binary = URL(fileURLWithPath: "/opt/homebrew/bin/mgba")
        XCTAssertEqual(generator.resolveExecutable(binary), binary)
    }

    // MARK: - Bundle-ID uniqueness

    func testBundleIdentifierUniquenessOnTitleCollision() {
        let ids = DefaultAppBundleGenerator.bundleIdentifiers(for: [
            (title: "Chrono Trigger", stableKey: "aaaaaaaa1111"),
            (title: "Chrono Trigger", stableKey: "bbbbbbbb2222"),
            (title: "Secret of Mana", stableKey: "cccccccc3333")
        ])
        XCTAssertEqual(ids.count, 3)
        XCTAssertNotEqual(ids[0], ids[1])                        // collision disambiguated
        XCTAssertEqual(ids[2], "com.romshortcutmaker.secret-of-mana")  // unique title untouched
        XCTAssertEqual(Set(ids).count, 3)
    }
}
