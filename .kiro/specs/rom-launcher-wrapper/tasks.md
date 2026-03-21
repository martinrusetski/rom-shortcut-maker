# Implementation Plan: Steam Shortcut to App Bundle Converter

## Overview

This implementation plan breaks down the Steam Shortcut to App Bundle Converter into discrete coding tasks. The system reads Steam's shortcuts.vdf file (populated by Steam ROM Manager) and generates native macOS .app bundles for each ROM game shortcut.

The implementation follows a bottom-up approach: core data models → VDF parser → app bundle generator → UI layer. Each task builds on previous work, with property-based tests to validate correctness properties throughout development.

## Tasks

- [ ] 1. Set up project structure and core data models
  - Create Xcode project for macOS application (Swift, minimum macOS 12)
  - Define core data structures: SteamShortcut, IconData, AppBundleConfig, AppConfiguration, ConversionState, ConvertedShortcut, LaunchConfiguration
  - Create protocol definitions: VDFParser, ShortcutFilter, AppBundleGenerator, ConfigurationManager
  - Set up directory structure for test fixtures
  - Add SwiftCheck dependency for property-based testing (optional)
  - _Requirements: All requirements (foundation)_

- [ ] 2. Implement VDF Parser component
  - [ ] 2.1 Implement binary VDF file reader
    - Read file as binary Data
    - Parse VDF type markers: 0x00 (section start), 0x01 (string), 0x02 (int32), 0x08 (end)
    - Extract null-terminated strings
    - Handle nested dictionaries
    - _Requirements: 2.1_
  
  - [ ] 2.2 Implement shortcut entry parser
    - Parse "shortcuts" section
    - Extract numbered shortcut entries (0, 1, 2, ...)
    - Extract fields: appid, AppName, Exe, StartDir, LaunchOptions, icon, tags
    - Build SteamShortcut objects from parsed data
    - _Requirements: 2.2_
  
  - [ ] 2.3 Implement icon data extraction
    - Detect embedded icon data (base64 or binary)
    - Detect icon file paths
    - Handle missing icons gracefully
    - _Requirements: 5.1, 5.2_
  
  - [ ] 2.4 Implement VDF file validation
    - Check file exists and is readable
    - Validate VDF format (starts with "shortcuts" key)
    - Detect corrupted data
    - _Requirements: 1.5, 2.5_
  
  - [ ]* 2.5 Write property test for VDF parsing completeness
    - **Property 1: VDF Parsing Completeness**
    - **Validates: Requirements 2.1, 2.2**
    - Generate sample VDF data, verify all shortcuts extracted
  
  - [ ] 2.6 Write unit tests for VDF parser
    - Test parsing sample shortcuts.vdf with known shortcuts
    - Test embedded icon data extraction
    - Test icon file path extraction
    - Test RetroArch shortcuts with core arguments
    - Test corrupted VDF data handling
    - _Requirements: 2.1, 2.2, 2.3, 2.5_

- [ ] 3. Implement Shortcut Filter component
  - [ ] 3.1 Implement emulator detection
    - Define EmulatorType enum with common emulators
    - Implement executable path pattern matching
    - Case-insensitive matching
    - Support .app bundle paths and direct executable paths
    - _Requirements: 3.1, 3.2_
  
  - [ ] 3.2 Implement ROM shortcut filtering
    - Filter shortcuts by emulator detection
    - Return only ROM-related shortcuts
    - _Requirements: 3.1, 3.4_
  
  - [ ]* 3.3 Write property test for emulator detection accuracy
    - **Property 3: Emulator Detection Accuracy**
    - **Validates: Requirements 3.1, 3.2**
    - Generate shortcuts with emulator paths, verify correct identification
  
  - [ ] 3.4 Write unit tests for shortcut filter
    - Test RetroArch executable detection
    - Test Dolphin executable detection
    - Test other common emulators
    - Test non-emulator shortcuts are filtered out
    - Test case-insensitive matching
    - _Requirements: 3.1, 3.2_

