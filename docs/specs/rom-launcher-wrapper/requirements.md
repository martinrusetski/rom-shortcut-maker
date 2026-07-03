# Requirements Document: Steam Shortcut to App Bundle Converter

## Introduction

The Steam Shortcut to App Bundle Converter is a native macOS application that reads Steam's shortcuts.vdf file (populated by Steam ROM Manager) and generates native macOS .app bundles for each shortcut. This allows users to launch their ROM games directly from Finder, Spotlight, or the Dock without requiring Steam to be running.

The tool leverages Steam ROM Manager's existing functionality for ROM scanning, emulator detection, metadata fetching, and artwork management, focusing solely on converting Steam shortcuts into standalone macOS applications.

## Glossary

- **shortcuts.vdf**: Steam's binary VDF (Valve Data Format) file containing non-Steam game shortcuts
- **Steam ROM Manager (SRM)**: Third-party tool that scans ROMs and adds them as Steam shortcuts
- **VDF_Parser**: Component that reads and parses Steam's binary shortcuts.vdf format
- **App_Bundle_Generator**: Component that creates native macOS .app bundles
- **Steam_Shortcut**: Entry in shortcuts.vdf containing game title, launch command, icon, and metadata
- **App_Bundle**: Native macOS .app wrapper that launches a game via its emulator

## Requirements

### Requirement 1: Locate Steam Shortcuts File

**User Story:** As a user, I want the application to automatically find my Steam shortcuts file, so I don't have to manually locate it.

#### Acceptance Criteria

1. THE Application SHALL search for shortcuts.vdf in the standard Steam userdata directory: `~/Library/Application Support/Steam/userdata/*/config/shortcuts.vdf`
2. WHERE multiple Steam user accounts exist, THE Application SHALL detect all shortcuts.vdf files and allow the user to select which to process
3. THE Application SHALL allow users to manually specify a shortcuts.vdf file path if auto-detection fails
4. WHEN no shortcuts.vdf file is found, THE Application SHALL display a clear error message with instructions
5. THE Application SHALL validate that the located file is a valid VDF format before processing

### Requirement 2: Parse Steam Shortcuts VDF File

**User Story:** As a user, I want the application to read my Steam shortcuts, so it can create app bundles for my games.

#### Acceptance Criteria

1. THE VDF_Parser SHALL read Steam's binary shortcuts.vdf format
2. THE VDF_Parser SHALL extract for each shortcut: app ID, app name, executable path, launch options, icon path/data, and tags
3. THE VDF_Parser SHALL handle both embedded icon data and icon file paths
4. THE VDF_Parser SHALL skip Steam shortcuts that are not ROM-related (based on executable path patterns)
5. WHEN the VDF file is corrupted or unreadable, THE VDF_Parser SHALL report a clear error message

### Requirement 3: Filter ROM-Related Shortcuts

**User Story:** As a user, I want only my ROM game shortcuts converted to app bundles, not my other Steam shortcuts.

#### Acceptance Criteria

1. THE Application SHALL identify ROM-related shortcuts by detecting emulator executables in the launch command
2. THE Application SHALL recognize common emulator names: RetroArch, Dolphin, PCSX2, PPSSPP, Citra, Ryujinx, mGBA, DeSmuME, OpenEmu, Yuzu, and others
3. THE Application SHALL allow users to manually select which shortcuts to convert
4. THE Application SHALL display a preview list of detected ROM shortcuts before conversion
5. THE Application SHALL remember user filtering preferences between sessions

### Requirement 4: Extract Launch Configuration

**User Story:** As a user, I want app bundles to launch games with the exact same settings Steam ROM Manager configured, so games work identically.

#### Acceptance Criteria

1. THE VDF_Parser SHALL extract the complete launch command including emulator path, ROM path, and all arguments
2. THE VDF_Parser SHALL preserve argument order and quoting from the Steam shortcut
3. THE VDF_Parser SHALL extract working directory if specified in the shortcut
4. THE VDF_Parser SHALL handle both absolute and relative paths in launch commands
5. THE VDF_Parser SHALL detect and extract RetroArch core specifications from launch arguments

### Requirement 5: Handle Shortcut Icons

**User Story:** As a user, I want app bundles to use the same cover art that appears in Steam, so my library looks consistent.

#### Acceptance Criteria

