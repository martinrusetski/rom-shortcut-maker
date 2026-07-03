//
//  EmulatorConfigManagerTests.swift
//  SteamShortcutConverterTests
//
//  Tests for availability/default resolution and persistence.
//

import XCTest
@testable import SteamShortcutConverter

final class EmulatorConfigManagerTests: XCTestCase {

    var database: SystemDatabase!
    let appsDir = URL(fileURLWithPath: "/FakeApps")
    let binDir = URL(fileURLWithPath: "/FakeBin")

    let snes = Platform(id: "snes", displayName: "SNES")
    let wiiu = Platform(id: "wiiu", displayName: "Wii U")

    override func setUpWithError() throws {
        database = try SystemDatabase()
    }

    /// A detector where RetroArch + Snes9x are installed, and only the snes9x
    /// core is present (bsnes core is absent).
    private func makeStandardDetector() -> EmulatorDetector {
        let fs = FakeAppDiscovering()
        let retroArch = appsDir.appendingPathComponent("RetroArch.app")
        let snes9x = appsDir.appendingPathComponent("Snes9x.app")
        fs.appsByDir[appsDir.path] = [retroArch, snes9x]
        let coresDir = retroArch.appendingPathComponent("Contents/Resources/cores")
        fs.filesByDir[coresDir.path] = [coresDir.appendingPathComponent("snes9x_libretro.dylib")]
        return EmulatorDetector(
            database: database, fs: fs,
            appSearchDirectories: [appsDir], binSearchDirectories: [binDir],
            extraCoreDirectories: []
        )
    }

    private func makeEmptyDetector() -> EmulatorDetector {
        EmulatorDetector(
            database: database, fs: FakeAppDiscovering(),
            appSearchDirectories: [appsDir], binSearchDirectories: [binDir],
            extraCoreDirectories: []
        )
    }

    // MARK: - Availability

    func testAvailableOptionsIncludesStandaloneAndInstalledCoreExcludesAbsent() {
        let manager = EmulatorConfigManager(
            database: database, detector: makeStandardDetector(),
            store: InMemoryEmulatorConfigStore()
        )
        let choices = manager.availableOptions(for: snes).map { $0.choice }
        XCTAssertTrue(choices.contains(.standalone(.snes9x)))
        XCTAssertTrue(choices.contains(.retroArchCore(core: "snes9x_libretro.dylib")))
        XCTAssertFalse(choices.contains(.standalone(.bsnes)))                    // not installed
        XCTAssertFalse(choices.contains(.retroArchCore(core: "bsnes_libretro.dylib"))) // core absent
    }

    func testNothingInstalledYieldsNoOptionsAndNilDefault() {
        let manager = EmulatorConfigManager(
            database: database, detector: makeEmptyDetector(),
            store: InMemoryEmulatorConfigStore()
        )
        XCTAssertTrue(manager.availableOptions(for: wiiu).isEmpty)
        XCTAssertNil(manager.defaultChoice(for: wiiu))
    }

    func testDisablingEmulatorRemovesItFromAvailable() {
        let manager = EmulatorConfigManager(
            database: database, detector: makeStandardDetector(),
            store: InMemoryEmulatorConfigStore()
        )
        manager.setEnabled(false, for: .snes9x)
        XCTAssertFalse(manager.availableOptions(for: snes).contains { $0.choice == .standalone(.snes9x) })
    }

    func testConfiguredPathCountsAsInstalled() {
        let manager = EmulatorConfigManager(
            database: database, detector: makeEmptyDetector(),
            store: InMemoryEmulatorConfigStore()
        )
        // bsnes isn't detected, but the user configured a path.
        manager.setPath("/Applications/bsnes.app", for: .bsnes)
        XCTAssertTrue(manager.availableOptions(for: snes).contains { $0.choice == .standalone(.bsnes) })
    }

    // MARK: - Default choice

