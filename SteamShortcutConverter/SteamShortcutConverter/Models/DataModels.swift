//
//  DataModels.swift
//  SteamShortcutConverter
//
//  Core data structures for the Steam Shortcut to App Bundle Converter
//

import Foundation
import CryptoKit

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
    var customNames: [UInt32: String]
    
    init(
        shortcutsVDFPath: String? = nil,
        outputDirectory: String? = nil,
        selectedShortcutIDs: Set<UInt32> = [],
        removeOrphanedBundles: Bool = false,
        lastConversionDate: Date? = nil,
        customNames: [UInt32: String] = [:]
    ) {
        self.shortcutsVDFPath = shortcutsVDFPath
        self.outputDirectory = outputDirectory
        self.selectedShortcutIDs = selectedShortcutIDs
        self.removeOrphanedBundles = removeOrphanedBundles
        self.lastConversionDate = lastConversionDate
        self.customNames = customNames
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

// MARK: - ROM Pipeline: Platform

/// A game platform / console, as defined by the System Database (Phase A2).
/// This is a lightweight identity value (id + display name); the database owns
/// the richer per-platform data (folder aliases, extensions, emulator options).
struct Platform: Codable, Equatable, Hashable, Identifiable {
    let id: String            // canonical id, e.g. "snes"
    let displayName: String   // e.g. "SNES"

    init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

// MARK: - ROM Pipeline: Emulator Choice

/// How a ROM is launched: either a standalone emulator, or RetroArch with a
/// specific core. A platform can have several valid choices and which ones are
/// usable depends on what the user has installed, which is why the assignment is
/// a choice, not a bare `EmulatorType`.
enum EmulatorChoice: Equatable, Hashable {
    case standalone(EmulatorType)
    case retroArchCore(core: String)   // e.g. "snes9x_libretro.dylib"

    /// Stable identity string for change detection. Distinguishes two RetroArch
    /// cores, which share the same emulator binary and args template and would
    /// otherwise hash identically.
    var signatureToken: String {
        switch self {
        case .standalone(let type): return "standalone:" + type.rawValue
        case .retroArchCore(let core): return "core:" + core
        }
    }

    /// A cheap, value-typed display name for list rows — no database lookup.
    /// The richer, curated names (e.g. "bsnes (RetroArch)") live in the
    /// database and are used in the Game Properties window.
    var shortDisplayName: String {
        switch self {
        case .standalone(let type):
            return type.rawValue
        case .retroArchCore(let core):
            return core
                .replacingOccurrences(of: "_libretro.dylib", with: "")
                .replacingOccurrences(of: ".dylib", with: "")
        }
    }
}

extension EmulatorChoice: Codable {
    // Tagged-object encoding, matching config.json v2:
    //   { "type": "standalone",    "emulator": "Snes9x" }
    //   { "type": "retroArchCore", "core": "snes9x_libretro.dylib" }
    enum CodingKeys: String, CodingKey {
        case type
        case emulator
        case core
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .standalone(let type):
            try container.encode("standalone", forKey: .type)
            try container.encode(type.rawValue, forKey: .emulator)
        case .retroArchCore(let core):
            try container.encode("retroArchCore", forKey: .type)
            try container.encode(core, forKey: .core)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "standalone":
            let raw = try container.decode(String.self, forKey: .emulator)
            guard let emulator = EmulatorType(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .emulator,
                    in: container,
                    debugDescription: "Unknown emulator identifier: \(raw)"
                )
            }
            self = .standalone(emulator)
        case "retroArchCore":
            let core = try container.decode(String.self, forKey: .core)
            self = .retroArchCore(core: core)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown EmulatorChoice type: \(type)"
            )
        }
    }
}

// MARK: - ROM Pipeline: Artwork Status

/// Runtime status of a game's artwork.
enum ArtworkStatus: Equatable {
    case none
    case downloading
    case cached(URL)
    case failed(String)
}

extension ArtworkStatus: Codable {
    enum CodingKeys: String, CodingKey {
        case type
        case url
        case message
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try container.encode("none", forKey: .type)
        case .downloading:
            try container.encode("downloading", forKey: .type)
        case .cached(let url):
            try container.encode("cached", forKey: .type)
            try container.encode(url, forKey: .url)
        case .failed(let message):
            try container.encode("failed", forKey: .type)
            try container.encode(message, forKey: .message)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "none":
            self = .none
        case "downloading":
            self = .downloading
        case "cached":
            let url = try container.decode(URL.self, forKey: .url)
            self = .cached(url)
        case "failed":
            let message = try container.decode(String.self, forKey: .message)
            self = .failed(message)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown ArtworkStatus type: \(type)"
            )
        }
    }
}

