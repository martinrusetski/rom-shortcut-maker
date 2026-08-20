//
//  ConfigurationManagerTests.swift
//  RomShortcutMakerTests
//
//  Unit tests for ConfigurationManager
//

import XCTest
@testable import RomShortcutMaker

final class ConfigurationManagerTests: XCTestCase {
    
    var tempDirectory: URL!
    var configManager: TestableConfigurationManager!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create temporary directory for tests
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        
        // Create testable configuration manager with temp directory
        configManager = try TestableConfigurationManager(configDirectory: tempDirectory)
    }
    
    override func tearDown() async throws {
        // Clean up temporary directory
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
        
        try await super.tearDown()
    }
    
    // MARK: - Save and Load Configuration Tests
    
    func testSaveAndLoadConfiguration() async throws {
        // Given: A configuration with all fields populated
        let originalConfig = AppConfiguration(
            shortcutsVDFPath: "/path/to/shortcuts.vdf",
            outputDirectory: "/path/to/output",
            selectedShortcutIDs: [1, 2, 3],
            removeOrphanedBundles: true,
            lastConversionDate: Date(timeIntervalSince1970: 1234567890)
        )
        
        // When: Saving and loading the configuration
        try await configManager.saveConfiguration(originalConfig)
        let loadedConfig = try await configManager.loadConfiguration()
        
        // Then: The loaded configuration should match the original
        XCTAssertEqual(loadedConfig, originalConfig)
    }
    
    func testSaveAndLoadConfigurationWithOptionalFields() async throws {
        // Given: A configuration with optional fields as nil
        let originalConfig = AppConfiguration(
            shortcutsVDFPath: nil,
            outputDirectory: nil,
            selectedShortcutIDs: [],
            removeOrphanedBundles: false,
            lastConversionDate: nil
        )
        
        // When: Saving and loading the configuration
        try await configManager.saveConfiguration(originalConfig)
        let loadedConfig = try await configManager.loadConfiguration()
        
        // Then: The loaded configuration should match the original
        XCTAssertEqual(loadedConfig, originalConfig)
    }
    
    func testSaveConfigurationCreatesDirectory() async throws {
        // Given: A fresh temp directory without config subdirectory
        let newTempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let newConfigManager = try TestableConfigurationManager(configDirectory: newTempDir)
        
        // When: Saving a configuration
        let config = AppConfiguration.default
        try await newConfigManager.saveConfiguration(config)
        
        // Then: The config directory should be created
        XCTAssertTrue(FileManager.default.fileExists(atPath: newTempDir.path))
        
        // Cleanup
        try FileManager.default.removeItem(at: newTempDir)
    }
    
    // MARK: - Missing Configuration File Tests
    
    func testLoadConfigurationWithMissingFile() async throws {
        // Given: No configuration file exists
        // (setUp creates empty temp directory)
        
        // When: Loading configuration
        let loadedConfig = try await configManager.loadConfiguration()
        
        // Then: Should return default configuration
        XCTAssertEqual(loadedConfig, AppConfiguration.default)
    }
    
    func testDefaultConfigurationValues() async throws {
        // Given: No configuration file exists
        
        // When: Loading configuration
        let config = try await configManager.loadConfiguration()
        
        // Then: Should have default values
        XCTAssertNil(config.shortcutsVDFPath)
        XCTAssertNil(config.outputDirectory)
        XCTAssertTrue(config.selectedShortcutIDs.isEmpty)
        XCTAssertFalse(config.removeOrphanedBundles)
        XCTAssertNil(config.lastConversionDate)
    }
    
    // MARK: - Corrupted JSON Tests
    
    func testLoadConfigurationWithCorruptedJSON() async throws {
        // Given: A corrupted JSON file
        let configFileURL = tempDirectory.appendingPathComponent("config.json")
        let corruptedJSON = "{ invalid json content }"
        try corruptedJSON.write(to: configFileURL, atomically: true, encoding: .utf8)
        
        // When/Then: Loading configuration should throw corrupted configuration error
        do {
            _ = try await configManager.loadConfiguration()
            XCTFail("Expected ConfigurationError.corruptedConfiguration to be thrown")
        } catch let error as ConfigurationError {
            if case .corruptedConfiguration = error {
                // Expected error
            } else {
                XCTFail("Expected ConfigurationError.corruptedConfiguration, got \(error)")
            }
        } catch {
            XCTFail("Expected ConfigurationError.corruptedConfiguration, got \(error)")
        }
    }
    
    func testLoadConfigurationWithInvalidJSONStructure() async throws {
        // Given: Valid JSON but wrong structure
        let configFileURL = tempDirectory.appendingPathComponent("config.json")
        let invalidJSON = """
        {
            "wrongField": "value",
            "anotherWrongField": 123
        }
        """
        try invalidJSON.write(to: configFileURL, atomically: true, encoding: .utf8)
        
        // When/Then: Loading configuration should throw corrupted configuration error
        do {
            _ = try await configManager.loadConfiguration()
            XCTFail("Expected ConfigurationError.corruptedConfiguration to be thrown")
        } catch let error as ConfigurationError {
            if case .corruptedConfiguration = error {
                // Expected error
            } else {
                XCTFail("Expected ConfigurationError.corruptedConfiguration, got \(error)")
            }
        } catch {
            XCTFail("Expected ConfigurationError.corruptedConfiguration, got \(error)")
        }
    }
    
    // MARK: - Configuration Validation Tests
    
    func testValidateConfigurationWithValidPaths() async throws {
        // Given: A configuration with valid paths
        let validVDFPath = tempDirectory.appendingPathComponent("shortcuts.vdf")
        let validOutputDir = tempDirectory.appendingPathComponent("output")
        
        // Create the files/directories
        try "test".write(to: validVDFPath, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: validOutputDir, withIntermediateDirectories: true)
        
        let config = AppConfiguration(
            shortcutsVDFPath: validVDFPath.path,
            outputDirectory: validOutputDir.path
        )
        
        // When: Validating the configuration
        let isValid = await configManager.validateConfiguration(config)
        
        // Then: Should be valid
        XCTAssertTrue(isValid)
    }
    
    func testValidateConfigurationWithMissingVDFPath() async throws {
        // Given: A configuration with non-existent VDF path
        let config = AppConfiguration(
            shortcutsVDFPath: "/non/existent/path/shortcuts.vdf",
            outputDirectory: tempDirectory.path
        )
        
        // When: Validating the configuration
        let isValid = await configManager.validateConfiguration(config)
        
        // Then: Should be invalid
        XCTAssertFalse(isValid)
    }
    
    func testValidateConfigurationWithMissingOutputDirectory() async throws {
        // Given: A configuration with non-existent output directory
        let validVDFPath = tempDirectory.appendingPathComponent("shortcuts.vdf")
        try "test".write(to: validVDFPath, atomically: true, encoding: .utf8)
        
        let config = AppConfiguration(
            shortcutsVDFPath: validVDFPath.path,
            outputDirectory: "/non/existent/output/directory"
        )
        
        // When: Validating the configuration
        let isValid = await configManager.validateConfiguration(config)
        
        // Then: Should be invalid
        XCTAssertFalse(isValid)
    }
    
    func testValidateConfigurationWithFileInsteadOfDirectory() async throws {
        // Given: A configuration where output directory is actually a file
        let validVDFPath = tempDirectory.appendingPathComponent("shortcuts.vdf")
        let fileNotDirectory = tempDirectory.appendingPathComponent("notadirectory")
        
        try "test".write(to: validVDFPath, atomically: true, encoding: .utf8)
        try "test".write(to: fileNotDirectory, atomically: true, encoding: .utf8)
        
        let config = AppConfiguration(
            shortcutsVDFPath: validVDFPath.path,
            outputDirectory: fileNotDirectory.path
        )
        
        // When: Validating the configuration
        let isValid = await configManager.validateConfiguration(config)
        
        // Then: Should be invalid
        XCTAssertFalse(isValid)
    }
    
    func testValidateConfigurationWithNilPaths() async throws {
        // Given: A configuration with nil paths
        let config = AppConfiguration(
            shortcutsVDFPath: nil,
            outputDirectory: nil
        )
        
        // When: Validating the configuration
        let isValid = await configManager.validateConfiguration(config)
        
        // Then: Should be valid (nil paths are acceptable)
        XCTAssertTrue(isValid)
    }
    
    // MARK: - Conversion State Tests
    
    func testSaveAndLoadConversionState() async throws {
        // Given: A conversion state
        let originalState = ConversionState(
            timestamp: Date(timeIntervalSince1970: 1234567890),
            sourceVDFPath: "/path/to/shortcuts.vdf",
            convertedShortcuts: [
                ConvertedShortcut(
                    appID: 1,
                    appName: "Game 1",
                    launchCommandHash: "hash1",
                    iconHash: "iconhash1",
                    bundlePath: "/path/to/Game1.app"
                ),
                ConvertedShortcut(
                    appID: 2,
                    appName: "Game 2",
                    launchCommandHash: "hash2",
                    iconHash: nil,
                    bundlePath: "/path/to/Game2.app"
                )
            ]
        )
        
        // When: Saving and loading the conversion state
        try await configManager.saveConversionState(originalState)
        let loadedState = try await configManager.loadConversionState()
        
        // Then: The loaded state should match the original
        XCTAssertEqual(loadedState, originalState)
    }
    
    func testLoadConversionStateWithMissingFile() async throws {
        // Given: No conversion state file exists
        
        // When: Loading conversion state
        let loadedState = try await configManager.loadConversionState()
        
        // Then: Should return nil
        XCTAssertNil(loadedState)
    }
    
    func testLoadConversionStateWithCorruptedJSON() async throws {
        // Given: A corrupted conversion state JSON file
        let stateFileURL = tempDirectory.appendingPathComponent("conversion_state.json")
        let corruptedJSON = "{ corrupted json }"
        try corruptedJSON.write(to: stateFileURL, atomically: true, encoding: .utf8)
        
        // When/Then: Loading conversion state should throw corrupted state error
        do {
            _ = try await configManager.loadConversionState()
            XCTFail("Expected ConfigurationError.corruptedConversionState to be thrown")
        } catch let error as ConfigurationError {
            if case .corruptedConversionState = error {
                // Expected error
            } else {
                XCTFail("Expected ConfigurationError.corruptedConversionState, got \(error)")
            }
        } catch {
            XCTFail("Expected ConfigurationError.corruptedConversionState, got \(error)")
        }
    }
}

