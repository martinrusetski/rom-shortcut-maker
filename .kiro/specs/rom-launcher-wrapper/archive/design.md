# Design Document: ROM Shortcut Maker

## Overview

The ROM Shortcut Maker is a native macOS application that automates the process of creating launchable app bundles for retro game ROMs. The system scans user-specified directories for ROM files, detects installed emulators, fetches game metadata and cover art, and generates native macOS .app wrappers that launch games directly from Finder, Spotlight, or the Dock.

The application uses Steam ROM Manager parsers for system-to-emulator associations and launch parameters, ensuring compatibility with the industry-standard retro gaming configuration format. The design emphasizes automation, simplicity, and native macOS integration.

### Key Design Goals

- Minimize manual configuration through intelligent automation
- Provide native macOS experience with .app bundles that integrate with Spotlight and Launchpad
- Generate fully autonomous app bundles that work independently without requiring ROM Shortcut Maker to be running or installed
- Support incremental rescanning to efficiently handle library changes
- Use Steam ROM Manager parsers for broad compatibility with established configurations
- Handle edge cases gracefully (multi-disk games, missing metadata, invalid files)

## Architecture

The system follows a pipeline architecture with five primary components that process ROM files through sequential stages:

```
[User Input] → [ROM Scanner] → [Emulator Detector] → [Metadata Fetcher] → [App Wrapper Generator] → [.app Bundles]
                      ↓                ↓                      ↓
                [File System]    [Applications]      [Online APIs]
```

### Component Overview

1. **ROM Scanner**: Discovers ROM files in user-specified directories, extracts game names, and maintains a registry of discovered files
2. **Emulator Detector**: Identifies installed emulators in /Applications and associates them with ROM types based on Steam ROM Manager parsers
3. **Metadata Fetcher**: Queries online databases for game information and cover art, with local caching to minimize API requests
4. **App Wrapper Generator**: Creates native macOS .app bundles with launch scripts, icons, and proper metadata
5. **Configuration Manager**: Handles persistence of user settings, scan directories, and emulator preferences
6. **UI Controller**: Provides the user interface for configuration, progress monitoring, and error reporting

### Data Flow

1. User configures scan directories through the UI
2. ROM Scanner recursively discovers ROM files and extracts game names
3. Emulator Detector matches ROM types to installed emulators using Steam ROM Manager parsers
4. Metadata Fetcher retrieves game information and cover art (with caching)
5. App Wrapper Generator creates .app bundles with launch scripts
6. Configuration Manager persists settings for future sessions

### Incremental Rescan Strategy

The system maintains a scan state file that records:
- Previously discovered ROM files with their paths, sizes, and modification timestamps
- Generated app wrapper paths and their associated ROM files

On rescan:
- Compare current filesystem state against previous scan state
- Identify new, modified, and removed ROM files
- Generate app wrappers only for new/modified ROMs
- Optionally clean up app wrappers for removed ROMs

## Components and Interfaces

### ROM Scanner

**Responsibilities:**
- Recursively scan user-specified directories for ROM files
- Filter files by supported extensions
- Extract game names from filenames
- Detect multi-disk games and group them appropriately
- Maintain scan state for incremental rescanning

**Interface:**
```swift
protocol ROMScanner {
    func scanDirectories(_ paths: [URL]) async throws -> [ROMFile]
    func incrementalScan(previousState: ScanState, directories: [URL]) async throws -> ScanDelta
    func extractGameName(from filename: String) -> String
    func detectMultiDiskGroup(files: [ROMFile]) -> [MultiDiskGame]
}

struct ROMFile {
    let path: URL
    let filename: String
    let gameName: String
    let fileExtension: String
    let fileSize: Int64
    let modificationDate: Date
    let systemType: SystemType?
}

struct ScanDelta {
    let newROMs: [ROMFile]
    let modifiedROMs: [ROMFile]
    let removedROMs: [ROMFile]
    let unchangedROMs: [ROMFile]
}

struct MultiDiskGame {
    let gameName: String
    let discs: [ROMFile]
    let primaryDisc: ROMFile
}
```

