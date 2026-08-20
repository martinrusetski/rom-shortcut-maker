//
//  RomConfigMigrationTests.swift
//  RomShortcutMakerTests
//

import XCTest
@testable import RomShortcutMaker

final class RomConfigMigrationTests: XCTestCase {

    func testMigrationFromV1CarriesScalars() {
        let v1 = AppConfiguration(
            shortcutsVDFPath: "/x/shortcuts.vdf",
            outputDirectory: "/Users/x/Games",
            selectedShortcutIDs: [1, 2],
            removeOrphanedBundles: true,
            lastConversionDate: Date(timeIntervalSince1970: 1000),
            customNames: [7: "Custom"]
        )
        let v2 = AppConfigurationV2.migrated(fromV1: v1)
        XCTAssertEqual(v2.version, 2)
        XCTAssertEqual(v2.sourceMode, "vdf")
        XCTAssertEqual(v2.outputDirectory, "/Users/x/Games")
        XCTAssertTrue(v2.removeOrphanedBundles)
        XCTAssertEqual(v2.lastConversionDate, Date(timeIntervalSince1970: 1000))
        XCTAssertEqual(v2.legacyCustomNames[7], "Custom")
        XCTAssertTrue(v2.watchedFolders.isEmpty)
        XCTAssertTrue(v2.gameOverrides.isEmpty)
    }

    func testStoreMigratesV1FileOnLoad() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MigrateTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Write a v1 config.json (no version field).
        let v1 = AppConfiguration(outputDirectory: "/Games", removeOrphanedBundles: true, customNames: [5: "Zelda"])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(v1).write(to: dir.appendingPathComponent("config.json"))

        let store = DefaultRomConfigStore(directory: dir)
        let loaded = try await store.load()
        XCTAssertEqual(loaded.version, 2)
        XCTAssertEqual(loaded.outputDirectory, "/Games")
        XCTAssertEqual(loaded.legacyCustomNames[5], "Zelda")
    }

    func testV2RoundTrip() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("V2Tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = DefaultRomConfigStore(directory: dir)
        var config = AppConfigurationV2(
            watchedFolders: ["/ROMs/Consoles", "/ROMs/Handhelds"],
            outputDirectory: "/Out",
            steamGridDBApiKey: "key"
        )
        config.gameOverrides["abc"] = GameOverride(customTitle: "T", emulator: .standalone(.snes9x))
        try await store.save(config)

        let reloaded = try await DefaultRomConfigStore(directory: dir).load()
        XCTAssertEqual(reloaded, config)
    }

    func testExcludedOnlyOverrideRoundTrips() throws {
        let override = GameOverride(excluded: true)
        let encoded = try JSONEncoder().encode(override)
        let decoded = try JSONDecoder().decode(GameOverride.self, from: encoded)
        XCTAssertEqual(decoded, override)
        XCTAssertEqual(decoded.excluded, true)
        // An override carrying only `excluded` is still non-empty, so the empty
        // cleanup in updateOverride keeps it around.
        XCTAssertNotEqual(override, GameOverride())
    }
}
