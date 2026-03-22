//
//  ShortcutFilterTests.swift
//  SteamShortcutConverterTests
//
//  Unit tests for ShortcutFilter emulator detection
//

import XCTest
@testable import SteamShortcutConverter

final class ShortcutFilterTests: XCTestCase {
    
    var filter: DefaultShortcutFilter!
    
    override func setUp() {
        super.setUp()
        filter = DefaultShortcutFilter()
    }
    
    override func tearDown() {
        filter = nil
        super.tearDown()
    }
    
    // MARK: - RetroArch Detection Tests
    
    func testDetectRetroArchAppBundle() {
        let shortcut = SteamShortcut(
            appID: 1,
            appName: "Test Game",
            exe: "/Applications/RetroArch.app"
        )
        
        let detected = filter.detectEmulator(for: shortcut)
        XCTAssertEqual(detected, .retroArch, "Should detect RetroArch from .app bundle path")
    }
    
    func testDetectRetroArchDirectExecutable() {
        let shortcut = SteamShortcut(
            appID: 2,
            appName: "Test Game",
            exe: "/usr/local/bin/retroarch"
        )
        
        let detected = filter.detectEmulator(for: shortcut)
        XCTAssertEqual(detected, .retroArch, "Should detect RetroArch from direct executable path")
    }
    
    func testDetectRetroArchCaseInsensitive() {
        let shortcut = SteamShortcut(
            appID: 3,
            appName: "Test Game",
            exe: "/Applications/RETROARCH.APP"
        )
        
        let detected = filter.detectEmulator(for: shortcut)
        XCTAssertEqual(detected, .retroArch, "Should detect RetroArch with case-insensitive matching")
    }
    
    // MARK: - Dolphin Detection Tests
    
    func testDetectDolphinAppBundle() {
        let shortcut = SteamShortcut(
            appID: 4,
            appName: "Test Game",
            exe: "/Applications/Dolphin.app"
        )
        
        let detected = filter.detectEmulator(for: shortcut)
        XCTAssertEqual(detected, .dolphin, "Should detect Dolphin from .app bundle path")
    }
    
    func testDetectDolphinEmuVariant() {
        let shortcut = SteamShortcut(
            appID: 5,
            appName: "Test Game",
            exe: "/usr/local/bin/dolphin-emu"
        )
        
        let detected = filter.detectEmulator(for: shortcut)
        XCTAssertEqual(detected, .dolphin, "Should detect Dolphin from dolphin-emu executable")
    }
    
    // MARK: - PCSX2 Detection Tests
    
    func testDetectPCSX2AppBundle() {
        let shortcut = SteamShortcut(
            appID: 6,
            appName: "Test Game",
            exe: "/Applications/PCSX2.app"
        )
        
        let detected = filter.detectEmulator(for: shortcut)
        XCTAssertEqual(detected, .pcsx2, "Should detect PCSX2 from .app bundle path")
    }
    
    func testDetectPCSX2DirectExecutable() {
        let shortcut = SteamShortcut(
            appID: 7,
            appName: "Test Game",
            exe: "/usr/local/bin/pcsx2"
        )
        
        let detected = filter.detectEmulator(for: shortcut)
        XCTAssertEqual(detected, .pcsx2, "Should detect PCSX2 from direct executable path")
    }
    
    // MARK: - PPSSPP Detection Tests
    
    func testDetectPPSSPPAppBundle() {
        let shortcut = SteamShortcut(
            appID: 8,
            appName: "Test Game",
            exe: "/Applications/PPSSPP.app"
        )
        
        let detected = filter.detectEmulator(for: shortcut)
        XCTAssertEqual(detected, .ppsspp, "Should detect PPSSPP from .app bundle path")
    }
    
    // MARK: - Other Emulator Detection Tests
    
    func testDetectCitra() {
        let shortcut = SteamShortcut(
            appID: 9,
            appName: "Test Game",
            exe: "/Applications/Citra.app"
        )
        
        let detected = filter.detectEmulator(for: shortcut)
        XCTAssertEqual(detected, .citra, "Should detect Citra")
    }
    
    func testDetectRyujinx() {
        let shortcut = SteamShortcut(
            appID: 10,
            appName: "Test Game",
            exe: "/Applications/Ryujinx.app"
        )
        
        let detected = filter.detectEmulator(for: shortcut)
        XCTAssertEqual(detected, .ryujinx, "Should detect Ryujinx")
    }
    
    func testDetectMGBA() {
        let shortcut = SteamShortcut(
            appID: 11,
            appName: "Test Game",
            exe: "/usr/local/bin/mgba"
        )
        
        let detected = filter.detectEmulator(for: shortcut)
        XCTAssertEqual(detected, .mgba, "Should detect mGBA")
    }
    
