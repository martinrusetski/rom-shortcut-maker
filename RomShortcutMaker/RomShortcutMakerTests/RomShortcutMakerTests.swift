//
//  RomShortcutMakerTests.swift
//  RomShortcutMakerTests
//
//  Unit tests for Rom Shortcut Maker
//

import XCTest
@testable import RomShortcutMaker

final class RomShortcutMakerTests: XCTestCase {
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    // MARK: - Data Model Tests
    
    func testSteamShortcutInitialization() throws {
        let shortcut = SteamShortcut(
            appID: 12345,
            appName: "Test Game",
            exe: "/path/to/emulator",
            startDir: "/path/to/dir",
            launchOptions: "--fullscreen",
            icon: .filePath("/path/to/icon.png"),
            tags: ["ROM", "NES"]
        )
        
        XCTAssertEqual(shortcut.appID, 12345)
        XCTAssertEqual(shortcut.appName, "Test Game")
        XCTAssertEqual(shortcut.exe, "/path/to/emulator")
        XCTAssertEqual(shortcut.startDir, "/path/to/dir")
        XCTAssertEqual(shortcut.launchOptions, "--fullscreen")
        XCTAssertEqual(shortcut.tags, ["ROM", "NES"])
    }
    
    func testIconDataEmbedded() throws {
        let data = Data([0x01, 0x02, 0x03])
        let iconData = IconData.embedded(data)
        
        if case .embedded(let extractedData) = iconData {
            XCTAssertEqual(extractedData, data)
        } else {
            XCTFail("Expected embedded icon data")
        }
    }
    
    func testIconDataFilePath() throws {
        let path = "/path/to/icon.png"
        let iconData = IconData.filePath(path)
        
        if case .filePath(let extractedPath) = iconData {
            XCTAssertEqual(extractedPath, path)
        } else {
            XCTFail("Expected file path icon data")
        }
    }
    
    func testAppConfigurationDefault() throws {
        let config = AppConfiguration.default
        
        XCTAssertNil(config.shortcutsVDFPath)
        XCTAssertNil(config.outputDirectory)
        XCTAssertTrue(config.selectedShortcutIDs.isEmpty)
        XCTAssertFalse(config.removeOrphanedBundles)
        XCTAssertNil(config.lastConversionDate)
    }
    
    func testLaunchConfigurationInitialization() throws {
        let launchConfig = LaunchConfiguration(
            executablePath: "/Applications/RetroArch.app/Contents/MacOS/RetroArch",
            arguments: ["-L", "nestopia_libretro.dylib", "/path/to/game.nes"],
            workingDirectory: "/path/to/roms"
        )
        
        XCTAssertEqual(launchConfig.executablePath, "/Applications/RetroArch.app/Contents/MacOS/RetroArch")
        XCTAssertEqual(launchConfig.arguments.count, 3)
        XCTAssertEqual(launchConfig.workingDirectory, "/path/to/roms")
    }
    
    func testConvertedShortcutEquality() throws {
        let shortcut1 = ConvertedShortcut(
            appID: 123,
            appName: "Game",
            launchCommandHash: "abc123",
            iconHash: "def456",
            bundlePath: "/path/to/bundle"
        )
        
        let shortcut2 = ConvertedShortcut(
            appID: 123,
            appName: "Game",
            launchCommandHash: "abc123",
            iconHash: "def456",
            bundlePath: "/path/to/bundle"
        )
        
        XCTAssertEqual(shortcut1, shortcut2)
    }
    
    // MARK: - Emulator Type Tests
    
    func testEmulatorTypePatterns() throws {
        XCTAssertTrue(EmulatorType.retroArch.executablePatterns.contains("retroarch"))
        XCTAssertTrue(EmulatorType.dolphin.executablePatterns.contains("dolphin"))
        XCTAssertTrue(EmulatorType.ppsspp.executablePatterns.contains("ppsspp"))
    }
}
