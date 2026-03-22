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
        
        print("[FILTER] path=\(path.prefix(80))")
        print("[FILTER] lowercased=\(lowercasedPath.prefix(80))")
        print("[FILTER] extracted=\(executableName)")
        
        // Check each emulator type for pattern matches
        for emulatorType in EmulatorType.allCases {
            for pattern in emulatorType.executablePatterns {
                if executableName.contains(pattern.lowercased()) {
                    print("[FILTER] MATCHED \(emulatorType.rawValue)")
                    return emulatorType
                }
            }
        }
        
        print("[FILTER] NO MATCH")
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
        
        // If the path starts with a quote, extract just the quoted part
        if processedPath.hasPrefix("\"") {
            // Find the closing quote
            if let endQuoteIndex = processedPath.dropFirst().firstIndex(of: "\"") {
                processedPath = String(processedPath[processedPath.index(after: processedPath.startIndex)..<endQuoteIndex])
            }
        } else {
            // No quotes - split on space to get just the executable path
            if let spaceIndex = processedPath.firstIndex(of: " ") {
                processedPath = String(processedPath[..<spaceIndex])
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
