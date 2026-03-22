//
//  DataModels.swift
//  SteamShortcutConverter
//
//  Core data structures for the Steam Shortcut to App Bundle Converter
//

import Foundation

// MARK: - Steam Shortcut Data

/// Represents a single shortcut entry from Steam's shortcuts.vdf file
struct SteamShortcut: Equatable, Codable {
    let appID: UInt32
    let appName: String
    let exe: String
    let startDir: String?
    let launchOptions: String?
    let icon: IconData?
    let tags: [String]
    
    init(
        appID: UInt32,
        appName: String,
        exe: String,
        startDir: String? = nil,
        launchOptions: String? = nil,
        icon: IconData? = nil,
        tags: [String] = []
    ) {
        self.appID = appID
        self.appName = appName
        self.exe = exe
        self.startDir = startDir
        self.launchOptions = launchOptions
        self.icon = icon
        self.tags = tags
    }
}

// MARK: - Icon Data

/// Represents icon data from a Steam shortcut (either embedded or file path)
enum IconData: Equatable, Codable {
    case embedded(Data)
    case filePath(String)
    
    enum CodingKeys: String, CodingKey {
        case type
        case data
        case path
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .embedded(let data):
            try container.encode("embedded", forKey: .type)
            try container.encode(data, forKey: .data)
        case .filePath(let path):
            try container.encode("filePath", forKey: .type)
            try container.encode(path, forKey: .path)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "embedded":
            let data = try container.decode(Data.self, forKey: .data)
            self = .embedded(data)
        case "filePath":
            let path = try container.decode(String.self, forKey: .path)
            self = .filePath(path)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown IconData type: \(type)"
            )
        }
    }
}

// MARK: - App Bundle Configuration

/// Configuration for generating a single app bundle
struct AppBundleConfig: Equatable {
    let bundleName: String
    let bundleIdentifier: String
    let displayName: String
    let version: String
    let launchScript: String
    let iconData: IconData?
    let outputDirectory: URL
    
    init(
        bundleName: String,
        bundleIdentifier: String,
        displayName: String,
        version: String = "1.0",
        launchScript: String,
        iconData: IconData? = nil,
        outputDirectory: URL
    ) {
        self.bundleName = bundleName
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.version = version
        self.launchScript = launchScript
        self.iconData = iconData
        self.outputDirectory = outputDirectory
    }
}

// MARK: - Application Configuration

/// Persistent application configuration
struct AppConfiguration: Equatable, Codable {
    var shortcutsVDFPath: String?
    var outputDirectory: String?
    var selectedShortcutIDs: Set<UInt32>
    var removeOrphanedBundles: Bool
    var lastConversionDate: Date?
    
    init(
        shortcutsVDFPath: String? = nil,
        outputDirectory: String? = nil,
        selectedShortcutIDs: Set<UInt32> = [],
        removeOrphanedBundles: Bool = false,
        lastConversionDate: Date? = nil
    ) {
        self.shortcutsVDFPath = shortcutsVDFPath
        self.outputDirectory = outputDirectory
        self.selectedShortcutIDs = selectedShortcutIDs
        self.removeOrphanedBundles = removeOrphanedBundles
        self.lastConversionDate = lastConversionDate
    }
    
    static var `default`: AppConfiguration {
        AppConfiguration()
    }
}

// MARK: - Conversion State

/// Represents the state of a conversion operation
struct ConversionState: Equatable, Codable {
    let timestamp: Date
    let sourceVDFPath: String
    let convertedShortcuts: [ConvertedShortcut]
    
    init(
        timestamp: Date = Date(),
        sourceVDFPath: String,
        convertedShortcuts: [ConvertedShortcut]
    ) {
        self.timestamp = timestamp
        self.sourceVDFPath = sourceVDFPath
        self.convertedShortcuts = convertedShortcuts
    }
}

// MARK: - Converted Shortcut

/// Record of a converted shortcut for incremental update tracking
struct ConvertedShortcut: Equatable, Codable, Hashable {
    let appID: UInt32
    let appName: String
    let launchCommandHash: String
    let iconHash: String?
    let bundlePath: String
    