**Implementation Notes:**
- Use FileManager for directory traversal
- Support extensions: .nes, .snes, .smc, .gba, .gbc, .gb, .nds, .n64, .z64, .v64, .iso, .cue, .bin, .chd, .rvz, .wbfs, .gcm, .gcz, .ciso, .wad, .dol, .elf, .xci, .nsp, .md, .smd, .gen, .32x, .sms, .gg, .sg
- Multi-disk detection patterns: "(Disc N)", "(CD N)", "(Disk N)", case-insensitive
- Game name extraction: remove extension, remove region tags, remove disc indicators

### Emulator Detector

**Responsibilities:**
- Scan /Applications for installed emulators
- Load and parse Steam ROM Manager parser JSON files
- Associate ROM types with compatible emulators
- Extract launch parameters from parser configurations

**Interface:**
```swift
protocol EmulatorDetector {
    func detectInstalledEmulators() async throws -> [Emulator]
    func loadSteamROMManagerParsers() throws -> [ParserConfig]
    func matchEmulator(for romFile: ROMFile, from emulators: [Emulator]) -> EmulatorMatch?
}

struct Emulator {
    let name: String
    let bundlePath: URL
    let executablePath: URL
    let supportedExtensions: Set<String>
    let launchTemplate: String
}

struct ParserConfig {
    let parserType: String
    let configTitle: String
    let steamCategory: String
    let executablePath: String
    let executableArgs: String
    let romDirectory: String
    let steamDirectory: String
    let startInDirectory: String
    let userAccounts: UserAccounts
    let parserInputs: ParserInputs
    let titleFromVariable: TitleFromVariable
    let fuzzyMatch: FuzzyMatch
    let executableModifier: String
    let onlineImageQueries: String
    let imagePool: String
    let defaultImage: String
    let localImages: String
}

struct ParserInputs {
    let glob: String  // File extension pattern like "**/*.{nes,NES}"
    let globRegex: String?
}

struct UserAccounts {
    let specifiedAccounts: String?
    let skipWithMissingDataDir: Bool
    let useCredentials: Bool
}

struct TitleFromVariable {
    let limitToGroups: String
    let caseInsensitiveVariables: Bool
    let skipFileIfVariableWasNotFound: Bool
    let tryToMatchTitle: Bool
}

struct FuzzyMatch {
    let use: Bool
    let removeCharacters: Bool
    let removeBrackets: Bool
}

enum EmulatorMatch {
    case single(Emulator)
    case multiple([Emulator])  // User must choose
    case none
}

enum SystemType: String {
    case nes, snes, n64, gamecube, wii
    case gameboy, gba, nds, n3ds
    case genesis, saturn, dreamcast
    case ps1, ps2, psp
    case switch
    // ... additional systems
}
```

**Implementation Notes:**
- Steam ROM Manager parsers stored as embedded JSON resources or downloaded from GitHub
- Parser glob patterns converted to file extension sets (e.g., "**/*.{nes,NES}" → [".nes"])
- Emulator detection via bundle identifier matching or executable name matching
- Support for RetroArch cores (requires core specification in parser)

### Metadata Fetcher

**Responsibilities:**
- Query online game databases for metadata
- Download and cache cover art
- Respect API rate limits
- Provide fallback to filename-based naming

**Interface:**
```swift
protocol MetadataFetcher {
    func fetchMetadata(for romFile: ROMFile) async throws -> GameMetadata?
    func downloadCoverArt(from url: URL) async throws -> Data
    func getCachedMetadata(for romFile: ROMFile) -> GameMetadata?
    func cacheMetadata(_ metadata: GameMetadata, for romFile: ROMFile) throws
}

struct GameMetadata {
    let title: String
    let description: String?
    let releaseDate: Date?
    let publisher: String?
    let genre: String?
    let coverArtURL: URL?
    let coverArtData: Data?
}
```

