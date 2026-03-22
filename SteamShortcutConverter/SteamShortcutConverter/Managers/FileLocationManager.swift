//
//  FileLocationManager.swift
//  SteamShortcutConverter
//
//  Manages shortcuts.vdf file location and discovery
//

import Foundation

/// Errors related to file location
enum FileLocationError: LocalizedError {
    case noShortcutsFileFound
    case invalidVDFFile(String)
    case fileNotReadable(String)
    
    var errorDescription: String? {
        switch self {
        case .noShortcutsFileFound:
            return """
            No shortcuts.vdf file found.
            
            To locate your shortcuts.vdf file:
            1. Open Steam and ensure you have non-Steam games added
            2. The file should be located at:
               ~/Library/Application Support/Steam/userdata/[USER_ID]/config/shortcuts.vdf
            3. If you use Steam ROM Manager, run it first to generate shortcuts
            4. You can manually select the file using the file picker
            """
        case .invalidVDFFile(let path):
            return "The selected file is not a valid VDF file: \(path)"
        case .fileNotReadable(let path):
            return "Cannot read file: \(path)"
        }
    }
}

/// Manager for locating shortcuts.vdf files
class FileLocationManager {
    
    private let fileManager = FileManager.default
    private let validator = VDFValidator()
    
    // MARK: - Auto-Detection
    
    /// Auto-detect shortcuts.vdf files in standard Steam locations
    /// - Returns: Array of found shortcuts.vdf file paths
    func autoDetectShortcutsFiles() -> [String] {
        var foundPaths: [String] = []
        
        // Build path to Steam userdata directory
        let homeDirectory = NSHomeDirectory()
        let steamUserdataPath = "\(homeDirectory)/Library/Application Support/Steam/userdata"
        
        // Check if Steam userdata directory exists
        guard fileManager.fileExists(atPath: steamUserdataPath) else {
            return foundPaths
        }
        
        // Enumerate user directories
        do {
            let userDirs = try fileManager.contentsOfDirectory(atPath: steamUserdataPath)
            
            for userDir in userDirs {
                // Skip non-directory entries
                var isDirectory: ObjCBool = false
                let userDirPath = "\(steamUserdataPath)/\(userDir)"
                guard fileManager.fileExists(atPath: userDirPath, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    continue
                }
                
                // Check for shortcuts.vdf in config subdirectory
                let shortcutsPath = "\(userDirPath)/config/shortcuts.vdf"
                if fileManager.fileExists(atPath: shortcutsPath) {
                    // Validate the file before adding
                    do {
                        try validator.validateFile(at: shortcutsPath)
                        foundPaths.append(shortcutsPath)
                    } catch {
                        // Skip invalid files
                        print("Skipping invalid VDF file: \(shortcutsPath)")
                    }
                }
            }
        } catch {
            print("Error enumerating Steam userdata directory: \(error)")
        }
        
        return foundPaths
    }
    
    // MARK: - Manual Selection
    
    /// Validate a manually selected shortcuts.vdf file
    /// - Parameter path: Path to the file to validate
    /// - Throws: FileLocationError if file is invalid
    func validateManualSelection(at path: String) throws {
        // Check if file exists
        guard fileManager.fileExists(atPath: path) else {
            throw FileLocationError.fileNotReadable(path)
        }
        
        // Check if file is readable
        guard fileManager.isReadableFile(atPath: path) else {
            throw FileLocationError.fileNotReadable(path)
        }
        
        // Validate VDF format
        do {
            try validator.validateFile(at: path)
        } catch {
            throw FileLocationError.invalidVDFFile(path)
        }
    }
    
    // MARK: - Error Handling
    
    /// Get user-friendly error message when no file is found
    /// - Returns: Error with instructions for locating the file
    func getNoFileFoundError() -> FileLocationError {
        return .noShortcutsFileFound
    }
}