    init(
        appID: UInt32,
        appName: String,
        launchCommandHash: String,
        iconHash: String? = nil,
        bundlePath: String
    ) {
        self.appID = appID
        self.appName = appName
        self.launchCommandHash = launchCommandHash
        self.iconHash = iconHash
        self.bundlePath = bundlePath
    }
}

// MARK: - Launch Configuration

/// Extracted launch configuration from a Steam shortcut
struct LaunchConfiguration: Equatable {
    let executablePath: String
    let arguments: [String]
    let workingDirectory: String?
    
    init(
        executablePath: String,
        arguments: [String] = [],
        workingDirectory: String? = nil
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.workingDirectory = workingDirectory
    }
}

// MARK: - Conversion Summary

/// Summary of a conversion operation
struct ConversionSummary: Equatable {
    let bundlesCreated: Int
    let bundlesUpdated: Int
    let bundlesSkipped: Int
    let bundlesRemoved: Int
    let errors: [ConversionError]
    let warnings: [ConversionWarning]
    
    init(
        bundlesCreated: Int = 0,
        bundlesUpdated: Int = 0,
        bundlesSkipped: Int = 0,
        bundlesRemoved: Int = 0,
        errors: [ConversionError] = [],
        warnings: [ConversionWarning] = []
    ) {
        self.bundlesCreated = bundlesCreated
        self.bundlesUpdated = bundlesUpdated
        self.bundlesSkipped = bundlesSkipped
        self.bundlesRemoved = bundlesRemoved
        self.errors = errors
        self.warnings = warnings
    }
    
    var totalBundles: Int {
        bundlesCreated + bundlesUpdated
    }
    
    var hasIssues: Bool {
        !errors.isEmpty || !warnings.isEmpty
    }
}

/// Represents an error that occurred during conversion
struct ConversionError: Equatable, Identifiable {
    let id = UUID()
    let shortcutName: String
    let message: String
    
    static func == (lhs: ConversionError, rhs: ConversionError) -> Bool {
        lhs.shortcutName == rhs.shortcutName && lhs.message == rhs.message
    }
}

/// Represents a warning that occurred during conversion
struct ConversionWarning: Equatable, Identifiable {
    let id = UUID()
    let shortcutName: String
    let type: WarningType
    let message: String
    
    enum WarningType: String, Equatable {
        case missingEmulator = "Missing Emulator"
        case missingROM = "Missing ROM"
        case iconConversionFailure = "Icon Conversion Failed"
    }
    
    static func == (lhs: ConversionWarning, rhs: ConversionWarning) -> Bool {
        lhs.shortcutName == rhs.shortcutName && 
        lhs.type == rhs.type && 
        lhs.message == rhs.message
    }
}

// MARK: - Error Types

/// Represents different types of errors that can occur in the application
enum AppError: LocalizedError, Equatable {
    case fileNotFound(path: String)
    case invalidVDFFormat(path: String)
    case outputDirectoryNotWritable(path: String)
    case conversionFailed(shortcutName: String, reason: String)
    case configurationError(message: String)
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .invalidVDFFormat(let path):
            return "Invalid VDF format in file: \(path). Please ensure this is a valid shortcuts.vdf file."
        case .outputDirectoryNotWritable(let path):
            return "Cannot write to output directory: \(path). Please select a different location."
        case .conversionFailed(let shortcutName, let reason):
            return "Failed to convert '\(shortcutName)': \(reason)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        }
    }
    
    var actionableMessage: String {
        switch self {
        case .fileNotFound:
            return "Use the Browse button to select a valid shortcuts.vdf file."
        case .invalidVDFFormat:
            return "Try running Steam ROM Manager to regenerate the shortcuts file."
        case .outputDirectoryNotWritable:
            return "Choose a different output directory with write permissions."
        case .conversionFailed:
            return "Check that the emulator and ROM files exist at the specified paths."
        case .configurationError:
            return "Reset configuration or manually correct the settings."
        }
    }
}
