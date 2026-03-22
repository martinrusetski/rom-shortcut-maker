//
//  ShortcutParserTests.swift
//  SteamShortcutConverterTests
//
//  Unit tests for ShortcutParser
//

import XCTest
@testable import SteamShortcutConverter

final class ShortcutParserTests: XCTestCase {
    
    var parser: ShortcutParser!
    
    override func setUp() {
        super.setUp()
        parser = ShortcutParser()
    }
    
    override func tearDown() {
        parser = nil
        super.tearDown()
    }
    
    // MARK: - Basic Parsing Tests
    
    func testParseEmptyShortcutsSection() throws {
        let vdfData: [String: Any] = [
            "shortcuts": [String: Any]()
        ]
        
        let shortcuts = try parser.parseShortcuts(from: vdfData)
        
        XCTAssertTrue(shortcuts.isEmpty, "Empty shortcuts section should return empty array")
    }
    
    func testParseSingleShortcut() throws {
        let vdfData: [String: Any] = [
            "shortcuts": [
                "0": [
                    "appid": Int32(12345),
                    "AppName": "Test Game",
                    "Exe": "/path/to/emulator",
                    "StartDir": "/path/to/dir",
                    "LaunchOptions": "-fullscreen",
                    "icon": "/path/to/icon.png"
                ] as [String: Any]
            ]
        ]
        
        let shortcuts = try parser.parseShortcuts(from: vdfData)
        
        XCTAssertEqual(shortcuts.count, 1)
        
        let shortcut = shortcuts[0]
        XCTAssertEqual(shortcut.appID, 12345)
        XCTAssertEqual(shortcut.appName, "Test Game")
        XCTAssertEqual(shortcut.exe, "/path/to/emulator")
        XCTAssertEqual(shortcut.startDir, "/path/to/dir")
        XCTAssertEqual(shortcut.launchOptions, "-fullscreen")
        
        if case .filePath(let path) = shortcut.icon {
            XCTAssertEqual(path, "/path/to/icon.png")
        } else {
            XCTFail("Expected filePath icon")
        }
    }
    
    func testParseMultipleShortcuts() throws {
        let vdfData: [String: Any] = [
            "shortcuts": [
                "0": [
                    "appid": Int32(100),
                    "AppName": "Game 1",
                    "Exe": "/emulator1"
                ] as [String: Any],
                "1": [
                    "appid": Int32(200),
                    "AppName": "Game 2",
                    "Exe": "/emulator2"
                ] as [String: Any],
                "2": [
                    "appid": Int32(300),
                    "AppName": "Game 3",
                    "Exe": "/emulator3"
                ] as [String: Any]
            ]
        ]
        
        let shortcuts = try parser.parseShortcuts(from: vdfData)
        
        XCTAssertEqual(shortcuts.count, 3)
        XCTAssertEqual(shortcuts[0].appName, "Game 1")
        XCTAssertEqual(shortcuts[1].appName, "Game 2")
        XCTAssertEqual(shortcuts[2].appName, "Game 3")
    }
    
    func testParseShortcutWithMinimalFields() throws {
        // Only required fields: appid, AppName, Exe
        let vdfData: [String: Any] = [
            "shortcuts": [
                "0": [
                    "appid": Int32(999),
                    "AppName": "Minimal Game",
                    "Exe": "/path/to/game"
                ] as [String: Any]
            ]
        ]
        
        let shortcuts = try parser.parseShortcuts(from: vdfData)
        
        XCTAssertEqual(shortcuts.count, 1)
        
        let shortcut = shortcuts[0]
        XCTAssertEqual(shortcut.appID, 999)
        XCTAssertEqual(shortcut.appName, "Minimal Game")
        XCTAssertEqual(shortcut.exe, "/path/to/game")
        XCTAssertNil(shortcut.startDir)
        XCTAssertNil(shortcut.launchOptions)
        XCTAssertNil(shortcut.icon)
        XCTAssertTrue(shortcut.tags.isEmpty)
    }
    
    // MARK: - Icon Parsing Tests
    
    func testParseShortcutWithIconPath() throws {
        let vdfData: [String: Any] = [
            "shortcuts": [
                "0": [
                    "appid": Int32(123),
                    "AppName": "Game",
                    "Exe": "/exe",
                    "icon": "/path/to/icon.png"
                ] as [String: Any]
            ]
        ]
        
        let shortcuts = try parser.parseShortcuts(from: vdfData)
        
        XCTAssertEqual(shortcuts.count, 1)
        
        if case .filePath(let path) = shortcuts[0].icon {
            XCTAssertEqual(path, "/path/to/icon.png")
        } else {
            XCTFail("Expected filePath icon")
        }
    }
    
