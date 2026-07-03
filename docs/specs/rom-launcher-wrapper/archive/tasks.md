# Implementation Plan: ROM Shortcut Maker

## Overview

This implementation plan breaks down the ROM Shortcut Maker into discrete coding tasks that build incrementally toward a complete macOS application. The system will scan directories for ROM files, detect installed emulators, fetch game metadata, and generate native .app bundles that launch games directly from Finder, Spotlight, or the Dock.

The implementation follows a bottom-up approach: core data models → individual components → integration → UI layer. Each task builds on previous work, with property-based tests using SwiftCheck to validate correctness properties throughout development.

## Tasks

- [ ] 1. Set up project structure and core data models
  - Create Xcode project for macOS application (Swift, minimum macOS 12)
  - Define core data structures: ROMFile, ScanState, ScanDelta, MultiDiskGame, Emulator, ParserConfig, GameMetadata, AppConfiguration
  - Create protocol definitions for all components: ROMScanner, EmulatorDetector, MetadataFetcher, AppWrapperGenerator, ConfigurationManager
  - Set up directory structure for Steam ROM Manager parsers and test fixtures
  - Add SwiftCheck dependency for property-based testing
  - _Requirements: All requirements (foundation)_

- [ ] 2. Implement ROM Scanner component
  - [ ] 2.1 Implement basic directory scanning with FileManager
    - Recursive directory traversal for user-specified paths
    - File extension filtering for supported ROM types (.nes, .snes, .smc, .gba, .gbc, .gb, .nds, .n64, .z64, .v64, .iso, .cue, .bin, .chd, .rvz, .wbfs, .gcm, .gcz, .ciso, .wad, .dol, .elf, .xci, .nsp, .md, .smd, .gen, .32x, .sms, .gg, .sg)
    - Extract file metadata: path, size, modification date
    - _Requirements: 1.1, 1.2, 1.4_
  
  - [ ]* 2.2 Write property test for recursive ROM discovery
    - **Property 1: Recursive ROM Discovery**
    - **Validates: Requirements 1.1, 1.2, 1.4**
    - Generate random directory trees with ROM files at various depths, verify all discovered
  
  - [ ] 2.3 Implement game name extraction from filenames
    - Remove file extension
    - Remove region tags (USA), (Europe), (Japan), etc.
    - Remove disc indicators (Disc 1), (CD1), etc.
    - Remove version tags [!], [a], [b], etc.
    - Handle edge cases: multiple parentheses, special characters
    - _Requirements: 1.3_
  
  - [ ]* 2.4 Write property test for game name extraction
    - **Property 2: Game Name Extraction**
    - **Validates: Requirements 1.3**
    - Generate random ROM filenames with various formats, verify non-empty extraction
  
  - [ ] 2.5 Implement error handling for unreadable files
    - Catch file permission errors and continue scanning
    - Log errors with file path and reason
    - Handle invalid symlinks gracefully
    - _Requirements: 9.1_
  
  - [ ]* 2.6 Write property test for scan error recovery
    - **Property 16: Error Recovery During Scanning**
    - **Validates: Requirements 9.1**
    - Generate directories with unreadable files, verify continued scanning

- [ ] 3. Implement multi-disk game detection
  - [ ] 3.1 Implement multi-disk pattern detection
    - Detect patterns: "(Disc N)", "(Disk N)", "(CD N)", "(CD N)", case-insensitive
    - Extract base game name by removing disc indicators
    - Group ROM files by base name
    - Identify primary disc (lowest disc number)
    - _Requirements: 13.1, 13.2_
  
  - [ ]* 3.2 Write property test for multi-disk grouping
    - **Property 25: Multi-Disk Game Detection and Grouping**
    - **Validates: Requirements 13.1, 13.2**
    - Generate multi-disk filenames, verify correct grouping
  
  - [ ]* 3.3 Write unit tests for multi-disk edge cases
    - Test mixed disc numbering formats
    - Test games with similar names but different disc counts
    - Test single-disc games that shouldn't be grouped
    - _Requirements: 13.1, 13.2_

