# Design Document: Steam Shortcut to App Bundle Converter

## Overview

The Steam Shortcut to App Bundle Converter is a native macOS application that reads Steam's shortcuts.vdf file (populated by Steam ROM Manager) and generates native macOS .app bundles for each ROM game shortcut. This provides an alternative launch method that doesn't require Steam to be running.

The design philosophy is simplicity: leverage Steam ROM Manager's existing functionality for ROM management, and focus solely on converting Steam shortcuts into standalone macOS applications.

### Key Design Goals

- Read-only operation: never modify Steam's shortcuts.vdf
- High fidelity: preserve exact launch commands from Steam
- Minimal user configuration: auto-detect shortcuts.vdf location
- Incremental updates: efficiently handle changes to Steam shortcuts
- Native macOS integration: .app bundles work with Spotlight and Launchpad

## Architecture

The system follows a simple pipeline architecture:

```
[shortcuts.vdf] → [VDF Parser] → [Shortcut Filter] → [App Bundle Generator] → [.app Bundles]
```

### Component Overview

1. **VDF Parser**: Reads Steam's binary shortcuts.vdf format and extracts shortcut data
2. **Shortcut Filter**: Identifies ROM-related shortcuts and allows user selection
3. **App Bundle Generator**: Creates native macOS .app bundles with launch scripts
4. **Configuration Manager**: Persists user settings between sessions
5. **UI Controller**: Provides interface for shortcut selection and conversion

### Data Flow

1. User launches application
2. Application auto-detects shortcuts.vdf location (or user specifies manually)
3. VDF Parser reads shortcuts.vdf and extracts all shortcuts
4. Shortcut Filter identifies ROM-related shortcuts based on emulator detection
5. User selects which shortcuts to convert
6. App Bundle Generator creates .app bundles for selected shortcuts
7. Configuration Manager saves settings for next session

## Components and Interfaces

### VDF Parser

**Responsibilities:**
- Read Steam's binary shortcuts.vdf format
- Parse shortcut entries and extract metadata
- Handle both embedded icons and icon file paths
- Validate VDF file structure

**Interface:**
```swift
protocol VDFParser {
    func parseShortcutsFile(at path: URL) throws -> [SteamShortcut]
    func validateVDFFile(at path: URL) -> Bool
}

struct SteamShortcut {
    let appID: UInt32
    let appName: String
    let executable: String
    let startDir: String?
    let launchOptions: String
    let icon: IconData
    let tags: [String]
    let isHidden: Bool
    let allowDesktopConfig: Bool
    let allowOverlay: Bool
    let openVR: Bool
    let lastPlayTime: UInt32
}

enum IconData {
    case embedded(Data)
    case filePath(String)
    case none
}
```

**Implementation Notes:**
- Use Swift's Data API for binary parsing
- VDF format: alternating key-value pairs with type markers
- Shortcuts section starts with "shortcuts" key
- Each shortcut is a numbered dictionary (0, 1, 2, ...)
- Icon data may be embedded as base64 or referenced as file path
- Consider using existing Swift VDF library if available

### Shortcut Filter

**Responsibilities:**
- Identify ROM-related shortcuts by emulator detection
- Filter out non-ROM Steam shortcuts
- Provide user selection interface
- Remember user preferences

**Interface:**
```swift
protocol ShortcutFilter {
    func filterROMShortcuts(from shortcuts: [SteamShortcut]) -> [SteamShortcut]
    func isEmulatorExecutable(_ path: String) -> Bool
    func detectEmulatorName(from executable: String) -> String?
}

enum EmulatorType: String, CaseIterable {
    case retroarch = "RetroArch"
    case dolphin = "Dolphin"
    case pcsx2 = "PCSX2"
    case ppsspp = "PPSSPP"
    case citra = "Citra"
    case ryujinx = "Ryujinx"
    case mgba = "mGBA"
    case desmume = "DeSmuME"
    case openemu = "OpenEmu"
    case yuzu = "Yuzu"
    
    var executablePatterns: [String] {
        switch self {
        case .retroarch: return ["retroarch", "RetroArch"]
        case .dolphin: return ["dolphin", "Dolphin"]
        case .pcsx2: return ["pcsx2", "PCSX2"]
        case .ppsspp: return ["ppsspp", "PPSSPP"]
        case .citra: return ["citra", "Citra"]
        case .ryujinx: return ["ryujinx", "Ryujinx"]
        case .mgba: return ["mgba", "mGBA"]
        case .desmume: return ["desmume", "DeSmuME"]
        case .openemu: return ["openemu", "OpenEmu"]
        case .yuzu: return ["yuzu", "Yuzu"]
        }
    }
}
```

