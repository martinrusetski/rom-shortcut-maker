//
//  VDFToGameEntryBridgeTests.swift
//  RomShortcutMakerTests
//

import XCTest
@testable import RomShortcutMaker

final class VDFToGameEntryBridgeTests: XCTestCase {

    var bridge: VDFToGameEntryBridge!

    override func setUpWithError() throws {
        bridge = VDFToGameEntryBridge(database: try SystemDatabase())
    }

    override func tearDownWithError() throws {
        bridge = nil
    }

    func testMapsStandaloneShortcut() {
        let shortcut = SteamShortcut(
            appID: 1,
            appName: "Chrono Trigger",
            exe: "/Applications/Snes9x.app",
            startDir: nil,
            launchOptions: "\"/ROMs/Chrono Trigger.sfc\""
        )
        let entry = bridge.makeEntry(from: shortcut)
        XCTAssertEqual(entry?.title, "Chrono Trigger")
        XCTAssertEqual(entry?.emulator, .standalone(.snes9x))
        XCTAssertEqual(entry?.romPath.path, "/ROMs/Chrono Trigger.sfc")
        XCTAssertEqual(entry?.platform.id, "snes")
        XCTAssertEqual(entry?.source, .steamVDF)
    }

    func testMapsRetroArchShortcutExcludingCore() {
        let shortcut = SteamShortcut(
            appID: 2,
            appName: "Super Metroid",
            exe: "/Applications/RetroArch.app/Contents/MacOS/RetroArch",
            startDir: nil,
            launchOptions: "-L /cores/snes9x_libretro.dylib \"/ROMs/Super Metroid.sfc\""
        )
        let entry = bridge.makeEntry(from: shortcut)
        XCTAssertEqual(entry?.romPath.path, "/ROMs/Super Metroid.sfc")
        XCTAssertEqual(entry?.emulator, .standalone(.retroArch))
    }

    func testLegacyCustomNameReattaches() {
        let shortcut = SteamShortcut(
            appID: 42,
            appName: "Original Name",
            exe: "/Applications/Snes9x.app",
            startDir: nil,
            launchOptions: "\"/ROMs/Game.sfc\""
        )
        let entry = bridge.makeEntry(from: shortcut, legacyCustomNames: [42: "My Custom Name"])
        XCTAssertEqual(entry?.title, "My Custom Name")
    }

    func testNoRomArgumentReturnsNil() {
        let shortcut = SteamShortcut(
            appID: 3, appName: "No ROM", exe: "/Applications/Snes9x.app",
            startDir: nil, launchOptions: nil)
        XCTAssertNil(bridge.makeEntry(from: shortcut))
    }
}
