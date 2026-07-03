//
//  EmulatorDetectorTests.swift
//  SteamShortcutConverterTests
//
//  Hermetic tests for EmulatorDetector + EmulatorMatcher (fake filesystem).
//

import XCTest
@testable import SteamShortcutConverter

/// Fake filesystem lister for hermetic detection tests.
final class FakeAppDiscovering: AppDiscovering {
    var appsByDir: [String: [URL]] = [:]
    var executablesByDir: [String: [URL]] = [:]
    var filesByDir: [String: [URL]] = [:]
    var bundleExecutables: [String: String] = [:]   // app path -> CFBundleExecutable
    var fileContents: [String: String] = [:]         // file path -> text contents

    func appBundles(in directory: URL) -> [URL] { appsByDir[directory.path] ?? [] }
    func executables(in directory: URL) -> [URL] { executablesByDir[directory.path] ?? [] }
    func files(in directory: URL, withExtension ext: String) -> [URL] {
        (filesByDir[directory.path] ?? []).filter { $0.pathExtension.lowercased() == ext.lowercased() }
    }
    func infoPlistExecutable(for appBundle: URL) -> String? { bundleExecutables[appBundle.path] }
    func readText(at url: URL) -> String? { fileContents[url.path] }
}

final class EmulatorDetectorTests: XCTestCase {

    var database: SystemDatabase!
    let appsDir = URL(fileURLWithPath: "/FakeApps")
    let binDir = URL(fileURLWithPath: "/FakeBin")

    override func setUpWithError() throws {
        database = try SystemDatabase()
    }

    private func makeDetector(fs: FakeAppDiscovering) -> EmulatorDetector {
        EmulatorDetector(
            database: database,
            fs: fs,
            appSearchDirectories: [appsDir],
            binSearchDirectories: [binDir],
            extraCoreDirectories: []
        )
    }

    // MARK: - Strict matching

    func testStrictMatchRejectsSubstringFalsePositives() {
        XCTAssertFalse(EmulatorMatcher.matches(basename: "software", pattern: "ares"))
        XCTAssertFalse(EmulatorMatcher.matches(basename: "confuser", pattern: "fuse"))
        XCTAssertFalse(EmulatorMatcher.matches(basename: "clicker", pattern: "clk"))
    }

    func testStrictMatchAcceptsRealNames() {
        XCTAssertTrue(EmulatorMatcher.matches(basename: "RetroArch", pattern: "retroarch"))
        XCTAssertTrue(EmulatorMatcher.matches(basename: "dolphin-emu", pattern: "dolphin"))
        XCTAssertTrue(EmulatorMatcher.matches(basename: "snes9x", pattern: "snes9x"))
        XCTAssertTrue(EmulatorMatcher.matches(basename: "ares", pattern: "ares"))
    }

    // MARK: - App detection

    func testDetectAppViaBundleName() {
        let fs = FakeAppDiscovering()
        let snes9x = appsDir.appendingPathComponent("Snes9x.app")
        fs.appsByDir[appsDir.path] = [snes9x]
        let detector = makeDetector(fs: fs)
        XCTAssertEqual(detector.detectAll()[.snes9x], [snes9x])
    }

    func testDetectAppViaInfoPlistExecutable() {
        let fs = FakeAppDiscovering()
        // Bundle named ambiguously, but its CFBundleExecutable identifies it.
        let app = appsDir.appendingPathComponent("My Retro Frontend.app")
        fs.appsByDir[appsDir.path] = [app]
        fs.bundleExecutables[app.path] = "RetroArch"
        let detector = makeDetector(fs: fs)
        XCTAssertEqual(detector.detectAll()[.retroArch], [app])
    }

    func testAmbiguousAppNameDoesNotFalseMatch() {
        let fs = FakeAppDiscovering()
        let app = appsDir.appendingPathComponent("Software Updater.app")
        fs.appsByDir[appsDir.path] = [app]
        let detector = makeDetector(fs: fs)
        // "Software" must not match "ares".
        XCTAssertNil(detector.detectAll()[.ares])
    }

    func testDetectCliExecutable() {
        let fs = FakeAppDiscovering()
        fs.executablesByDir[binDir.path] = [binDir.appendingPathComponent("mgba")]
        let detector = makeDetector(fs: fs)
        XCTAssertEqual(detector.detectAll()[.mgba]?.first?.lastPathComponent, "mgba")
    }

    // MARK: - Core enumeration (via .info metadata)

    func testInstalledCoresMapViaInfoFiles() {
        let fs = FakeAppDiscovering()
        let retroArch = appsDir.appendingPathComponent("RetroArch.app")
        fs.appsByDir[appsDir.path] = [retroArch]
        let coresDir = retroArch.appendingPathComponent("Contents/Resources/cores")
        let infoDir = retroArch.appendingPathComponent("Contents/Resources/info")
        fs.filesByDir[coresDir.path] = [
            coresDir.appendingPathComponent("mednafen_saturn_libretro.dylib"),
            coresDir.appendingPathComponent("random.dylib")           // not a libretro core
        ]
        fs.fileContents[infoDir.appendingPathComponent("mednafen_saturn_libretro.info").path] = """
        display_name = "Sega - Saturn (Beetle Saturn)"
        systemid = "sega_saturn"
        """
        let detector = EmulatorDetector(
            database: database, fs: fs,
            appSearchDirectories: [appsDir], binSearchDirectories: [],
            extraCoreDirectories: [], extraInfoDirectories: [])

        let cores = detector.installedCores()
        XCTAssertEqual(cores.count, 1, "only *_libretro.dylib files count")
        XCTAssertEqual(cores.first?.filename, "mednafen_saturn_libretro.dylib")
        XCTAssertEqual(cores.first?.systemId, "sega_saturn")
        XCTAssertEqual(cores.first?.displayName, "Sega - Saturn (Beetle Saturn)")
    }

    // MARK: - Real Info.plist parsing (DefaultAppDiscovering)

    func testDefaultAppDiscoveringReadsRealInfoPlist() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("DetectorTests-\(UUID().uuidString)")
        let app = temp.appendingPathComponent("Cemu.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleExecutable": "Cemu"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        defer { try? FileManager.default.removeItem(at: temp) }

        let discovering = DefaultAppDiscovering()
        let bundles = discovering.appBundles(in: temp)
        XCTAssertEqual(bundles.map { $0.lastPathComponent }, ["Cemu.app"])
        XCTAssertEqual(discovering.infoPlistExecutable(for: app), "Cemu")
    }
}