    func testParseShortcutWithEmbeddedIcon() throws {
        let iconData = Data([0x89, 0x50, 0x4E, 0x47]) // PNG header
        
        let vdfData: [String: Any] = [
            "shortcuts": [
                "0": [
                    "appid": Int32(123),
                    "AppName": "Game",
                    "Exe": "/exe",
                    "icon": iconData
                ] as [String: Any]
            ]
        ]
        
        let shortcuts = try parser.parseShortcuts(from: vdfData)
        
        XCTAssertEqual(shortcuts.count, 1)
        
        if case .embedded(let data) = shortcuts[0].icon {
            XCTAssertEqual(data, iconData)
        } else {
            XCTFail("Expected embedded icon")
        }
    }
    
    func testParseShortcutWithEmptyIconString() throws {
        let vdfData: [String: Any] = [
            "shortcuts": [
                "0": [
                    "appid": Int32(123),
                    "AppName": "Game",
                    "Exe": "/exe",
                    "icon": ""
                ] as [String: Any]
            ]
        ]
        
        let shortcuts = try parser.parseShortcuts(from: vdfData)
        
        XCTAssertEqual(shortcuts.count, 1)
        XCTAssertNil(shortcuts[0].icon, "Empty icon string should result in nil icon")
    }
    
    func testParseShortcutWithNoIcon() throws {
        let vdfData: [String: Any] = [
            "shortcuts": [
                "0": [
                    "appid": Int32(123),
                    "AppName": "Game",
                    "Exe": "/exe"
                ] as [String: Any]
            ]
        ]
        
        let shortcuts = try parser.parseShortcuts(from: vdfData)
        
        XCTAssertEqual(shortcuts.count, 1)
        XCTAssertNil(shortcuts[0].icon)
    }
    
    // MARK: - Tags Parsing Tests
    
