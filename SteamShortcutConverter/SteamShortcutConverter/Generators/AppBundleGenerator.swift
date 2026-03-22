//
//  AppBundleGenerator.swift
//  SteamShortcutConverter
//
//  Generates native macOS .app bundles from Steam shortcuts
//

import Foundation

/// Implementation of AppBundleGenerator protocol
class DefaultAppBundleGenerator: AppBundleGenerator {
    
    private let fileManager = FileManager.default
    
    // MARK: - Public Methods
    
    /// Generate a macOS app bundle from configuration
    /// - Parameter config: Configuration for the app bundle
    /// - Returns: URL to the generated app bundle
    /// - Throws: Error if bundle generation fails
    func generateAppBundle(with config: AppBundleConfig) async throws -> URL {
        let logger = Logger.shared
        
        // Validate output directory is writable
        guard fileManager.isWritableFile(atPath: config.outputDirectory.path) else {
            logger.logDirectoryNotWritable(config.outputDirectory.path)
            throw AppBundleGeneratorError.directoryNotWritable(config.outputDirectory.path)
        }
        
        // Create the app bundle directory structure
        let bundleURL = try await createAppBundleStructure(for: config)
        
        // Generate Info.plist
        try await generateInfoPlist(for: config, at: bundleURL)
        
        // Generate launch script
        try await generateLaunchScript(for: config, at: bundleURL)
        
        // Set executable permissions on launch script
        try await setExecutablePermissions(at: bundleURL)
        
        // Convert and save icon if available
        if let iconData = config.iconData {
            do {
                try await convertIcon(iconData, to: bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns"))
            } catch {
                // Log warning but continue - use default icon
                logger.logIconConversionFailure(config.bundleName, error: error)
                // Icon conversion failure is non-fatal
            }
        }
        
        logger.logBundleCreated(config.bundleName)
        return bundleURL
    }
    
    /// Convert icon data to .icns format
    /// - Parameters:
    ///   - iconData: The icon data to convert
    ///   - outputURL: URL where the .icns file should be saved
    /// - Throws: Error if conversion fails
    func convertIcon(_ iconData: IconData, to outputURL: URL) async throws {
        let tempImageURL: URL
        
        // Extract icon data and resolve paths
        switch iconData {
        case .embedded(let data):
            // Save embedded data to temporary file
            tempImageURL = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("png")
            try data.write(to: tempImageURL)
            
        case .filePath(let path):
            // Resolve icon file path
            let iconURL = URL(fileURLWithPath: path)
            
            // Check if path is relative to Steam's grid directory
            if !fileManager.fileExists(atPath: iconURL.path) {
                // Try resolving relative to Steam's grid directory
                let steamGridPath = NSHomeDirectory() + "/Library/Application Support/Steam/userdata"
                let resolvedURL = URL(fileURLWithPath: steamGridPath)
                    .appendingPathComponent(path)
                
                if fileManager.fileExists(atPath: resolvedURL.path) {
                    tempImageURL = resolvedURL
                } else {
                    throw AppBundleGeneratorError.iconNotFound("Icon file not found: \(path)")
                }
            } else {
                tempImageURL = iconURL
            }
        }
        
        // Convert to .icns using sips
        do {
            try await convertToIcns(from: tempImageURL, to: outputURL)
        } catch {
            // Handle conversion failure gracefully - use default icon or skip
            throw AppBundleGeneratorError.iconConversionFailed("Failed to convert icon: \(error.localizedDescription)")
        }
        
        // Clean up temporary file if we created one
        if case .embedded = iconData {
            try? fileManager.removeItem(at: tempImageURL)
        }
    }
    
    // MARK: - Private Methods
    
    /// Create the .app bundle directory structure
    /// - Parameter config: Configuration for the app bundle
    /// - Returns: URL to the created app bundle
    /// - Throws: Error if directory creation fails
    private func createAppBundleStructure(for config: AppBundleConfig) async throws -> URL {
        // Construct the full app bundle path
        let bundleURL = config.outputDirectory
            .appendingPathComponent(config.bundleName)
            .appendingPathExtension("app")
        
        // Create Contents directory
        let contentsURL = bundleURL.appendingPathComponent("Contents")
        
        // Create MacOS subdirectory
        let macOSURL = contentsURL.appendingPathComponent("MacOS")
        
        // Create Resources subdirectory
        let resourcesURL = contentsURL.appendingPathComponent("Resources")
        
        // Create all directories with proper permissions
        // 0o755 = rwxr-xr-x (owner: read/write/execute, group/others: read/execute)
        let directoryAttributes: [FileAttributeKey: Any] = [
            .posixPermissions: 0o755
        ]
        
        try fileManager.createDirectory(
            at: macOSURL,
            withIntermediateDirectories: true,
            attributes: directoryAttributes
        )
        
        try fileManager.createDirectory(
            at: resourcesURL,
            withIntermediateDirectories: true,
            attributes: directoryAttributes
        )
        
        return bundleURL
    }
    
    /// Generate Info.plist file for the app bundle
    /// - Parameters:
    ///   - config: Configuration for the app bundle
    ///   - bundleURL: URL to the app bundle
    /// - Throws: Error if plist generation fails
    private func generateInfoPlist(for config: AppBundleConfig, at bundleURL: URL) async throws {
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        
        // Build Info.plist content
        var plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>\(config.bundleIdentifier)</string>
            <key>CFBundleName</key>
            <string>\(config.bundleName)</string>
            <key>CFBundleDisplayName</key>
            <string>\(config.displayName)</string>
            <key>CFBundleVersion</key>
            <string>\(config.version)</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
            <key>CFBundleExecutable</key>
            <string>launch.sh</string>
        """
        
        // Add icon reference if available
        if config.iconData != nil {
            plistContent += """
            
                <key>CFBundleIconFile</key>
                <string>AppIcon</string>
            """
        }
        
        plistContent += """
        
        </dict>
        </plist>
        """
        
        // Write plist to file
        try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
    }
    
    /// Generate launch script for the app bundle
    /// - Parameters:
    ///   - config: Configuration for the app bundle
    ///   - bundleURL: URL to the app bundle
    /// - Throws: Error if script generation fails
    private func generateLaunchScript(for config: AppBundleConfig, at bundleURL: URL) async throws {
        let scriptURL = bundleURL.appendingPathComponent("Contents/MacOS/launch.sh")
        
        // Escape the launch script content for shell execution
        let escapedLaunchScript = escapeShellCommand(config.launchScript)
        
        // Build launch script with proper shebang
        let scriptContent = """
        #!/bin/bash
        # Generated by Steam Shortcut to App Bundle Converter
        # Original Steam launch command preserved exactly
        
        \(escapedLaunchScript)
        """
        
        // Write script to file
        try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
    }
    
    /// Escape special characters in shell command
    /// Properly quotes paths with spaces and escapes special shell characters
    /// - Parameter command: The command to escape
    /// - Returns: Escaped command safe for shell execution
    private func escapeShellCommand(_ command: String) -> String {
        // Split command into tokens while preserving quoted sections
        var result = ""
        var currentToken = ""
        var insideQuotes = false
        var quoteChar: Character?
        
        for char in command {
            if char == "\"" || char == "'" {
                if insideQuotes && char == quoteChar {
                    // End of quoted section
                    insideQuotes = false
                    quoteChar = nil
                    currentToken.append(char)
                } else if !insideQuotes {
                    // Start of quoted section
                    insideQuotes = true
                    quoteChar = char
                    currentToken.append(char)
                } else {
                    // Different quote inside quotes
                    currentToken.append(char)
                }
            } else if char.isWhitespace && !insideQuotes {
                // End of token
                if !currentToken.isEmpty {
                    result += escapeToken(currentToken) + String(char)
                    currentToken = ""
                } else {
                    result.append(char)
                }
            } else {
                currentToken.append(char)
            }
        }
        
        // Add final token
        if !currentToken.isEmpty {
            result += escapeToken(currentToken)
        }
        
        return result
    }
    
    /// Escape a single token for shell execution
    /// - Parameter token: The token to escape
    /// - Returns: Escaped token
    private func escapeToken(_ token: String) -> String {
        // If already quoted, return as-is
        if (token.hasPrefix("\"") && token.hasSuffix("\"")) ||
           (token.hasPrefix("'") && token.hasSuffix("'")) {
            return token
        }
        
        // Check if token needs quoting (contains spaces or special characters)
        let specialChars = CharacterSet(charactersIn: " $`\\\"'")
        if token.rangeOfCharacter(from: specialChars) != nil {
            // Escape special characters within double quotes
            var escaped = token
            escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
            escaped = escaped.replacingOccurrences(of: "$", with: "\\$")
            escaped = escaped.replacingOccurrences(of: "`", with: "\\`")
            escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        
        return token
    }
    
    /// Set executable permissions on the launch script
    /// - Parameter bundleURL: URL to the app bundle
    /// - Throws: Error if permission setting fails
    private func setExecutablePermissions(at bundleURL: URL) async throws {
        let scriptURL = bundleURL.appendingPathComponent("Contents/MacOS/launch.sh")
        
        // Set executable permissions (0o755 = rwxr-xr-x)
        let attributes: [FileAttributeKey: Any] = [
            .posixPermissions: 0o755
        ]
        
        try fileManager.setAttributes(attributes, ofItemAtPath: scriptURL.path)
    }
    
    /// Convert image to .icns format using sips
    /// - Parameters:
    ///   - sourceURL: URL to source image file
    ///   - outputURL: URL where .icns file should be saved
    /// - Throws: Error if conversion fails
    private func convertToIcns(from sourceURL: URL, to outputURL: URL) async throws {
        // Handle .ico files by converting to PNG first
        var workingSourceURL = sourceURL
        var needsCleanup = false
        
        if sourceURL.pathExtension.lowercased() == "ico" {
            // Convert ICO to PNG using sips
            let tempPNGURL = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("png")
            
            let convertProcess = Process()
            convertProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
            convertProcess.arguments = [
                "-s", "format", "png",
                sourceURL.path,
                "--out", tempPNGURL.path
            ]
            
            try convertProcess.run()
            convertProcess.waitUntilExit()
            
            guard convertProcess.terminationStatus == 0 else {
                throw AppBundleGeneratorError.iconConversionFailed("Failed to convert ICO to PNG: sips exit code \(convertProcess.terminationStatus)")
            }
            
            workingSourceURL = tempPNGURL
            needsCleanup = true
        }
        
        // Create iconset directory
        let iconsetURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("iconset")
        
        try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
        
        // Define icon sizes for macOS
        let iconSizes: [(size: Int, scale: Int)] = [
            (16, 1), (16, 2),
            (32, 1), (32, 2),
            (128, 1), (128, 2),
            (256, 1), (256, 2),
            (512, 1), (512, 2)
        ]
        
        // Generate each icon size using sips
        for (size, scale) in iconSizes {
            let actualSize = size * scale
            let filename = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@\(scale)x.png"
            let outputIconURL = iconsetURL.appendingPathComponent(filename)
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
            process.arguments = [
                "-z", "\(actualSize)", "\(actualSize)",
                workingSourceURL.path,
                "--out", outputIconURL.path
            ]
            
            try process.run()
            process.waitUntilExit()
            
            guard process.terminationStatus == 0 else {
                // Clean up temp PNG if we created it
                if needsCleanup {
                    try? fileManager.removeItem(at: workingSourceURL)
                }
                throw AppBundleGeneratorError.iconConversionFailed("sips failed with status \(process.terminationStatus)")
            }
        }
        
        // Convert iconset to icns using iconutil
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = [
            "-c", "icns",
            iconsetURL.path,
            "-o", outputURL.path
        ]
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            // Clean up temp PNG if we created it
            if needsCleanup {
                try? fileManager.removeItem(at: workingSourceURL)
            }
            throw AppBundleGeneratorError.iconConversionFailed("iconutil failed with status \(process.terminationStatus)")
        }
        
        // Clean up iconset directory and temp PNG
        try? fileManager.removeItem(at: iconsetURL)
        if needsCleanup {
            try? fileManager.removeItem(at: workingSourceURL)
        }
    }
}

// MARK: - Error Types

enum AppBundleGeneratorError: LocalizedError {
    case notImplemented(String)
    case directoryCreationFailed(String)
    case invalidConfiguration(String)
    case iconNotFound(String)
    case iconConversionFailed(String)
    case directoryNotWritable(String)
    case missingEmulator(String)
    case missingROM(String)
    
    var errorDescription: String? {
        switch self {
        case .notImplemented(let message):
            return "Not implemented: \(message)"
        case .directoryCreationFailed(let message):
            return "Failed to create directory: \(message)"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .iconNotFound(let message):
            return "Icon not found: \(message)"
        case .iconConversionFailed(let message):
            return "Icon conversion failed: \(message)"
        case .directoryNotWritable(let message):
            return "Output directory is not writable: \(message). Please select a different location."
        case .missingEmulator(let message):
            return "Emulator not found: \(message). The app bundle will be created but may not launch correctly."
        case .missingROM(let message):
            return "ROM file not found: \(message). The app bundle will be created but may not launch correctly."
        }
    }
}
