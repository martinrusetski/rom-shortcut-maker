//
//  LaunchCommandParserTests.swift
//  SteamShortcutConverterTests
//
//  Unit tests for LaunchCommandParser
//

import XCTest
@testable import SteamShortcutConverter

final class LaunchCommandParserTests: XCTestCase {
    
    var parser: LaunchCommandParser!
    
    override func setUpWithError() throws {
        parser = LaunchCommandParser()
    }
    
    override func tearDownWithError() throws {
        parser = nil
    }
    
    // MARK: - Simple Launch Command Tests
    
    func testSimpleLaunchCommand() throws {
        // Test simple launch command extraction
        let shortcut = SteamShortcut(
            appID: 1,
            appName: "Test Game",
            exe: "/Applications/RetroArch.app/Contents/MacOS/RetroArch",
            startDir: nil,
            launchOptions: nil
        )
        
        let config = try parser.parseLaunchConfiguration(from: shortcut)
        
        XCTAssertEqual(config.executablePath, "/Applications/RetroArch.app/Contents/MacOS/RetroArch")
        XCTAssertTrue(config.arguments.isEmpty)
        XCTAssertNil(config.workingDirectory)
    }
    
    // MARK: - Complex Command with Multiple Arguments
    
    func testComplexCommandWithMultipleArguments() throws {
        // Test complex command with multiple arguments
        let shortcut = SteamShortcut(
            appID: 2,
            appName: "Complex Game",
            exe: "/Applications/RetroArch.app/Contents/MacOS/RetroArch",
            startDir: "/Users/test/roms",
            launchOptions: "-L nestopia_libretro.dylib --fullscreen --verbose"
        )
        
        let config = try parser.parseLaunchConfiguration(from: shortcut)
        
        XCTAssertEqual(config.executablePath, "/Applications/RetroArch.app/Contents/MacOS/RetroArch")
        XCTAssertEqual(config.arguments.count, 4)
        XCTAssertEqual(config.arguments[0], "-L")
        // Relative path with file extension should be resolved against working directory
        XCTAssertEqual(config.arguments[1], "/Users/test/roms/nestopia_libretro.dylib")
        XCTAssertEqual(config.arguments[2], "--fullscreen")
        XCTAssertEqual(config.arguments[3], "--verbose")
        XCTAssertEqual(config.workingDirectory, "/Users/test/roms")
    }
    
    // MARK: - RetroArch with Core Specification
    
    func testRetroArchWithCoreSpecification() throws {
        // Test RetroArch with core specification
        let shortcut = SteamShortcut(
            appID: 3,
            appName: "Super Mario Bros",
            exe: "/Applications/RetroArch.app/Contents/MacOS/RetroArch",
            startDir: nil,
            launchOptions: "-L /Applications/RetroArch.app/Contents/Resources/cores/nestopia_libretro.dylib /Users/test/roms/mario.nes"
        )
        
        let config = try parser.parseLaunchConfiguration(from: shortcut)
        
        XCTAssertEqual(config.executablePath, "/Applications/RetroArch.app/Contents/MacOS/RetroArch")
        XCTAssertEqual(config.arguments.count, 3)
        XCTAssertEqual(config.arguments[0], "-L")
        XCTAssertEqual(config.arguments[1], "/Applications/RetroArch.app/Contents/Resources/cores/nestopia_libretro.dylib")
        XCTAssertEqual(config.arguments[2], "/Users/test/roms/mario.nes")
    }
    
    // MARK: - Paths with Spaces
    
