//
//  ShortcutParser.swift
//  SteamShortcutConverter
//
//  Parser for extracting Steam shortcut entries from VDF data
//

import Foundation

/// Errors that can occur during shortcut parsing
enum ShortcutParserError: Error, LocalizedError {
    case noShortcutsSection
    case invalidShortcutEntry(String)
    case missingRequiredField(String, String) // shortcut ID, field name
    
    var errorDescription: String? {
        switch self {
        case .noShortcutsSection:
            return "No 'shortcuts' section found in VDF data"
        case .invalidShortcutEntry(let id):
            return "Invalid shortcut entry: \(id)"
        case .missingRequiredField(let id, let field):
            return "Missing required field '\(field)' in shortcut \(id)"
        }
    }
}

/// Parser for extracting Steam shortcuts from VDF data
class ShortcutParser {
    
    /// Parse shortcuts from VDF dictionary
    /// - Parameter vdfData: Dictionary representation of VDF data from BinaryVDFReader
    /// - Returns: Array of SteamShortcut objects
    /// - Throws: ShortcutParserError if parsing fails
    func parseShortcuts(from vdfData: [String: Any]) throws -> [SteamShortcut] {
        // Extract the "shortcuts" section
        guard let shortcutsSection = vdfData["shortcuts"] as? [String: Any] else {
            throw ShortcutParserError.noShortcutsSection
        }
        
        var shortcuts: [SteamShortcut] = []
        
        // Iterate through numbered entries (0, 1, 2, ...)
        // Sort keys to ensure consistent ordering
        let sortedKeys = shortcutsSection.keys.sorted { (key1, key2) -> Bool in
            // Try to convert to integers for proper numeric sorting
            if let num1 = Int(key1), let num2 = Int(key2) {
                return num1 < num2
            }
            return key1 < key2
        }
        
        for key in sortedKeys {
            guard let shortcutDict = shortcutsSection[key] as? [String: Any] else {
                continue // Skip non-dictionary entries
            }
            
            do {
                let shortcut = try parseShortcutEntry(id: key, data: shortcutDict)
                shortcuts.append(shortcut)
            } catch {
                // Log error but continue parsing other shortcuts
                print("Warning: Failed to parse shortcut \(key): \(error)")
                continue
            }
        }
        
        return shortcuts
    }
    
    // MARK: - Private Parsing Methods
    
    /// Parse a single shortcut entry
    private func parseShortcutEntry(id: String, data: [String: Any]) throws -> SteamShortcut {
        // Extract required fields - VDF field names are case-sensitive and lowercase
        guard let appName = data["appname"] as? String else {
            throw ShortcutParserError.missingRequiredField(id, "appname")
        }
        
        guard let exe = data["exe"] as? String else {
            throw ShortcutParserError.missingRequiredField(id, "exe")
        }
        
        // appid can be either Int32 or UInt32 in VDF
        let appID: UInt32
        if let appIDInt32 = data["appid"] as? Int32 {
            appID = UInt32(bitPattern: appIDInt32)
        } else if let appIDUInt32 = data["appid"] as? UInt32 {
            appID = appIDUInt32
        } else {
            throw ShortcutParserError.missingRequiredField(id, "appid")
        }
        
        // Extract optional fields
        let startDir = data["StartDir"] as? String
        let launchOptions = data["LaunchOptions"] as? String
        
        // Extract icon data
        let icon = extractIconData(from: data)
        
        // Extract tags
        let tags = extractTags(from: data)
        
        return SteamShortcut(
            appID: appID,
            appName: appName,
            exe: exe,
            startDir: startDir,
            launchOptions: launchOptions,
            icon: icon,
            tags: tags
        )
    }
    
    /// Extract icon data from shortcut entry
    private func extractIconData(from data: [String: Any]) -> IconData? {
        // Check for icon field
        guard let iconValue = data["icon"] else {
            return nil
        }
        
        // Icon can be either a string (file path) or binary data
        if let iconPath = iconValue as? String, !iconPath.isEmpty {
            return .filePath(iconPath)
        } else if let iconData = iconValue as? Data, !iconData.isEmpty {
            return .embedded(iconData)
        }
        
        return nil
    }
    
    /// Extract tags from shortcut entry
    private func extractTags(from data: [String: Any]) -> [String] {
        // Tags are stored in a nested "tags" dictionary with numeric keys
        guard let tagsDict = data["tags"] as? [String: Any] else {
            return []
        }
        
        var tags: [String] = []
        
        // Sort keys numerically to maintain order
        let sortedKeys = tagsDict.keys.sorted { (key1, key2) -> Bool in
            if let num1 = Int(key1), let num2 = Int(key2) {
                return num1 < num2
            }
            return key1 < key2
        }
        
        for key in sortedKeys {
            if let tag = tagsDict[key] as? String, !tag.isEmpty {
                tags.append(tag)
            }
        }
        
        return tags
    }
}