- [ ] 4. Implement launch configuration extraction
  - [ ] 4.1 Implement launch command parser
    - Extract executable path from Exe field
    - Extract arguments from LaunchOptions field
    - Preserve argument order and quoting
    - Extract working directory from StartDir field
    - _Requirements: 4.1, 4.2, 4.3_
  
  - [ ] 4.2 Implement path handling
    - Handle absolute paths
    - Handle relative paths (resolve if needed)
    - Detect RetroArch core specifications
    - _Requirements: 4.4, 4.5_
  
  - [ ]* 4.3 Write property test for launch command preservation
    - **Property 2: Launch Command Preservation**
    - **Validates: Requirements 4.1, 4.2, 7.1, 7.2**
    - Generate shortcuts with various launch commands, verify exact preservation
  
  - [ ] 4.4 Write unit tests for launch configuration
    - Test simple launch command extraction
    - Test complex command with multiple arguments
    - Test RetroArch with core specification
    - Test paths with spaces
    - Test working directory extraction
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

- [ ] 5. Checkpoint - VDF parsing and filtering complete
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 6. Implement App Bundle Generator component
  - [ ] 6.1 Implement app bundle directory structure creation
    - Create .app/Contents/ directory structure
    - Create MacOS/, Resources/ subdirectories
    - Set proper directory permissions
    - _Requirements: 6.1_
  
  - [ ] 6.2 Implement Info.plist generation
    - Create Info.plist with CFBundleIdentifier, CFBundleName, CFBundleDisplayName, CFBundleVersion
    - Generate bundle identifier: com.steamshortcutconverter.{sanitized-game-name}
    - Include icon file reference when available
    - Write plist in XML format
    - _Requirements: 6.3, 6.4_
  
  - [ ] 6.3 Implement launch script generation
    - Generate bash script with exact Steam launch command
    - Include proper shebang (#!/bin/bash)
    - Preserve all arguments and quoting
    - Set working directory if specified
    - _Requirements: 6.2, 7.1, 7.2, 7.4_
  
  - [ ] 6.4 Implement special character escaping in launch scripts
    - Properly quote paths with spaces
    - Escape special shell characters: $, `, \, ", '
    - Test with edge case filenames
    - _Requirements: 7.3_
  
  - [ ]* 6.5 Write property test for path special character handling
    - **Property 8: Path Special Character Handling**
    - **Validates: Requirements 7.3**
    - Generate paths with special characters, verify proper escaping
  
  - [ ] 6.6 Implement executable permissions setting
    - Set launch script to executable (chmod +x)
    - Verify permissions after creation
    - _Requirements: 6.5_
  
  - [ ] 6.7 Implement icon conversion
    - Extract icon data from SteamShortcut
    - Resolve icon file paths relative to Steam's grid directory
    - Convert PNG/JPG to .icns format using sips or ImageIO
    - Save as AppIcon.icns in Resources/
    - Handle conversion failures gracefully (use default icon)
    - _Requirements: 5.3, 5.4, 5.5_
  
  - [ ]* 6.8 Write property test for app bundle structure validity
    - **Property 4: App Bundle Structure Validity**
    - **Validates: Requirements 6.1, 6.2, 6.4, 6.5**
    - Generate app bundles, verify all required components present
  
  - [ ]* 6.9 Write property test for icon conversion success
    - **Property 5: Icon Conversion Success**
    - **Validates: Requirements 5.1, 5.2, 5.3, 5.4, 5.5**
    - Generate shortcuts with icons, verify .icns creation or default icon
  
  - [ ] 6.10 Write unit tests for app bundle generator
    - Test bundle structure creation
    - Test Info.plist generation
    - Test launch script generation for simple command
    - Test launch script generation for RetroArch with core
    - Test icon conversion from PNG
    - Test default icon when conversion fails
    - Test game names with special characters
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 7.1, 7.2, 7.3_

- [ ] 7. Implement Configuration Manager component
  - [ ] 7.1 Implement configuration data model
    - Define AppConfiguration struct with Codable conformance
    - Include: shortcutsVDFPath, outputDirectory, selectedShortcutIDs, removeOrphanedBundles, lastConversionDate
    - _Requirements: 11.1, 11.2, 11.3, 11.4_
  
  - [ ] 7.2 Implement configuration file I/O
    - Create config directory: ~/Library/Application Support/SteamShortcutConverter/
    - Implement JSON serialization and deserialization
    - Write configuration to config.json
    - Read configuration from config.json
    - _Requirements: 11.1, 11.2, 11.3, 11.4_
  
  - [ ] 7.3 Implement configuration validation
    - Verify paths exist
    - Validate output directory is writable
    - _Requirements: 10.5_
  
  - [ ] 7.4 Implement corrupted configuration handling
    - Detect JSON parse errors
    - Use default configuration on corruption
    - Notify user of configuration reset
    - _Requirements: 10.5_
  
  - [ ]* 7.5 Write property test for configuration round-trip
    - **Property 6: Configuration Round-Trip Preservation**
    - **Validates: Requirements 11.1, 11.2, 11.3, 11.4, 11.5**
    - Generate random configurations, verify serialization round-trip
  
  - [ ] 7.6 Write unit tests for configuration manager
    - Test save and load configuration
    - Test missing configuration file
    - Test corrupted JSON handling
    - Test default configuration values
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5_

- [ ] 8. Implement incremental update functionality
  - [ ] 8.1 Implement conversion state persistence
    - Define ConversionState struct with Codable conformance
    - Include: timestamp, sourceVDFPath, convertedShortcuts
    - Save conversion state to conversion_state.json after each conversion
    - Load previous conversion state before incremental conversion
    - _Requirements: 8.1_
  
  - [ ] 8.2 Implement change detection algorithm
    - Compare current shortcuts against previous conversion state
    - Identify new shortcuts (not in previous state)
    - Identify removed shortcuts (in previous state but not current)
    - Identify modified shortcuts (different launch command or icon hash)
    - Identify unchanged shortcuts (same app ID, launch command, and icon)
    - _Requirements: 8.1, 8.2, 8.3, 8.4_
  
  - [ ] 8.3 Implement selective bundle generation
    - Generate bundles only for new and modified shortcuts
    - Skip bundle generation for unchanged shortcuts
    - Update conversion state with new bundle records
    - _Requirements: 8.5_
  
  - [ ] 8.4 Implement orphaned bundle cleanup
    - Identify bundles for removed shortcuts
    - Delete bundle .app directories when removeOrphanedBundles is enabled
    - Log cleanup actions
    - _Requirements: 8.3_
  
  - [ ]* 8.5 Write property test for incremental update detection
    - **Property 7: Incremental Update Detection**
    - **Validates: Requirements 8.1, 8.2, 8.3, 8.4**
    - Generate two conversion states, verify correct change identification
  
  - [ ] 8.6 Write unit tests for incremental updates
    - Test new shortcut detection
    - Test removed shortcut detection
    - Test modified shortcut detection (changed launch command)
    - Test modified shortcut detection (changed icon)
    - Test unchanged shortcut preservation
    - Test orphaned bundle cleanup
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_

- [ ] 9. Checkpoint - Core functionality complete
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 10. Implement shortcuts.vdf file location
  - [ ] 10.1 Implement auto-detection
    - Search ~/Library/Application Support/Steam/userdata/*/config/shortcuts.vdf
    - Find all matching files (multiple Steam accounts)
    - Return list of found shortcuts.vdf paths
    - _Requirements: 1.1, 1.2_
  
  - [ ] 10.2 Implement manual file selection
    - Provide file picker for manual shortcuts.vdf selection
    - Validate selected file is valid VDF format
    - _Requirements: 1.3, 1.5_
  
  - [ ] 10.3 Implement error handling for missing file
    - Display clear error message when no shortcuts.vdf found
    - Provide instructions for locating file manually
    - _Requirements: 1.4, 10.1_
  
  - [ ] 10.4 Write unit tests for file location
    - Test auto-detection with single Steam account
    - Test auto-detection with multiple Steam accounts
    - Test manual file selection
    - Test error handling when file not found
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

- [ ] 11. Implement UI Controller and main application window
  - [ ] 11.1 Create main window with SwiftUI
    - Design layout: shortcuts.vdf path, shortcut list, output directory, progress view
    - Implement file picker for shortcuts.vdf selection
    - Implement directory picker for output directory
    - _Requirements: 9.3_
  
  - [ ] 11.2 Implement shortcut list view
    - Display detected shortcuts with columns: name, emulator, icon preview
    - Implement checkboxes for selection/deselection
    - Show only ROM-related shortcuts (filtered)
    - _Requirements: 9.1, 9.2, 3.3, 3.4_
  
  - [ ] 11.3 Implement conversion progress UI
    - Show progress bar with percentage
    - Display current game being processed
    - Show counts: total shortcuts, processed, remaining
    - _Requirements: 9.4_
  
  - [ ] 11.4 Implement conversion completion summary
    - Display total bundles created
    - Display total bundles updated
    - Show error count with details
    - Show warnings (missing emulator, missing ROM, icon conversion failures)
    - _Requirements: 9.5_
  
  - [ ] 11.5 Implement error display
    - Show error messages in alert dialogs
    - Display warnings in summary view
    - Provide actionable error messages
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_
  
  - [ ] 11.6 Implement settings panel
    - Checkbox for "Remove orphaned bundles"
    - Display last conversion date
    - Button to reset configuration
    - _Requirements: 11.4_

- [ ] 12. Implement error handling and logging
  - [ ] 12.1 Implement error handling for VDF parsing
    - Handle file not found
    - Handle invalid VDF format
    - Handle corrupted data
    - Display appropriate error messages
    - _Requirements: 1.4, 2.5, 10.1_
  
  - [ ] 12.2 Implement error handling for app bundle generation
    - Handle output directory not writable
    - Handle icon conversion failure
    - Handle missing emulator
    - Handle missing ROM
    - Display appropriate warnings
    - _Requirements: 10.2, 10.3, 10.4, 10.5_
  
  - [ ] 12.3 Implement logging system
    - Log errors and warnings to console
    - Log conversion actions (created, updated, skipped)
    - Include timestamps in log messages
    - _Requirements: All error handling requirements_

- [ ] 13. Integration and end-to-end workflow
  - [ ] 13.1 Wire all components together
    - Connect UI actions to component methods
    - Implement async/await pipeline: locate → parse → filter → generate
    - Handle component errors and propagate to UI
    - _Requirements: All requirements_
  
  - [ ] 13.2 Implement full conversion workflow
    - User selects shortcuts.vdf (auto-detect or manual)
    - Parse VDF and extract shortcuts
    - Filter ROM-related shortcuts
    - User selects shortcuts to convert
    - User selects output directory
    - Generate app bundles (with progress updates)
    - Display completion summary
    - Save configuration and conversion state
    - _Requirements: All requirements_
  
  - [ ] 13.3 Implement incremental conversion workflow
    - Load previous conversion state
    - Detect changes (new, modified, removed shortcuts)
    - Generate bundles only for changes
    - Clean up orphaned bundles if enabled
    - Display completion summary
    - Save updated conversion state
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_
  
  - [ ] 13.4 Write integration tests
    - Test end-to-end: parse VDF → filter → generate bundles
    - Test incremental update: initial conversion → modify VDF → detect changes
    - Test icon handling: embedded icon → extract → convert → bundle
    - Test launch script: complex command → preserve exactly
    - _Requirements: All requirements_

- [ ] 14. Final checkpoint and validation
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 15. Manual testing and polish
  - [ ] 15.1 Test with real Steam ROM Manager data
    - Use actual shortcuts.vdf from Steam ROM Manager
    - Verify all ROM shortcuts detected correctly
    - Verify app bundles launch games correctly
    - _Requirements: All requirements_
  
  - [ ] 15.2 Test macOS integration
    - Verify Spotlight search finds generated apps
    - Verify Launchpad displays generated apps
    - Verify icons display correctly in Finder
    - Verify Dock integration works
    - _Requirements: 6.1, 6.3_
  
  - [ ] 15.3 Test with various emulators
    - Test RetroArch shortcuts with different cores
    - Test Dolphin shortcuts
    - Test PPSSPP shortcuts
    - Test other common emulators
    - _Requirements: 3.1, 3.2, 4.5_
  
  - [ ] 15.4 Test edge cases
    - Test game names with special characters
    - Test paths with spaces
    - Test very long game names
    - Test shortcuts with missing icons
    - Test shortcuts with missing emulators
    - _Requirements: 7.3, 10.2, 10.3, 10.4_
  
  - [ ] 15.5 Polish UI and user experience
    - Improve error messages
    - Add tooltips and help text
    - Improve progress feedback
    - Add keyboard shortcuts
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5_

## Notes

- Tasks marked with `*` are optional property-based tests and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Property-based tests use SwiftCheck with minimum 100 iterations per property (if implemented)
- App bundles are fully self-contained with absolute paths
- The implementation uses Swift and native macOS APIs (SwiftUI, FileManager, Foundation)
- All file I/O operations use async/await for non-blocking execution
- Read-only operation: never modify Steam's shortcuts.vdf file