- [ ] 4. Implement Emulator Detector component
  - [ ] 4.1 Implement emulator scanning in /Applications
    - Scan /Applications directory for .app bundles
    - Identify emulators by bundle identifier or app name
    - Extract executable path from bundle structure
    - Support: RetroArch, Dolphin, PCSX2, PPSSPP, Citra, Ryujinx, mGBA, DeSmuME, OpenEmu
    - _Requirements: 2.1, 2.2, 2.3_
  
  - [ ] 4.2 Create Steam ROM Manager parser JSON files
    - Download or bundle parser files from https://github.com/SteamGridDB/steam-rom-manager/tree/master/files/presets
    - Include parsers for: NES, SNES, N64, GameCube, Wii, Game Boy, GBA, DS, 3DS, Switch, Genesis, Saturn, Dreamcast, PS1, PS2, PSP
    - Parsers define file extensions in parserInputs.glob field
    - Parsers define emulator paths in executable.path field
    - Parsers define launch arguments in executableArgs field
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_
  
  - [ ] 4.3 Implement Steam ROM Manager parser JSON parser
    - Load JSON parser files from embedded resources or downloaded location
    - Parse ParserConfig objects with all fields: parserType, configTitle, steamCategory, executablePath, executableArgs, parserInputs, etc.
    - Extract file extensions from glob patterns (e.g., "**/*.{nes,NES}" → [".nes"])
    - Validate parser structure
    - Provide fallback parsers if files missing
    - _Requirements: 7.1, 7.2_
  
  - [ ] 4.4 Implement ROM-to-emulator matching logic
    - Match ROM file extension to system type using Steam ROM Manager parsers
    - Find compatible emulators from detected set
    - Apply priority ordering from parsers
    - Handle multiple compatible emulators (return all for user choice)
    - Flag unmatchable ROMs (no compatible emulator)
    - _Requirements: 2.4, 2.5, 3.1, 3.2, 3.5_
  
  - [ ]* 4.5 Write property test for ROM-emulator matching completeness
    - **Property 3: ROM-Emulator Matching Completeness**
    - **Validates: Requirements 3.1**
    - Generate ROM files and emulator sets, verify matching when compatible emulators exist
  
  - [ ]* 4.6 Write property test for emulator priority ordering
    - **Property 4: Emulator Priority Ordering**
    - **Validates: Requirements 3.2, 7.4**
    - Generate scenarios with multiple compatible emulators, verify priority ordering
  
  - [ ]* 4.7 Write property test for unmatchable ROM flagging
    - **Property 5: Unmatchable ROM Flagging**
    - **Validates: Requirements 2.5, 3.5**
    - Generate ROMs with unsupported extensions, verify flagging
  
  - [ ]* 4.8 Write property test for parser extension mapping
    - **Property 15: Parser Extension Mapping**
    - **Validates: Requirements 7.3**
    - Generate system types, verify extension mapping from Steam ROM Manager parsers