**Implementation Notes:**
- Primary API: ScreenScraper or TheGamesDB
- Cache location: ~/Library/Caches/ROMShortcutMaker/
- Cache key: hash of ROM filename + system type
- Rate limiting: exponential backoff on 429 responses

### App Wrapper Generator

**Responsibilities:**
- Create macOS .app bundle structure
- Generate launch scripts with proper emulator invocation
- Set app icons from cover art
- Create Info.plist with proper metadata
- Handle multi-disk game playlist generation
- Update existing app bundles when edited

**Interface:**
```swift
protocol AppWrapperGenerator {
    func generateAppWrapper(
        rom: ROMFile,
        emulator: Emulator,
        metadata: GameMetadata?,
        outputDirectory: URL
    ) async throws -> URL
    
    func generateMultiDiskWrapper(
        game: MultiDiskGame,
        emulator: Emulator,
        metadata: GameMetadata?,
        outputDirectory: URL
    ) async throws -> URL
    
    func updateAppWrapper(
        at path: URL,
        newEmulator: Emulator?,
        newLaunchParams: [String]?
    ) throws
}

struct AppWrapperConfig {
    let bundleName: String
    let bundleIdentifier: String
    let displayName: String
    let version: String
    let iconData: Data?
    let launchScript: String
}
```

**Implementation Notes:**
- Bundle structure: AppName.app/Contents/{MacOS, Resources, Info.plist}
- Launch script: bash script that invokes emulator with ROM path
- Icon generation: convert cover art to .icns format using sips
- Bundle identifier format: com.romshortcutmaker.{sanitized-game-name}
- Multi-disk: generate .m3u playlist for supported emulators
- **App bundles are fully self-contained**: All paths are absolute, no runtime dependency on ROM Shortcut Maker
- Launch parameters extracted from Steam ROM Manager parser executableArgs field

### Configuration Manager

**Responsibilities:**
- Persist user settings between sessions
- Load and validate configuration on startup
- Handle configuration file corruption gracefully

**Interface:**
```swift
protocol ConfigurationManager {
    func loadConfiguration() throws -> AppConfiguration
    func saveConfiguration(_ config: AppConfiguration) throws
    func resetToDefaults() -> AppConfiguration
}

struct AppConfiguration: Codable {
    let scanDirectories: [URL]
    let outputDirectory: URL
    let emulatorOverrides: [String: String]  // ROM path -> Emulator name
    let removeOrphanedWrappers: Bool
    let metadataCacheEnabled: Bool
}
```

**Implementation Notes:**
- Configuration file: ~/Library/Application Support/ROMShortcutMaker/config.json
- JSON format for human readability
- Validation on load: check directory existence, emulator validity

## Data Models

### Core Data Structures

```swift
// Scan state for incremental rescanning
struct ScanState: Codable {
    let timestamp: Date
    let scannedDirectories: [URL]
    let discoveredROMs: [ROMFileRecord]
    let generatedWrappers: [WrapperRecord]
}

struct ROMFileRecord: Codable {
    let path: String
    let fileSize: Int64
    let modificationDate: Date
    let systemType: String
    let associatedEmulator: String
}

struct WrapperRecord: Codable {
    let wrapperPath: String
    let romPath: String
    let creationDate: Date
}

// Multi-disk game representation
struct MultiDiskGame {
    let gameName: String
    let discs: [ROMFile]
    let primaryDisc: ROMFile
    
    var discCount: Int { discs.count }
}

// Emulator launch configuration
struct LaunchConfiguration {
    let emulatorPath: URL
    let romPath: URL
    let arguments: [String]
    let environment: [String: String]
}
```

### File System Structure

```
~/Library/Application Support/ROMShortcutMaker/
├── config.json                    # User configuration
├── scan_state.json                # Previous scan state
└── steam_rom_manager_parsers/     # Steam ROM Manager parser JSON files
    ├── Nintendo - Nintendo Entertainment System.json
    ├── Nintendo - Super Nintendo Entertainment System.json
    ├── Sony - PlayStation.json
    └── ...

~/Library/Caches/ROMShortcutMaker/
└── metadata/                      # Cached game metadata
    ├── {hash1}.json
    ├── {hash1}_cover.png
    └── ...

{User-Specified Output Directory}/
├── Super Mario Bros.app
├── The Legend of Zelda.app
├── Final Fantasy VII.app
└── ...
```