**Implementation Notes:**
- Check executable path for known emulator names
- Case-insensitive matching
- Support both .app bundle paths and direct executable paths
- Maintain whitelist of known emulators

### App Bundle Generator

**Responsibilities:**
- Create macOS .app bundle structure
- Generate launch scripts with exact Steam launch commands
- Convert icons to .icns format
- Create Info.plist with proper metadata

**Interface:**
```swift
protocol AppBundleGenerator {
    func generateAppBundle(
        for shortcut: SteamShortcut,
        outputDirectory: URL
    ) async throws -> URL
    
    func updateAppBundle(
        at path: URL,
        with shortcut: SteamShortcut
    ) throws
}

struct AppBundleConfig {
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
- Launch script: bash script that executes Steam's launch command
- Bundle identifier format: com.steamshortcutconverter.{sanitized-game-name}
- Icon conversion: use sips command or ImageIO framework
- Preserve exact launch command from Steam including all arguments

### Configuration Manager

**Responsibilities:**
- Persist user settings between sessions
- Load and validate configuration on startup
- Handle missing or corrupted configuration

**Interface:**
```swift
protocol ConfigurationManager {
    func loadConfiguration() throws -> AppConfiguration
    func saveConfiguration(_ config: AppConfiguration) throws
}

struct AppConfiguration: Codable {
    let shortcutsVDFPath: URL?
    let outputDirectory: URL
    let selectedShortcutIDs: Set<UInt32>
    let removeOrphanedBundles: Bool
    let lastConversionDate: Date?
}
```

**Implementation Notes:**
- Configuration file: ~/Library/Application Support/SteamShortcutConverter/config.json
- JSON format for human readability
- Validation on load: check paths exist

## Data Models

### Core Data Structures

```swift
// Conversion state for incremental updates
struct ConversionState: Codable {
    let timestamp: Date
    let sourceVDFPath: URL
    let convertedShortcuts: [ConvertedShortcut]
}

struct ConvertedShortcut: Codable {
    let appID: UInt32
    let appName: String
    let bundlePath: URL
    let launchCommandHash: String  // Hash of launch command to detect changes
    let iconHash: String?  // Hash of icon data to detect changes
}

// Launch configuration extracted from Steam shortcut
struct LaunchConfiguration {
    let executable: String
    let arguments: [String]
    let workingDirectory: String?
    let environment: [String: String]
}
```

### File System Structure

```
~/Library/Application Support/SteamShortcutConverter/
├── config.json                    # User configuration
└── conversion_state.json          # Previous conversion state

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
│       └── AppIcon.icns           # Game icon
```

### Launch Script Template

```bash
#!/bin/bash
# Generated by Steam Shortcut to App Bundle Converter
# Original Steam launch command preserved exactly

{exact_steam_launch_command}
```

## VDF File Format

Steam's shortcuts.vdf uses a binary format with the following structure:

```
File Header: "shortcuts" (null-terminated string)
  Shortcut 0:
    "0" (null-terminated string)
      "appid" → uint32
      "AppName" → string
      "Exe" → string
      "StartDir" → string
      "icon" → string or binary data
      "LaunchOptions" → string
      "tags" → dictionary
      ...
  Shortcut 1:
    "1" (null-terminated string)
      ...
