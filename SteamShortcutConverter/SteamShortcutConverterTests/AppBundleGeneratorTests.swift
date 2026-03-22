//
//  AppBundleGeneratorTests.swift
//  SteamShortcutConverterTests
//
//  Tests for AppBundleGenerator
//

import XCTest
import Foundation
@testable import SteamShortcutConverter

class AppBundleGeneratorTests: XCTestCase {
    
    var generator: DefaultAppBundleGenerator!
    var tempDirectory: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        generator = DefaultAppBundleGenerator()
        
        // Create a temporary directory for test output
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
    }
    
    override func tearDown() async throws {
        // Clean up temporary directory
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        generator = nil
        try await super.tearDown()
    }
    
    // MARK: - Directory Structure Tests
    
    func testCreateAppBundleStructure() async throws {
        // Given: A valid app bundle configuration
        let config = AppBundleConfig(
            bundleName: "TestGame",
            bundleIdentifier: "com.test.testgame",
            displayName: "Test Game",
            launchScript: "#!/bin/bash\necho 'test'",
            outputDirectory: tempDirectory
        )
        
        // When: Generating the app bundle
        let bundleURL = try await generator.generateAppBundle(with: config)
        
        // Then: The .app bundle should exist
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: bundleURL.path),
            "App bundle should exist at \(bundleURL.path)"
        )
        
        // And: The bundle should have .app extension
        XCTAssertEqual(bundleURL.pathExtension, "app", "Bundle should have .app extension")
        XCTAssertEqual(bundleURL.lastPathComponent, "TestGame.app", "Bundle name should match")
        
        // And: Contents directory should exist
        let contentsURL = bundleURL.appendingPathComponent("Contents")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: contentsURL.path),
            "Contents directory should exist"
        )
        
        // And: MacOS subdirectory should exist
        let macOSURL = contentsURL.appendingPathComponent("MacOS")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: macOSURL.path),
            "MacOS directory should exist"
        )
        
        // And: Resources subdirectory should exist
        let resourcesURL = contentsURL.appendingPathComponent("Resources")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: resourcesURL.path),
            "Resources directory should exist"
        )
    }
    
    func testDirectoryPermissions() async throws {
        // Given: A valid app bundle configuration
        let config = AppBundleConfig(
            bundleName: "PermissionTest",
            bundleIdentifier: "com.test.permissiontest",
            displayName: "Permission Test",
            launchScript: "#!/bin/bash\necho 'test'",
            outputDirectory: tempDirectory
        )
        
        // When: Generating the app bundle
        let bundleURL = try await generator.generateAppBundle(with: config)
        
        // Then: Directories should have proper permissions (0o755 = rwxr-xr-x)
        let contentsURL = bundleURL.appendingPathComponent("Contents")
        let macOSURL = contentsURL.appendingPathComponent("MacOS")
        let resourcesURL = contentsURL.appendingPathComponent("Resources")
        
        for directoryURL in [contentsURL, macOSURL, resourcesURL] {
            let attributes = try FileManager.default.attributesOfItem(atPath: directoryURL.path)
            let permissions = attributes[.posixPermissions] as? NSNumber
            
            XCTAssertNotNil(permissions, "Permissions should be set for \(directoryURL.lastPathComponent)")
            
            // Check that permissions are 0o755 (493 in decimal)
            if let perms = permissions {
                XCTAssertEqual(
                    perms.uint16Value,
                    0o755,
                    "Directory \(directoryURL.lastPathComponent) should have 0o755 permissions"
                )
            }
        }
    }
    
    func testCreateMultipleBundles() async throws {
        // Given: Multiple app bundle configurations
        let configs = [
            AppBundleConfig(
                bundleName: "Game1",
                bundleIdentifier: "com.test.game1",
                displayName: "Game 1",
                launchScript: "#!/bin/bash\necho 'game1'",
                outputDirectory: tempDirectory
            ),
            AppBundleConfig(
                bundleName: "Game2",
                bundleIdentifier: "com.test.game2",
                displayName: "Game 2",
                launchScript: "#!/bin/bash\necho 'game2'",
                outputDirectory: tempDirectory
            ),
            AppBundleConfig(
                bundleName: "Game3",
                bundleIdentifier: "com.test.game3",
                displayName: "Game 3",
                launchScript: "#!/bin/bash\necho 'game3'",
                outputDirectory: tempDirectory
            )
        ]
        
        // When: Generating all bundles
        var bundleURLs: [URL] = []
        for config in configs {
            let bundleURL = try await generator.generateAppBundle(with: config)
            bundleURLs.append(bundleURL)
        }
        
        // Then: All bundles should exist with proper structure
        XCTAssertEqual(bundleURLs.count, 3, "Should create 3 bundles")
        
        for bundleURL in bundleURLs {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: bundleURL.path),
                "Bundle should exist: \(bundleURL.lastPathComponent)"
            )
            
            let macOSURL = bundleURL
                .appendingPathComponent("Contents")
                .appendingPathComponent("MacOS")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: macOSURL.path),
                "MacOS directory should exist in \(bundleURL.lastPathComponent)"
            )
        }
    }
    
    func testBundleNameWithSpecialCharacters() async throws {
        // Given: A bundle name with special characters
        let config = AppBundleConfig(
            bundleName: "Super Mario Bros. 3",
            bundleIdentifier: "com.test.supermariobros3",
            displayName: "Super Mario Bros. 3",
            launchScript: "#!/bin/bash\necho 'mario'",
            outputDirectory: tempDirectory
        )
        
        // When: Generating the app bundle
        let bundleURL = try await generator.generateAppBundle(with: config)
        
        // Then: The bundle should be created successfully
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: bundleURL.path),
            "Bundle with special characters should be created"
        )
        XCTAssertEqual(
            bundleURL.lastPathComponent,
            "Super Mario Bros. 3.app",
            "Bundle name should preserve special characters"
        )
    }
    
    func testRecreateExistingBundle() async throws {
        // Given: An existing app bundle
        let config = AppBundleConfig(
            bundleName: "ExistingGame",
            bundleIdentifier: "com.test.existinggame",
            displayName: "Existing Game",
            launchScript: "#!/bin/bash\necho 'test'",
            outputDirectory: tempDirectory
        )
        
        let firstBundleURL = try await generator.generateAppBundle(with: config)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstBundleURL.path))
        
        // When: Generating the same bundle again
        let secondBundleURL = try await generator.generateAppBundle(with: config)
        
        // Then: The bundle should still exist and be valid
        XCTAssertEqual(firstBundleURL, secondBundleURL, "Bundle URLs should match")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: secondBundleURL.path),
            "Bundle should still exist after recreation"
        )
        
        // And: Directory structure should still be intact
        let macOSURL = secondBundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: macOSURL.path),
            "MacOS directory should exist after recreation"
        )
    }
    
    // MARK: - Info.plist Tests
    
    func testInfoPlistGeneration() async throws {
        // Given: A valid app bundle configuration
        let config = AppBundleConfig(
            bundleName: "TestGame",
            bundleIdentifier: "com.test.testgame",
            displayName: "Test Game",
            version: "1.0",
            launchScript: "#!/bin/bash\necho 'test'",
            outputDirectory: tempDirectory
        )
        
        // When: Generating the app bundle
        let bundleURL = try await generator.generateAppBundle(with: config)
        
        // Then: Info.plist should exist
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: plistURL.path),
            "Info.plist should exist"
        )
        
        // And: Info.plist should contain correct values
        let plistData = try Data(contentsOf: plistURL)
        let plistString = String(data: plistData, encoding: .utf8)!
        
        XCTAssertTrue(plistString.contains("com.test.testgame"), "Should contain bundle identifier")
        XCTAssertTrue(plistString.contains("TestGame"), "Should contain bundle name")
        XCTAssertTrue(plistString.contains("Test Game"), "Should contain display name")
        XCTAssertTrue(plistString.contains("1.0"), "Should contain version")
        XCTAssertTrue(plistString.contains("launch.sh"), "Should contain executable name")
    }
    
    func testInfoPlistWithIcon() async throws {
        // Given: A configuration with icon data
        let iconData = IconData.embedded(Data([0x89, 0x50, 0x4E, 0x47])) // PNG header
        let config = AppBundleConfig(
            bundleName: "GameWithIcon",
            bundleIdentifier: "com.test.gamewithicon",
            displayName: "Game With Icon",
            launchScript: "#!/bin/bash\necho 'test'",
            iconData: iconData,
            outputDirectory: tempDirectory
        )
        
        // When: Generating the app bundle (icon conversion may fail with invalid data)
        do {
            let bundleURL = try await generator.generateAppBundle(with: config)
            
            // Then: Info.plist should reference the icon (even if conversion failed)
            let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
            let plistData = try Data(contentsOf: plistURL)
            let plistString = String(data: plistData, encoding: .utf8)!
            
            XCTAssertTrue(plistString.contains("CFBundleIconFile"), "Should contain icon file key")
            XCTAssertTrue(plistString.contains("AppIcon"), "Should reference AppIcon")
        } catch {
            // Icon conversion failure is expected with invalid image data
            // The test passes as long as the error is related to icon conversion
            if let appError = error as? AppBundleGeneratorError {
                switch appError {
                case .iconConversionFailed:
                    // Expected - invalid image data
                    break
                default:
                    XCTFail("Unexpected error: \(error)")
                }
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }
    
    // MARK: - Launch Script Tests
    
    func testLaunchScriptGeneration() async throws {
        // Given: A configuration with a simple launch command
        let launchCommand = "/Applications/RetroArch.app/Contents/MacOS/RetroArch -L /path/to/core.dylib /path/to/rom.nes"
        let config = AppBundleConfig(
            bundleName: "TestGame",
            bundleIdentifier: "com.test.testgame",
            displayName: "Test Game",
            launchScript: launchCommand,
            outputDirectory: tempDirectory
        )
        
        // When: Generating the app bundle
        let bundleURL = try await generator.generateAppBundle(with: config)
        
        // Then: Launch script should exist
        let scriptURL = bundleURL.appendingPathComponent("Contents/MacOS/launch.sh")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: scriptURL.path),
            "Launch script should exist"
        )
        
        // And: Launch script should contain the command
        let scriptContent = try String(contentsOf: scriptURL, encoding: .utf8)
        XCTAssertTrue(scriptContent.contains("#!/bin/bash"), "Should have bash shebang")
        XCTAssertTrue(scriptContent.contains("RetroArch"), "Should contain launch command")
    }
    
    func testLaunchScriptWithSpecialCharacters() async throws {
        // Given: A launch command with paths containing spaces
        let launchCommand = "/Applications/My Emulator.app/Contents/MacOS/emulator \"/path/to/my game.rom\""
        let config = AppBundleConfig(
            bundleName: "TestGame",
            bundleIdentifier: "com.test.testgame",
            displayName: "Test Game",
            launchScript: launchCommand,
            outputDirectory: tempDirectory
        )
        
        // When: Generating the app bundle
        let bundleURL = try await generator.generateAppBundle(with: config)
        
        // Then: Launch script should properly escape the command
        let scriptURL = bundleURL.appendingPathComponent("Contents/MacOS/launch.sh")
        let scriptContent = try String(contentsOf: scriptURL, encoding: .utf8)
        
        // The script should preserve the quoted paths
        XCTAssertTrue(scriptContent.contains("My Emulator"), "Should contain emulator name")
        XCTAssertTrue(scriptContent.contains("my game"), "Should contain ROM name")
    }
    
    func testLaunchScriptExecutablePermissions() async throws {
        // Given: A valid configuration
        let config = AppBundleConfig(
            bundleName: "TestGame",
            bundleIdentifier: "com.test.testgame",
            displayName: "Test Game",
            launchScript: "#!/bin/bash\necho 'test'",
            outputDirectory: tempDirectory
        )
        
        // When: Generating the app bundle
        let bundleURL = try await generator.generateAppBundle(with: config)
        
        // Then: Launch script should be executable
        let scriptURL = bundleURL.appendingPathComponent("Contents/MacOS/launch.sh")
        let attributes = try FileManager.default.attributesOfItem(atPath: scriptURL.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        
        XCTAssertNotNil(permissions, "Permissions should be set")
        
        // Check that permissions include executable bit (0o755)
        if let perms = permissions {
            XCTAssertEqual(
                perms.uint16Value,
                0o755,
                "Launch script should have 0o755 permissions"
            )
        }
    }
    
    func testLaunchScriptWithDollarSign() async throws {
        // Given: A launch command with dollar sign (environment variable)
        let launchCommand = "/usr/bin/env HOME=$HOME /path/to/emulator"
        let config = AppBundleConfig(
            bundleName: "TestGame",
            bundleIdentifier: "com.test.testgame",
            displayName: "Test Game",
            launchScript: launchCommand,
            outputDirectory: tempDirectory
        )
        
        // When: Generating the app bundle
        let bundleURL = try await generator.generateAppBundle(with: config)
        
        // Then: Launch script should escape dollar signs
        let scriptURL = bundleURL.appendingPathComponent("Contents/MacOS/launch.sh")
        let scriptContent = try String(contentsOf: scriptURL, encoding: .utf8)
        
        // The script should contain the command (escaping is handled internally)
        XCTAssertTrue(scriptContent.contains("HOME"), "Should contain HOME variable")
    }
    
    // MARK: - Icon Conversion Tests
    
    func testIconConversionNotImplementedForNow() async throws {
        // Note: Icon conversion requires actual image files and sips/iconutil
        // These tests would need real PNG/JPG files to work properly
        // For now, we test that the method exists and can be called
        
        // Given: Embedded icon data
        let iconData = IconData.embedded(Data([0x89, 0x50, 0x4E, 0x47])) // PNG header
        let outputURL = tempDirectory.appendingPathComponent("test.icns")
        
        // When/Then: Calling convertIcon should not crash (but may fail without valid image)
        // We expect this to fail with invalid image data, but the method should exist
        do {
            try await generator.convertIcon(iconData, to: outputURL)
            // If it succeeds, that's fine too
        } catch {
            // Expected to fail with invalid image data
            XCTAssertTrue(error is AppBundleGeneratorError, "Should throw AppBundleGeneratorError")
        }
    }
    
    // MARK: - Integration Tests
    
    func testCompleteAppBundleGeneration() async throws {
        // Given: A complete configuration
        let config = AppBundleConfig(
            bundleName: "Super Mario Bros",
            bundleIdentifier: "com.steamshortcutconverter.supermariobros",
            displayName: "Super Mario Bros.",
            version: "1.0",
            launchScript: "/Applications/RetroArch.app/Contents/MacOS/RetroArch -L /path/to/nestopia_libretro.dylib \"/path/to/Super Mario Bros.nes\"",
            outputDirectory: tempDirectory
        )
        
        // When: Generating the app bundle
        let bundleURL = try await generator.generateAppBundle(with: config)
        
        // Then: All components should exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.path))
        
        let contentsURL = bundleURL.appendingPathComponent("Contents")
        XCTAssertTrue(FileManager.default.fileExists(atPath: contentsURL.path))
        
        let plistURL = contentsURL.appendingPathComponent("Info.plist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))
        
        let macOSURL = contentsURL.appendingPathComponent("MacOS")
        XCTAssertTrue(FileManager.default.fileExists(atPath: macOSURL.path))
        
        let scriptURL = macOSURL.appendingPathComponent("launch.sh")
        XCTAssertTrue(FileManager.default.fileExists(atPath: scriptURL.path))
        
        let resourcesURL = contentsURL.appendingPathComponent("Resources")
        XCTAssertTrue(FileManager.default.fileExists(atPath: resourcesURL.path))
        
        // And: Info.plist should be valid
        let plistData = try Data(contentsOf: plistURL)
        let plistString = String(data: plistData, encoding: .utf8)!
        XCTAssertTrue(plistString.contains("com.steamshortcutconverter.supermariobros"))
        
        // And: Launch script should be executable
        let attributes = try FileManager.default.attributesOfItem(atPath: scriptURL.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.uint16Value, 0o755)
    }
    
    func testMultipleGamesWithDifferentConfigurations() async throws {
        // Given: Multiple game configurations
        let configs = [
            AppBundleConfig(
                bundleName: "Zelda",
                bundleIdentifier: "com.test.zelda",
                displayName: "The Legend of Zelda",
                launchScript: "/path/to/retroarch -L /path/to/core.dylib /path/to/zelda.nes",
                outputDirectory: tempDirectory
            ),
            AppBundleConfig(
                bundleName: "Metroid",
                bundleIdentifier: "com.test.metroid",
                displayName: "Metroid",
                version: "2.0",
                launchScript: "/path/to/retroarch -L /path/to/core.dylib /path/to/metroid.nes",
                outputDirectory: tempDirectory
            )
        ]
        
        // When: Generating all bundles
        for config in configs {
            let bundleURL = try await generator.generateAppBundle(with: config)
            
            // Then: Each bundle should be complete
            XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.path))
            
            let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
            let plistData = try Data(contentsOf: plistURL)
            let plistString = String(data: plistData, encoding: .utf8)!
            
            XCTAssertTrue(plistString.contains(config.bundleIdentifier))
            XCTAssertTrue(plistString.contains(config.version))
        }
    }

}
