//
//  LaunchCommandParser.swift
//  SteamShortcutConverter
//
//  Parser for extracting launch configuration from Steam shortcuts
//

import Foundation

/// Errors that can occur during launch command parsing
enum LaunchCommandParserError: Error, LocalizedError {
    case emptyExecutablePath
    case invalidLaunchOptions(String)
    
    var errorDescription: String? {
        switch self {
        case .emptyExecutablePath:
            return "Executable path is empty"
        case .invalidLaunchOptions(let options):
            return "Invalid launch options: \(options)"
        }
    }
}

/// Parser for extracting launch configuration from Steam shortcuts
class LaunchCommandParser {
    
    /// Parse launch configuration from a Steam shortcut
    /// - Parameter shortcut: The Steam shortcut to parse
    /// - Returns: LaunchConfiguration with executable path, arguments, and working directory
    /// - Throws: LaunchCommandParserError if parsing fails
    func parseLaunchConfiguration(from shortcut: SteamShortcut) throws -> LaunchConfiguration {
        // The exe field holds a single executable path. It may be wrapped in
        // matching quotes, but it is NOT a full command line — arguments live in
        // the LaunchOptions field. Treating it as a whole path keeps unquoted
        // paths that contain spaces (e.g. "/Applications/My Emulator.app/...")
        // intact instead of splitting them on the first space.
        let executablePath = stripSurroundingQuotes(
            shortcut.exe.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        guard !executablePath.isEmpty else {
            throw LaunchCommandParserError.emptyExecutablePath
        }

        // Handle path resolution for executable
        let resolvedExecutablePath = resolvePath(executablePath, relativeTo: shortcut.startDir)

        // Arguments come exclusively from the LaunchOptions field
        var allArguments = parseArguments(from: shortcut.launchOptions)

        // Resolve paths in arguments (only for arguments that look like paths)
        allArguments = allArguments.map { arg in
            // Only resolve if it looks like a path (not a flag starting with -)
            if shouldResolvePath(arg) {
                return resolvePath(arg, relativeTo: shortcut.startDir)
            }
            return arg
        }
        
        // Extract working directory from StartDir field
        let workingDirectory = shortcut.startDir?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return LaunchConfiguration(
            executablePath: resolvedExecutablePath,
            arguments: allArguments,
            workingDirectory: workingDirectory?.isEmpty == false ? workingDirectory : nil
        )
    }
    
    /// Detect if the launch configuration uses RetroArch with a core specification
    /// - Parameter config: The launch configuration to check
    /// - Returns: The core path if RetroArch core is detected, nil otherwise
    func detectRetroArchCore(in config: LaunchConfiguration) -> String? {
        // Check if executable is RetroArch
        guard isRetroArchExecutable(config.executablePath) else {
            return nil
        }
        
        // Look for -L or --libretro flag followed by core path
        for i in 0..<config.arguments.count - 1 {
            let arg = config.arguments[i]
            if arg == "-L" || arg == "--libretro" {
                let corePath = config.arguments[i + 1]
                // Verify it looks like a core file
                if corePath.hasSuffix(".dylib") || corePath.hasSuffix(".so") || corePath.contains("_libretro") {
                    return corePath
                }
            }
        }
        
        return nil
    }
    
    /// Check if an executable path is RetroArch
    /// - Parameter path: The executable path to check
    /// - Returns: True if the path appears to be RetroArch
    func isRetroArchExecutable(_ path: String) -> Bool {
        let lowercasePath = path.lowercased()
        return lowercasePath.contains("retroarch")
    }
    
    // MARK: - Private Methods
    
    /// Strip a single pair of matching surrounding quotes from a string.
    /// `"/Applications/My App.app"` → `/Applications/My App.app`. Internal
    /// spaces are preserved. Unquoted strings are returned unchanged.
    /// - Parameter value: The string to unwrap
    /// - Returns: The string without surrounding quotes
    private func stripSurroundingQuotes(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, let last = value.last else {
            return value
        }
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
    
    /// Determine if an argument should be resolved as a path
    /// - Parameter arg: The argument to check
    /// - Returns: True if the argument looks like a path that should be resolved
    private func shouldResolvePath(_ arg: String) -> Bool {
        // Don't resolve flags (arguments starting with -)
        if arg.hasPrefix("-") {
            return false
        }
        
        // Don't resolve if it's empty
        if arg.isEmpty {
            return false
        }
        
        // Resolve if it contains path separators or file extensions
        if arg.contains("/") || arg.contains(".") {
            return true
        }
        
        // For other cases, don't resolve (could be plain arguments)
        return false
    }
    
    /// Resolve a path (handle absolute and relative paths)
    /// - Parameters:
    ///   - path: The path to resolve
    ///   - baseDirectory: Optional base directory for relative path resolution
    /// - Returns: Resolved absolute path, or original path if already absolute
    private func resolvePath(_ path: String, relativeTo baseDirectory: String?) -> String {
        // If path is already absolute, return as-is
        if path.hasPrefix("/") || path.hasPrefix("~") {
            // Expand tilde if present
            if path.hasPrefix("~") {
                return NSString(string: path).expandingTildeInPath
            }
            return path
        }
        
        // If we have a base directory and path is relative, resolve it
        if let baseDir = baseDirectory, !baseDir.isEmpty {
            let expandedBaseDir = NSString(string: baseDir).expandingTildeInPath
            return NSString(string: expandedBaseDir).appendingPathComponent(path)
        }
        
        // Otherwise return the path as-is (might be relative to working directory at runtime)
        return path
    }
    
    /// Parse arguments from launch options string
    /// Preserves argument order and quoting
    /// - Parameter launchOptions: The launch options string from Steam shortcut
    /// - Returns: Array of parsed arguments
    private func parseArguments(from launchOptions: String?) -> [String] {
        guard let launchOptions = launchOptions?.trimmingCharacters(in: .whitespacesAndNewlines),
              !launchOptions.isEmpty else {
            return []
        }
        
        var arguments: [String] = []
        var currentArgument = ""
        var insideQuotes = false
        var quoteChar: Character?
        var escapeNext = false
        
        for char in launchOptions {
            if escapeNext {
                // Add escaped character literally
                currentArgument.append(char)
                escapeNext = false
                continue
            }
            
            if char == "\\" {
                // Escape next character
                escapeNext = true
                continue
            }
            
            if char == "\"" || char == "'" {
                if insideQuotes {
                    if char == quoteChar {
                        // End of quoted section
                        insideQuotes = false
                        quoteChar = nil
                    } else {
                        // Different quote character inside quotes
                        currentArgument.append(char)
                    }
                } else {
                    // Start of quoted section
                    insideQuotes = true
                    quoteChar = char
                }
                continue
            }
            
            if char.isWhitespace && !insideQuotes {
                // End of argument
                if !currentArgument.isEmpty {
                    arguments.append(currentArgument)
                    currentArgument = ""
                }
                continue
            }
            
            // Regular character
            currentArgument.append(char)
        }
        
        // Add final argument if any
        if !currentArgument.isEmpty {
            arguments.append(currentArgument)
        }
        
        return arguments
    }
}
