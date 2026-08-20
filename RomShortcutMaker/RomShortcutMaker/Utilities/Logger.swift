//
//  Logger.swift
//  RomShortcutMaker
//
//  Logging system for errors, warnings, and conversion actions
//

import Foundation

/// Log level for categorizing messages
enum LogLevel: String {
    case error = "ERROR"
    case warning = "WARNING"
    case info = "INFO"
    case debug = "DEBUG"
}

/// Centralized logging system
class Logger {
    
    /// Shared singleton instance
    static let shared = Logger()
    
    private let dateFormatter: DateFormatter
    
    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }
    
    // MARK: - Public Logging Methods
    
    /// Log an error message
    /// - Parameters:
    ///   - message: The error message
    ///   - error: Optional error object
    func error(_ message: String, error: Error? = nil) {
        log(message, level: .error, error: error)
    }
    
    /// Log a warning message
    /// - Parameter message: The warning message
    func warning(_ message: String) {
        log(message, level: .warning)
    }
    
    /// Log an info message
    /// - Parameter message: The info message
    func info(_ message: String) {
        log(message, level: .info)
    }
    
    /// Log a debug message
    /// - Parameter message: The debug message
    func debug(_ message: String) {
        log(message, level: .debug)
    }
    
    // MARK: - Conversion Action Logging
    
    /// Log a conversion action
    /// - Parameters:
    ///   - action: The action performed (e.g., "Created", "Updated", "Skipped")
    ///   - bundleName: Name of the app bundle
    func logConversionAction(_ action: String, bundleName: String) {
        info("\(action): \(bundleName)")
    }
    
    /// Log bundle creation
    /// - Parameter bundleName: Name of the created bundle
    func logBundleCreated(_ bundleName: String) {
        logConversionAction("Created bundle", bundleName: bundleName)
    }
    
    /// Log bundle update
    /// - Parameter bundleName: Name of the updated bundle
    func logBundleUpdated(_ bundleName: String) {
        logConversionAction("Updated bundle", bundleName: bundleName)
    }
    
    /// Log bundle skipped
    /// - Parameter bundleName: Name of the skipped bundle
    func logBundleSkipped(_ bundleName: String) {
        logConversionAction("Skipped bundle (unchanged)", bundleName: bundleName)
    }
    
    /// Log bundle deleted
    /// - Parameter bundleName: Name of the deleted bundle
    func logBundleDeleted(_ bundleName: String) {
        logConversionAction("Deleted orphaned bundle", bundleName: bundleName)
    }
    
    // MARK: - VDF Parsing Logging
    
    /// Log VDF parsing start
    /// - Parameter path: Path to the VDF file
    func logVDFParsingStart(_ path: String) {
        info("Parsing VDF file: \(path)")
    }
    
    /// Log VDF parsing completion
    /// - Parameter shortcutCount: Number of shortcuts parsed
    func logVDFParsingComplete(_ shortcutCount: Int) {
        info("Parsed \(shortcutCount) shortcuts from VDF file")
    }
    
    /// Log VDF parsing error
    /// - Parameters:
    ///   - path: Path to the VDF file
    ///   - error: The error that occurred
    func logVDFParsingError(_ path: String, error: Error) {
        self.error("Failed to parse VDF file: \(path)", error: error)
    }
    
    // MARK: - Icon Conversion Logging
    
    /// Log icon conversion failure
    /// - Parameters:
    ///   - bundleName: Name of the bundle
    ///   - error: The error that occurred
    func logIconConversionFailure(_ bundleName: String, error: Error) {
        warning("Icon conversion failed for \(bundleName): \(error.localizedDescription). Using default icon.")
    }
    
    // MARK: - Private Methods
    
    /// Core logging method
    /// - Parameters:
    ///   - message: The message to log
    ///   - level: The log level
    ///   - error: Optional error object
    private func log(_ message: String, level: LogLevel, error: Error? = nil) {
        let timestamp = dateFormatter.string(from: Date())
        var logMessage = "[\(timestamp)] [\(level.rawValue)] \(message)"
        
        if let error = error {
            logMessage += " | Error: \(error.localizedDescription)"
        }
        
        // Print to console
        print(logMessage)
        
        // In a production app, you might also write to a log file here
    }
}

// MARK: - Convenience Extensions

extension Logger {
    /// Log missing emulator warning
    /// - Parameters:
    ///   - emulatorPath: Path to the missing emulator
    ///   - bundleName: Name of the bundle
    func logMissingEmulator(_ emulatorPath: String, bundleName: String) {
        warning("Emulator not found at '\(emulatorPath)' for bundle '\(bundleName)'. Bundle will fail at launch.")
    }
    
    /// Log missing ROM warning
    /// - Parameters:
    ///   - romPath: Path to the missing ROM
    ///   - bundleName: Name of the bundle
    func logMissingROM(_ romPath: String, bundleName: String) {
        warning("ROM not found at '\(romPath)' for bundle '\(bundleName)'. Bundle will fail at launch.")
    }
    
    /// Log directory not writable error
    /// - Parameter path: Path to the directory
    func logDirectoryNotWritable(_ path: String) {
        error("Output directory is not writable: \(path)")
    }
}