    func testPathsWithSpaces() throws {
        // Test paths with spaces (quoted)
        let shortcut = SteamShortcut(
            appID: 4,
            appName: "Game with Spaces",
            exe: "/Applications/My Emulator.app/Contents/MacOS/Emulator",
            startDir: "/Users/test/My ROMs",
            launchOptions: "\"/Users/test/My ROMs/Game Name.rom\" --config \"/Users/test/My Config/settings.cfg\""
        )
        
        let config = try parser.parseLaunchConfiguration(from: shortcut)
        
        XCTAssertEqual(config.executablePath, "/Applications/My Emulator.app/Contents/MacOS/Emulator")
        XCTAssertEqual(config.arguments.count, 3)
        XCTAssertEqual(config.arguments[0], "/Users/test/My ROMs/Game Name.rom")
        XCTAssertEqual(config.arguments[1], "--config")
        XCTAssertEqual(config.arguments[2], "/Users/test/My Config/settings.cfg")
        XCTAssertEqual(config.workingDirectory, "/Users/test/My ROMs")
    }
    
    func testPathsWithSpacesSingleQuotes() throws {
        // Test paths with spaces using single quotes
        let shortcut = SteamShortcut(
            appID: 5,
            appName: "Game with Single Quotes",
            exe: "/Applications/Emulator.app/Contents/MacOS/Emulator",
            startDir: nil,
            launchOptions: "'/Users/test/My ROMs/Game.rom' --fullscreen"
        )
        
        let config = try parser.parseLaunchConfiguration(from: shortcut)
        
        XCTAssertEqual(config.executablePath, "/Applications/Emulator.app/Contents/MacOS/Emulator")
        XCTAssertEqual(config.arguments.count, 2)
        XCTAssertEqual(config.arguments[0], "/Users/test/My ROMs/Game.rom")
        XCTAssertEqual(config.arguments[1], "--fullscreen")
    }
    
    // MARK: - Working Directory Extraction
    
    func testWorkingDirectoryExtraction() throws {
        // Test working directory extraction
        let shortcut = SteamShortcut(
            appID: 6,
            appName: "Game with WorkDir",
            exe: "/Applications/Emulator.app/Contents/MacOS/Emulator",
            startDir: "/Users/test/game_directory",
            launchOptions: "game.rom"
        )
        
        let config = try parser.parseLaunchConfiguration(from: shortcut)
        
        XCTAssertEqual(config.executablePath, "/Applications/Emulator.app/Contents/MacOS/Emulator")
        XCTAssertEqual(config.arguments.count, 1)
        // Relative path with file extension should be resolved against working directory
        XCTAssertEqual(config.arguments[0], "/Users/test/game_directory/game.rom")
        XCTAssertEqual(config.workingDirectory, "/Users/test/game_directory")
    }
    
    func testEmptyWorkingDirectory() throws {
        // Test empty working directory is treated as nil
        let shortcut = SteamShortcut(
            appID: 7,
            appName: "Game with Empty WorkDir",
            exe: "/Applications/Emulator.app/Contents/MacOS/Emulator",
            startDir: "   ",
            launchOptions: "game.rom"
        )
        
        let config = try parser.parseLaunchConfiguration(from: shortcut)
        
        XCTAssertNil(config.workingDirectory)
    }
    
    // MARK: - Edge Cases
    
    func testEmptyLaunchOptions() throws {
        // Test empty launch options
        let shortcut = SteamShortcut(
            appID: 8,
            appName: "Game with No Options",
            exe: "/Applications/Emulator.app/Contents/MacOS/Emulator",
            startDir: nil,
            launchOptions: ""
        )
        
        let config = try parser.parseLaunchConfiguration(from: shortcut)
        
        XCTAssertTrue(config.arguments.isEmpty)
    }
    
    func testWhitespaceOnlyLaunchOptions() throws {
        // Test whitespace-only launch options
        let shortcut = SteamShortcut(
            appID: 9,
            appName: "Game with Whitespace Options",
            exe: "/Applications/Emulator.app/Contents/MacOS/Emulator",
            startDir: nil,
            launchOptions: "   \t  \n  "
        )
        
        let config = try parser.parseLaunchConfiguration(from: shortcut)
        
        XCTAssertTrue(config.arguments.isEmpty)
    }
    