### App Bundle Structure

```
GameName.app/
├── Contents/
│   ├── Info.plist                 # Bundle metadata
│   ├── MacOS/
│   │   └── launch.sh              # Launch script (executable)
│   └── Resources/
│       ├── AppIcon.icns           # Game cover art as icon
│       └── game_info.json         # ROM path, emulator, multi-disk info
```

### Launch Script Template

```bash
#!/bin/bash
# Generated by ROM Shortcut Maker
# This script is self-contained and works independently of ROM Shortcut Maker

EMULATOR_PATH="{emulator_path}"
ROM_PATH="{rom_path}"
LAUNCH_ARGS=({launch_args})

# Launch emulator with ROM
open -a "$EMULATOR_PATH" --args "${LAUNCH_ARGS[@]}" "$ROM_PATH"
```


## Correctness Properties

A property is a characteristic or behavior that should hold true across all valid executions of a system - essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.

### Property 1: Recursive ROM Discovery

For any directory tree containing ROM files with supported extensions, the ROM Scanner should discover all ROM files regardless of nesting depth.

**Validates: Requirements 1.1, 1.2, 1.4**

### Property 2: Game Name Extraction

For any ROM file with a valid filename, extracting the game name should produce a non-empty string that excludes the file extension.

**Validates: Requirements 1.3**

### Property 3: ROM-Emulator Matching Completeness

For any ROM file with a supported extension and a set of installed emulators, if a compatible emulator exists in the set, the ROM Scanner should successfully match the ROM to an emulator.

**Validates: Requirements 3.1**

### Property 4: Emulator Priority Ordering

For any ROM type supported by multiple emulators, when Steam ROM Manager parsers define a priority order, the selected emulator should be the highest-priority compatible emulator from the installed set.

**Validates: Requirements 3.2, 7.4**

### Property 5: Unmatchable ROM Flagging

For any ROM file with an extension not supported by any installed emulator, the ROM Scanner should flag the ROM as unmatchable.

**Validates: Requirements 2.5, 3.5**

### Property 6: Metadata Structure Completeness

For any successfully fetched game metadata, the metadata object should contain at minimum a title field, with optional fields for description, release date, publisher, genre, and cover art URL.

**Validates: Requirements 4.2**

### Property 7: Metadata Caching Prevents Redundant Requests

For any ROM file, fetching metadata twice should result in only one external API request, with the second fetch returning cached data.

**Validates: Requirements 4.4**

### Property 8: Metadata Fetch Fallback

For any ROM file where metadata fetching fails, the system should use the ROM filename as the game title and proceed without cover art.

**Validates: Requirements 4.5**

### Property 9: App Bundle Generation Completeness

For any ROM file with an associated emulator, the App Wrapper Generator should create a valid .app bundle containing a launch script, Info.plist, and proper directory structure.

**Validates: Requirements 5.1, 5.2**

### Property 10: App Bundle Metadata Completeness

For any generated app bundle, the Info.plist should contain bundle identifier, version, and display name fields, and when cover art is available, the bundle should include an icon file.

**Validates: Requirements 5.3, 5.4, 5.5**

### Property 11: App Bundle Executable Permissions

For any generated app bundle, the launch script should have executable permissions set (chmod +x).

**Validates: Requirements 5.6**

### Property 12: Output Directory Consistency

For any set of generated app bundles, all bundles should be located in the user-specified output directory.

**Validates: Requirements 5.7**

### Property 13: Launch Script Parameter Inclusion

For any generated app bundle, the launch script should contain the emulator path, ROM path, and any emulator-specific launch parameters defined in Steam ROM Manager parsers.

**Validates: Requirements 6.1, 6.3, 6.4, 7.5**

### Property 14: Special Character Path Handling

