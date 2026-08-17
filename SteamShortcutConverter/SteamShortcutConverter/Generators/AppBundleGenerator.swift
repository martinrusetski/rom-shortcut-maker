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
    private let defaultShortcutIconURL: URL?

    init(defaultShortcutIconURL: URL? = nil) {
        self.defaultShortcutIconURL = defaultShortcutIconURL
            ?? Bundle.module.url(forResource: "DefaultShortcutIcon", withExtension: "icns")
    }

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
        
        let iconDestination = bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
        var installedCustomIcon = false
        if let iconData = config.iconData {
            do {
                try await convertIcon(iconData, to: iconDestination)
                installedCustomIcon = true
            } catch {
                logger.logIconConversionFailure(config.bundleName, error: error)
            }
        }

        if !installedCustomIcon {
            try installDefaultShortcutIcon(to: iconDestination)
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
        try await createAppBundleStructure(bundleName: config.bundleName, outputDirectory: config.outputDirectory)
    }

    private func createAppBundleStructure(bundleName: String, outputDirectory: URL) async throws -> URL {
        // Construct the full app bundle path
        let bundleURL = outputDirectory
            .appendingPathComponent(bundleName)
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
        try await generateInfoPlist(
            bundleIdentifier: config.bundleIdentifier,
            bundleName: config.bundleName,
            displayName: config.displayName,
            version: config.version,
            hasIcon: true,
            at: bundleURL
        )
    }

    private func generateInfoPlist(
        bundleIdentifier: String,
        bundleName: String,
        displayName: String,
        version: String,
        hasIcon: Bool,
        at bundleURL: URL
    ) async throws {
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")

        // Build Info.plist content
        var plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>\(bundleIdentifier)</string>
            <key>CFBundleName</key>
            <string>\(bundleName)</string>
            <key>CFBundleDisplayName</key>
            <string>\(displayName)</string>
            <key>CFBundleVersion</key>
            <string>\(version)</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
            <key>CFBundleExecutable</key>
            <string>launch.sh</string>
        """

        // Add icon reference if available
        if hasIcon {
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

    // MARK: - ROM Pipeline: Game bundle path

    func generateAppBundle(for game: ResolvedGameBundle) async throws -> URL {
        let logger = Logger.shared

        guard fileManager.isWritableFile(atPath: game.outputDirectory.path) else {
            logger.logDirectoryNotWritable(game.outputDirectory.path)
            throw AppBundleGeneratorError.directoryNotWritable(game.outputDirectory.path)
        }

        let bundleURL = try await createAppBundleStructure(
            bundleName: game.bundleName,
            outputDirectory: game.outputDirectory
        )

        try await generateInfoPlist(
            bundleIdentifier: game.bundleIdentifier,
            bundleName: game.bundleName,
            displayName: game.displayName,
            version: game.version,
            hasIcon: true,
            at: bundleURL
        )

        // Build the launch command ONCE from structured pieces (single escaping).
        let command = try buildLaunchCommand(
            emulator: game.executablePath,
            launchArguments: game.launchArguments,
            rom: game.romPath,
            core: game.corePath
        )
        let scriptContent = """
        #!/bin/bash
        # Generated by Rom Shortcut Maker
        exec \(command)
        """
        let scriptURL = bundleURL.appendingPathComponent("Contents/MacOS/launch.sh")
        try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
        try await setExecutablePermissions(at: bundleURL)

        // Prefer supplied artwork, then fall back to the bundled shortcut icon.
        let icnsDestination = bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
        var installedCustomIcon = false
        if let icns = game.iconICNS {
            try? fileManager.removeItem(at: icnsDestination)
            do {
                try fileManager.copyItem(at: icns, to: icnsDestination)
                installedCustomIcon = true
            } catch {
                logger.logIconConversionFailure(game.bundleName, error: error)
            }
        } else if let png = game.iconOriginalPNG {
            do {
                try await convertToIcns(from: png, to: icnsDestination)
                installedCustomIcon = true
            } catch {
                logger.logIconConversionFailure(game.bundleName, error: error)
            }
        }

        if !installedCustomIcon {
            try installDefaultShortcutIcon(to: icnsDestination)
        }

        logger.logBundleCreated(game.bundleName)
        return bundleURL
    }

    private func installDefaultShortcutIcon(to destination: URL) throws {
        guard let source = defaultShortcutIconURL,
              fileManager.fileExists(atPath: source.path) else {
            throw AppBundleGeneratorError.iconNotFound("Bundled default shortcut icon is missing")
        }

        try? fileManager.removeItem(at: destination)
        do {
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            throw AppBundleGeneratorError.iconConversionFailed(
                "Failed to copy bundled default shortcut icon: \(error.localizedDescription)"
            )
        }
    }

    /// Resolve an emulator path to a launchable executable: for an `.app`, the
    /// inner `Contents/MacOS/<CFBundleExecutable>` binary; otherwise the path itself.
    func resolveExecutable(_ url: URL) -> URL {
        guard url.pathExtension.lowercased() == "app" else { return url }
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        if let data = try? Data(contentsOf: plistURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
           let dict = plist as? [String: Any],
           let executable = dict["CFBundleExecutable"] as? String {
            return url.appendingPathComponent("Contents/MacOS/\(executable)")
        }
        let fallback = url.deletingPathExtension().lastPathComponent
        return url.appendingPathComponent("Contents/MacOS/\(fallback)")
    }

    /// Resolve placeholders in structured arguments and produce a single,
    /// correctly shell-quoted command line.
    ///
    /// `.app` emulators are launched via LaunchServices (`open -a`), NOT by
    /// exec'ing their inner Mach-O directly. Exec'ing the inner binary runs the
    /// emulator inside the process LaunchServices registered as *our* bundle, so
    /// AppKit binds the emulator's window to the wrong app identity. Some
    /// emulators (RetroArch) then hit "terminate after last window closed" and
    /// quit instantly on launch. `open -a` gives the emulator its own identity.
    /// CLI binaries have no such identity and are exec'd directly.
    func buildLaunchCommand(
        emulator: URL,
        launchArguments: [String],
        rom: URL,
        core: URL?
    ) throws -> String {
        let resolvedArguments = try LaunchArguments.resolve(launchArguments, rom: rom, core: core)

        if emulator.pathExtension.lowercased() == "app" {
            var parts = ["/usr/bin/open", "-a", emulator.path]
            if !resolvedArguments.isEmpty {
                parts.append("--args")
                parts.append(contentsOf: resolvedArguments)
            }
            return parts.map { Self.shellQuote($0) }.joined(separator: " ")
        }

        let executable = resolveExecutable(emulator)
        return ([executable.path] + resolvedArguments)
            .map { Self.shellQuote($0) }
            .joined(separator: " ")
    }

    // MARK: - Static helpers

    /// POSIX single-quote shell escaping — the one, well-tested escaper. Wraps in
    /// single quotes and escapes embedded single quotes, which neutralizes spaces,
    /// `$`, backticks, and double quotes with no second escaping pass.
    static func shellQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Sanitize a title into a bundle-identifier component (lowercase, hyphenated,
    /// alphanumerics + hyphen only).
    static func sanitizedIdentifierComponent(_ title: String) -> String {
        let lowered = title.lowercased().replacingOccurrences(of: " ", with: "-")
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        let filtered = String(lowered.filter { allowed.contains($0) })
        let trimmed = filtered.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "game" : trimmed
    }

    /// Sanitize a display title into the Finder-visible `.app` bundle name.
    /// This is shared with generation planning so the preview compares the
    /// exact destination that the generator will write.
    static func sanitizedBundleName(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: ":/\\")
        let cleaned = title.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "Game" : cleaned
    }

    /// Assign unique bundle identifiers for a batch of (title, stableKey) items.
    /// Titles that sanitize to the same base get a short stableKey suffix.
    static func bundleIdentifiers(for items: [(title: String, stableKey: String)]) -> [String] {
        let bases = items.map { "com.romshortcutmaker." + sanitizedIdentifierComponent($0.title) }
        var counts: [String: Int] = [:]
        for base in bases { counts[base, default: 0] += 1 }
        return zip(items, bases).map { item, base in
            if (counts[base] ?? 0) > 1 {
                return base + "." + String(item.stableKey.prefix(8))
            }
            return base
        }
    }
}

// MARK: - ROM Pipeline: Resolved game bundle

/// Fully resolved inputs for generating a `.app` from a `GameEntry`.
struct ResolvedGameBundle {
    let bundleName: String
    let bundleIdentifier: String
    let displayName: String
    let version: String
    let executablePath: URL     // emulator (.app bundle or CLI binary)
    let launchArguments: [String]
    let romPath: URL
    let corePath: URL?          // RetroArch core .dylib (nil for standalone)
    let iconICNS: URL?          // pre-converted .icns to copy
    let iconOriginalPNG: URL?   // original PNG to convert
    let outputDirectory: URL

    init(
        bundleName: String,
        bundleIdentifier: String,
        displayName: String,
        version: String = "1.0",
        executablePath: URL,
        launchArguments: [String],
        romPath: URL,
        corePath: URL? = nil,
        iconICNS: URL? = nil,
        iconOriginalPNG: URL? = nil,
        outputDirectory: URL
    ) {
        self.bundleName = bundleName
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.version = version
        self.executablePath = executablePath
        self.launchArguments = launchArguments
        self.romPath = romPath
        self.corePath = corePath
        self.iconICNS = iconICNS
        self.iconOriginalPNG = iconOriginalPNG
        self.outputDirectory = outputDirectory
    }
}

/// Protocol for the ROM-pipeline bundle generation path (injected in A8).
protocol GameBundleGenerating {
    func generateAppBundle(for game: ResolvedGameBundle) async throws -> URL
}

extension DefaultAppBundleGenerator: GameBundleGenerating {}

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