    func testEmptyExecutablePath() throws {
        // Test empty executable path throws error
        let shortcut = SteamShortcut(
            appID: 10,
            appName: "Invalid Game",
            exe: "",
            startDir: nil,
            launchOptions: nil
        )
        
        XCTAssertThrowsError(try parser.parseLaunchConfiguration(from: shortcut)) { error in
            XCTAssertTrue(error is LaunchCommandParserError)
            if case LaunchCommandParserError.emptyExecutablePath = error {
                // Expected error
            } else {
                XCTFail("Expected emptyExecutablePath error")
            }
        }
    }
    
    // MARK: - Special Characters and Escaping
    
    func testEscapedQuotes() throws {
        // Test escaped quotes in arguments
        let shortcut = SteamShortcut(
            appID: 11,
            appName: "Game with Escaped Quotes",
            exe: "/Applications/Emulator.app/Contents/MacOS/Emulator",
            startDir: nil,
            launchOptions: "--title \"Game \\\"Title\\\" Here\" --verbose"
        )
        
        let config = try parser.parseLaunchConfiguration(from: shortcut)
        
        XCTAssertEqual(config.arguments.count, 3)
        XCTAssertEqual(config.arguments[0], "--title")
        XCTAssertEqual(config.arguments[1], "Game \"Title\" Here")
        XCTAssertEqual(config.arguments[2], "--verbose")
    }
    
    func testMixedQuotes() throws {
        // Test mixed quote types
        let shortcut = SteamShortcut(
            appID: 12,
            appName: "Game with Mixed Quotes",
            exe: "/Applications/Emulator.app/Contents/MacOS/Emulator",
            startDir: nil,
            launchOptions: "--arg1 \"value with 'single' quotes\" --arg2 'value with \"double\" quotes'"
        )
        
        let config = try parser.parseLaunchConfiguration(from: shortcut)
        
        XCTAssertEqual(config.arguments.count, 4)
        XCTAssertEqual(config.arguments[0], "--arg1")
        XCTAssertEqual(config.arguments[1], "value with 'single' quotes")
        XCTAssertEqual(config.arguments[2], "--arg2")
        XCTAssertEqual(config.arguments[3], "value with \"double\" quotes")
    }
    
    func testArgumentOrderPreservation() throws {
        // Test that argument order is preserved exactly
        let shortcut = SteamShortcut(
            appID: 13,
            appName: "Order Test",
            exe: "/Applications/Emulator.app/Contents/MacOS/Emulator",
            startDir: nil,
            launchOptions: "first second third fourth fifth"
        )
        
        let config = try parser.parseLaunchConfiguration(from: shortcut)
        
        XCTAssertEqual(config.arguments.count, 5)
        XCTAssertEqual(config.arguments[0], "first")
        XCTAssertEqual(config.arguments[1], "second")
        XCTAssertEqual(config.arguments[2], "third")
        XCTAssertEqual(config.arguments[3], "fourth")
        XCTAssertEqual(config.arguments[4], "fifth")
    }
    
    // MARK: - Path Handling Tests
    
    func testAbsolutePathHandling() throws {
        // Test that absolute paths are preserved
        let shortcut = SteamShortcut(
            appID: 14,
            appName: "Absolute Path Test",
            exe: "/Applications/RetroArch.app/Contents/MacOS/RetroArch",
            startDir: nil,
            launchOptions: "-L /Applications/RetroArch.app/Contents/Resources/cores/snes9x_libretro.dylib /Users/test/roms/game.sfc"
        )
        
        let config = try parser.parseLaunchConfiguration(from: shortcut)
        
        XCTAssertEqual(config.executablePath, "/Applications/RetroArch.app/Contents/MacOS/RetroArch")
        XCTAssertEqual(config.arguments[0], "-L")
        XCTAssertEqual(config.arguments[1], "/Applications/RetroArch.app/Contents/Resources/cores/snes9x_libretro.dylib")
        XCTAssertEqual(config.arguments[2], "/Users/test/roms/game.sfc")
    }
    
