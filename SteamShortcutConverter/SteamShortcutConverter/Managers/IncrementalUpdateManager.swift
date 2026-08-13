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

// MARK: - ROM Pipeline change types

/// A detected change for a ROM-pipeline game entry.
struct GameChange {
    let entry: GameEntry?
    let changeType: ShortcutChangeType
    let previousBundlePath: String?

    init(entry: GameEntry?, changeType: ShortcutChangeType, previousBundlePath: String? = nil) {
        self.entry = entry
        self.changeType = changeType
        self.previousBundlePath = previousBundlePath
    }
}

/// Record of a converted game for incremental update tracking. Keyed by
/// `stableKey` (ROM-path hash), NOT a Steam appID.
struct ConvertedGame: Equatable, Codable, Hashable {
    let stableKey: String
    let title: String
    let changeSignatureHash: String
    let bundlePath: String
}

/// Previous conversion state for the ROM pipeline.
struct GameConversionState: Equatable, Codable {
    let timestamp: Date
    let convertedGames: [ConvertedGame]

    init(timestamp: Date = Date(), convertedGames: [ConvertedGame]) {
        self.timestamp = timestamp
        self.convertedGames = convertedGames
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
    ///   - customNames: Dictionary of custom names for shortcuts
    /// - Returns: Dictionary mapping app IDs to their change types
    func detectChanges(
        currentShortcuts: [SteamShortcut],
        previousState: ConversionState?,
        customNames: [UInt32: String] = [:]
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
        
        // Build lookup dictionary for previous shortcuts (handle duplicates by keeping first)
        var previousShortcuts: [UInt32: ConvertedShortcut] = [:]
        for record in previousState.convertedShortcuts {
            if previousShortcuts[record.appID] == nil {
                previousShortcuts[record.appID] = record
            }
        }
        
        // Build lookup dictionary for current shortcuts (handle duplicates by keeping first)
        var currentShortcutsDict: [UInt32: SteamShortcut] = [:]
        for shortcut in currentShortcuts {
            if currentShortcutsDict[shortcut.appID] == nil {
                currentShortcutsDict[shortcut.appID] = shortcut
            }
        }
        
        // Check current shortcuts for new or modified entries
        for shortcut in currentShortcuts {
            if let previous = previousShortcuts[shortcut.appID] {
                // Shortcut exists in previous state - check if modified or if bundle is missing
                let currentLaunchHash = computeLaunchCommandHash(for: shortcut)
                let currentIconHash = computeIconHash(for: shortcut)
                
                // Get current display name (custom or original)
                let currentDisplayName = customNames[shortcut.appID] ?? shortcut.appName
                
                // Check if the bundle actually exists on disk
                let bundleExists = fileManager.fileExists(atPath: previous.bundlePath)
                
                // Check if the name has changed (which would change the bundle path)
                let nameChanged = currentDisplayName != previous.appName
                
                if !bundleExists {
                    // Bundle was deleted - treat as modified to regenerate
                    changes[shortcut.appID] = ShortcutChange(
                        shortcut: shortcut,
                        changeType: .modified,
                        previousBundlePath: previous.bundlePath
                    )
                } else if nameChanged {
                    // Name changed - need to delete old bundle and create new one
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
                    Logger.shared.logBundleDeleted(bundlePath)
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

    // MARK: - ROM Pipeline: Change Detection

    /// Compare current game entries against a previous conversion state, keyed by
    /// `stableKey`. Preserves the "regenerate if the bundle is missing on disk"
    /// behavior of the Steam path.
    func detectChanges(
        currentGames: [GameEntry],
        previousState: GameConversionState?,
        outputDirectory: URL?
    ) -> [String: GameChange] {
        var changes: [String: GameChange] = [:]

        guard let previousState = previousState else {
            for entry in currentGames {
                changes[entry.stableKey] = GameChange(entry: entry, changeType: .new)
            }
            return changes
        }

        var previousByKey: [String: ConvertedGame] = [:]
        for record in previousState.convertedGames where previousByKey[record.stableKey] == nil {
            previousByKey[record.stableKey] = record
        }

        var currentKeys: Set<String> = []
        for entry in currentGames {
            currentKeys.insert(entry.stableKey)
            if let previous = previousByKey[entry.stableKey] {
                let signature = computeChangeSignature(for: entry)
                let bundleExists = fileManager.fileExists(atPath: previous.bundlePath)
                let expectedBundlePath = outputDirectory?
                    .appendingPathComponent(DefaultAppBundleGenerator.sanitizedBundleName(entry.title))
                    .appendingPathExtension("app")
                    .standardizedFileURL.path
                let previousBundlePath = URL(fileURLWithPath: previous.bundlePath)
                    .standardizedFileURL.path
                let destinationChanged = expectedBundlePath.map { $0 != previousBundlePath } ?? false
                if !bundleExists {
                    changes[entry.stableKey] = GameChange(entry: entry, changeType: .modified, previousBundlePath: previous.bundlePath)
                } else if destinationChanged {
                    changes[entry.stableKey] = GameChange(entry: entry, changeType: .modified, previousBundlePath: previous.bundlePath)
                } else if signature != previous.changeSignatureHash {
                    changes[entry.stableKey] = GameChange(entry: entry, changeType: .modified, previousBundlePath: previous.bundlePath)
                } else {
                    changes[entry.stableKey] = GameChange(entry: entry, changeType: .unchanged, previousBundlePath: previous.bundlePath)
                }
            } else {
                changes[entry.stableKey] = GameChange(entry: entry, changeType: .new)
            }
        }

        for previous in previousState.convertedGames where !currentKeys.contains(previous.stableKey) {
            changes[previous.stableKey] = GameChange(entry: nil, changeType: .removed, previousBundlePath: previous.bundlePath)
        }

        return changes
    }

    /// The change signature for a game entry: hashes title + ROM file signatures
    /// + resolved emulator + args template + artwork bytes.
    func computeChangeSignature(for entry: GameEntry) -> String {
        var parts: [String] = []
        parts.append(entry.title)
        parts.append(entry.launchPath.standardizedFileURL.path)
        parts.append(romFileSignature(entry.romPath) ?? "nosig")
        // Signature of member files (a .cue's tracks, an .m3u's discs) so a
        // re-dumped track is detected even though the entry-point file is
        // unchanged.
        for member in entry.additionalFiles.sorted(by: { $0.path < $1.path }) {
            parts.append(romFileSignature(member) ?? "")
        }
        // Include the emulator choice itself: switching between two RetroArch
        // cores keeps the same binary path and args template, so the choice is the
        // only thing that distinguishes them.
        parts.append(entry.emulator?.signatureToken ?? "nochoice")
        parts.append(entry.emulatorPath?.path ?? "noemu")
        parts.append(entry.launchArguments.joined(separator: "\u{1F}"))
        switch entry.artworkStatus {
        case .cached(let url):
            parts.append("art:" + artworkSignature(url))
        default:
            parts.append("art:none")
        }
        let data = Data(parts.joined(separator: "|").utf8)
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Artwork files are small compared with ROMs, so hashing their bytes is
    /// cheap and correctly detects a replacement written to the same cache URL.
    private func artworkSignature(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "missing:" + url.path }
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    /// A cheap change-detection signature for a ROM file: its size and
    /// modification time. We deliberately do NOT hash file contents — a replaced
    /// or re-dumped ROM changes its size and/or mtime, and full-content SHA256 of
    /// multi-GB ISOs blocked the main thread for 10+ seconds (beachball) during
    /// generation. Returns nil if the file can't be stat'd.
    func romFileSignature(_ url: URL) -> String? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              let mtime = attributes[.modificationDate] as? Date else {
            return nil
        }
        return "\(size)-\(mtime.timeIntervalSince1970)"
    }

    /// Build a `ConvertedGame` record for a generated bundle.
    func buildConvertedGame(for entry: GameEntry, bundlePath: String) -> ConvertedGame {
        ConvertedGame(
            stableKey: entry.stableKey,
            title: entry.title,
            changeSignatureHash: computeChangeSignature(for: entry),
            bundlePath: bundlePath
        )
    }

    /// Delete orphaned bundles for removed games.
    func cleanupOrphanedGameBundles(
        changes: [String: GameChange],
        removeOrphaned: Bool
    ) throws -> [String] {
        guard removeOrphaned else { return [] }
        var deletedPaths: [String] = []
        for (_, change) in changes where change.changeType == .removed {
            guard let bundlePath = change.previousBundlePath else { continue }
            if fileManager.fileExists(atPath: bundlePath) {
                try fileManager.removeItem(at: URL(fileURLWithPath: bundlePath))
                deletedPaths.append(bundlePath)
                Logger.shared.logBundleDeleted(bundlePath)
            }
        }
        return deletedPaths
    }
}
