//
//  SystemDatabaseTests.swift
//  RomShortcutMakerTests
//
//  Unit tests for SystemDatabase (JSON-backed emulator/system knowledge base).
//

import XCTest
@testable import RomShortcutMaker

final class SystemDatabaseTests: XCTestCase {

    var database: SystemDatabase!

    override func setUpWithError() throws {
        database = try SystemDatabase()
    }

    override func tearDownWithError() throws {
        database = nil
    }

    // MARK: - Loading

    func testJSONLoadsFromBundle() throws {
        // If setUp succeeded, loading worked. Sanity-check content.
        XCTAssertFalse(database.allPlatforms.isEmpty)
        XCTAssertTrue(database.allPlatforms.contains(Platform(id: "snes", displayName: "SNES")))
    }

    // MARK: - Drift check

    func testEmulatorBlockIdentifiersMapToRealEmulatorTypes() {
        for id in database.emulatorBlockIdentifiers {
            XCTAssertNotNil(EmulatorType(rawValue: id), "emulators[] id '\(id)' has no EmulatorType")
        }
    }

    func testAllStandaloneOptionsMapToRealEmulatorTypes() {
        for platform in database.allPlatforms {
            for option in database.emulatorOptions(for: platform) {
                if case .standalone(let type) = option.choice {
                    // Round-trip proves the type is real (it decoded from the raw value).
                    XCTAssertNotNil(EmulatorType(rawValue: type.rawValue))
                }
            }
        }
    }

    func testInitThrowsOnUnknownEmulator() {
        let badJSON = """
        {
          "version": 1,
          "platforms": [
            { "id": "snes", "displayName": "SNES", "folderAliases": ["snes"],
              "romExtensions": [".sfc"],
              "emulatorOptions": [ { "type": "standalone", "emulator": "TotallyNotAnEmulator" } ] }
          ],
          "emulators": []
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try SystemDatabase(data: badJSON))
    }

    func testInitThrowsOnUnknownOptionType() {
        let badJSON = """
        {
          "version": 1,
          "platforms": [
            { "id": "snes", "displayName": "SNES", "folderAliases": ["snes"],
              "romExtensions": [".sfc"],
              "emulatorOptions": [ { "type": "quantumWarp", "emulator": "Snes9x" } ] }
          ],
          "emulators": []
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try SystemDatabase(data: badJSON))
    }

    // MARK: - Folder-name inference (primary signal)

    func testPlatformForFolderNameCaseInsensitiveAlias() {
        XCTAssertEqual(database.platform(forFolderName: "Super Nintendo")?.id, "snes")
        XCTAssertEqual(database.platform(forFolderName: "SNES")?.id, "snes")
        XCTAssertEqual(database.platform(forFolderName: "psx")?.id, "ps1")
    }

    func testPlatformForUnknownFolderName() {
        XCTAssertNil(database.platform(forFolderName: "Games"))
    }

    func testSegaModel2FolderAliasResolves() {
        // The user's real folder is literally "Sega Model 2 Arcade".
        XCTAssertEqual(database.platform(forFolderName: "Sega Model 2 Arcade")?.id, "sega-model2")
        XCTAssertEqual(database.platform(forFolderName: "model2")?.id, "sega-model2")
    }

    // MARK: - Extension inference (secondary signal, surfaces collisions)

    func testIsoExtensionSurfacesCollisions() {
        let ids = Set(database.platforms(forExtension: ".iso").map { $0.id })
        XCTAssertEqual(ids, ["gamecube", "wii", "ps2", "psp", "ps3", "xbox", "xbox360", "3do"])
    }

    func testExtensionMatchIsCaseInsensitiveAndDotTolerant() {
        let withDot = Set(database.platforms(forExtension: ".SFC").map { $0.id })
        let withoutDot = Set(database.platforms(forExtension: "sfc").map { $0.id })
        XCTAssertEqual(withDot, ["snes"])
        XCTAssertEqual(withoutDot, ["snes"])
    }

    func testMDSIsScanSupportedButPlatformNeutral() {
        XCTAssertTrue(database.allRomExtensions.contains(".mds"))
        XCTAssertTrue(database.platforms(forExtension: ".mds").isEmpty)
    }