For any ROM file path containing spaces, quotes, or special shell characters, the generated launch script should properly escape or quote the path to prevent shell injection or parsing errors.

**Validates: Requirements 6.5**

### Property 15: Parser Extension Mapping

For any system type defined in Steam ROM Manager parsers, the ROM Scanner should use the parser-defined file extensions (from parserInputs.glob) when identifying ROM files for that system.

**Validates: Requirements 7.3**

### Property 16: Error Recovery During Scanning

For any directory containing both readable and unreadable ROM files, the ROM Scanner should successfully scan all readable files and continue operation despite errors on unreadable files.

**Validates: Requirements 9.1**

### Property 17: Metadata Fetch Error Recovery

For any batch of ROM files where some metadata fetches fail, the system should successfully process all ROMs, using fallback naming for failed fetches.

**Validates: Requirements 9.2**

### Property 18: App Wrapper Generation Error Recovery

For any batch of ROM files where some app wrapper generations fail, the system should successfully generate wrappers for all other ROMs and log errors for failures.

**Validates: Requirements 9.3**

### Property 19: Configuration Round-Trip Preservation

For any valid AppConfiguration object, serializing to JSON, then deserializing, should produce an equivalent configuration object with all fields preserved.

**Validates: Requirements 10.1, 10.2, 10.3, 10.4**

### Property 20: Incremental Scan Change Detection

For any two directory scans of the same directories at different times, the incremental scan should correctly identify all new, modified, and removed ROM files based on file paths, sizes, and modification timestamps.

**Validates: Requirements 11.1, 11.2, 11.3, 11.4**

### Property 21: Incremental Wrapper Generation

For any incremental rescan result, app wrappers should be generated only for new and modified ROM files, not for unchanged ROM files.

**Validates: Requirements 11.5, 11.7**

### Property 22: Orphaned Wrapper Cleanup

For any ROM file removed between scans, when the user preference for cleanup is enabled, the corresponding app wrapper should be removed from the output directory.

**Validates: Requirements 11.6**

### Property 23: App Wrapper Update Preservation

For any existing app wrapper being updated with new emulator or launch parameters, the wrapper's icon and Info.plist metadata (excluding launch-related fields) should remain unchanged.

**Validates: Requirements 12.5, 12.6**

### Property 24: Emulator Compatibility Validation

For any app wrapper edit that changes the associated emulator, the new emulator should support the ROM file's extension according to Steam ROM Manager parsers.

**Validates: Requirements 12.7**

### Property 25: Multi-Disk Game Detection and Grouping

For any set of ROM files with filenames matching multi-disk patterns (e.g., "(Disc 1)", "(Disc 2)", "(CD1)", "(CD2)"), the ROM Scanner should group files with the same base name into a single multi-disk game entry.

**Validates: Requirements 13.1, 13.2**

### Property 26: Multi-Disk Single Wrapper Generation

For any multi-disk game, the App Wrapper Generator should create exactly one app bundle that launches the first disc.

**Validates: Requirements 13.3**

### Property 27: Multi-Disk Metadata Inclusion

For any multi-disk game app bundle, the bundle's metadata should include the file paths of all disc files belonging to the game.

**Validates: Requirements 13.4**

### Property 28: Multi-Disk Playlist Generation

For any multi-disk game where the associated emulator supports .m3u playlist format, the App Wrapper Generator should create a .m3u playlist file containing all disc paths.

**Validates: Requirements 13.5**

### Property 29: Multi-Disk Metadata Fetch Efficiency

For any multi-disk game with N discs, the Metadata Fetcher should make exactly one metadata request (not N requests).

**Validates: Requirements 13.6**

## Error Handling

The system employs a fail-gracefully strategy where individual failures do not halt the entire pipeline:

### ROM Scanning Errors

- **Unreadable files**: Log error with file path and reason, continue scanning remaining files
- **Permission denied**: Log error, skip directory, continue with accessible directories
- **Invalid symlinks**: Log warning, skip file, continue scanning

### Emulator Detection Errors

