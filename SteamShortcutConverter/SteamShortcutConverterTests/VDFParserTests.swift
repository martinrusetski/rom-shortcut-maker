//
//  VDFParserTests.swift
//  SteamShortcutConverterTests
//
//  Comprehensive unit tests for VDF parser pipeline
//  Tests Requirements: 2.1, 2.2, 2.3, 2.5
//

import XCTest
@testable import SteamShortcutConverter

final class VDFParserTests: XCTestCase {
    
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        
        // Create a temporary directory for test files
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        super.tearDown()
    }
    
    // MARK: - Test Parsing Sample shortcuts.vdf with Known Shortcuts
    
    func testParseSampleShortcutsVDFWithKnownShortcuts() throws {
        // Create a realistic shortcuts.vdf with multiple known shortcuts
        let vdfData = createSampleShortcutsVDF()
        
        // Parse the VDF
        let reader = BinaryVDFReader(data: vdfData)
        let vdfDict = try reader.read()
        
        let parser = ShortcutParser()
        let shortcuts = try parser.parseShortcuts(from: vdfDict)
        
        // Verify we got all shortcuts
        XCTAssertEqual(shortcuts.count, 3, "Should parse all 3 shortcuts")
        
        // Verify first shortcut (Super Mario 64)
        let mario = shortcuts[0]
        XCTAssertEqual(mario.appID, 2147483647)
        XCTAssertEqual(mario.appName, "Super Mario 64")
        XCTAssertEqual(mario.exe, "/Applications/RetroArch.app/Contents/MacOS/RetroArch")
        XCTAssertEqual(mario.startDir, "/Applications/RetroArch.app/Contents/MacOS")
        XCTAssertEqual(mario.launchOptions, "-L \"/Users/user/cores/mupen64plus_libretro.dylib\" \"/Users/user/ROMs/N64/Super Mario 64.z64\"")
        XCTAssertEqual(mario.tags, ["Nintendo 64", "Platform", "Favorite"])
        
        // Verify second shortcut (Zelda)
        let zelda = shortcuts[1]
        XCTAssertEqual(zelda.appID, 2147483646)
        XCTAssertEqual(zelda.appName, "The Legend of Zelda: Ocarina of Time")
        XCTAssertEqual(zelda.exe, "/Applications/RetroArch.app/Contents/MacOS/RetroArch")
        XCTAssertEqual(zelda.launchOptions, "-L \"/Users/user/cores/mupen64plus_libretro.dylib\" \"/Users/user/ROMs/N64/Zelda OOT.z64\"")
        
        // Verify third shortcut (Metroid Prime)
        let metroid = shortcuts[2]
        XCTAssertEqual(metroid.appID, 2147483645)
        XCTAssertEqual(metroid.appName, "Metroid Prime")
        XCTAssertEqual(metroid.exe, "/Applications/Dolphin.app/Contents/MacOS/Dolphin")
        XCTAssertEqual(metroid.launchOptions, "-e \"/Users/user/ROMs/GameCube/Metroid Prime.iso\"")
    }
    
    // MARK: - Test Embedded Icon Data Extraction
    
    func testEmbeddedIconDataExtraction() throws {
        // Create VDF with embedded icon data
        // Note: The binary VDF format stores embedded icons differently than file paths
        // We'll test the parser's ability to handle Data objects in the dictionary
        let iconData = Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52  // IHDR chunk start
        ])
        
        // Create a dictionary directly (simulating what BinaryVDFReader would produce)
        let vdfDict: [String: Any] = [
            "shortcuts": [
                "0": [
                    "appid": Int32(12345),
                    "AppName": "Test Game",
                    "Exe": "/test/exe",
                    "icon": iconData  // Embedded as Data
                ] as [String: Any]
            ]
        ]
        
        let parser = ShortcutParser()
        let shortcuts = try parser.parseShortcuts(from: vdfDict)
        
        XCTAssertEqual(shortcuts.count, 1)
        
        // Verify embedded icon data
        if case .embedded(let extractedData) = shortcuts[0].icon {
            XCTAssertEqual(extractedData, iconData, "Embedded icon data should match")
        } else {
            XCTFail("Expected embedded icon data")
        }
    }
    
    func testEmbeddedIconDataWithLargeImage() throws {
        // Create a larger embedded icon (simulating a real PNG)
        let iconData = Data(repeating: 0xAB, count: 1024) // 1KB of data
        
        // Create a dictionary directly
        let vdfDict: [String: Any] = [
            "shortcuts": [
                "0": [
                    "appid": Int32(12345),
                    "AppName": "Test Game",
                    "Exe": "/test/exe",
                    "icon": iconData
                ] as [String: Any]
            ]
        ]
        
        let parser = ShortcutParser()
        let shortcuts = try parser.parseShortcuts(from: vdfDict)
        
        XCTAssertEqual(shortcuts.count, 1)
        
        if case .embedded(let extractedData) = shortcuts[0].icon {
            XCTAssertEqual(extractedData.count, 1024)
            XCTAssertEqual(extractedData, iconData)
        } else {
            XCTFail("Expected embedded icon data")
        }
    }
    
    // MARK: - Test Icon File Path Extraction
    
    func testIconFilePathExtraction() throws {
        // Create VDF with icon file path
        let iconPath = "/Users/user/Library/Application Support/Steam/userdata/12345/config/grid/2147483647p.png"
        let vdfData = createVDFWithIconPath(iconPath: iconPath)
        
        let reader = BinaryVDFReader(data: vdfData)
        let vdfDict = try reader.read()
        
        let parser = ShortcutParser()
        let shortcuts = try parser.parseShortcuts(from: vdfDict)
        
        XCTAssertEqual(shortcuts.count, 1)
        
        // Verify icon file path
        if case .filePath(let extractedPath) = shortcuts[0].icon {
            XCTAssertEqual(extractedPath, iconPath)
        } else {
            XCTFail("Expected filePath icon")
        }
    }
    
    func testIconFilePathWithSpecialCharacters() throws {
        // Test icon path with spaces and special characters
        let iconPath = "/Users/user name/Steam/grid/Game (USA) [v1.2].png"
        let vdfData = createVDFWithIconPath(iconPath: iconPath)
        
        let reader = BinaryVDFReader(data: vdfData)
        let vdfDict = try reader.read()
        
        let parser = ShortcutParser()
        let shortcuts = try parser.parseShortcuts(from: vdfDict)
        
        XCTAssertEqual(shortcuts.count, 1)
        
        if case .filePath(let extractedPath) = shortcuts[0].icon {
            XCTAssertEqual(extractedPath, iconPath)
        } else {
            XCTFail("Expected filePath icon")
        }
    }
    
    func testMissingIconHandling() throws {
        // Create VDF without icon field
        let vdfData = createVDFWithoutIcon()
        
        let reader = BinaryVDFReader(data: vdfData)
        let vdfDict = try reader.read()
        
        let parser = ShortcutParser()
        let shortcuts = try parser.parseShortcuts(from: vdfDict)
        
        XCTAssertEqual(shortcuts.count, 1)
        XCTAssertNil(shortcuts[0].icon, "Missing icon should result in nil")
    }
    
    // MARK: - Test RetroArch Shortcuts with Core Arguments
    
    func testRetroArchShortcutWithCoreArguments() throws {
        // Create VDF with RetroArch shortcut including core specification
        let vdfData = createRetroArchShortcut(
            corePath: "/Users/user/Library/Application Support/RetroArch/cores/snes9x_libretro.dylib",
            romPath: "/Users/user/ROMs/SNES/Super Metroid.sfc"
        )
        
        let reader = BinaryVDFReader(data: vdfData)
        let vdfDict = try reader.read()
        
        let parser = ShortcutParser()
        let shortcuts = try parser.parseShortcuts(from: vdfDict)
        
        XCTAssertEqual(shortcuts.count, 1)
        
        let shortcut = shortcuts[0]
        XCTAssertTrue(shortcut.exe.contains("RetroArch"))
        XCTAssertNotNil(shortcut.launchOptions)
        XCTAssertTrue(shortcut.launchOptions!.contains("-L"))
        XCTAssertTrue(shortcut.launchOptions!.contains("snes9x_libretro.dylib"))
        XCTAssertTrue(shortcut.launchOptions!.contains("Super Metroid.sfc"))
    }
    
    func testRetroArchShortcutWithMultipleCores() throws {
        // Test parsing multiple RetroArch shortcuts with different cores
        let vdfData = createMultipleRetroArchShortcuts()
        
        let reader = BinaryVDFReader(data: vdfData)
        let vdfDict = try reader.read()
        
        let parser = ShortcutParser()
        let shortcuts = try parser.parseShortcuts(from: vdfDict)
        
        XCTAssertEqual(shortcuts.count, 3)
        
        // Verify each has different core
        XCTAssertTrue(shortcuts[0].launchOptions!.contains("mupen64plus_libretro.dylib"))
        XCTAssertTrue(shortcuts[1].launchOptions!.contains("snes9x_libretro.dylib"))
        XCTAssertTrue(shortcuts[2].launchOptions!.contains("mgba_libretro.dylib"))
    }
    
    func testRetroArchShortcutWithQuotedPaths() throws {
        // Test RetroArch with paths containing spaces (quoted)
        let vdfData = createRetroArchShortcut(
            corePath: "/Users/user name/RetroArch/cores/genesis plus gx_libretro.dylib",
            romPath: "/Users/user name/ROMs/Sega Genesis/Sonic the Hedgehog 2.md"
        )
        
        let reader = BinaryVDFReader(data: vdfData)
        let vdfDict = try reader.read()
        
        let parser = ShortcutParser()
        let shortcuts = try parser.parseShortcuts(from: vdfDict)
        
        XCTAssertEqual(shortcuts.count, 1)
        
        let launchOptions = shortcuts[0].launchOptions!
        // Verify paths are preserved with quotes
        XCTAssertTrue(launchOptions.contains("\"") || launchOptions.contains("user name"))
    }
    
    // MARK: - Test Corrupted VDF Data Handling
    
    func testCorruptedVDFUnexpectedEndOfData() {
        // Create incomplete VDF (missing end markers)
        var data = Data()
        data.append(0x00) // Section start
        data.append(contentsOf: "shortcuts".utf8)
        data.append(0x00)
        // Missing end markers - corrupted
        
        let validator = VDFValidator()
        
        XCTAssertThrowsError(try validator.validateData(data)) { error in
            XCTAssertTrue(error is VDFValidationError)
            if case VDFValidationError.corruptedData = error {
                // Expected error
            } else {
                XCTFail("Expected corruptedData error")
            }
        }
    }
    
    func testCorruptedVDFInvalidTypeMarker() {
        // Create VDF with invalid type marker
        var data = Data()
        data.append(0xFF) // Invalid type marker
        
        let validator = VDFValidator()
        
        XCTAssertThrowsError(try validator.validateData(data)) { error in
            XCTAssertTrue(error is VDFValidationError)
        }
    }
    
    func testCorruptedVDFInvalidUTF8String() {
        // Create VDF with invalid UTF-8 sequence
        var data = Data()
        data.append(0x01) // String marker
        data.append(contentsOf: [0xFF, 0xFE, 0xFD]) // Invalid UTF-8
        data.append(0x00)
        
        let validator = VDFValidator()
        
        XCTAssertThrowsError(try validator.validateData(data)) { error in
            XCTAssertTrue(error is VDFValidationError)
        }
    }
    
    func testCorruptedVDFTruncatedInt32() {
        // Create VDF with truncated int32 value
        var data = Data()
        data.append(0x02) // Int32 marker
        data.append(contentsOf: "appid".utf8)
        data.append(0x00)
        data.append(contentsOf: [0x01, 0x02]) // Only 2 bytes instead of 4
        // Missing remaining bytes
        
        let reader = BinaryVDFReader(data: data)
        
        XCTAssertThrowsError(try reader.read()) { error in
            XCTAssertTrue(error is VDFReaderError)
            if case VDFReaderError.unexpectedEndOfData = error {
                // Expected error
            } else {
                XCTFail("Expected unexpectedEndOfData error")
            }
        }
    }
    
    func testCorruptedVDFMismatchedSectionMarkers() {
        // Create VDF with mismatched section start/end
        var data = Data()
        data.append(0x00) // Section start
        data.append(contentsOf: "shortcuts".utf8)
        data.append(0x00)
        
        data.append(0x00) // Another section start
        data.append(contentsOf: "0".utf8)
        data.append(0x00)
        
        // Only one end marker (should have two)
        data.append(0x08)
        
        let reader = BinaryVDFReader(data: data)
        
        XCTAssertThrowsError(try reader.read()) { error in
            XCTAssertTrue(error is VDFReaderError)
        }
    }
    
    func testPartiallyCorruptedVDFSkipsInvalidEntries() throws {
        // Create VDF where one shortcut is invalid but others are valid
        var data = Data()
        
        // Start shortcuts section
        data.append(0x00)
        data.append(contentsOf: "shortcuts".utf8)
        data.append(0x00)
        
        // Valid shortcut "0"
        addValidShortcut(to: &data, id: "0", appid: 100, name: "Valid Game", exe: "/valid/exe")
        
        // Invalid shortcut "1" (missing required fields)
        data.append(0x00)
        data.append(contentsOf: "1".utf8)
        data.append(0x00)
        data.append(0x01) // Only has AppName, missing appid and Exe
        data.append(contentsOf: "AppName".utf8)
        data.append(0x00)
        data.append(contentsOf: "Invalid Game".utf8)
        data.append(0x00)
        data.append(0x08) // End invalid shortcut
        
        // Valid shortcut "2"
        addValidShortcut(to: &data, id: "2", appid: 200, name: "Another Valid Game", exe: "/another/exe")
        
        data.append(0x08) // End shortcuts
        data.append(0x08) // End root
        
        let reader = BinaryVDFReader(data: data)
        let vdfDict = try reader.read()
        
        let parser = ShortcutParser()
        let shortcuts = try parser.parseShortcuts(from: vdfDict)
        
        // Should skip invalid entry and return only valid ones
        XCTAssertEqual(shortcuts.count, 2)
        XCTAssertEqual(shortcuts[0].appName, "Valid Game")
        XCTAssertEqual(shortcuts[1].appName, "Another Valid Game")
    }
    
    // MARK: - Integration Tests with File I/O
    
    func testParseShortcutsVDFFromFile() throws {
        // Create a VDF file and test file-based parsing
        let vdfData = createSampleShortcutsVDF()
        let testFile = tempDirectory.appendingPathComponent("shortcuts.vdf")
        try vdfData.write(to: testFile)
        
        // Validate the file
        let validator = VDFValidator()
        XCTAssertNoThrow(try validator.validateFile(at: testFile.path))
        
        // Read and parse
        let fileData = try Data(contentsOf: testFile)
        let reader = BinaryVDFReader(data: fileData)
        let vdfDict = try reader.read()
        
        let parser = ShortcutParser()
        let shortcuts = try parser.parseShortcuts(from: vdfDict)
        
        XCTAssertEqual(shortcuts.count, 3)
    }
    
    // MARK: - Helper Methods
    
    /// Create a sample shortcuts.vdf with multiple known shortcuts
    private func createSampleShortcutsVDF() -> Data {
        var data = Data()
        
        // Start shortcuts section
        data.append(0x00)
        data.append(contentsOf: "shortcuts".utf8)
        data.append(0x00)
        
        // Shortcut 0: Super Mario 64 (RetroArch)
        data.append(0x00)
        data.append(contentsOf: "0".utf8)
        data.append(0x00)
        
        addInt32(to: &data, key: "appid", value: 2147483647)
        addString(to: &data, key: "AppName", value: "Super Mario 64")
        addString(to: &data, key: "Exe", value: "/Applications/RetroArch.app/Contents/MacOS/RetroArch")
        addString(to: &data, key: "StartDir", value: "/Applications/RetroArch.app/Contents/MacOS")
        addString(to: &data, key: "LaunchOptions", value: "-L \"/Users/user/cores/mupen64plus_libretro.dylib\" \"/Users/user/ROMs/N64/Super Mario 64.z64\"")
        addString(to: &data, key: "icon", value: "/Users/user/Steam/grid/2147483647p.png")
        
        // Add tags
        data.append(0x00)
        data.append(contentsOf: "tags".utf8)
        data.append(0x00)
        addString(to: &data, key: "0", value: "Nintendo 64")
        addString(to: &data, key: "1", value: "Platform")
        addString(to: &data, key: "2", value: "Favorite")
        data.append(0x08) // End tags
        
        data.append(0x08) // End shortcut 0
        
        // Shortcut 1: Zelda OOT (RetroArch)
        data.append(0x00)
        data.append(contentsOf: "1".utf8)
        data.append(0x00)
        
        addInt32(to: &data, key: "appid", value: 2147483646)
        addString(to: &data, key: "AppName", value: "The Legend of Zelda: Ocarina of Time")
        addString(to: &data, key: "Exe", value: "/Applications/RetroArch.app/Contents/MacOS/RetroArch")
        addString(to: &data, key: "LaunchOptions", value: "-L \"/Users/user/cores/mupen64plus_libretro.dylib\" \"/Users/user/ROMs/N64/Zelda OOT.z64\"")
        
        data.append(0x08) // End shortcut 1
        
        // Shortcut 2: Metroid Prime (Dolphin)
        data.append(0x00)
        data.append(contentsOf: "2".utf8)
        data.append(0x00)
        
        addInt32(to: &data, key: "appid", value: 2147483645)
        addString(to: &data, key: "AppName", value: "Metroid Prime")
        addString(to: &data, key: "Exe", value: "/Applications/Dolphin.app/Contents/MacOS/Dolphin")
        addString(to: &data, key: "LaunchOptions", value: "-e \"/Users/user/ROMs/GameCube/Metroid Prime.iso\"")
        
        data.append(0x08) // End shortcut 2
        
        data.append(0x08) // End shortcuts
        data.append(0x08) // End root
        
        return data
    }
    
    /// Create VDF with embedded icon data
    private func createVDFWithEmbeddedIcon(iconData: Data) -> Data {
        // Note: In real VDF files, embedded icons are stored as binary data
        // For this test, we'll create a VDF structure and manually inject the icon data
        // into the parsed dictionary since the binary VDF format doesn't directly support
        // arbitrary binary data in the same way
        
        // Create a basic VDF without icon first
        var data = Data()
        
        data.append(0x00)
        data.append(contentsOf: "shortcuts".utf8)
        data.append(0x00)
        
        data.append(0x00)
        data.append(contentsOf: "0".utf8)
        data.append(0x00)
        
        addInt32(to: &data, key: "appid", value: 12345)
        addString(to: &data, key: "AppName", value: "Test Game")
        addString(to: &data, key: "Exe", value: "/test/exe")
        
        // For embedded icon, we'll use an empty string as placeholder
        // In real scenarios, Steam stores this differently
        addString(to: &data, key: "icon", value: "")
        
        data.append(0x08) // End shortcut
        data.append(0x08) // End shortcuts
        data.append(0x08) // End root
        
        return data
    }
    
    /// Create VDF with icon file path
    private func createVDFWithIconPath(iconPath: String) -> Data {
        var data = Data()
        
        data.append(0x00)
        data.append(contentsOf: "shortcuts".utf8)
        data.append(0x00)
        
        data.append(0x00)
        data.append(contentsOf: "0".utf8)
        data.append(0x00)
        
        addInt32(to: &data, key: "appid", value: 12345)
        addString(to: &data, key: "AppName", value: "Test Game")
        addString(to: &data, key: "Exe", value: "/test/exe")
        addString(to: &data, key: "icon", value: iconPath)
        
        data.append(0x08) // End shortcut
        data.append(0x08) // End shortcuts
        data.append(0x08) // End root
        
        return data
    }
    
    /// Create VDF without icon field
    private func createVDFWithoutIcon() -> Data {
        var data = Data()
        
        data.append(0x00)
        data.append(contentsOf: "shortcuts".utf8)
        data.append(0x00)
        
        data.append(0x00)
        data.append(contentsOf: "0".utf8)
        data.append(0x00)
        
        addInt32(to: &data, key: "appid", value: 12345)
        addString(to: &data, key: "AppName", value: "Test Game")
        addString(to: &data, key: "Exe", value: "/test/exe")
        
        data.append(0x08) // End shortcut
        data.append(0x08) // End shortcuts
        data.append(0x08) // End root
        
        return data
    }
    
    /// Create RetroArch shortcut with core arguments
    private func createRetroArchShortcut(corePath: String, romPath: String) -> Data {
        var data = Data()
        
        data.append(0x00)
        data.append(contentsOf: "shortcuts".utf8)
        data.append(0x00)
        
        data.append(0x00)
        data.append(contentsOf: "0".utf8)
        data.append(0x00)
        
        addInt32(to: &data, key: "appid", value: 12345)
        addString(to: &data, key: "AppName", value: "Test ROM")
        addString(to: &data, key: "Exe", value: "/Applications/RetroArch.app/Contents/MacOS/RetroArch")
        addString(to: &data, key: "LaunchOptions", value: "-L \"\(corePath)\" \"\(romPath)\"")
        
        data.append(0x08) // End shortcut
        data.append(0x08) // End shortcuts
        data.append(0x08) // End root
        
        return data
    }
    
    /// Create multiple RetroArch shortcuts with different cores
    private func createMultipleRetroArchShortcuts() -> Data {
        var data = Data()
        
        data.append(0x00)
        data.append(contentsOf: "shortcuts".utf8)
        data.append(0x00)
        
        // N64 game
        data.append(0x00)
        data.append(contentsOf: "0".utf8)
        data.append(0x00)
        addInt32(to: &data, key: "appid", value: 100)
        addString(to: &data, key: "AppName", value: "N64 Game")
        addString(to: &data, key: "Exe", value: "/Applications/RetroArch.app")
        addString(to: &data, key: "LaunchOptions", value: "-L \"/cores/mupen64plus_libretro.dylib\" \"/roms/game.z64\"")
        data.append(0x08)
        
        // SNES game
        data.append(0x00)
        data.append(contentsOf: "1".utf8)
        data.append(0x00)
        addInt32(to: &data, key: "appid", value: 200)
        addString(to: &data, key: "AppName", value: "SNES Game")
        addString(to: &data, key: "Exe", value: "/Applications/RetroArch.app")
        addString(to: &data, key: "LaunchOptions", value: "-L \"/cores/snes9x_libretro.dylib\" \"/roms/game.sfc\"")
        data.append(0x08)
        
        // GBA game
        data.append(0x00)
        data.append(contentsOf: "2".utf8)
        data.append(0x00)
        addInt32(to: &data, key: "appid", value: 300)
        addString(to: &data, key: "AppName", value: "GBA Game")
        addString(to: &data, key: "Exe", value: "/Applications/RetroArch.app")
        addString(to: &data, key: "LaunchOptions", value: "-L \"/cores/mgba_libretro.dylib\" \"/roms/game.gba\"")
        data.append(0x08)
        
        data.append(0x08) // End shortcuts
        data.append(0x08) // End root
        
        return data
    }
    
    /// Add a valid shortcut to VDF data
    private func addValidShortcut(to data: inout Data, id: String, appid: Int32, name: String, exe: String) {
        data.append(0x00)
        data.append(contentsOf: id.utf8)
        data.append(0x00)
        
        addInt32(to: &data, key: "appid", value: appid)
        addString(to: &data, key: "AppName", value: name)
        addString(to: &data, key: "Exe", value: exe)
        
        data.append(0x08)
    }
    
    /// Add a string key-value pair to VDF data
    private func addString(to data: inout Data, key: String, value: String) {
        data.append(0x01)
        data.append(contentsOf: key.utf8)
        data.append(0x00)
        data.append(contentsOf: value.utf8)
        data.append(0x00)
    }
    
    /// Add an int32 key-value pair to VDF data
    private func addInt32(to data: inout Data, key: String, value: Int32) {
        data.append(0x02)
        data.append(contentsOf: key.utf8)
        data.append(0x00)
        var val = value
        data.append(contentsOf: withUnsafeBytes(of: &val) { Data($0) })
    }
}