- [ ] 5. Checkpoint - Core scanning and matching complete
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 6. Implement Metadata Fetcher component
  - [ ] 6.1 Implement metadata cache system
    - Create cache directory: ~/Library/Caches/ROMShortcutMaker/metadata/
    - Generate cache keys from ROM filename hash + system type
    - Implement cache read/write for metadata JSON and cover art images
    - _Requirements: 4.4_
  
  - [ ] 6.2 Implement online metadata API client
    - Choose API: ScreenScraper or TheGamesDB
    - Implement HTTP client with URLSession
    - Parse API responses into GameMetadata objects
    - Handle API authentication if required
    - _Requirements: 4.1, 4.2_
  
  - [ ] 6.3 Implement cover art download
    - Download images from metadata cover art URLs
    - Save to cache directory
    - Handle image format conversion if needed
    - _Requirements: 4.3_
  
  - [ ] 6.4 Implement rate limiting and retry logic
    - Detect 429 (rate limit) responses
    - Implement exponential backoff
    - Retry up to 3 times
    - Respect API rate limits
    - _Requirements: 4.6_
  
  - [ ] 6.5 Implement metadata fetch fallback
    - Use ROM filename as title when API fails
    - Skip cover art when unavailable
    - Log fetch failures
    - Continue processing without blocking
    - _Requirements: 4.5, 9.2_
  
  - [ ]* 6.6 Write property test for metadata structure completeness
    - **Property 6: Metadata Structure Completeness**
    - **Validates: Requirements 4.2**
    - Generate metadata responses, verify required fields present
  
  - [ ]* 6.7 Write property test for metadata caching
    - **Property 7: Metadata Caching Prevents Redundant Requests**
    - **Validates: Requirements 4.4**
    - Generate ROM files, verify single API call on repeated fetches
  
  - [ ]* 6.8 Write property test for metadata fallback
    - **Property 8: Metadata Fetch Fallback**
    - **Validates: Requirements 4.5**
    - Generate fetch failures, verify filename fallback
  
  - [ ]* 6.9 Write property test for metadata error recovery
    - **Property 17: Metadata Fetch Error Recovery**
    - **Validates: Requirements 9.2**
    - Generate batch with some fetch failures, verify all processed
  
  - [ ]* 6.10 Write property test for multi-disk fetch efficiency
    - **Property 29: Multi-Disk Metadata Fetch Efficiency**
    - **Validates: Requirements 13.6**
    - Generate multi-disk games, verify single metadata fetch