    func testDetectDeSmuME() {
        let shortcut = SteamShortcut(
            appID: 12,
            appName: "Test Game",
            exe: "/Applications/DeSmuME.app"
        )
        
        let detected = filter.detectEmulator(for: shortcut)
        XCTAssertEqual(detected, .desmume, "Should detect DeSmuME")
    }
    
    func testDetectOpenEmu() {
        let shortcut = SteamShortcut(
            appID: 13,
            appName: "Test Game",
            exe: "/Applications/OpenEmu.app"
        )
        
        let detected = filter.detectEmulator(for: shortcut)
        XCTAssertEqual(detected, .openemu, "Should detect OpenEmu")
    }
    
    func testDetectYuzu() {
        let shortcut = SteamShortcut(
            appID: 14,
            appName: "Test Game",
            exe: "/Applications/Yuzu.app"
        )
        
        let detected = filter.detectEmulator(for: shortcut)
        XCTAssertEqual(detected, .yuzu, "Should detect Yuzu")
    }
    
    // MARK: - Non-Emulator Detection Tests
    
    func testNonEmulatorShortcutNotDetected() {
        let shortcut = SteamShortcut(
            appID: 15,
            appName: "Steam Game",
            exe: "/Applications/SomeGame.app"
        )
        
        let detected = filter.detectEmulator(for: shortcut)
        XCTAssertNil(detected, "Should not detect non-emulator shortcuts")
    }
    
    func testRegularApplicationNotDetected() {
        let shortcut = SteamShortcut(
            appID: 16,
            appName: "Regular App",
            exe: "/Applications/Safari.app"
        )
        
        let detected = filter.detectEmulator(for: shortcut)
        XCTAssertNil(detected, "Should not detect regular applications as emulators")
    }
    
    // MARK: - Filter ROM Shortcuts Tests
    
    func testFilterROMShortcuts() {
        let shortcuts = [
            SteamShortcut(appID: 1, appName: "ROM Game 1", exe: "/Applications/RetroArch.app"),
            SteamShortcut(appID: 2, appName: "Regular Game", exe: "/Applications/SomeGame.app"),
            SteamShortcut(appID: 3, appName: "ROM Game 2", exe: "/Applications/Dolphin.app"),
            SteamShortcut(appID: 4, appName: "Another App", exe: "/Applications/Safari.app"),
            SteamShortcut(appID: 5, appName: "ROM Game 3", exe: "/usr/local/bin/pcsx2")
        ]
        
        let filtered = filter.filterROMShortcuts(from: shortcuts)
        
        XCTAssertEqual(filtered.count, 3, "Should filter to only ROM-related shortcuts")
        XCTAssertTrue(filtered.contains { $0.appID == 1 }, "Should include RetroArch shortcut")
        XCTAssertTrue(filtered.contains { $0.appID == 3 }, "Should include Dolphin shortcut")
        XCTAssertTrue(filtered.contains { $0.appID == 5 }, "Should include PCSX2 shortcut")
        XCTAssertFalse(filtered.contains { $0.appID == 2 }, "Should not include non-emulator shortcut")
        XCTAssertFalse(filtered.contains { $0.appID == 4 }, "Should not include regular app shortcut")
    }
    
    func testFilterROMShortcutsEmptyArray() {
        let shortcuts: [SteamShortcut] = []
        let filtered = filter.filterROMShortcuts(from: shortcuts)
        
        XCTAssertTrue(filtered.isEmpty, "Should return empty array for empty input")
    }
    
    func testFilterROMShortcutsNoEmulators() {
        let shortcuts = [
            SteamShortcut(appID: 1, appName: "Game 1", exe: "/Applications/Game1.app"),
            SteamShortcut(appID: 2, appName: "Game 2", exe: "/Applications/Game2.app")
        ]
        
        let filtered = filter.filterROMShortcuts(from: shortcuts)
        
        XCTAssertTrue(filtered.isEmpty, "Should return empty array when no emulators detected")
    }
    
    // MARK: - Edge Case Tests
    
    func testDetectEmulatorWithComplexPath() {
        let shortcut = SteamShortcut(
            appID: 17,
            appName: "Test Game",
            exe: "/Users/username/Games/Emulators/RetroArch.app/Contents/MacOS/RetroArch"
        )
        
        let detected = filter.detectEmulator(for: shortcut)
        XCTAssertEqual(detected, .retroArch, "Should detect emulator in complex nested path")
    }
    
    func testDetectEmulatorWithSpacesInPath() {
        let shortcut = SteamShortcut(
            appID: 18,
            appName: "Test Game",
            exe: "/Applications/My Emulators/RetroArch.app"
        )
        
        let detected = filter.detectEmulator(for: shortcut)
        XCTAssertEqual(detected, .retroArch, "Should detect emulator in path with spaces")
    }
}