    func testDefaultChoiceFallsBackToFirstAvailable() {
        let manager = EmulatorConfigManager(
            database: database, detector: makeStandardDetector(),
            store: InMemoryEmulatorConfigStore()
        )
        // Order: Snes9x (installed) is first available.
        XCTAssertEqual(manager.defaultChoice(for: snes), .standalone(.snes9x))
    }

    func testDefaultChoiceHonorsConfiguredDefault() {
        let manager = EmulatorConfigManager(
            database: database, detector: makeStandardDetector(),
            store: InMemoryEmulatorConfigStore()
        )
        manager.setDefaultChoice(.retroArchCore(core: "snes9x_libretro.dylib"), for: snes)
        XCTAssertEqual(manager.defaultChoice(for: snes), .retroArchCore(core: "snes9x_libretro.dylib"))
    }

    func testConfiguredDefaultIgnoredWhenNotAvailable() {
        let manager = EmulatorConfigManager(
            database: database, detector: makeStandardDetector(),
            store: InMemoryEmulatorConfigStore()
        )
        // bsnes isn't installed, so a default pointing at it is ignored.
        manager.setDefaultChoice(.standalone(.bsnes), for: snes)
        XCTAssertEqual(manager.defaultChoice(for: snes), .standalone(.snes9x))
    }

    // MARK: - Resolution

    func testResolveStandalone() {
        let manager = EmulatorConfigManager(
            database: database, detector: makeStandardDetector(),
            store: InMemoryEmulatorConfigStore()
        )
        let resolved = manager.resolve(.standalone(.snes9x))
        XCTAssertEqual(resolved?.emulatorPath.lastPathComponent, "Snes9x.app")
        XCTAssertNil(resolved?.corePath)
        XCTAssertFalse(resolved?.argsTemplate.contains("{core}") ?? true)
    }

    func testResolveRetroArchCore() {
        let manager = EmulatorConfigManager(
            database: database, detector: makeStandardDetector(),
            store: InMemoryEmulatorConfigStore()
        )
        let resolved = manager.resolve(.retroArchCore(core: "snes9x_libretro.dylib"))
        XCTAssertEqual(resolved?.emulatorPath.lastPathComponent, "RetroArch.app")
        XCTAssertEqual(resolved?.corePath?.lastPathComponent, "snes9x_libretro.dylib")
        XCTAssertTrue(resolved?.argsTemplate.contains("{core}") ?? false)
    }

    func testResolveUnavailableReturnsNil() {
        let manager = EmulatorConfigManager(
            database: database, detector: makeEmptyDetector(),
            store: InMemoryEmulatorConfigStore()
        )
        XCTAssertNil(manager.resolve(.standalone(.snes9x)))
    }

    // MARK: - Persistence

    func testMutationsPersistAcrossManagers() {
        let store = InMemoryEmulatorConfigStore()
        let first = EmulatorConfigManager(
            database: database, detector: makeStandardDetector(), store: store
        )
        first.setEnabled(false, for: .snes9x)
        first.setDefaultChoice(.retroArchCore(core: "snes9x_libretro.dylib"), for: snes)

        let second = EmulatorConfigManager(
            database: database, detector: makeStandardDetector(), store: store
        )
        XCTAssertEqual(second.setting(for: .snes9x)?.enabled, false)
        XCTAssertEqual(second.defaultChoiceSetting(for: snes), .retroArchCore(core: "snes9x_libretro.dylib"))
    }

    func testFileStoreRoundTrip() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("emu-config-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = FileEmulatorConfigStore(fileURL: fileURL)
        var data = EmulatorConfigData()
        data.emulators["Snes9x"] = EmulatorSetting(path: "/Applications/Snes9x.app", enabled: true)
        data.defaults["snes"] = .standalone(.snes9x)
        store.save(data)

        let reloaded = FileEmulatorConfigStore(fileURL: fileURL).load()
        XCTAssertEqual(reloaded, data)
    }
}
