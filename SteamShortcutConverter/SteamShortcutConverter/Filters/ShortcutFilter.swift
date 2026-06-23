//
//  ShortcutFilter.swift
//  SteamShortcutConverter
//
//  Filters ROM-related shortcuts by detecting emulator executables
//

import Foundation

/// Implementation of ShortcutFilter protocol for identifying ROM-related shortcuts
class DefaultShortcutFilter: ShortcutFilter {
    
    // MARK: - ShortcutFilter Protocol
    
    /// Filter shortcuts to only include ROM-related entries
    /// - Parameter shortcuts: Array of all Steam shortcuts
    /// - Returns: Array of ROM-related shortcuts
    func filterROMShortcuts(from shortcuts: [SteamShortcut]) -> [SteamShortcut] {
        return shortcuts.filter { shortcut in
            detectEmulator(for: shortcut) != nil
        }
    }
    
    /// Detect if a shortcut is for an emulator
    /// - Parameter shortcut: The shortcut to check
    /// - Returns: The detected emulator type, or nil if not an emulator
    func detectEmulator(for shortcut: SteamShortcut) -> EmulatorType? {
        return detectEmulatorFromPath(shortcut.exe)
    }
    
    // MARK: - Private Helper Methods
    
    /// Detect emulator type from an executable path
    /// - Parameter path: The executable path to analyze
    /// - Returns: The detected emulator type, or nil if not recognized
    private func detectEmulatorFromPath(_ path: String) -> EmulatorType? {
        // Normalize path for case-insensitive matching
        let lowercasedPath = path.lowercased()
        
        // Extract the executable name from the path
        // Handle both .app bundle paths and direct executable paths
        let executableName = extractExecutableName(from: lowercasedPath)

        // Check each emulator type for pattern matches
        for emulatorType in EmulatorType.allCases {
            for pattern in emulatorType.executablePatterns {
                if executableName.contains(pattern.lowercased()) {
                    return emulatorType
                }
            }
        }

        return nil
    }
    
    /// Extract the executable name from a path
    /// Handles both .app bundle paths (e.g., "/path/to/RetroArch.app") and
    /// direct executable paths (e.g., "/path/to/retroarch")
    /// Also handles paths with arguments (e.g., '"/path/to/RetroArch.app" -L ...')
    /// - Parameter path: The path to process (should be lowercased)
    /// - Returns: The executable name component
    private func extractExecutableName(from path: String) -> String {
        var processedPath = path.trimmingCharacters(in: .whitespaces)

        // The exe field is a single executable path. If it is wrapped in quotes,
        // extract the quoted contents; otherwise use the whole string. We must NOT
        // split on spaces — a path like "/Applications/My Emulators/RetroArch.app"
        // contains spaces yet is a single path.
        if processedPath.hasPrefix("\"") {
            // Find the closing quote
            if let endQuoteIndex = processedPath.dropFirst().firstIndex(of: "\"") {
                processedPath = String(processedPath[processedPath.index(after: processedPath.startIndex)..<endQuoteIndex])
            }
        }

        // Remove .app extension if present
        if processedPath.hasSuffix(".app") {
            processedPath = String(processedPath.dropLast(4))
        }
        
        // Get the last path component
        let components = processedPath.split(separator: "/")
        guard let lastComponent = components.last else {
            return path
        }
        
        return String(lastComponent)
    }
}