    func testPerEmulatorFormatCompatibilityRules() {
        let options = database.emulatorOptions(for: Platform(id: "ps2", displayName: "PS2"))
        let pcsx2 = options.first { $0.choice == .standalone(.pcsx2) }
        let play = options.first { $0.choice == .standalone(.play) }
        XCTAssertTrue(pcsx2?.supports(extension: ".mds") == true)
        XCTAssertFalse(play?.supports(extension: ".mds") == true)
    }

    func testM3UCapabilityIsLimitedToVerifiedProfiles() {
        func option(_ choice: EmulatorChoice, platformID: String, name: String) -> EmulatorOption? {
            database.emulatorOptions(for: Platform(id: platformID, displayName: name))
                .first { $0.choice == choice }
        }

        XCTAssertTrue(option(.standalone(.dolphin), platformID: "gamecube", name: "GameCube")?.supportsM3U == true)
        XCTAssertTrue(option(.standalone(.duckstation), platformID: "ps1", name: "PS1")?.supportsM3U == true)
        XCTAssertTrue(option(.standalone(.mednafen), platformID: "saturn", name: "Saturn")?.supportsM3U == true)

        for candidate in [
            option(.standalone(.pcsx2), platformID: "ps2", name: "PS2"),
            option(.standalone(.ppsspp), platformID: "psp", name: "PSP"),
            option(.standalone(.ymir), platformID: "saturn", name: "Saturn"),
            option(.standalone(.flycast), platformID: "dreamcast", name: "Dreamcast")
        ] {
            XCTAssertFalse(candidate?.supportsM3U == true)
            XCTAssertFalse(candidate?.supports(extension: ".m3u") == true)
        }

        XCTAssertEqual(
            Set(database.platforms(forExtension: ".m3u").map(\.id)),
            ["gamecube", "ps1", "ps2", "psp", "saturn", "dreamcast"]
        )
    }

    func testZIPCompatibilityIsExplicitPerEmulator() {
        let snesOptions = database.emulatorOptions(for: Platform(id: "snes", displayName: "SNES"))
        let snes9x = snesOptions.first { $0.choice == .standalone(.snes9x) }
        let bsnes = snesOptions.first { $0.choice == .standalone(.bsnes) }
        XCTAssertTrue(snes9x?.supports(extension: ".zip") == true)
        XCTAssertFalse(bsnes?.supports(extension: ".zip") == true)

        let ps2Options = database.emulatorOptions(for: Platform(id: "ps2", displayName: "PS2"))
        let pcsx2 = ps2Options.first { $0.choice == .standalone(.pcsx2) }
        XCTAssertFalse(pcsx2?.supports(extension: ".zip") == true)
    }

    func testSingleFileZIPPlatformsAreExplicit() {
        XCTAssertTrue(database.supportsSingleFileZIP(for: Platform(id: "genesis", displayName: "Genesis")))
        XCTAssertFalse(database.supportsSingleFileZIP(for: Platform(id: "ps1", displayName: "PlayStation")))

        // Arcade ZIPs are ROM sets, not single compressed console ROMs, but MAME
        // still launches the archive directly.
        XCTAssertFalse(database.supportsSingleFileZIP(for: Platform(id: "arcade", displayName: "Arcade")))
        XCTAssertTrue(database.supportsZIPLaunch(for: Platform(id: "arcade", displayName: "Arcade")))
    }

    // MARK: - Emulator options

    func testSnesStandaloneOptions() {
        let snes = Platform(id: "snes", displayName: "SNES")
        let options = database.emulatorOptions(for: snes)
        // Cores are now discovered dynamically from installed .info files, so the
        // static DB carries only standalone emulators.
        XCTAssertTrue(options.contains { $0.choice == .standalone(.snes9x) })
        XCTAssertTrue(options.contains { $0.choice == .standalone(.bsnes) })
        XCTAssertEqual(options.first?.choice, .standalone(.snes9x))
        XCTAssertFalse(options.contains { if case .retroArchCore = $0.choice { return true }; return false })
    }