- [ ] 7. Implement App Wrapper Generator component
  - [ ] 7.1 Implement app bundle directory structure creation
    - Create .app/Contents/ directory structure
    - Create MacOS/, Resources/ subdirectories
    - Set proper directory permissions
    - _Requirements: 5.1_
  
  - [ ] 7.2 Implement Info.plist generation
    - Create Info.plist with CFBundleIdentifier, CFBundleName, CFBundleDisplayName, CFBundleVersion
    - Generate bundle identifier: com.romshortcutmaker.{sanitized-game-name}
    - Include icon file reference when available
    - Write plist in XML format
    - _Requirements: 5.3, 5.5_
  
  - [ ] 7.3 Implement launch script generation
    - Generate bash script with emulator path, ROM path, and launch arguments
    - Use absolute paths for emulator and ROM
    - Include proper shebang (#!/bin/bash)
    - Use 'open -a' command for macOS app launching
    - Apply Steam ROM Manager parser launch parameters from executableArgs field
    - _Requirements: 5.2, 6.1, 6.3, 6.4_
  
  - [ ] 7.4 Implement special character escaping in launch scripts
    - Properly quote ROM paths with spaces
    - Escape special shell characters: $, `, \, ", '
    - Test with edge case filenames
    - _Requirements: 6.5_
  
  - [ ]* 7.5 Write property test for special character handling
    - **Property 14: Special Character Path Handling**
    - **Validates: Requirements 6.5**
    - Generate ROM paths with special characters, verify proper escaping
  
  - [ ] 7.6 Implement executable permissions setting
    - Set launch script to executable (chmod +x)
    - Verify permissions after creation
    - _Requirements: 5.6_
  
  - [ ] 7.7 Implement cover art to icon conversion
    - Convert PNG/JPG cover art to .icns format using sips command
    - Save as AppIcon.icns in Resources/
    - Handle conversion failures gracefully (skip icon)
    - _Requirements: 5.4_
  
  - [ ] 7.8 Implement multi-disk .m3u playlist generation
    - Detect if emulator supports .m3u playlists
    - Generate .m3u file with all disc paths
    - Save playlist in Resources/ directory
    - Update launch script to use playlist instead of single ROM
    - _Requirements: 13.5_
  
  - [ ] 7.9 Implement multi-disk metadata inclusion
    - Create game_info.json in Resources/ with all disc paths
    - Include disc count and primary disc indicator
    - _Requirements: 13.4_
  
  - [ ] 7.10 Implement single wrapper generation for multi-disk games
    - Generate one app bundle per multi-disk game (not per disc)
    - Use primary disc (Disc 1) as launch target
    - _Requirements: 13.3_
  
  - [ ]* 7.11 Write property test for app bundle generation completeness
    - **Property 9: App Bundle Generation Completeness**
    - **Validates: Requirements 5.1, 5.2**
    - Generate ROM-emulator pairs, verify valid bundle structure
  
  - [ ]* 7.12 Write property test for bundle metadata completeness
    - **Property 10: App Bundle Metadata Completeness**
    - **Validates: Requirements 5.3, 5.4, 5.5**
    - Generate app bundles, verify Info.plist completeness
  
  - [ ]* 7.13 Write property test for executable permissions
    - **Property 11: App Bundle Executable Permissions**
    - **Validates: Requirements 5.6**
    - Generate app bundles, verify launch script permissions
  
  - [ ]* 7.14 Write property test for output directory consistency
    - **Property 12: Output Directory Consistency**
    - **Validates: Requirements 5.7**
    - Generate multiple bundles, verify all in output directory
  
  - [ ]* 7.15 Write property test for launch script parameter inclusion
    - **Property 13: Launch Script Parameter Inclusion**
    - **Validates: Requirements 6.1, 6.3, 6.4, 7.5**
    - Generate bundles, verify script contains required parameters
  
  - [ ]* 7.16 Write property test for multi-disk single wrapper
    - **Property 26: Multi-Disk Single Wrapper Generation**
    - **Validates: Requirements 13.3**
    - Generate multi-disk games, verify single wrapper creation
  
  - [ ]* 7.17 Write property test for multi-disk metadata inclusion
    - **Property 27: Multi-Disk Metadata Inclusion**
    - **Validates: Requirements 13.4**
    - Generate multi-disk bundles, verify all disc paths included
  
  - [ ]* 7.18 Write property test for playlist generation
    - **Property 28: Multi-Disk Playlist Generation**
    - **Validates: Requirements 13.5**
    - Generate multi-disk games with playlist-supporting emulators, verify .m3u creation
  
  - [ ]* 7.19 Write property test for wrapper generation error recovery
    - **Property 18: App Wrapper Generation Error Recovery**
    - **Validates: Requirements 9.3**
    - Generate batch with some generation failures, verify others succeed

- [ ] 8. Checkpoint - App wrapper generation complete
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 9. Implement Configuration Manager component
  - [ ] 9.1 Implement configuration data model
    - Define AppConfiguration struct with Codable conformance
    - Include: scanDirectories, outputDirectory, emulatorOverrides, removeOrphanedWrappers, metadataCacheEnabled
    - _Requirements: 10.1_
  
  - [ ] 9.2 Implement configuration file I/O
    - Create config directory: ~/Library/Application Support/ROMShortcutMaker/
    - Implement JSON serialization and deserialization
    - Write configuration to config.json
    - Read configuration from config.json
    - _Requirements: 10.1, 10.2, 10.3_
  
  - [ ] 9.3 Implement configuration validation
    - Verify scan directories exist
    - Verify output directory is writable
    - Validate emulator override references
    - _Requirements: 10.2_
  
  - [ ] 9.4 Implement corrupted configuration handling
    - Detect JSON parse errors
    - Use default configuration on corruption
    - Backup corrupted file before overwriting
    - Notify user of configuration reset
    - _Requirements: 10.5_
  
  - [ ]* 9.5 Write property test for configuration round-trip
    - **Property 19: Configuration Round-Trip Preservation**
    - **Validates: Requirements 10.1, 10.2, 10.3, 10.4**
    - Generate random configurations, verify serialization round-trip

- [ ] 10. Implement incremental rescan functionality
  - [ ] 10.1 Implement scan state persistence
    - Define ScanState struct with Codable conformance
    - Include: timestamp, scannedDirectories, discoveredROMs, generatedWrappers
    - Save scan state to scan_state.json after each scan
    - Load previous scan state before incremental scan
    - _Requirements: 11.1_
  
  - [ ] 10.2 Implement change detection algorithm
    - Compare current ROM files against previous scan state
    - Identify new ROMs (not in previous state)
    - Identify removed ROMs (in previous state but not current)
    - Identify modified ROMs (different size or modification date)
    - Identify unchanged ROMs (same path, size, and date)
    - Return ScanDelta with categorized changes
    - _Requirements: 11.1, 11.2, 11.3, 11.4_
  
  - [ ] 10.3 Implement selective wrapper generation
    - Generate wrappers only for new and modified ROMs
    - Skip wrapper generation for unchanged ROMs
    - Update scan state with new wrapper records
    - _Requirements: 11.5, 11.7_
  
  - [ ] 10.4 Implement orphaned wrapper cleanup
    - Identify wrappers for removed ROMs
    - Delete wrapper .app bundles when removeOrphanedWrappers is enabled
    - Log cleanup actions
    - _Requirements: 11.6_
  
  - [ ]* 10.5 Write property test for change detection
    - **Property 20: Incremental Scan Change Detection**
    - **Validates: Requirements 11.1, 11.2, 11.3, 11.4**
    - Generate two scan states, verify correct change identification
  
  - [ ]* 10.6 Write property test for incremental wrapper generation
    - **Property 21: Incremental Wrapper Generation**
    - **Validates: Requirements 11.5, 11.7**
    - Generate scan deltas, verify wrappers only for changed ROMs
  
  - [ ]* 10.7 Write property test for orphaned cleanup
    - **Property 22: Orphaned Wrapper Cleanup**
    - **Validates: Requirements 11.6**
    - Generate removed ROMs, verify wrapper cleanup when enabled

- [ ] 11. Implement app bundle editing functionality
  - [ ] 11.1 Implement app bundle parsing
    - Read existing app bundle structure
    - Parse Info.plist to extract metadata
    - Parse launch script to extract emulator and ROM paths
    - Parse game_info.json for multi-disk information
    - _Requirements: 12.1, 12.2_
  
  - [ ] 11.2 Implement emulator change validation
    - Verify new emulator is installed
    - Check new emulator supports ROM file extension
    - Use Steam ROM Manager parsers for compatibility validation
    - _Requirements: 12.7_
  
  - [ ]* 11.3 Write property test for compatibility validation
    - **Property 24: Emulator Compatibility Validation**
    - **Validates: Requirements 12.7**
    - Generate emulator changes, verify compatibility checking
  
  - [ ] 11.4 Implement app bundle update
    - Regenerate launch script with new emulator or parameters
    - Preserve existing Info.plist metadata (except launch-related fields)
    - Preserve existing icon file
    - Update game_info.json if needed
    - _Requirements: 12.3, 12.4, 12.5, 12.6_
  
  - [ ]* 11.5 Write property test for update preservation
    - **Property 23: App Wrapper Update Preservation**
    - **Validates: Requirements 12.5, 12.6**
    - Generate wrapper updates, verify icon/metadata preservation

- [ ] 12. Checkpoint - Core functionality complete
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 13. Implement UI Controller and main application window
  - [ ] 13.1 Create main window with SwiftUI
    - Design layout: scan directory list, ROM list, progress view, log view
    - Implement directory picker for adding scan directories
    - Implement directory picker for output directory
    - _Requirements: 8.1_
  
  - [ ] 13.2 Implement ROM list view
    - Display discovered ROMs with columns: name, system, emulator, metadata status
    - Show multi-disk games as single entries with disc count indicator
    - Implement sorting and filtering
    - _Requirements: 8.2, 13.7_
  
  - [ ] 13.3 Implement emulator override UI
    - Allow user to click ROM and select different emulator from dropdown
    - Show only compatible emulators for ROM type
    - Save overrides to configuration
    - _Requirements: 3.3, 8.3_
  
  - [ ] 13.4 Implement scan progress UI
    - Show progress bar with percentage
    - Display current file being processed
    - Show counts: total ROMs, processed, remaining
    - _Requirements: 8.5_
  
  - [ ] 13.5 Implement scan completion summary
    - Display total wrappers created
    - Show error count with link to log view
    - Show warnings (missing metadata, unmatchable ROMs)
    - _Requirements: 1.5, 8.6_
  
  - [ ] 13.6 Implement error log view
    - Display all errors and warnings in scrollable list
    - Include timestamp, component, and message
    - Provide copy and export functionality
    - _Requirements: 9.5_
  
  - [ ] 13.7 Implement scan and rescan buttons
    - "Scan" button: full scan of all directories
    - "Rescan" button: incremental scan for changes
    - Disable buttons during scan operation
    - _Requirements: 8.4_
  
  - [ ] 13.8 Implement app bundle editing UI
    - Right-click context menu on ROM list: "Edit App Bundle"
    - Modal dialog showing current emulator and launch parameters
    - Emulator dropdown with compatible options
    - Launch parameter text field
    - Save and Cancel buttons
    - _Requirements: 12.1, 12.2, 12.3, 12.4_

- [ ] 14. Implement error handling and logging
  - [ ] 14.1 Create centralized logging system
    - Implement Logger class with log levels: error, warning, info, debug
    - Write logs to ~/Library/Logs/ROMShortcutMaker/app.log
    - Maintain in-memory log buffer for UI display
    - Include timestamp, level, component, and message in log format
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5_
  
  - [ ] 14.2 Implement error notifications
    - Show alert dialogs for critical errors (output directory not writable, insufficient disk space)
    - Show toast notifications for warnings (missing metadata, emulator path invalid)
    - _Requirements: 9.4_

- [ ] 15. Integration and end-to-end workflow
  - [ ] 15.1 Wire all components together
    - Connect UI actions to component methods
    - Implement async/await pipeline: scan → detect → fetch → generate
    - Handle component errors and propagate to UI
    - _Requirements: All requirements_
  
  - [ ] 15.2 Implement full scan workflow
    - User adds scan directories
    - User clicks "Scan" button
    - ROM Scanner discovers files
    - Emulator Detector matches emulators
    - Metadata Fetcher retrieves data (with progress updates)
    - App Wrapper Generator creates bundles (with progress updates)
    - Display completion summary
    - _Requirements: All requirements_
  
  - [ ] 15.3 Implement incremental rescan workflow
    - User clicks "Rescan" button
    - Load previous scan state
    - Detect changes (new, modified, removed ROMs)
    - Generate wrappers only for changes
    - Clean up orphaned wrappers if enabled
    - Display completion summary
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5, 11.6, 11.7_
  
  - [ ] 15.4 Implement edit workflow
    - User selects ROM and chooses "Edit App Bundle"
    - Load existing bundle configuration
    - User changes emulator or parameters
    - Validate compatibility
    - Update app bundle
    - Refresh ROM list
    - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5, 12.6, 12.7_
  
  - [ ]* 15.5 Write integration tests
    - Test end-to-end: scan → detect → fetch → generate
    - Test incremental rescan: initial scan → add ROM → rescan → verify only new wrapper
    - Test multi-disk workflow: scan multi-disk game → verify single wrapper with playlist
    - Test edit workflow: generate wrapper → edit emulator → verify updated launch script
    - _Requirements: All requirements_

- [ ] 16. Final checkpoint and validation
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Property-based tests use SwiftCheck with minimum 100 iterations per property
- App bundles are fully self-contained with absolute paths (no runtime dependency on ROM Shortcut Maker)
- The implementation uses Swift and native macOS APIs (SwiftUI, FileManager, URLSession)
- Steam ROM Manager parsers are embedded as JSON resources in the app bundle or downloaded from GitHub
- All file I/O operations use async/await for non-blocking execution