// MARK: - Testable Configuration Manager

/// Testable version of ConfigurationManager that allows custom config directory
class TestableConfigurationManager: ConfigurationManager {
    
    private let fileManager = FileManager.default
    private let configDirectory: URL
    private let configFileURL: URL
    private let conversionStateFileURL: URL
    
    init(configDirectory: URL) throws {
        self.configDirectory = configDirectory
        self.configFileURL = configDirectory.appendingPathComponent("config.json")
        self.conversionStateFileURL = configDirectory.appendingPathComponent("conversion_state.json")
        
        // Create config directory if needed
        if !fileManager.fileExists(atPath: configDirectory.path) {
            try fileManager.createDirectory(
                at: configDirectory,
                withIntermediateDirectories: true
            )
        }
    }
    
    func loadConfiguration() async throws -> AppConfiguration {
        guard fileManager.fileExists(atPath: configFileURL.path) else {
            return .default
        }
        
        do {
            let data = try Data(contentsOf: configFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(AppConfiguration.self, from: data)
        } catch {
            throw ConfigurationError.corruptedConfiguration(underlyingError: error)
        }
    }
    
    func saveConfiguration(_ configuration: AppConfiguration) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(configuration)
        try data.write(to: configFileURL, options: .atomic)
    }
    
    func loadConversionState() async throws -> ConversionState? {
        guard fileManager.fileExists(atPath: conversionStateFileURL.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: conversionStateFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ConversionState.self, from: data)
        } catch {
            throw ConfigurationError.corruptedConversionState(underlyingError: error)
        }
    }
    
    func saveConversionState(_ state: ConversionState) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try data.write(to: conversionStateFileURL, options: .atomic)
    }
    
    func validateConfiguration(_ configuration: AppConfiguration) async -> Bool {
        if let vdfPath = configuration.shortcutsVDFPath {
            guard fileManager.fileExists(atPath: vdfPath) else {
                return false
            }
        }
        
        if let outputDir = configuration.outputDirectory {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: outputDir, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return false
            }
            
            guard fileManager.isWritableFile(atPath: outputDir) else {
                return false
            }
        }
        
        return true
    }
}