    func testParseShortcutWithTags() throws {
        let vdfData: [String: Any] = [
            "shortcuts": [
                "0": [
                    "appid": Int32(123),
                    "AppName": "Game",
                    "Exe": "/exe",
                    "tags": [
                        "0": "Action",
                        "1": "RPG",
                        "2": "Multiplayer"
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ]
        
        let shortcuts = try parser.parseShortcuts(from: vdfData)
        
        XCTAssertEqual(shortcuts.count, 1)
        XCTAssertEqual(shortcuts[0].tags, ["Action", "RPG", "Multiplayer"])
    }
    
    func testParseShortcutWithNoTags() throws {
        let vdfData: [String: Any] = [
            "shortcuts": [
                "0": [
                    "appid": Int32(123),
                    "AppName": "Game",
                    "Exe": "/exe"
                ] as [String: Any]
            ]
        ]
        
        let shortcuts = try parser.parseShortcuts(from: vdfData)
        
        XCTAssertEqual(shortcuts.count, 1)
        XCTAssertTrue(shortcuts[0].tags.isEmpty)
    }
    
    func testParseShortcutWithEmptyTags() throws {
        let vdfData: [String: Any] = [
            "shortcuts": [
                "0": [
                    "appid": Int32(123),
                    "AppName": "Game",
                    "Exe": "/exe",
                    "tags": [String: Any]()
                ] as [String: Any]
            ]
        ]
        
        let shortcuts = try parser.parseShortcuts(from: vdfData)
        
        XCTAssertEqual(shortcuts.count, 1)
        XCTAssertTrue(shortcuts[0].tags.isEmpty)
    }
    
    // MARK: - Error Handling Tests
    
    func testParseWithoutShortcutsSection() {
        let vdfData: [String: Any] = [
            "other_section": [String: Any]()
        ]
        
        XCTAssertThrowsError(try parser.parseShortcuts(from: vdfData)) { error in
            XCTAssertTrue(error is ShortcutParserError)
            if case ShortcutParserError.noShortcutsSection = error {
                // Expected error
            } else {
                XCTFail("Expected noShortcutsSection error")
            }
        }
    }
    
    func testParseMissingAppName() {
        let vdfData: [String: Any] = [
            "shortcuts": [
                "0": [
                    "appid": Int32(123),
                    "Exe": "/exe"
                ] as [String: Any]
            ]
        ]
        
        // Should skip invalid shortcut and return empty array
        let shortcuts = try? parser.parseShortcuts(from: vdfData)
        XCTAssertNotNil(shortcuts)
        XCTAssertTrue(shortcuts?.isEmpty ?? false, "Invalid shortcuts should be skipped")
    }
    
    func testParseMissingExe() {
        let vdfData: [String: Any] = [
            "shortcuts": [
                "0": [
                    "appid": Int32(123),
                    "AppName": "Game"
                ] as [String: Any]
            ]
        ]
        
        // Should skip invalid shortcut and return empty array
        let shortcuts = try? parser.parseShortcuts(from: vdfData)
        XCTAssertNotNil(shortcuts)
        XCTAssertTrue(shortcuts?.isEmpty ?? false, "Invalid shortcuts should be skipped")
    }
    
    func testParseMissingAppID() {
        let vdfData: [String: Any] = [
            "shortcuts": [
                "0": [
                    "AppName": "Game",
                    "Exe": "/exe"
                ] as [String: Any]
            ]
        ]
        
        // Should skip invalid shortcut and return empty array
        let shortcuts = try? parser.parseShortcuts(from: vdfData)
        XCTAssertNotNil(shortcuts)
        XCTAssertTrue(shortcuts?.isEmpty ?? false, "Invalid shortcuts should be skipped")
    }
    
    // MARK: - Integration Tests
    
    func testParseComplexShortcut() throws {
        // Test a realistic shortcut with all fields
        let vdfData: [String: Any] = [
            "shortcuts": [
                "0": [
                    "appid": Int32(2147483647), // Max Int32
                    "AppName": "Super Mario 64",
                    "Exe": "/Applications/RetroArch.app/Contents/MacOS/RetroArch",
                    "StartDir": "/Applications/RetroArch.app/Contents/MacOS/",
                    "LaunchOptions": "-L /path/to/core.dylib \"/path/to/Super Mario 64.z64\"",
                    "icon": "/Users/user/Library/Application Support/Steam/userdata/12345/config/grid/12345p.png",
                    "tags": [
                        "0": "Nintendo 64",
                        "1": "Platform",
                        "2": "Favorite"
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ]
        
        let shortcuts = try parser.parseShortcuts(from: vdfData)
        
        XCTAssertEqual(shortcuts.count, 1)
        
        let shortcut = shortcuts[0]
        XCTAssertEqual(shortcut.appID, 2147483647)
        XCTAssertEqual(shortcut.appName, "Super Mario 64")
        XCTAssertEqual(shortcut.exe, "/Applications/RetroArch.app/Contents/MacOS/RetroArch")
        XCTAssertEqual(shortcut.startDir, "/Applications/RetroArch.app/Contents/MacOS/")
        XCTAssertEqual(shortcut.launchOptions, "-L /path/to/core.dylib \"/path/to/Super Mario 64.z64\"")
        XCTAssertEqual(shortcut.tags, ["Nintendo 64", "Platform", "Favorite"])
        
        if case .filePath(let path) = shortcut.icon {
            XCTAssertTrue(path.contains("grid"))
        } else {
            XCTFail("Expected filePath icon")
        }
    }
    
    func testParseShortcutsWithNonSequentialKeys() throws {
        // Test that parser handles non-sequential keys (e.g., 0, 2, 5)
        let vdfData: [String: Any] = [
            "shortcuts": [
                "5": [
                    "appid": Int32(500),
                    "AppName": "Game 5",
                    "Exe": "/exe5"
                ] as [String: Any],
                "0": [
                    "appid": Int32(100),
                    "AppName": "Game 0",
                    "Exe": "/exe0"
                ] as [String: Any],
                "2": [
                    "appid": Int32(200),
                    "AppName": "Game 2",
                    "Exe": "/exe2"
                ] as [String: Any]
            ]
        ]
        
        let shortcuts = try parser.parseShortcuts(from: vdfData)
        
        XCTAssertEqual(shortcuts.count, 3)
        // Should be sorted by key
        XCTAssertEqual(shortcuts[0].appName, "Game 0")
        XCTAssertEqual(shortcuts[1].appName, "Game 2")
        XCTAssertEqual(shortcuts[2].appName, "Game 5")
    }
}