    func testLibretroSystemsMapping() {
        XCTAssertEqual(database.libretroSystems(for: Platform(id: "saturn", displayName: "Saturn")), ["sega_saturn"])
        XCTAssertEqual(database.libretroSystems(for: Platform(id: "snes", displayName: "SNES")), ["super_nes"])
        XCTAssertEqual(database.libretroSystems(for: Platform(id: "ps1", displayName: "PS1")), ["playstation"])
        XCTAssertTrue(database.libretroSystems(for: Platform(id: "switch", displayName: "Switch")).isEmpty)
        XCTAssertEqual(database.libretroSystems(for: Platform(id: "3do", displayName: "3DO")), ["3do"])
    }

    func testWiiUHasNoRetroArchOption() {
        let wiiu = Platform(id: "wiiu", displayName: "Wii U")
        let options = database.emulatorOptions(for: wiiu)
        XCTAssertFalse(options.isEmpty)
        for option in options {
            if case .retroArchCore = option.choice {
                XCTFail("wiiu should have no RetroArch core option")
            }
        }
    }

    func testPopularModernPlatformProfiles() throws {
        let xbox = try XCTUnwrap(database.allPlatforms.first { $0.id == "xbox" })
        XCTAssertEqual(
            database.launchArguments(for: .standalone(.xemu), platform: xbox),
            ["-dvd_path", "{romPath}"]
        )

        let xbox360 = try XCTUnwrap(database.allPlatforms.first { $0.id == "xbox360" })
        XCTAssertEqual(
            database.emulatorOptions(for: xbox360).map(\.choice),
            [.standalone(.xenios), .standalone(.xenia)]
        )

        let ps4 = try XCTUnwrap(database.allPlatforms.first { $0.id == "ps4" })
        XCTAssertEqual(
            database.launchArguments(for: .standalone(.shadps4QtLauncher), platform: ps4),
            ["-d", "-g", "{romContents}"]
        )
        XCTAssertEqual(
            database.launchArguments(for: .standalone(.shadps4), platform: ps4),
            ["-g", "{romContents}"]
        )

        let switchPlatform = try XCTUnwrap(database.allPlatforms.first { $0.id == "switch" })
        let switchChoices = database.emulatorOptions(for: switchPlatform).map(\.choice)
        XCTAssertEqual(switchChoices, [.standalone(.ryubing), .standalone(.astris)])

        let c64 = try XCTUnwrap(database.allPlatforms.first { $0.id == "c64" })
        XCTAssertEqual(
            database.launchArguments(for: .standalone(.vice), platform: c64),
            ["-autostart", "{romPath}"]
        )
    }

    func testVitaReferenceProfile() throws {
        let vita = try XCTUnwrap(database.allPlatforms.first { $0.id == "psvita" })
        XCTAssertEqual(
            database.launchArguments(for: .standalone(.vita3k), platform: vita),
            ["-r", "{romContents}"]
        )
    }

    // MARK: - Launch profiles

    func testRetroArchProfileContainsCorePlaceholder() {
        let arguments = database.launchArguments(
            for: .retroArchCore(core: "snes9x_libretro.dylib"),
            platform: Platform(id: "snes", displayName: "SNES")
        )
        XCTAssertTrue(arguments.contains("{corePath}"))
        XCTAssertTrue(arguments.contains("{romPath}"))
    }

    func testStandaloneProfileHasNoExecutableOrCorePlaceholder() {
        let arguments = database.launchArguments(
            for: .standalone(.snes9x),
            platform: Platform(id: "snes", displayName: "SNES")
        )
        XCTAssertFalse(arguments.contains("{corePath}"))
        XCTAssertFalse(arguments.contains("{emulator}"))
        XCTAssertTrue(arguments.contains("{romPath}"))
    }

    func testPlatformSpecificProfilesOverrideEmulatorDefaults() {
        XCTAssertEqual(
            database.launchArguments(
                for: .standalone(.dolphin),
                platform: Platform(id: "gamecube", displayName: "GameCube")
            ),
            ["-b", "-e", "{romPath}"]
        )
        XCTAssertEqual(
            database.launchArguments(
                for: .standalone(.mame),
                platform: Platform(id: "arcade", displayName: "Arcade")
            ),
            ["-rompath", "{romDirectory}", "{romStem}"]
        )
        XCTAssertEqual(
            database.launchArguments(
                for: .standalone(.ares),
                platform: Platform(id: "n64", displayName: "Nintendo 64")
            ),
            ["--fullscreen", "--system", "Nintendo 64", "{romPath}"]
        )
    }