- **Missing /Applications directory**: Use empty emulator list, warn user
- **Corrupted app bundles**: Skip invalid bundle, continue detection
- **Missing Steam ROM Manager parsers**: Use built-in fallback parsers, log warning

### Metadata Fetching Errors

- **API unavailable**: Use filename-based naming, skip cover art, log error
- **Rate limit exceeded**: Implement exponential backoff, retry up to 3 times
- **Network timeout**: Use cached data if available, otherwise use filename
- **Invalid response**: Log error, use filename-based naming

### App Wrapper Generation Errors

- **Output directory not writable**: Fail entire generation, prompt user for new directory
- **Insufficient disk space**: Fail generation, display error with space requirements
- **Icon conversion failure**: Generate wrapper without icon, log warning
- **Launch script creation failure**: Skip ROM, log error with details

### Configuration Errors

- **Corrupted config file**: Use default configuration, notify user, backup corrupted file
- **Invalid JSON**: Parse error logged, use defaults, offer to reset configuration
- **Missing config file**: Create new config with defaults, no error

### Error Logging

All errors are logged to:
- In-memory log buffer (displayed in UI)
- Persistent log file: ~/Library/Logs/ROMShortcutMaker/app.log
- Console output (when running from terminal)

Error log format:
```
[TIMESTAMP] [LEVEL] [COMPONENT] Message
[2024-01-15 14:32:10] [ERROR] [ROMScanner] Failed to read file: /path/to/rom.nes (Permission denied)
```

## Testing Strategy

The ROM Shortcut Maker will employ a dual testing approach combining unit tests for specific examples and edge cases with property-based tests for universal correctness guarantees.

### Property-Based Testing

Property-based testing will be implemented using the **SwiftCheck** library for Swift, which provides QuickCheck-style property testing with automatic test case generation.

**Configuration:**
- Minimum 100 iterations per property test
- Each test tagged with format: `Feature: rom-launcher-wrapper, Property N: [property description]`
- Custom generators for ROM files, directory structures, and configuration objects

**Property Test Coverage:**

Each correctness property defined in this document will be implemented as a property-based test:

1. **Property 1 (Recursive ROM Discovery)**: Generate random directory trees with ROM files at various depths, verify all are discovered
2. **Property 2 (Game Name Extraction)**: Generate random ROM filenames with various formats, verify non-empty extraction
3. **Property 3 (ROM-Emulator Matching)**: Generate ROM files and emulator sets, verify matching when compatible emulators exist
4. **Property 4 (Emulator Priority)**: Generate scenarios with multiple compatible emulators, verify priority ordering
5. **Property 5 (Unmatchable Flagging)**: Generate ROMs with unsupported extensions, verify flagging
6. **Property 6 (Metadata Structure)**: Generate metadata responses, verify required fields present
7. **Property 7 (Metadata Caching)**: Generate ROM files, verify single API call on repeated fetches
8. **Property 8 (Metadata Fallback)**: Generate fetch failures, verify filename fallback
9. **Property 9 (App Bundle Generation)**: Generate ROM-emulator pairs, verify valid bundle structure
10. **Property 10 (Bundle Metadata)**: Generate app bundles, verify Info.plist completeness
11. **Property 11 (Executable Permissions)**: Generate app bundles, verify launch script permissions
12. **Property 12 (Output Directory)**: Generate multiple bundles, verify all in output directory
13. **Property 13 (Launch Script Parameters)**: Generate bundles, verify script contains required parameters
14. **Property 14 (Special Character Handling)**: Generate ROM paths with special characters, verify proper escaping
15. **Property 15 (Template Extension Mapping)**: Generate system types, verify extension mapping from templates
16. **Property 16 (Scan Error Recovery)**: Generate directories with unreadable files, verify continued scanning
17. **Property 17 (Metadata Error Recovery)**: Generate batch with some fetch failures, verify all processed
18. **Property 18 (Wrapper Error Recovery)**: Generate batch with some generation failures, verify others succeed
19. **Property 19 (Configuration Round-Trip)**: Generate random configurations, verify serialization round-trip
20. **Property 20 (Change Detection)**: Generate two scan states, verify correct change identification
21. **Property 21 (Incremental Generation)**: Generate scan deltas, verify wrappers only for changed ROMs
22. **Property 22 (Orphaned Cleanup)**: Generate removed ROMs, verify wrapper cleanup when enabled
23. **Property 23 (Update Preservation)**: Generate wrapper updates, verify icon/metadata preservation
24. **Property 24 (Compatibility Validation)**: Generate emulator changes, verify compatibility checking
25. **Property 25 (Multi-Disk Grouping)**: Generate multi-disk filenames, verify correct grouping
26. **Property 26 (Single Wrapper)**: Generate multi-disk games, verify single wrapper creation
27. **Property 27 (Multi-Disk Metadata)**: Generate multi-disk bundles, verify all disc paths included
28. **Property 28 (Playlist Generation)**: Generate multi-disk games with playlist-supporting emulators, verify .m3u creation
29. **Property 29 (Fetch Efficiency)**: Generate multi-disk games, verify single metadata fetch