    func testRelativePathResolution() throws {
        // Test that relative paths are resolved against working directory
        let shortcut = SteamShortcut(
            appID: 15,
            appName: "Relative Path Test",
            exe: "/Applications/Emulator.app/Contents/MacOS/Emulator",
            startDir: "/Users/test/games",
            launchOptions: "roms/game.rom saves/save.sav"
        )
        
        let config = try parser.parseLaunchConfiguration(from: shortcut)
        
        XCTAssertEqual(config.executablePath, "/Applications/Emulator.app/Contents/MacOS/Emulator")
        XCTAssertEqual(config.arguments[0], "/Users/test/games/roms/game.rom")
        XCTAssertEqual(config.arguments[1], "/Users/test/games/saves/save.sav")
        XCTAssertEqual(config.workingDirectory, "/Users/test/games")
    }
    
    func testTildeExpansion() throws {
        // Test that tilde paths are expanded
        let shortcut = SteamShortcut(
            appID: 16,
            appName: "Tilde Path Test",
            exe: "~/Applications/Emulator.app/Contents/MacOS/Emulator",
            startDir: nil,
            launchOptions: "~/Documents/roms/game.rom"
        )
        
        let config = try parser.parseLaunchConfiguration(from: shortcut)
        
        // Verify tilde was expanded (should not start with ~)
        XCTAssertFalse(config.executablePath.hasPrefix("~"))
        XCTAssertTrue(config.executablePath.hasPrefix("/"))
        XCTAssertFalse(config.arguments[0].hasPrefix("~"))
        XCTAssertTrue(config.arguments[0].hasPrefix("/"))
    }
    
    func testMixedAbsoluteAndRelativePaths() throws {
        // Test mixed absolute and relative paths
        let shortcut = SteamShortcut(
            appID: 17,
            appName: "Mixed Paths Test",
            exe: "/Applications/RetroArch.app/Contents/MacOS/RetroArch",
            startDir: "/Users/test/roms",
            launchOptions: "-L /Applications/RetroArch.app/Contents/Resources/cores/nestopia_libretro.dylib mario.nes"
        )
        
        let config = try parser.parseLaunchConfiguration(from: shortcut)
        
        XCTAssertEqual(config.executablePath, "/Applications/RetroArch.app/Contents/MacOS/RetroArch")
        XCTAssertEqual(config.arguments[0], "-L")
        // Absolute path should remain absolute
        XCTAssertEqual(config.arguments[1], "/Applications/RetroArch.app/Contents/Resources/cores/nestopia_libretro.dylib")
        // Relative path should be resolved
        XCTAssertEqual(config.arguments[2], "/Users/test/roms/mario.nes")
    }
    
    func testRelativePathWithoutWorkingDirectory() throws {
        // Test that relative paths without working directory are preserved
        let shortcut = SteamShortcut(
            appID: 18,
            appName: "Relative No WorkDir Test",
            exe: "/Applications/Emulator.app/Contents/MacOS/Emulator",
            startDir: nil,
            launchOptions: "game.rom"
        )
        
        let config = try parser.parseLaunchConfiguration(from: shortcut)
        
        XCTAssertEqual(config.executablePath, "/Applications/Emulator.app/Contents/MacOS/Emulator")
        // Without working directory, relative path should be preserved as-is
        XCTAssertEqual(config.arguments[0], "game.rom")
    }
    
    // MARK: - RetroArch Core Detection Tests
    