    func testDOSFormatsAreExplicitPerBackend() throws {
        let dos = try XCTUnwrap(database.allPlatforms.first { $0.id == "dos" })
        let choices: [EmulatorType] = [.dosboxStaging, .dosboxX, .dosbox]

        for choice in choices {
            let option = try XCTUnwrap(
                database.emulatorOptions(for: dos).first { $0.choice == .standalone(choice) }
            )
            XCTAssertTrue(option.supports(extension: ".exe"))
            XCTAssertTrue(option.supports(extension: ".com"))
            XCTAssertTrue(option.supports(extension: ".bat"))
            XCTAssertTrue(option.supports(extension: ".conf"))
            XCTAssertFalse(option.supports(extension: ".dosz"))
        }
    }

    func testDOSBoxConfigurationUsesConfLaunchMode() {
        for choice in [EmulatorType.dosboxStaging, .dosboxX, .dosbox] {
            XCTAssertEqual(
                database.launchArguments(
                    for: .standalone(choice),
                    platform: Platform(id: "dos", displayName: "DOS"),
                    romExtension: ".conf"
                ),
                ["-conf", "{romPath}"]
            )
        }
    }

    func testAdditionalMaintainedMacProfiles() throws {
        let gb = try XCTUnwrap(database.allPlatforms.first { $0.id == "gb" })
        XCTAssertEqual(database.emulatorOptions(for: gb).first?.choice, .standalone(.skyemu))
        XCTAssertTrue(database.emulatorOptions(for: gb).first?.supports(extension: ".zip") == true)

        let ds = try XCTUnwrap(database.allPlatforms.first { $0.id == "nds" })
        XCTAssertTrue(database.supportsSingleFileZIP(for: ds))
        XCTAssertTrue(
            database.emulatorOptions(for: ds)
                .first { $0.choice == .standalone(.skyemu) }?
                .supports(extension: ".zip") == true
        )

        let saturn = try XCTUnwrap(database.allPlatforms.first { $0.id == "saturn" })
        XCTAssertEqual(database.emulatorOptions(for: saturn).first?.choice, .standalone(.ymir))

        let atariST = try XCTUnwrap(database.allPlatforms.first { $0.id == "atarist" })
        XCTAssertEqual(database.platform(forFolderName: "Atari ST"), atariST)
        XCTAssertEqual(
            database.launchArguments(for: .standalone(.hatari), platform: atariST),
            ["{romPath}"]
        )

        let scummVM = try XCTUnwrap(database.allPlatforms.first { $0.id == "scummvm" })
        XCTAssertEqual(
            database.launchArguments(for: .standalone(.scummvm), platform: scummVM),
            ["-f", "-p", "{romDirectory}", "{romContents}"]
        )

        let threeDO = try XCTUnwrap(database.allPlatforms.first { $0.id == "3do" })
        for ext in [".cue", ".chd", ".iso", ".bin"] {
            XCTAssertTrue(database.platforms(forExtension: ext).contains(threeDO))
        }
    }

    func testDOSOnlyGlobalExtensionDoesNotClaimHostExecutables() {
        XCTAssertEqual(database.platforms(forExtension: ".dosz").map(\.id), ["dos"])
        XCTAssertTrue(database.platforms(forExtension: ".exe").isEmpty)
        XCTAssertTrue(database.platforms(forExtension: ".bat").isEmpty)
        XCTAssertTrue(database.platforms(forExtension: ".conf").isEmpty)
    }

    // MARK: - Extension set

    func testAllRomExtensionsNormalized() {
        let exts = database.allRomExtensions
        XCTAssertTrue(exts.contains(".sfc"))
        XCTAssertTrue(exts.contains(".iso"))
        // All normalized with a leading dot, lowercase.
        for ext in exts {
            XCTAssertTrue(ext.hasPrefix("."))
            XCTAssertEqual(ext, ext.lowercased())
        }
    }
}