```

Type markers:
- 0x00: Section start
- 0x01: String value
- 0x02: Int32 value
- 0x08: End of section

**Parsing Strategy:**
- Read file as binary data
- Parse type markers and extract values
- Build SteamShortcut objects from parsed data
- Handle variable-length strings and nested structures

## Correctness Properties

### Property 1: VDF Parsing Completeness

For any valid shortcuts.vdf file, the VDF Parser should extract all shortcut entries without data loss.

**Validates: Requirements 2.1, 2.2**

### Property 2: Launch Command Preservation

For any Steam shortcut, the generated app bundle's launch script should contain the exact launch command from the shortcut without modification.

**Validates: Requirements 4.1, 4.2, 7.1, 7.2**

### Property 3: Emulator Detection Accuracy

For any Steam shortcut with an executable path containing a known emulator name, the Shortcut Filter should correctly identify it as ROM-related.

**Validates: Requirements 3.1, 3.2**

### Property 4: App Bundle Structure Validity

For any generated app bundle, the bundle should contain all required components: Contents/MacOS/launch.sh (executable), Contents/Info.plist, and Contents/Resources/ directory.

**Validates: Requirements 6.1, 6.2, 6.4, 6.5**

### Property 5: Icon Conversion Success

For any Steam shortcut with icon data, the generated app bundle should include a valid .icns file, or use a default icon if conversion fails.

**Validates: Requirements 5.1, 5.2, 5.3, 5.4, 5.5**

### Property 6: Configuration Round-Trip Preservation

For any valid AppConfiguration object, serializing to JSON then deserializing should produce an equivalent configuration object.

**Validates: Requirements 11.1, 11.2, 11.3, 11.4, 11.5**

### Property 7: Incremental Update Detection

For any two conversion states, the system should correctly identify new, modified, and removed shortcuts based on app IDs and launch command hashes.

**Validates: Requirements 8.1, 8.2, 8.3, 8.4**

### Property 8: Path Special Character Handling

For any launch command containing paths with spaces or special characters, the generated launch script should properly preserve quoting and escaping.

**Validates: Requirements 7.3**

## Error Handling

### VDF Parsing Errors

- **File not found**: Display file picker for manual selection
- **Invalid VDF format**: Show error with file path and suggest re-running Steam ROM Manager
- **Corrupted data**: Skip corrupted entries, log warnings, continue with valid entries

### App Bundle Generation Errors

- **Output directory not writable**: Prompt user for different location
- **Icon conversion failure**: Use default icon, log warning, continue
- **Missing emulator**: Warn user, create bundle anyway (will fail at launch)
- **Missing ROM**: Warn user, create bundle anyway (will fail at launch)

### Configuration Errors

- **Corrupted config**: Use defaults, notify user
- **Invalid paths**: Re-prompt for valid paths
- **Missing config**: Create new with defaults

## Testing Strategy

### Unit Tests

**VDF Parser Tests:**
- Parse sample shortcuts.vdf with known shortcuts
- Handle embedded icon data
- Handle icon file paths
- Parse RetroArch shortcuts with core arguments
- Handle corrupted VDF data gracefully

**Shortcut Filter Tests:**
- Detect RetroArch executables
- Detect Dolphin executables
- Detect other common emulators
- Ignore non-emulator Steam shortcuts
- Case-insensitive emulator name matching

**App Bundle Generator Tests:**
- Create valid .app bundle structure
- Generate executable launch script
- Convert PNG icon to .icns
- Create Info.plist with correct fields
- Handle game names with special characters

**Configuration Manager Tests:**
- Save and load configuration
- Handle missing configuration file
- Validate loaded configuration
- Round-trip serialization

### Integration Tests

- End-to-end: parse VDF → filter shortcuts → generate bundles
- Incremental update: initial conversion → modify VDF → detect changes
- Icon handling: embedded icon → extract → convert → bundle
- Launch script: complex command with arguments → preserve exactly

### Manual Testing

- [ ] Test with real shortcuts.vdf from Steam ROM Manager
- [ ] Verify generated app bundles launch games correctly
- [ ] Test Spotlight search for generated apps
- [ ] Test Launchpad integration
- [ ] Verify icons display correctly in Finder
- [ ] Test incremental updates after adding games in SRM
- [ ] Test with various emulators (RetroArch, Dolphin, PPSSPP)
- [ ] Test with game names containing special characters

## Implementation Notes

- Use Swift for native macOS development
- SwiftUI for user interface
- Consider using existing VDF parsing library if available
- App bundles are fully self-contained with absolute paths
- Read-only operation: never modify Steam files
- Minimal dependencies: leverage macOS built-in tools (sips for icon conversion)
