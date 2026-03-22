//
//  ConfigurationManager.swift
//  SteamShortcutConverter
//
//  Configuration persistence and validation
//

import Foundation

/// Default implementation of ConfigurationManager protocol
class DefaultConfigurationManager: ConfigurationManager {
    
    // MARK: - Properties
    
    private let fileManager = FileManager.default
    private let configDirectory: URL
    private let configFileURL: URL
    private let conversionStateFileURL: URL
    
    // MARK: - Initialization
    
    init() throws {
        // Get Application Support directory
        guard let appSupportDir = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw ConfigurationError.applicationSupportDirectoryNotFound
        }
        
        // Create config directory path
        configDirectory = appSupportDir.appendingPathComponent("SteamShortcutConverter")
        configFileURL = configDirectory.appendingPathComponent("config.json")
        conversionStateFileURL = configDirectory.appendingPathComponent("conversion_state.json")
        
        // Create config directory if it doesn't exist
        try createConfigDirectoryIfNeeded()
    }
    
    // MARK: - ConfigurationManager Protocol
    
    func loadConfiguration() async throws -> AppConfiguration {
        // Check if config file exists
        guard fileManager.fileExists(atPath: configFileURL.path) else {
            // Return default configuration if file doesn't exist
            return .default
        }
        
        do {
            // Read config file
            let data = try Data(contentsOf: configFileURL)
            
            // Decode JSON
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let configuration = try decoder.decode(AppConfiguration.self, from: data)
            
            return configuration
        } catch {
            // If JSON is corrupted, return default configuration
            throw ConfigurationError.corruptedConfiguration(underlyingError: error)
        }
    }
    
    func saveConfiguration(_ configuration: AppConfiguration) async throws {
        // Ensure config directory exists
        try createConfigDirectoryIfNeeded()
        
        // Encode configuration to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(configuration)
        
        // Write to file
        try data.write(to: configFileURL, options: .atomic)
    }
    
    func loadConversionState() async throws -> ConversionState? {
        // Check if conversion state file exists
        guard fileManager.fileExists(atPath: conversionStateFileURL.path) else {
            return nil
        }
        
        do {
            // Read conversion state file
            let data = try Data(contentsOf: conversionStateFileURL)
            
            // Decode JSON
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(ConversionState.self, from: data)
            
            return state
        } catch {
            // If JSON is corrupted, return nil
            throw ConfigurationError.corruptedConversionState(underlyingError: error)
        }
    }
    
    func saveConversionState(_ state: ConversionState) async throws {
        // Ensure config directory exists
        try createConfigDirectoryIfNeeded()
        
        // Encode conversion state to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        
        // Write to file
        try data.write(to: conversionStateFileURL, options: .atomic)
    }
    
    func validateConfiguration(_ configuration: AppConfiguration) async -> Bool {
        // Validate shortcuts VDF path if specified
        if let vdfPath = configuration.shortcutsVDFPath {
            guard fileManager.fileExists(atPath: vdfPath) else {
                return false
            }
        }
        
        // Validate output directory if specified
        if let outputDir = configuration.outputDirectory {
            // Check if directory exists
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: outputDir, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return false
            }
            
            // Check if directory is writable
            guard fileManager.isWritableFile(atPath: outputDir) else {
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Private Helpers
    
    private func createConfigDirectoryIfNeeded() throws {
        guard !fileManager.fileExists(atPath: configDirectory.path) else {
            return
        }
        
        try fileManager.createDirectory(
            at: configDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}

// MARK: - Configuration Errors

enum ConfigurationError: LocalizedError {
    case applicationSupportDirectoryNotFound
    case corruptedConfiguration(underlyingError: Error)
    case corruptedConversionState(underlyingError: Error)
    case invalidPath(String)
    case directoryNotWritable(String)
    
    var errorDescription: String? {
        switch self {
        case .applicationSupportDirectoryNotFound:
            return "Could not locate Application Support directory"
        case .corruptedConfiguration(let error):
            return "Configuration file is corrupted: \(error.localizedDescription). Using default configuration."
        case .corruptedConversionState(let error):
            return "Conversion state file is corrupted: \(error.localizedDescription)"
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        case .directoryNotWritable(let path):
            return "Directory is not writable: \(path)"
        }
    }
}
