//
//  VDFIntegrationTests.swift
//  SteamShortcutConverterTests
//
//  Integration tests for VDF reading and shortcut parsing
//

import XCTest
@testable import SteamShortcutConverter

final class VDFIntegrationTests: XCTestCase {
    
    // MARK: - Integration Tests
    
    func testReadAndParseShortcutsFromVDF() throws {
        // Create a complete VDF structure with shortcuts
        var data = Data()
        
        // Root section: "shortcuts"
        data.append(0x00) // Section start
        data.append(contentsOf: "shortcuts".utf8)
        data.append(0x00) // Null terminator
        
        // Shortcut entry "0"
        data.append(0x00) // Section start
        data.append(contentsOf: "0".utf8)
        data.append(0x00) // Null terminator
        
        // appid (Int32)
        data.append(0x02)
        data.append(contentsOf: "appid".utf8)
        data.append(0x00)
        var appid: Int32 = 12345
        data.append(contentsOf: withUnsafeBytes(of: &appid) { Data($0) })
        
        // AppName (String)
        data.append(0x01)
        data.append(contentsOf: "AppName".utf8)
        data.append(0x00)
        data.append(contentsOf: "Super Mario 64".utf8)
        data.append(0x00)
        
        // Exe (String)
        data.append(0x01)
        data.append(contentsOf: "Exe".utf8)
        data.append(0x00)
        data.append(contentsOf: "/Applications/RetroArch.app".utf8)
        data.append(0x00)
        
        // StartDir (String)
        data.append(0x01)
        data.append(contentsOf: "StartDir".utf8)
        data.append(0x00)
        data.append(contentsOf: "/Applications".utf8)
        data.append(0x00)
        
        // LaunchOptions (String)
        data.append(0x01)
        data.append(contentsOf: "LaunchOptions".utf8)
        data.append(0x00)
        data.append(contentsOf: "-L core.dylib rom.z64".utf8)
        data.append(0x00)
        
        // icon (String)
        data.append(0x01)
        data.append(contentsOf: "icon".utf8)
        data.append(0x00)
        data.append(contentsOf: "/path/to/icon.png".utf8)
        data.append(0x00)
        
        // tags section
        data.append(0x00) // Section start
        data.append(contentsOf: "tags".utf8)
        data.append(0x00)
        
        // tag 0
        data.append(0x01)
        data.append(contentsOf: "0".utf8)
        data.append(0x00)
        data.append(contentsOf: "Nintendo 64".utf8)
        data.append(0x00)
        
        // tag 1
        data.append(0x01)
        data.append(contentsOf: "1".utf8)
        data.append(0x00)
        data.append(contentsOf: "Platform".utf8)
        data.append(0x00)
        
        data.append(0x08) // End tags section
        
        data.append(0x08) // End shortcut "0"
        
        data.append(0x08) // End shortcuts section
        data.append(0x08) // End root
        
        // Step 1: Read VDF data
        let reader = BinaryVDFReader(data: data)
        let vdfDict = try reader.read()
        
        // Verify VDF structure
        XCTAssertNotNil(vdfDict["shortcuts"])
        
        // Step 2: Parse shortcuts
        let parser = ShortcutParser()
        let shortcuts = try parser.parseShortcuts(from: vdfDict)
        
        // Verify parsed shortcuts
        XCTAssertEqual(shortcuts.count, 1)
        
        let shortcut = shortcuts[0]
        XCTAssertEqual(shortcut.appID, 12345)
        XCTAssertEqual(shortcut.appName, "Super Mario 64")
        XCTAssertEqual(shortcut.exe, "/Applications/RetroArch.app")
        XCTAssertEqual(shortcut.startDir, "/Applications")
        XCTAssertEqual(shortcut.launchOptions, "-L core.dylib rom.z64")
        XCTAssertEqual(shortcut.tags, ["Nintendo 64", "Platform"])
        
        if case .filePath(let path) = shortcut.icon {
            XCTAssertEqual(path, "/path/to/icon.png")
        } else {
            XCTFail("Expected filePath icon")
        }
    }
    
    func testReadAndParseMultipleShortcuts() throws {
        // Create VDF with multiple shortcuts
        var data = Data()
        
        // Root section: "shortcuts"
        data.append(0x00)
        data.append(contentsOf: "shortcuts".utf8)
        data.append(0x00)
        
        // Helper function to add a shortcut
        func addShortcut(id: String, appid: Int32, name: String, exe: String) {
            data.append(0x00) // Section start
            data.append(contentsOf: id.utf8)
            data.append(0x00)
            
            // appid
            data.append(0x02)
            data.append(contentsOf: "appid".utf8)
            data.append(0x00)
            var appidValue = appid
            data.append(contentsOf: withUnsafeBytes(of: &appidValue) { Data($0) })
            
            // AppName
            data.append(0x01)
            data.append(contentsOf: "AppName".utf8)
            data.append(0x00)
            data.append(contentsOf: name.utf8)
            data.append(0x00)
            
            // Exe
            data.append(0x01)
            data.append(contentsOf: "Exe".utf8)
            data.append(0x00)
            data.append(contentsOf: exe.utf8)
            data.append(0x00)
            
            data.append(0x08) // End shortcut
        }
        
        addShortcut(id: "0", appid: 100, name: "Game 1", exe: "/emulator1")
        addShortcut(id: "1", appid: 200, name: "Game 2", exe: "/emulator2")
        addShortcut(id: "2", appid: 300, name: "Game 3", exe: "/emulator3")
        
        data.append(0x08) // End shortcuts section
        data.append(0x08) // End root
        
        // Read and parse
        let reader = BinaryVDFReader(data: data)
        let vdfDict = try reader.read()
        
        let parser = ShortcutParser()
        let shortcuts = try parser.parseShortcuts(from: vdfDict)
        
        // Verify
        XCTAssertEqual(shortcuts.count, 3)
        XCTAssertEqual(shortcuts[0].appName, "Game 1")
        XCTAssertEqual(shortcuts[1].appName, "Game 2")
        XCTAssertEqual(shortcuts[2].appName, "Game 3")
    }
    
    func testReadAndParseEmptyShortcutsSection() throws {
        // Create VDF with empty shortcuts section
        var data = Data()
        
        data.append(0x00) // Section start
        data.append(contentsOf: "shortcuts".utf8)
        data.append(0x00)
        data.append(0x08) // End shortcuts section (empty)
        data.append(0x08) // End root
        
        let reader = BinaryVDFReader(data: data)
        let vdfDict = try reader.read()
        
        let parser = ShortcutParser()
        let shortcuts = try parser.parseShortcuts(from: vdfDict)
        
        XCTAssertTrue(shortcuts.isEmpty)
    }
}
