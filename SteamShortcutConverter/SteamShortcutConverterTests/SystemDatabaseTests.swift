//
//  SystemDatabaseTests.swift
//  SteamShortcutConverterTests
//
//  Unit tests for SystemDatabase (JSON-backed emulator/system knowledge base).
//

import XCTest
@testable import SteamShortcutConverter

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
        XCTAssertEqual(ids, ["gamecube", "wii", "ps2", "psp", "ps3", "3do"])
    }

    func testExtensionMatchIsCaseInsensitiveAndDotTolerant() {
        let withDot = Set(database.platforms(forExtension: ".SFC").map { $0.id })
        let withoutDot = Set(database.platforms(forExtension: "sfc").map { $0.id })
        XCTAssertEqual(withDot, ["snes"])
        XCTAssertEqual(withoutDot, ["snes"])
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

    // MARK: - Args templates

    func testRetroArchTemplateContainsCorePlaceholder() {
        let template = database.argsTemplate(for: .retroArchCore(core: "snes9x_libretro.dylib"))
        XCTAssertTrue(template.contains("{core}"))
        XCTAssertTrue(template.contains("{rom}"))
    }

    func testStandaloneTemplateHasNoCorePlaceholder() {
        let template = database.argsTemplate(for: .standalone(.snes9x))
        XCTAssertFalse(template.contains("{core}"))
        XCTAssertTrue(template.contains("{emulator}"))
        XCTAssertTrue(template.contains("{rom}"))
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
