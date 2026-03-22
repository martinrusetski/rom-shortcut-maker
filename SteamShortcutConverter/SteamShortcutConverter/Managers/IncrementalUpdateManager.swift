//
//  IncrementalUpdateManager.swift
//  SteamShortcutConverter
//
//  Manages incremental updates for app bundle generation
//

import Foundation
import CryptoKit

/// Represents the type of change detected for a shortcut
enum ShortcutChangeType {
    case new
    case modified
    case removed
    case unchanged
}

/// Represents a detected change in shortcuts
struct ShortcutChange {
    let shortcut: SteamShortcut?
    let changeType: ShortcutChangeType
    let previousBundlePath: String?
    
    init(shortcut: SteamShortcut?, changeType: ShortcutChangeType, previousBundlePath: String? = nil) {
        self.shortcut = shortcut
        self.changeType = changeType
        self.previousBundlePath = previousBundlePath
    }
}

/// Manager for detecting and handling incremental updates
class IncrementalUpdateManager {
    
    private let fileManager = FileManager.default
    
    // MARK: - Change Detection
    
    /// Compare current shortcuts against previous conversion state
    /// - Parameters:
    ///   - currentShortcuts: Current shortcuts from VDF file
    ///   - previousState: Previous conversion state (nil if first conversion)
    /// - Returns: Dictionary mapping app IDs to their change types
    func detectChanges(
        currentShortcuts: [SteamShortcut],
        previousState: ConversionState?
    ) -> [UInt32: ShortcutChange] {
        var changes: [UInt32: ShortcutChange] = [:]
        
        // If no previous state, all shortcuts are new
        guard let previousState = previousState else {
            for shortcut in currentShortcuts {
                changes[shortcut.appID] = ShortcutChange(
                    shortcut: shortcut,
                    changeType: .new
                )
            }
            return changes
        }
        
        // Build lookup dictionary for previous shortcuts
        let previousShortcuts = Dictionary(
            uniqueKeysWithValues: previousState.convertedShortcuts.map { ($0.appID, $0) }
        )
        
        // Build lookup dictionary for current shortcuts
        let currentShortcutsDict = Dictionary(
            uniqueKeysWithValues: currentShortcuts.map { ($0.appID, $0) }
        )
        
        // Check current shortcuts for new or modified entries
        for shortcut in currentShortcuts {
            if let previous = previousShortcuts[shortcut.appID] {
                // Shortcut exists in previous state - check if modified or if bundle is missing
                let currentLaunchHash = computeLaunchCommandHash(for: shortcut)
                let currentIconHash = computeIconHash(for: shortcut)
                
                // Check if the bundle actually exists on disk
                let bundleExists = fileManager.fileExists(atPath: previous.bundlePath)
                
                if !bundleExists {
                    // Bundle was deleted - treat as modified to regenerate
                    changes[shortcut.appID] = ShortcutChange(
                        shortcut: shortcut,
                        changeType: .modified,
                        previousBundlePath: previous.bundlePath
                    )
                } else if currentLaunchHash != previous.launchCommandHash ||
                   currentIconHash != previous.iconHash {
                    // Shortcut has been modified
                    changes[shortcut.appID] = ShortcutChange(
                        shortcut: shortcut,
                        changeType: .modified,
                        previousBundlePath: previous.bundlePath
                    )
                } else {
                    // Shortcut is unchanged
                    changes[shortcut.appID] = ShortcutChange(
                        shortcut: shortcut,
                        changeType: .unchanged,
                        previousBundlePath: previous.bundlePath
                    )
                }
            } else {
                // New shortcut not in previous state
                changes[shortcut.appID] = ShortcutChange(
                    shortcut: shortcut,
                    changeType: .new
                )
            }
        }
        
        // Check for removed shortcuts (in previous state but not current)
        for previous in previousState.convertedShortcuts {
            if currentShortcutsDict[previous.appID] == nil {
                // Shortcut was removed
                changes[previous.appID] = ShortcutChange(
                    shortcut: nil,
                    changeType: .removed,
                    previousBundlePath: previous.bundlePath
                )
            }
        }
        
        return changes
    }
    
    // MARK: - Hash Computation
    
    /// Compute hash of launch command for change detection
    /// - Parameter shortcut: The shortcut to hash
    /// - Returns: SHA256 hash of the launch command
    func computeLaunchCommandHash(for shortcut: SteamShortcut) -> String {
        // Combine exe, startDir, and launchOptions into a single string
        var commandString = shortcut.exe
        if let startDir = shortcut.startDir {
            commandString += "|" + startDir
        }
        if let launchOptions = shortcut.launchOptions {
            commandString += "|" + launchOptions
        }
        
        // Compute SHA256 hash
        let data = Data(commandString.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Compute hash of icon data for change detection
    /// - Parameter shortcut: The shortcut to hash
    /// - Returns: SHA256 hash of the icon data, or nil if no icon
    func computeIconHash(for shortcut: SteamShortcut) -> String? {
        guard let icon = shortcut.icon else {
            return nil
        }
        
        let data: Data
        switch icon {
        case .embedded(let iconData):
            data = iconData
        case .filePath(let path):
            // Hash the file path itself, not the file contents
            // This is faster and sufficient for change detection
            data = Data(path.utf8)
        }
        
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Bundle Cleanup
    
    /// Delete orphaned app bundles for removed shortcuts
    /// - Parameters:
    ///   - changes: Dictionary of detected changes
    ///   - removeOrphaned: Whether to actually delete the bundles
    /// - Returns: Array of bundle paths that were deleted
    func cleanupOrphanedBundles(
        changes: [UInt32: ShortcutChange],
        removeOrphaned: Bool
    ) throws -> [String] {
        guard removeOrphaned else {
            return []
        }
        
        var deletedPaths: [String] = []
        
        for (_, change) in changes {
            if change.changeType == .removed,
               let bundlePath = change.previousBundlePath {
                // Delete the bundle
                let bundleURL = URL(fileURLWithPath: bundlePath)
                
                if fileManager.fileExists(atPath: bundlePath) {
                    try fileManager.removeItem(at: bundleURL)
                    deletedPaths.append(bundlePath)
                    print("Deleted orphaned bundle: \(bundlePath)")
                }
            }
        }
        
        return deletedPaths
    }
    
    // MARK: - Conversion State Building
    
    /// Build a ConvertedShortcut record for a shortcut
    /// - Parameters:
    ///   - shortcut: The shortcut to record
    ///   - bundlePath: Path to the generated bundle
    /// - Returns: ConvertedShortcut record
    func buildConvertedShortcut(
        for shortcut: SteamShortcut,
        bundlePath: String
    ) -> ConvertedShortcut {
        let launchHash = computeLaunchCommandHash(for: shortcut)
        let iconHash = computeIconHash(for: shortcut)
        
        return ConvertedShortcut(
            appID: shortcut.appID,
            appName: shortcut.appName,
            launchCommandHash: launchHash,
            iconHash: iconHash,
            bundlePath: bundlePath
        )
    }
}