// MARK: - ROM Pipeline: Game Source

/// Where a game entry originated.
enum GameSource: String, Codable {
    case romScan
    case steamVDF
}

// MARK: - ROM Pipeline: Game Status

/// At-a-glance readiness of a game, surfaced in the main list. Only `.ready`
/// games generate a bundle; the others are visibly flagged so a problem is
/// noticeable without opening anything. Artwork-missing is deliberately NOT a
/// status — the bundle falls back to a default icon, so it isn't "attention".
enum GameStatus: Equatable {
    case ready
    case noEmulator
    case unknownPlatform
}

// MARK: - ROM Pipeline: ROM Metadata

/// Metadata parsed from a ROM filename by `ROMFilenameParser`.
struct ROMMetadata: Codable, Equatable {
    let rawFilename: String
    let title: String
    let region: String?
    let version: String?
    let discNumber: Int?
    let discTotal: Int?
    let languages: [String]
    let flags: [String]

    init(
        rawFilename: String,
        title: String,
        region: String? = nil,
        version: String? = nil,
        discNumber: Int? = nil,
        discTotal: Int? = nil,
        languages: [String] = [],
        flags: [String] = []
    ) {
        self.rawFilename = rawFilename
        self.title = title
        self.region = region
        self.version = version
        self.discNumber = discNumber
        self.discTotal = discTotal
        self.languages = languages
        self.flags = flags
    }
}

// MARK: - ROM Pipeline: Game Entry

/// The core entity of the ROM pipeline. Supplants `SteamShortcut` everywhere
/// except the VDF import bridge.
struct GameEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String              // Display name (custom override or parsed title)
    let romPath: URL               // Path to ROM file on disk
    var romMetadata: ROMMetadata   // Parsed from filename
    var platform: Platform         // Resolved platform (see SystemDatabase)
    var emulator: EmulatorChoice?  // Assigned emulator choice (nil = unresolved)
    var emulatorPath: URL?         // Resolved executable path (RetroArch binary, for cores)
    var argsTemplate: String       // Argument template (defaults from emulator DB)
    var isSelected: Bool
    var artworkStatus: ArtworkStatus
    var source: GameSource

    /// Track / disc member files referenced by `romPath` (a .cue's tracks, an
    /// .m3u's discs). Hashed for change detection; not launched directly.
    var additionalFiles: [URL]
    /// Other launchable images of the same disc (e.g. a .chd alongside a .cue)
    /// the user can switch to.
    var alternateImages: [URL]
    /// User-chosen launch image among `romPath` + `alternateImages`. When nil,
    /// `romPath` (the platform-preferred image) is used. Does NOT affect
    /// `stableKey` — switching the image is the same game.
    var launchImage: URL?

    /// The path actually launched: the chosen image, else the primary rom path.
    var launchPath: URL { launchImage ?? romPath }

    /// At-a-glance readiness, derived purely from the entry (no I/O, no database
    /// lookup) so list rows can render it without observing the ViewModel. A
    /// known platform with no assigned emulator means nothing installed can run
    /// it; an "unknown" platform means the scan couldn't classify the ROM.
    var status: GameStatus {
        if platform.id == "unknown" { return .unknownPlatform }
        if emulator == nil { return .noEmulator }
        return .ready
    }

    /// Stable identity for caching/overrides: derived from `romPath`, NOT the
    /// random UUID. Use this (not `id`) as the key for gameOverrides and the
    /// artwork cache so re-scanning the same library reattaches state.
    var stableKey: String {
        let normalizedPath = romPath.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(normalizedPath.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    init(
        id: UUID = UUID(),
        title: String,
        romPath: URL,
        romMetadata: ROMMetadata,
        platform: Platform,
        emulator: EmulatorChoice? = nil,
        emulatorPath: URL? = nil,
        argsTemplate: String = "",
        isSelected: Bool = true,
        artworkStatus: ArtworkStatus = .none,
        source: GameSource = .romScan,
        additionalFiles: [URL] = [],
        alternateImages: [URL] = [],
        launchImage: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.romPath = romPath
        self.romMetadata = romMetadata
        self.platform = platform
        self.emulator = emulator
        self.emulatorPath = emulatorPath
        self.argsTemplate = argsTemplate
        self.isSelected = isSelected
        self.artworkStatus = artworkStatus
        self.source = source
        self.additionalFiles = additionalFiles
        self.alternateImages = alternateImages
        self.launchImage = launchImage
    }
}