1. THE VDF_Parser SHALL extract icon data from shortcuts.vdf when icons are embedded
2. THE VDF_Parser SHALL extract icon file paths when icons are stored as separate files
3. WHEN icon paths are relative, THE VDF_Parser SHALL resolve them relative to Steam's grid directory
4. THE App_Bundle_Generator SHALL convert extracted icons to .icns format for macOS
5. WHEN no icon is available, THE App_Bundle_Generator SHALL use a default ROM launcher icon

### Requirement 6: Generate Native macOS App Bundles

**User Story:** As a macOS user, I want native .app bundles for each game, so I can launch them from Finder, Spotlight, or the Dock.

#### Acceptance Criteria

1. THE App_Bundle_Generator SHALL create a macOS .app bundle for each selected Steam shortcut
2. THE App_Bundle_Generator SHALL include a launch script that executes the exact launch command from Steam
3. THE App_Bundle_Generator SHALL set the app bundle name to the game's title from Steam
4. THE App_Bundle_Generator SHALL include proper Info.plist metadata including bundle identifier, version, and display name
5. THE App_Bundle_Generator SHALL make the app wrapper executable with appropriate permissions
6. THE App_Bundle_Generator SHALL store all generated app wrappers in a user-specified output directory

### Requirement 7: Preserve Launch Command Fidelity

**User Story:** As a user, I want games to launch exactly as they do in Steam, so I don't have to troubleshoot launch issues.

#### Acceptance Criteria

1. THE App_Bundle_Generator SHALL use the exact launch command from the Steam shortcut without modification
2. THE App_Bundle_Generator SHALL preserve all command-line arguments in their original order
3. THE App_Bundle_Generator SHALL handle paths containing spaces and special characters correctly
4. THE App_Bundle_Generator SHALL set the working directory if specified in the Steam shortcut
5. THE App_Bundle_Generator SHALL use absolute paths for emulator and ROM files

### Requirement 8: Support Incremental Updates

**User Story:** As a user who frequently updates my Steam shortcuts via SRM, I want to easily refresh my app bundles without recreating everything.

#### Acceptance Criteria

1. THE Application SHALL detect which Steam shortcuts have changed since the last conversion
2. THE Application SHALL identify new shortcuts not yet converted to app bundles
3. THE Application SHALL identify removed shortcuts and optionally delete corresponding app bundles
4. THE Application SHALL identify modified shortcuts (changed launch command or icon) and update existing app bundles
5. THE Application SHALL preserve unchanged app bundles without regenerating them

### Requirement 9: Provide User Interface

**User Story:** As a user, I want a simple interface to select shortcuts and generate app bundles, so the process is straightforward.

#### Acceptance Criteria

1. THE Application SHALL display a list of detected Steam shortcuts with game names and emulators
2. THE Application SHALL allow users to select/deselect shortcuts for conversion via checkboxes
3. THE Application SHALL provide a directory picker for choosing the output location
4. THE Application SHALL display conversion progress with current game name and completion percentage
5. WHEN conversion completes, THE Application SHALL display a summary of created/updated app bundles

### Requirement 10: Handle Errors Gracefully

**User Story:** As a user, I want clear error messages when something goes wrong, so I can fix issues easily.

#### Acceptance Criteria

1. IF shortcuts.vdf cannot be found, THEN THE Application SHALL display instructions for locating it manually
2. IF a launch command references a missing emulator, THEN THE Application SHALL warn the user and skip that shortcut
3. IF a ROM file referenced in a shortcut is missing, THEN THE Application SHALL warn the user but still create the app bundle
4. IF icon conversion fails, THEN THE Application SHALL create the app bundle with a default icon
5. IF the output directory is not writable, THEN THE Application SHALL prompt the user to select a different location

### Requirement 11: Persist Configuration

**User Story:** As a user, I want my settings saved between sessions, so I don't have to reconfigure each time.

#### Acceptance Criteria

1. THE Application SHALL save the shortcuts.vdf file path between sessions
2. THE Application SHALL save the output directory path between sessions
3. THE Application SHALL save shortcut selection preferences between sessions
4. THE Application SHALL save the "remove orphaned bundles" preference
5. FOR ALL valid configuration objects, parsing then printing then parsing SHALL produce an equivalent configuration object (round-trip property)

## Notes

- This approach leverages Steam ROM Manager's existing functionality rather than duplicating it
- The tool is read-only with respect to Steam - it never modifies shortcuts.vdf
- App bundles are fully self-contained and work independently of Steam or this tool
- Users continue to use Steam ROM Manager for managing their ROM library
- This tool simply provides an alternative launch method via native macOS apps
