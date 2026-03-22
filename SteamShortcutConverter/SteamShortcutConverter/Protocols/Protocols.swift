//
//  Protocols.swift
//  SteamShortcutConverter
//
//  Protocol definitions for core components
//

import Foundation

// MARK: - VDF Parser Protocol

/// Protocol for parsing Steam's binary VDF (Valve Data Format) files
protocol VDFParser {
    /// Parse a shortcuts.vdf file and extract all shortcuts
    /// - Parameter fileURL: URL to the shortcuts.vdf file
    /// - Returns: Array of parsed SteamShortcut objects
    /// - Throws: Error if file cannot be read or parsed
    func parseShortcuts(from fileURL: URL) async throws -> [SteamShortcut]
    
    /// Validate that a file is a valid VDF format
    /// - Parameter fileURL: URL to the file to validate
    /// - Returns: True if the file is valid VDF format
    func validateVDFFile(at fileURL: URL) async throws -> Bool
}

// MARK: - Shortcut Filter Protocol

/// Protocol for filtering ROM-related shortcuts from all Steam shortcuts
protocol ShortcutFilter {
    /// Filter shortcuts to only include ROM-related entries
    /// - Parameter shortcuts: Array of all Steam shortcuts
    /// - Returns: Array of ROM-related shortcuts
    func filterROMShortcuts(from shortcuts: [SteamShortcut]) -> [SteamShortcut]
    
    /// Detect if a shortcut is for an emulator
    /// - Parameter shortcut: The shortcut to check
    /// - Returns: The detected emulator type, or nil if not an emulator
    func detectEmulator(for shortcut: SteamShortcut) -> EmulatorType?
}

/// Supported emulator types
enum EmulatorType: String, CaseIterable {
    case retroArch = "RetroArch"
    case dolphin = "Dolphin"
    case pcsx2 = "PCSX2"
    case ppsspp = "PPSSPP"
    case citra = "Citra"
    case ryujinx = "Ryujinx"
    case mgba = "mGBA"
    case desmume = "DeSmuME"
    case openemu = "OpenEmu"
    case yuzu = "Yuzu"
    case cemu = "Cemu"
    
    /// Common executable name patterns for this emulator
    var executablePatterns: [String] {
        switch self {
        case .retroArch:
            return ["retroarch"]
        case .dolphin:
            return ["dolphin", "dolphin-emu"]
        case .pcsx2:
            return ["pcsx2"]
        case .ppsspp:
            return ["ppsspp"]
        case .citra:
            return ["citra"]
        case .ryujinx:
            return ["ryujinx"]
        case .mgba:
            return ["mgba"]
        case .desmume:
            return ["desmume"]
        case .openemu:
            return ["openemu"]
        case .yuzu:
            return ["yuzu"]
        case .cemu:
            return ["cemu"]
        }
    }
}

// MARK: - App Bundle Generator Protocol

/// Protocol for generating native macOS app bundles
protocol AppBundleGenerator {
    /// Generate a macOS app bundle from configuration
    /// - Parameter config: Configuration for the app bundle
    /// - Returns: URL to the generated app bundle
    /// - Throws: Error if bundle generation fails
    func generateAppBundle(with config: AppBundleConfig) async throws -> URL
    
    /// Convert icon data to .icns format
    /// - Parameters:
    ///   - iconData: The icon data to convert
    ///   - outputURL: URL where the .icns file should be saved
    /// - Throws: Error if conversion fails
    func convertIcon(_ iconData: IconData, to outputURL: URL) async throws
}

// MARK: - Configuration Manager Protocol

/// Protocol for managing application configuration persistence
protocol ConfigurationManager {
    /// Load the application configuration
    /// - Returns: The loaded configuration, or default if none exists
    func loadConfiguration() async throws -> AppConfiguration
    
    /// Save the application configuration
    /// - Parameter configuration: The configuration to save
    /// - Throws: Error if save fails
    func saveConfiguration(_ configuration: AppConfiguration) async throws
    
    /// Load the conversion state
    /// - Returns: The last conversion state, or nil if none exists
    func loadConversionState() async throws -> ConversionState?
    
    /// Save the conversion state
    /// - Parameter state: The conversion state to save
    /// - Throws: Error if save fails
    func saveConversionState(_ state: ConversionState) async throws
    
    /// Validate that a configuration is valid
    /// - Parameter configuration: The configuration to validate
    /// - Returns: True if the configuration is valid
    func validateConfiguration(_ configuration: AppConfiguration) async -> Bool
}
