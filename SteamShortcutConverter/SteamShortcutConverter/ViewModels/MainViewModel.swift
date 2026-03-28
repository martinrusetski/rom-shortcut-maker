//
//  MainViewModel.swift
//  SteamShortcutConverter
//
//  View model for the main window
//

import Foundation
import SwiftUI

@MainActor
class MainViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var shortcutsVDFPath: String = ""
    @Published var outputDirectory: String = ""
    @Published var shortcuts: [SteamShortcut] = []
    @Published var selectedShortcutIDs: Set<UInt32> = []
    @Published var isProcessing: Bool = false
    @Published var progressMessage: String = ""
    @Published var progressValue: Double = 0.0
    @Published var errorMessage: String?
    @Published var currentError: AppError?
    @Published var autoDetectedPaths: [String] = []
    @Published var processedCount: Int = 0
    @Published var totalCount: Int = 0
    @Published var conversionSummary: ConversionSummary?
    @Published var showingSummary: Bool = false
    @Published var removeOrphanedBundles: Bool = false
    @Published var lastConversionDate: Date?
    @Published var customNames: [UInt32: String] = [:]
    
    var remainingCount: Int {
        totalCount - processedCount
    }
    
    // MARK: - Dependencies
    
    private let fileLocationManager = FileLocationManager()
    private let configurationManager: ConfigurationManager
    private let shortcutFilter: ShortcutFilter = DefaultShortcutFilter()
    private let shortcutParser = ShortcutParser()
    private let launchCommandParser = LaunchCommandParser()
    private let appBundleGenerator: AppBundleGenerator = DefaultAppBundleGenerator()
    
    // MARK: - Initialization
    
    init() {
        // Initialize configuration manager
        do {
            self.configurationManager = try DefaultConfigurationManager()
        } catch {
            // Fallback to a no-op implementation if initialization fails
            fatalError("Failed to initialize configuration manager: \(error)")
        }
        
        loadConfiguration()
        // Removed immediate autoDetectShortcutsFile() to avoid race condition
        // It will be called inside loadConfiguration() if no path is found
    }
    
    // MARK: - Configuration
    
    private func loadConfiguration() {
        Task {
            do {
                let config = try await configurationManager.loadConfiguration()
                await MainActor.run {
                    // Apply output directory first as it's independent
                    if let outputDir = config.outputDirectory {
                        outputDirectory = outputDir
                    }
                    
                    // Apply persistence-related settings
                    removeOrphanedBundles = config.removeOrphanedBundles
                    lastConversionDate = config.lastConversionDate
                    customNames = config.customNames
                    selectedShortcutIDs = config.selectedShortcutIDs
                    
                    // Finally, load shortcuts if path is valid
                    if let vdfPath = config.shortcutsVDFPath {
                        shortcutsVDFPath = vdfPath
                        // Load shortcuts WITHOUT resetting selection
                        loadShortcuts(forceAutoSelect: false)
                    } else {
                        // If no path was loaded, try auto-detect now
                        autoDetectShortcutsFile()
                    }
                }
            } catch {
                print("Failed to load configuration: \(error)")
                await MainActor.run {
                    // Try auto-detect if loading failed or file doesn't exist
                    autoDetectShortcutsFile()
                }
            }
        }
    }
    
    func saveConfiguration() {
        var config = AppConfiguration.default
        config.shortcutsVDFPath = shortcutsVDFPath.isEmpty ? nil : shortcutsVDFPath
        config.outputDirectory = outputDirectory.isEmpty ? nil : outputDirectory
        config.selectedShortcutIDs = selectedShortcutIDs
        config.removeOrphanedBundles = removeOrphanedBundles
        config.lastConversionDate = lastConversionDate
        config.customNames = customNames
        
        // Use the configuration manager to save
        Task {
            do {
                try await configurationManager.saveConfiguration(config)
                print("[CONFIG] Saved configuration successfully")
            } catch {
                print("Failed to save configuration: \(error)")
            }
        }
    }
    
    func resetConfiguration() {
        shortcutsVDFPath = ""
        outputDirectory = ""
        selectedShortcutIDs.removeAll()
        removeOrphanedBundles = false
        lastConversionDate = nil
        customNames.removeAll()
        
        Task {
            do {
                try await configurationManager.saveConfiguration(.default)
                await MainActor.run {
                    currentError = nil
                    errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    currentError = .configurationError(message: "Failed to reset configuration")
                }
            }
        }
    }
    
    // MARK: - Auto-Detection
    
    func autoDetectShortcutsFile() {
        autoDetectedPaths = fileLocationManager.autoDetectShortcutsFiles()
        
        // If we found exactly one file and don't have a path set, use it
        if autoDetectedPaths.count == 1 && shortcutsVDFPath.isEmpty {
            shortcutsVDFPath = autoDetectedPaths[0]
            saveConfiguration()
            loadShortcuts(forceAutoSelect: true)
        }
    }
    
    // MARK: - File Selection
    
    func selectShortcutsFile(url: URL) {
        do {
            try fileLocationManager.validateManualSelection(at: url.path)
            shortcutsVDFPath = url.path
            saveConfiguration()
            loadShortcuts(forceAutoSelect: true)
            errorMessage = nil
            currentError = nil
        } catch {
            let appError = AppError.fileNotFound(path: url.path)
            errorMessage = appError.errorDescription
            currentError = appError
        }
    }
    
    func selectOutputDirectory(url: URL) {
        outputDirectory = url.path
        saveConfiguration()
    }
    
    // MARK: - Validation
    
    var canProceed: Bool {
        !shortcutsVDFPath.isEmpty && !outputDirectory.isEmpty
    }
    
    // MARK: - Shortcut Loading
    
    /// Load and parse shortcuts from the VDF file
    func loadShortcuts(forceAutoSelect: Bool = false) {
        guard !shortcutsVDFPath.isEmpty else {
            shortcuts = []
            return
        }
        
        print("[VIEWMODEL] loadShortcuts() called with path: \(shortcutsVDFPath)")
        
        Task {
            do {
                // Read VDF file
                let fileURL = URL(fileURLWithPath: shortcutsVDFPath)
                let fileData = try Data(contentsOf: fileURL)
                
                print("[VIEWMODEL] Loaded VDF file, size=\(fileData.count) bytes")
                
                // Create reader and parse VDF
                let binaryVDFReader = BinaryVDFReader(data: fileData)
                let vdfData = try binaryVDFReader.read()
                
                // Parse shortcuts
                let allShortcuts = try shortcutParser.parseShortcuts(from: vdfData)
                
                print("[VIEWMODEL] Parsed \(allShortcuts.count) total shortcuts")
                
                // Filter to ROM-related shortcuts only
                let romShortcuts = shortcutFilter.filterROMShortcuts(from: allShortcuts)
                
                print("[VIEWMODEL] Filtered to \(romShortcuts.count) ROM shortcuts")
                
                await MainActor.run {
                    shortcuts = romShortcuts
                    errorMessage = nil
                    currentError = nil
                    
                    // Selection logic:
                    // 1. If forced, select all.
                    // 2. If current selection is empty, select all.
                    // 3. Otherwise, keep current selection but filter to valid IDs.
                    if forceAutoSelect || selectedShortcutIDs.isEmpty {
                        selectedShortcutIDs = Set(romShortcuts.map { $0.appID })
                    } else {
                        let validIDs = Set(romShortcuts.map { $0.appID })
                        selectedShortcutIDs = selectedShortcutIDs.intersection(validIDs)
                        
                        // If intersection is empty but we have shortcuts, auto-select all
                        if selectedShortcutIDs.isEmpty && !romShortcuts.isEmpty {
                            selectedShortcutIDs = Set(romShortcuts.map { $0.appID })
                        }
                    }
                    
                    saveConfiguration()
                }
            } catch {
                print("[VIEWMODEL] ERROR loading shortcuts: \(error.localizedDescription)")
                await MainActor.run {
                    shortcuts = []
                    let appError = AppError.invalidVDFFormat(path: shortcutsVDFPath)
                    errorMessage = appError.errorDescription
                    currentError = appError
                }
            }
        }
    }
    
    /// Get the detected emulator type for a shortcut
    func getEmulatorType(for shortcut: SteamShortcut) -> EmulatorType? {
        return shortcutFilter.detectEmulator(for: shortcut)
    }
    
    /// Toggle selection for a shortcut
    func toggleSelection(for shortcut: SteamShortcut) {
        if selectedShortcutIDs.contains(shortcut.appID) {
            selectedShortcutIDs.remove(shortcut.appID)
        } else {
            selectedShortcutIDs.insert(shortcut.appID)
        }
        saveConfiguration()
    }
    
    /// Check if a shortcut is selected
    func isSelected(_ shortcut: SteamShortcut) -> Bool {
        return selectedShortcutIDs.contains(shortcut.appID)
    }
    
    /// Select all shortcuts
    func selectAll() {
        selectedShortcutIDs = Set(shortcuts.map { $0.appID })
        saveConfiguration()
    }
    
    /// Deselect all shortcuts
    func deselectAll() {
        selectedShortcutIDs.removeAll()
        saveConfiguration()
    }
    
    // MARK: - Conversion
    
    /// Start the conversion process
    func startConversion() {
        isProcessing = true
        totalCount = selectedShortcutIDs.count
        processedCount = 0
        progressValue = 0.0
        progressMessage = "Starting conversion..."
        conversionSummary = nil
        showingSummary = false
        
        Task {
            await performConversion()
        }
    }
    
    /// Perform the full conversion workflow with incremental update support
    private func performConversion() async {
        var created = 0
        var updated = 0
        var skipped = 0
        var removed = 0
        var errors: [ConversionError] = []
        var warnings: [ConversionWarning] = []
        var convertedShortcuts: [ConvertedShortcut] = []
        
        // Get output directory URL
        guard !outputDirectory.isEmpty else {
            await MainActor.run {
                currentError = .outputDirectoryNotWritable(path: "No output directory selected")
                isProcessing = false
            }
            return
        }
        
        let outputDirURL = URL(fileURLWithPath: outputDirectory)
        
        // Validate output directory is writable
        guard FileManager.default.isWritableFile(atPath: outputDirectory) else {
            await MainActor.run {
                currentError = .outputDirectoryNotWritable(path: outputDirectory)
                isProcessing = false
            }
            return
        }
        
        // Load previous conversion state for incremental updates
        let previousState = try? await configurationManager.loadConversionState()
        
        // Get selected shortcuts
        let selectedShortcuts = shortcuts.filter { selectedShortcutIDs.contains($0.appID) }
        
        // Detect changes using IncrementalUpdateManager
        let incrementalManager = IncrementalUpdateManager()
        let changes = incrementalManager.detectChanges(
            currentShortcuts: selectedShortcuts,
            previousState: previousState,
            customNames: customNames
        )
        
        // Clean up orphaned bundles if enabled
        do {
            let deletedPaths = try incrementalManager.cleanupOrphanedBundles(
                changes: changes,
                removeOrphaned: removeOrphanedBundles
            )
            removed = deletedPaths.count
        } catch {
            print("Failed to cleanup orphaned bundles: \(error)")
        }
        
        // Process each selected shortcut based on change type
        for (index, shortcutID) in selectedShortcutIDs.enumerated() {
            guard let shortcut = shortcuts.first(where: { $0.appID == shortcutID }) else {
                continue
            }
            
            guard let change = changes[shortcut.appID] else {
                continue
            }
            
            await MainActor.run {
                processedCount = index + 1
                progressValue = Double(processedCount) / Double(totalCount)
                
                // Update progress message based on change type
                switch change.changeType {
                case .new:
                    progressMessage = "Creating: \(shortcut.appName)"
                case .modified:
                    progressMessage = "Updating: \(shortcut.appName)"
                case .unchanged:
                    progressMessage = "Skipping: \(shortcut.appName)"
                case .removed:
                    progressMessage = "Processing: \(shortcut.appName)"
                }
            }
            
            // Skip unchanged shortcuts - don't regenerate
            if change.changeType == .unchanged {
                skipped += 1
                
                // Preserve existing conversion record
                if let previousRecord = previousState?.convertedShortcuts.first(where: { $0.appID == shortcut.appID }) {
                    convertedShortcuts.append(previousRecord)
                }
                
                continue
            }
            
            // If this is a modification with a previous bundle path, delete the old bundle
            // This handles name changes where the bundle path changes
            if change.changeType == .modified, let oldBundlePath = change.previousBundlePath {
                let oldBundleURL = URL(fileURLWithPath: oldBundlePath)
                if FileManager.default.fileExists(atPath: oldBundlePath) {
                    do {
                        try FileManager.default.removeItem(at: oldBundleURL)
                        print("Deleted old bundle due to modification: \(oldBundlePath)")
                    } catch {
                        print("Failed to delete old bundle: \(error)")
                    }
                }
            }
            
            do {
                // Parse launch configuration
                let launchConfig = try launchCommandParser.parseLaunchConfiguration(from: shortcut)
                
                // Validate emulator exists
                if !FileManager.default.fileExists(atPath: launchConfig.executablePath) {
                    warnings.append(ConversionWarning(
                        shortcutName: shortcut.appName,
                        type: .missingEmulator,
                        message: "Emulator not found at: \(launchConfig.executablePath)"
                    ))
                }
                
                // Validate ROM exists (check arguments for file paths)
                for arg in launchConfig.arguments {
                    if arg.contains("/") && arg.contains(".") {
                        // Looks like a file path
                        if !FileManager.default.fileExists(atPath: arg) {
                            warnings.append(ConversionWarning(
                                shortcutName: shortcut.appName,
                                type: .missingROM,
                                message: "ROM file not found at: \(arg)"
                            ))
                            break // Only warn once per shortcut
                        }
                    }
                }
                
                // Build launch script from configuration
                let launchScript = buildLaunchScript(from: launchConfig)
                
                // Create app bundle configuration
                let bundleConfig = createAppBundleConfig(
                    for: shortcut,
                    launchScript: launchScript,
                    outputDirectory: outputDirURL
                )
                
                // Generate app bundle
                do {
                    let bundleURL = try await appBundleGenerator.generateAppBundle(with: bundleConfig)
                    
                    // Track success based on change type
                    switch change.changeType {
                    case .new:
                        created += 1
                    case .modified:
                        updated += 1
                    case .unchanged, .removed:
                        break
                    }
                    
                    // Record converted shortcut for state tracking using IncrementalUpdateManager
                    let displayName = getDisplayName(for: shortcut)
                    var convertedShortcut = incrementalManager.buildConvertedShortcut(
                        for: shortcut,
                        bundlePath: bundleURL.path
                    )
                    // Update the appName to reflect the display name (custom or original)
                    convertedShortcut = ConvertedShortcut(
                        appID: convertedShortcut.appID,
                        appName: displayName,
                        launchCommandHash: convertedShortcut.launchCommandHash,
                        iconHash: convertedShortcut.iconHash,
                        bundlePath: convertedShortcut.bundlePath
                    )
                    convertedShortcuts.append(convertedShortcut)
                    
                } catch let error as AppBundleGeneratorError {
                    // Handle specific bundle generation errors
                    switch error {
                    case .iconConversionFailed(let message):
                        // Icon conversion failure is non-fatal
                        warnings.append(ConversionWarning(
                            shortcutName: shortcut.appName,
                            type: .iconConversionFailure,
                            message: message
                        ))
                        
                        // Still count as created/updated since bundle was generated
                        switch change.changeType {
                        case .new:
                            created += 1
                        case .modified:
                            updated += 1
                        case .unchanged, .removed:
                            break
                        }
                        
                    case .directoryNotWritable(let message):
                        // Fatal error - stop conversion
                        errors.append(ConversionError(
                            shortcutName: shortcut.appName,
                            message: "Output directory not writable: \(message)"
                        ))
                        break
                        
                    default:
                        // Other errors - skip this shortcut
                        errors.append(ConversionError(
                            shortcutName: shortcut.appName,
                            message: error.localizedDescription
                        ))
                    }
                }
                
            } catch {
                // Failed to parse launch configuration or other error
                errors.append(ConversionError(
                    shortcutName: shortcut.appName,
                    message: "Failed to parse launch configuration: \(error.localizedDescription)"
                ))
            }
        }
        
        // Save conversion state
        let conversionState = ConversionState(
            timestamp: Date(),
            sourceVDFPath: shortcutsVDFPath,
            convertedShortcuts: convertedShortcuts
        )
        
        do {
            try await configurationManager.saveConversionState(conversionState)
        } catch {
            print("Failed to save conversion state: \(error)")
        }
        
        // Update last conversion date
        await MainActor.run {
            lastConversionDate = Date()
        }
        saveConfiguration()
        
        // Create summary with incremental update stats
        let summary = ConversionSummary(
            bundlesCreated: created,
            bundlesUpdated: updated,
            bundlesSkipped: skipped,
            bundlesRemoved: removed,
            errors: errors,
            warnings: warnings
        )
        
        await MainActor.run {
            isProcessing = false
            progressMessage = "Conversion complete"
            progressValue = 1.0
            conversionSummary = summary
            showingSummary = true
        }
    }
    
    /// Build launch script from launch configuration
    private func buildLaunchScript(from config: LaunchConfiguration) -> String {
        var script = ""
        
        // Handle .app bundles - need to find the actual executable
        var executablePath = config.executablePath
        if executablePath.hasSuffix(".app") {
            // For .app bundles, we need to use 'open' command or find the actual executable
            // Use 'open' command which handles app bundles properly
            script += "open -a \"\(executablePath)\""
            
            // Add --args flag before arguments when using 'open'
            if !config.arguments.isEmpty {
                script += " --args"
            }
        } else {
            // Direct executable - quote if contains spaces
            let quotedExecutable = executablePath.contains(" ") 
                ? "\"\(executablePath)\"" 
                : executablePath
            script += quotedExecutable
        }
        
        // Add arguments (quote if contains spaces)
        for arg in config.arguments {
            script += " "
            if arg.contains(" ") || arg.contains("$") || arg.contains("\"") {
                // Escape special characters and quote
                let escaped = arg
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "$", with: "\\$")
                script += "\"\(escaped)\""
            } else {
                script += arg
            }
        }
        
        return script
    }
    
    /// Create app bundle configuration from shortcut
    private func createAppBundleConfig(
        for shortcut: SteamShortcut,
        launchScript: String,
        outputDirectory: URL
    ) -> AppBundleConfig {
        // Use custom name if available, otherwise use original name
        let displayName = getDisplayName(for: shortcut)
        
        // Sanitize bundle name (remove invalid characters)
        let sanitizedName = sanitizeBundleName(displayName)
        
        // Create bundle identifier
        let bundleIdentifier = "com.steamshortcutconverter.\(sanitizedName.lowercased().replacingOccurrences(of: " ", with: "-"))"
        
        return AppBundleConfig(
            bundleName: sanitizedName,
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            version: "1.0",
            launchScript: launchScript,
            iconData: shortcut.icon,
            outputDirectory: outputDirectory
        )
    }
    
    /// Sanitize bundle name by removing invalid characters
    private func sanitizeBundleName(_ name: String) -> String {
        // Remove characters that are invalid in macOS file names
        let invalidChars = CharacterSet(charactersIn: ":/\\")
        return name.components(separatedBy: invalidChars).joined(separator: "-")
    }
    
    // MARK: - Custom Names
    
    /// Get the display name for a shortcut (custom name if set, otherwise original name)
    func getDisplayName(for shortcut: SteamShortcut) -> String {
        return customNames[shortcut.appID] ?? shortcut.appName
    }
    
    /// Set a custom name for a shortcut
    func setCustomName(_ name: String, for shortcut: SteamShortcut) {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            // If empty, remove custom name
            customNames.removeValue(forKey: shortcut.appID)
        } else {
            customNames[shortcut.appID] = name
        }
        saveConfiguration()
    }
    
    /// Check if a shortcut has a custom name
    func hasCustomName(for shortcut: SteamShortcut) -> Bool {
        return customNames[shortcut.appID] != nil
    }
    
    /// Reset custom name for a shortcut
    func resetCustomName(for shortcut: SteamShortcut) {
        customNames.removeValue(forKey: shortcut.appID)
        saveConfiguration()
    }
}