    func testDetectRetroArchCoreWithDashL() throws {
        // Test RetroArch core detection with -L flag
        let shortcut = SteamShortcut(
            appID: 19,
            appName: "RetroArch Core Test",
            exe: "/Applications/RetroArch.app/Contents/MacOS/RetroArch",
            startDir: nil,
            launchOptions: "-L /Applications/RetroArch.app/Contents/Resources/cores/snes9x_libretro.dylib /Users/test/roms/game.sfc"
        )
        
        let config = try parser.parseLaunchConfiguration(from: shortcut)
        let corePath = parser.detectRetroArchCore(in: config)
        
        XCTAssertNotNil(corePath)
        XCTAssertEqual(corePath, "/Applications/RetroArch.app/Contents/Resources/cores/snes9x_libretro.dylib")
    }
    
    func testDetectRetroArchCoreWithLongFlag() throws {
        // Test RetroArch core detection with --libretro flag
        let shortcut = SteamShortcut(
            appID: 20,
            appName: "RetroArch Long Flag Test",
            exe: "/Applications/RetroArch.app/Contents/MacOS/RetroArch",
            startDir: nil,
            launchOptions: "--libretro nestopia_libretro.dylib game.nes"
        )
        
        let config = try parser.parseLaunchConfiguration(from: shortcut)
        let corePath = parser.detectRetroArchCore(in: config)
        
        XCTAssertNotNil(corePath)
        XCTAssertTrue(corePath?.contains("nestopia_libretro.dylib") ?? false)
    }
    
    func testDetectRetroArchCoreNotPresent() throws {
        // Test that non-RetroArch shortcuts return nil
        let shortcut = SteamShortcut(
            appID: 21,
            appName: "Non-RetroArch Test",
            exe: "/Applications/Dolphin.app/Contents/MacOS/Dolphin",
            startDir: nil,
            launchOptions: "-e /Users/test/roms/game.iso"
        )
        
        let config = try parser.parseLaunchConfiguration(from: shortcut)
        let corePath = parser.detectRetroArchCore(in: config)
        
        XCTAssertNil(corePath)
    }
    
    func testDetectRetroArchWithoutCore() throws {
        // Test RetroArch without core specification
        let shortcut = SteamShortcut(
            appID: 22,
            appName: "RetroArch No Core Test",
            exe: "/Applications/RetroArch.app/Contents/MacOS/RetroArch",
            startDir: nil,
            launchOptions: "--fullscreen --verbose"
        )
        
        let config = try parser.parseLaunchConfiguration(from: shortcut)
        let corePath = parser.detectRetroArchCore(in: config)
        
        XCTAssertNil(corePath)
    }
    
    func testIsRetroArchExecutable() throws {
        // Test RetroArch executable detection
        XCTAssertTrue(parser.isRetroArchExecutable("/Applications/RetroArch.app/Contents/MacOS/RetroArch"))
        XCTAssertTrue(parser.isRetroArchExecutable("/usr/local/bin/retroarch"))
        XCTAssertTrue(parser.isRetroArchExecutable("/opt/RetroArch/retroarch"))
        XCTAssertFalse(parser.isRetroArchExecutable("/Applications/Dolphin.app/Contents/MacOS/Dolphin"))
        XCTAssertFalse(parser.isRetroArchExecutable("/usr/bin/emulator"))
    }
    
    func testRetroArchCoreWithRelativePath() throws {
        // Test RetroArch core with relative path resolution
        let shortcut = SteamShortcut(
            appID: 23,
            appName: "RetroArch Relative Core Test",
            exe: "/Applications/RetroArch.app/Contents/MacOS/RetroArch",
            startDir: "/Users/test/retroarch",
            launchOptions: "-L cores/genesis_plus_gx_libretro.dylib roms/sonic.md"
        )
        
        let config = try parser.parseLaunchConfiguration(from: shortcut)
        let corePath = parser.detectRetroArchCore(in: config)
        
        XCTAssertNotNil(corePath)
        // Core path should be resolved to absolute path
        XCTAssertEqual(corePath, "/Users/test/retroarch/cores/genesis_plus_gx_libretro.dylib")
    }
}