### Unit Testing

Unit tests will focus on specific examples, edge cases, and integration points:

**ROM Scanner Unit Tests:**
- Specific file extension recognition (.nes, .iso, .chd, etc.)
- Game name extraction with region tags: "Super Mario Bros (USA).nes"
- Game name extraction with disc indicators: "Final Fantasy VII (Disc 1).bin"
- Empty directory handling
- Symlink following behavior

**Emulator Detector Unit Tests:**
- Detection of specific emulators (RetroArch, Dolphin, PPSSPP)
- Steam ROM Manager parser parsing for specific systems (NES, PS1, N64)
- Priority ordering with example parser data
- Missing /Applications directory handling

**Metadata Fetcher Unit Tests:**
- Successful fetch with mock API response
- API rate limit handling (429 response)
- Network timeout handling
- Cache hit vs cache miss behavior
- Cover art download and conversion

**App Wrapper Generator Unit Tests:**
- Bundle structure creation for specific ROM
- Info.plist generation with specific metadata
- Icon conversion from PNG to ICNS
- Launch script generation for RetroArch with specific core
- Launch script generation for standalone emulator (Dolphin)
- .m3u playlist generation for multi-disk PS1 game

**Configuration Manager Unit Tests:**
- JSON serialization of example configuration
- JSON deserialization of example configuration
- Corrupted JSON handling
- Missing configuration file handling
- Default configuration values

**Integration Tests:**
- End-to-end: scan directory → detect emulators → fetch metadata → generate wrappers
- Incremental rescan: initial scan → add ROM → rescan → verify only new wrapper created
- Multi-disk workflow: scan multi-disk game → verify single wrapper with playlist
- Edit workflow: generate wrapper → edit emulator → verify updated launch script

### Test Data

Test fixtures will include:
- Sample ROM files (zero-byte placeholder files with correct extensions)
- Mock emulator app bundles (minimal .app structure)
- Steam ROM Manager parser JSON files for common systems
- Mock API responses for metadata fetching
- Sample configuration JSON files

### Continuous Integration

Tests will run on:
- macOS 12+ (Monterey and later)
- Swift 5.9+
- Xcode 15+

CI pipeline will:
1. Run all unit tests
2. Run all property-based tests (100 iterations each)
3. Generate code coverage report (target: >80%)
4. Run static analysis (SwiftLint)
5. Build release binary

### Manual Testing Checklist

Before each release:
- [ ] Test with real ROM collection (100+ files)
- [ ] Test with RetroArch and multiple standalone emulators
- [ ] Verify generated app bundles launch correctly
- [ ] Test Spotlight search for generated apps
- [ ] Test Launchpad integration
- [ ] Verify icons display correctly in Finder
- [ ] Test incremental rescan with added/removed ROMs
- [ ] Test multi-disk PS1 game with .m3u playlist
- [ ] Test configuration persistence across app restarts
- [ ] Test error handling with unreadable files
- [ ] Test with ROM paths containing spaces and special characters

