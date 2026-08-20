//
//  EmulatorConfigManagerTests.swift
//  RomShortcutMakerTests
//
//  Tests for availability/default resolution and persistence.
//

import XCTest
@testable import RomShortcutMaker

final class EmulatorConfigManagerTests: XCTestCase {

    var database: SystemDatabase!
    let appsDir = URL(fileURLWithPath: "/FakeApps")
    let binDir = URL(fileURLWithPath: "/FakeBin")

    let snes = Platform(id: "snes", displayName: "SNES")
    let ps2 = Platform(id: "ps2", displayName: "PS2")
    let wiiu = Platform(id: "wiiu", displayName: "Wii U")
    let dos = Platform(id: "dos", displayName: "DOS")

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
        let infoDir = retroArch.appendingPathComponent("Contents/Resources/info")
        fs.filesByDir[coresDir.path] = [coresDir.appendingPathComponent("snes9x_libretro.dylib")]
        fs.fileContents[infoDir.appendingPathComponent("snes9x_libretro.info").path] = """
        display_name = "Nintendo - SNES (Snes9x)"
        systemid = "super_nes"
        """
        return EmulatorDetector(
            database: database, fs: fs,
            appSearchDirectories: [appsDir], binSearchDirectories: [binDir],
            extraCoreDirectories: [], extraInfoDirectories: []
        )
    }

    private func makeEmptyDetector() -> EmulatorDetector {
        EmulatorDetector(
            database: database, fs: FakeAppDiscovering(),
            appSearchDirectories: [appsDir], binSearchDirectories: [binDir],
            extraCoreDirectories: [], extraInfoDirectories: []
        )
    }

    private func makeDOSDetector() -> EmulatorDetector {
        let fs = FakeAppDiscovering()
        let retroArch = appsDir.appendingPathComponent("RetroArch.app")
        let dosbox = appsDir.appendingPathComponent("DOSBox.app")
        fs.appsByDir[appsDir.path] = [retroArch, dosbox]
        let coresDir = retroArch.appendingPathComponent("Contents/Resources/cores")
        let infoDir = retroArch.appendingPathComponent("Contents/Resources/info")
        fs.filesByDir[coresDir.path] = [coresDir.appendingPathComponent("dosbox_pure_libretro.dylib")]
        fs.fileContents[infoDir.appendingPathComponent("dosbox_pure_libretro.info").path] = """
        display_name = "DOS (DOSBox-Pure)"
        systemid = "dos"
        supported_extensions = "zip|dosz|iso|cue|exe|com|bat"
        """
        return EmulatorDetector(
            database: database, fs: fs,
            appSearchDirectories: [appsDir], binSearchDirectories: [binDir],
            extraCoreDirectories: [], extraInfoDirectories: []
        )
    }

    private func makeThreeDODetector() -> EmulatorDetector {
        let fs = FakeAppDiscovering()
        let retroArch = appsDir.appendingPathComponent("RetroArch.app")
        fs.appsByDir[appsDir.path] = [retroArch]
        let coresDir = retroArch.appendingPathComponent("Contents/Resources/cores")
        let infoDir = retroArch.appendingPathComponent("Contents/Resources/info")
        fs.filesByDir[coresDir.path] = [coresDir.appendingPathComponent("opera_libretro.dylib")]
        fs.fileContents[infoDir.appendingPathComponent("opera_libretro.info").path] = """
        display_name = "The 3DO Company - 3DO (Opera)"
        systemid = "3do"
        supported_extensions = "iso|bin|chd|cue"
        """
        return EmulatorDetector(
            database: database, fs: fs,
            appSearchDirectories: [appsDir], binSearchDirectories: [binDir],
            extraCoreDirectories: [], extraInfoDirectories: []
        )
    }

    // MARK: - Availability

    func testSupportedOptionsIncludesMissingCuratedEmulators() {
        let manager = EmulatorConfigManager(
            database: database, detector: makeEmptyDetector(),
            store: InMemoryEmulatorConfigStore()
        )

        let choices = manager.supportedOptions(for: snes).map(\.choice)

        XCTAssertTrue(choices.contains(.standalone(.snes9x)))
        XCTAssertTrue(manager.availableOptions(for: snes).isEmpty)
    }

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

    func testZIPAvailabilityIncludesOnlyConfirmedOptions() {
        let manager = EmulatorConfigManager(
            database: database, detector: makeStandardDetector(),
            store: InMemoryEmulatorConfigStore()
        )

        let choices = manager.availableOptions(for: snes, romExtension: ".zip").map { $0.choice }
        XCTAssertTrue(choices.contains(.standalone(.snes9x)))
        XCTAssertTrue(choices.contains(.retroArchCore(core: "snes9x_libretro.dylib")))
    }

    func testZIPAvailabilityRejectsStandaloneWithoutExplicitSupport() {
        let manager = EmulatorConfigManager(
            database: database, detector: makeEmptyDetector(),
            store: InMemoryEmulatorConfigStore()
        )
        manager.setPath("/Applications/bsnes.app", for: .bsnes)

        XCTAssertTrue(manager.availableOptions(for: snes).contains { $0.choice == .standalone(.bsnes) })
        XCTAssertFalse(manager.availableOptions(for: snes, romExtension: ".zip").contains {
            $0.choice == .standalone(.bsnes)
        })
    }

    func testDOSBackendAvailabilityDependsOnActualFormatSupport() {
        let manager = EmulatorConfigManager(
            database: database, detector: makeDOSDetector(),
            store: InMemoryEmulatorConfigStore()
        )

        let archiveChoices = manager.availableOptions(for: dos, romExtension: ".dosz").map(\.choice)
        XCTAssertEqual(archiveChoices, [.retroArchCore(core: "dosbox_pure_libretro.dylib")])

        let configChoices = manager.availableOptions(for: dos, romExtension: ".conf").map(\.choice)
        XCTAssertEqual(configChoices, [.standalone(.dosbox)])
    }

    func testInstalledOperaCoreProvidesFormatAwareThreeDOSupport() {
        let threeDO = Platform(id: "3do", displayName: "3DO")
        let manager = EmulatorConfigManager(
            database: database, detector: makeThreeDODetector(),
            store: InMemoryEmulatorConfigStore()
        )
        let opera = EmulatorChoice.retroArchCore(core: "opera_libretro.dylib")

        XCTAssertEqual(manager.availableOptions(for: threeDO).map(\.choice), [opera])
        for ext in [".iso", ".bin", ".chd", ".cue"] {
            XCTAssertEqual(manager.availableOptions(for: threeDO, romExtension: ext).map(\.choice), [opera])
        }
        XCTAssertTrue(manager.availableOptions(for: threeDO, romExtension: ".mds").isEmpty)
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

    func testPCSX2AndARMSX2CanBeSelectedIndependently() {
        let fs = FakeAppDiscovering()
        let pcsx2 = appsDir.appendingPathComponent("PCSX2.app")
        let armsx2 = appsDir.appendingPathComponent("ARMSX2.app")
        fs.appsByDir[appsDir.path] = [pcsx2, armsx2]
        fs.bundleExecutables[pcsx2.path] = "pcsx2-qt"
        fs.bundleExecutables[armsx2.path] = "pcsx2-qt"
        let detector = EmulatorDetector(
            database: database, fs: fs,
            appSearchDirectories: [appsDir], binSearchDirectories: [binDir],
            extraCoreDirectories: [], extraInfoDirectories: []
        )
        let manager = EmulatorConfigManager(
            database: database, detector: detector,
            store: InMemoryEmulatorConfigStore()
        )

        let choices = manager.availableOptions(for: ps2).map { $0.choice }
        XCTAssertTrue(choices.contains(.standalone(.pcsx2)))
        XCTAssertTrue(choices.contains(.standalone(.armsx2)))
        XCTAssertEqual(manager.resolve(.standalone(.pcsx2), for: ps2)?.emulatorPath, pcsx2)
        XCTAssertEqual(manager.resolve(.standalone(.armsx2), for: ps2)?.emulatorPath, armsx2)
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
        let resolved = manager.resolve(.standalone(.snes9x), for: snes)
        XCTAssertEqual(resolved?.emulatorPath.lastPathComponent, "Snes9x.app")
        XCTAssertNil(resolved?.corePath)
        XCTAssertFalse(resolved?.launchArguments.contains("{corePath}") ?? true)
    }

    func testResolveRetroArchCore() {
        let manager = EmulatorConfigManager(
            database: database, detector: makeStandardDetector(),
            store: InMemoryEmulatorConfigStore()
        )
        let resolved = manager.resolve(
            .retroArchCore(core: "snes9x_libretro.dylib"),
            for: snes
        )
        XCTAssertEqual(resolved?.emulatorPath.lastPathComponent, "RetroArch.app")
        XCTAssertEqual(resolved?.corePath?.lastPathComponent, "snes9x_libretro.dylib")
        XCTAssertTrue(resolved?.launchArguments.contains("{corePath}") ?? false)
    }

    func testResolveUnavailableReturnsNil() {
        let manager = EmulatorConfigManager(
            database: database, detector: makeEmptyDetector(),
            store: InMemoryEmulatorConfigStore()
        )
        XCTAssertNil(manager.resolve(.standalone(.snes9x), for: snes))
    }

    func testResolveDOSBoxConfigurationUsesConfProfile() {
        let manager = EmulatorConfigManager(
            database: database, detector: makeDOSDetector(),
            store: InMemoryEmulatorConfigStore()
        )
        let resolved = manager.resolve(.standalone(.dosbox), for: dos, romExtension: ".conf")
        XCTAssertEqual(resolved?.launchArguments, ["-conf", "{romPath}"])
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
