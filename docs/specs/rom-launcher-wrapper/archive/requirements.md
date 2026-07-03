# Requirements Document

## Introduction

The ROM Shortcut Maker is a native macOS application that scans directories for ROM and disc game files, associates them with installed emulators, downloads metadata and cover art, and creates native macOS app wrappers that launch games directly without requiring Steam as a middleman. The system uses Steam ROM Manager parsers for emulator configuration and system associations.

## Glossary

- **ROM_Scanner**: The component that discovers ROM files and disc game files in specified directories
- **Emulator_Detector**: The component that identifies installed emulators in the Applications folder
- **Metadata_Fetcher**: The component that retrieves game information and cover art from online databases
- **App_Wrapper_Generator**: The component that creates native macOS application bundles for launching games
- **ROM_File**: A game file in formats such as .nes, .snes, .gba, .nds, .iso, .cue, .bin, .chd, etc.
- **App_Wrapper**: A native macOS .app bundle that launches a specific ROM with its associated emulator
- **Steam_ROM_Manager_Parser**: A JSON configuration file from Steam ROM Manager that defines file extensions (parserInputs.glob), emulator paths (executable.path), launch arguments (executableArgs), and system categories (steamCategories)
- **Game_Metadata**: Information about a game including title, description, release date, publisher, and cover art

## Requirements

### Requirement 1: Scan Directories for ROM Files

**User Story:** As a retro gaming enthusiast, I want the application to automatically discover all my ROM files across multiple folders, so that I don't have to manually register each game.

#### Acceptance Criteria

1. THE ROM_Scanner SHALL scan user-specified directories recursively for ROM files
2. THE ROM_Scanner SHALL detect ROM files with extensions including .nes, .snes, .smc, .gba, .gbc, .gb, .nds, .n64, .z64, .v64, .iso, .cue, .bin, .chd, .rvz, .wbfs, .gcm, .gcz, .ciso, .wad, .dol, .elf, .xci, .nsp, .md, .smd, .gen, .32x, .sms, .gg, .sg
3. WHEN a ROM file is discovered, THE ROM_Scanner SHALL extract the game name from the filename
4. THE ROM_Scanner SHALL maintain a list of discovered ROM files with their full file paths
5. WHEN the scan completes, THE ROM_Scanner SHALL report the total number of ROM files discovered

### Requirement 2: Detect Installed Emulators

**User Story:** As a user, I want the application to automatically find emulators installed on my Mac, so that I don't have to manually configure emulator paths.

#### Acceptance Criteria

1. THE Emulator_Detector SHALL scan the /Applications directory for installed emulators
2. THE Emulator_Detector SHALL identify emulators including RetroArch, Dolphin, PCSX2, PPSSPP, Citra, Ryujinx, Yuzu, mGBA, DeSmuME, OpenEmu, and other common emulators
3. WHEN an emulator is detected, THE Emulator_Detector SHALL store its application bundle path
4. THE Emulator_Detector SHALL associate each detected emulator with the ROM file extensions it supports based on Steam ROM Manager parsers
5. IF no compatible emulator is found for a ROM file type, THEN THE Emulator_Detector SHALL flag that ROM as unmatchable

### Requirement 3: Associate ROMs with Emulators

**User Story:** As a user, I want each ROM to be automatically paired with the correct emulator, so that games launch with the appropriate software.

#### Acceptance Criteria

1. THE ROM_Scanner SHALL match each ROM file to a compatible emulator based on file extension and Steam ROM Manager parsers
2. WHERE multiple emulators support the same ROM type, THE ROM_Scanner SHALL use the Steam ROM Manager parser priority order
3. WHERE multiple emulators support the same ROM type and no template priority exists, THE ROM_Scanner SHALL allow the user to select the preferred emulator
4. THE ROM_Scanner SHALL store the ROM-to-emulator association for each discovered game
5. WHEN a ROM cannot be matched to any installed emulator, THE ROM_Scanner SHALL mark it as requiring manual configuration

### Requirement 4: Download Game Metadata

**User Story:** As a user, I want the application to automatically fetch game information and cover art, so that my game library looks professional and organized.

#### Acceptance Criteria

1. WHEN a ROM file is discovered, THE Metadata_Fetcher SHALL query online game databases for matching metadata
2. THE Metadata_Fetcher SHALL retrieve game title, description, release date, publisher, genre, and cover art URL
3. THE Metadata_Fetcher SHALL download cover art images in high resolution when available
4. THE Metadata_Fetcher SHALL cache downloaded metadata and cover art locally to avoid redundant requests
5. IF metadata cannot be found for a ROM, THEN THE Metadata_Fetcher SHALL use the filename as the game title and skip cover art
6. THE Metadata_Fetcher SHALL respect rate limits of metadata provider APIs

### Requirement 5: Create Native macOS App Wrappers

**User Story:** As a macOS user, I want native .app bundles for each game, so that I can launch games from Finder, Spotlight, or the Dock like any other Mac application.

#### Acceptance Criteria

1. THE App_Wrapper_Generator SHALL create a macOS .app bundle for each ROM file
2. THE App_Wrapper_Generator SHALL include a launch script that opens the ROM with its associated emulator
3. THE App_Wrapper_Generator SHALL set the app bundle name to the game's metadata title
4. WHEN cover art is available, THE App_Wrapper_Generator SHALL use it as the app icon
5. THE App_Wrapper_Generator SHALL include proper Info.plist metadata including bundle identifier, version, and display name
6. THE App_Wrapper_Generator SHALL make the app wrapper executable with appropriate permissions
7. THE App_Wrapper_Generator SHALL store all generated app wrappers in a user-specified output directory

### Requirement 6: Handle Launch Parameters

**User Story:** As a user, I want games to launch with the correct emulator settings and parameters, so that they run properly without manual configuration.

#### Acceptance Criteria

1. THE App_Wrapper_Generator SHALL include emulator-specific launch parameters in the wrapper script based on Steam ROM Manager parsers
2. WHEN launching a RetroArch game, THE App_Wrapper_Generator SHALL specify the correct core for the ROM type
3. THE App_Wrapper_Generator SHALL pass the full ROM file path as a command-line argument to the emulator
4. WHERE an emulator requires specific flags or options, THE App_Wrapper_Generator SHALL include them in the launch command
5. THE App_Wrapper_Generator SHALL handle ROM paths containing spaces and special characters correctly

### Requirement 7: Support Steam ROM Manager Parser System

**User Story:** As a user familiar with Steam ROM Manager, I want the application to use the same parser configurations, so that my setup is consistent with the industry standard.

#### Acceptance Criteria

1. THE ROM_Scanner SHALL load Steam ROM Manager parser JSON files for system identification
2. THE ROM_Scanner SHALL support parser definitions for NES, SNES, N64, GameCube, Wii, Game Boy, GBA, DS, 3DS, Switch, Genesis, Saturn, Dreamcast, PS1, PS2, PSP, and other common systems
3. THE ROM_Scanner SHALL extract file extensions from the parserInputs.glob field in each parser
4. THE ROM_Scanner SHALL extract emulator executable paths from the executable.path field in each parser
5. WHERE Steam ROM Manager parsers specify launch arguments in executableArgs, THE App_Wrapper_Generator SHALL apply them

### Requirement 8: Provide User Interface for Configuration

**User Story:** As a user, I want a simple interface to configure scan directories and review discovered games, so that I can manage my ROM library easily.

#### Acceptance Criteria

1. THE Application SHALL provide a window for adding and removing ROM scan directories
2. THE Application SHALL display a list of discovered ROMs with their associated emulators and metadata status
3. THE Application SHALL allow users to manually override emulator associations for specific ROMs
4. THE Application SHALL provide a button to initiate the scanning and wrapper generation process
5. WHILE the scan is in progress, THE Application SHALL display progress information including current file and completion percentage
6. WHEN wrapper generation completes, THE Application SHALL display a summary of created app wrappers and any errors

### Requirement 9: Handle Errors Gracefully

**User Story:** As a user, I want clear error messages when something goes wrong, so that I can fix issues without frustration.

#### Acceptance Criteria

1. IF a ROM file cannot be read, THEN THE ROM_Scanner SHALL log the error and continue scanning other files
2. IF metadata fetching fails, THEN THE Metadata_Fetcher SHALL log the failure and proceed with filename-based naming
3. IF an app wrapper cannot be created, THEN THE App_Wrapper_Generator SHALL log the error with the ROM name and reason
4. IF an emulator path becomes invalid, THEN THE Application SHALL notify the user and request re-detection
5. THE Application SHALL display all errors and warnings in a dedicated log view accessible from the main interface

### Requirement 10: Parse and Print Configuration

**User Story:** As a user, I want my scan directories and emulator preferences saved between sessions, so that I don't have to reconfigure the application each time.

#### Acceptance Criteria

1. THE Application SHALL save user configuration including scan directories, output directory, and emulator overrides to a configuration file
2. WHEN the application launches, THE Application SHALL parse the configuration file and restore previous settings
3. THE Application SHALL format configuration data in JSON format
4. FOR ALL valid configuration objects, parsing then printing then parsing SHALL produce an equivalent configuration object (round-trip property)
5. IF the configuration file is corrupted, THEN THE Application SHALL use default settings and notify the user

### Requirement 11: Incremental Rescan for ROM Changes

**User Story:** As a user who frequently adds new ROMs to my collection, I want the application to efficiently rescan directories for changes without recreating existing app bundles, so that rescanning is fast and doesn't duplicate my library.

#### Acceptance Criteria

1. WHEN a rescan is initiated, THE ROM_Scanner SHALL compare discovered ROM files against previously scanned ROM files
2. THE ROM_Scanner SHALL identify new ROM files that were not present in the previous scan
3. THE ROM_Scanner SHALL identify ROM files that have been removed since the previous scan
4. THE ROM_Scanner SHALL identify ROM files that have been modified based on file size or modification timestamp
5. THE App_Wrapper_Generator SHALL create app wrappers only for new or modified ROM files
6. WHEN a ROM file is removed, THE Application SHALL optionally remove the corresponding app wrapper based on user preference
7. THE Application SHALL preserve existing app wrappers for unchanged ROM files

### Requirement 12: Edit Existing App Bundles

**User Story:** As a user, I want to edit already created app bundles to change settings like the associated emulator, so that I can fix mistakes or update configurations without recreating everything.

#### Acceptance Criteria

1. THE Application SHALL allow users to select an existing app wrapper for editing
2. THE Application SHALL display the current ROM file path, associated emulator, and launch parameters for the selected app wrapper
3. THE Application SHALL allow users to change the emulator associated with a specific ROM
4. THE Application SHALL allow users to modify launch parameters for a specific app wrapper
5. WHEN changes are saved, THE App_Wrapper_Generator SHALL update the app wrapper's launch script with the new configuration
6. THE Application SHALL preserve the app wrapper's icon and metadata when updating the launch script
7. THE Application SHALL validate that the new emulator is compatible with the ROM file type before applying changes

### Requirement 13: Support Multi-Disk Games

**User Story:** As a user with multi-disk games like PS1 titles, I want the application to recognize and handle games that span multiple disc files, so that I can launch them properly without creating separate entries for each disc.

#### Acceptance Criteria

1. THE ROM_Scanner SHALL detect multi-disk games by identifying files with common naming patterns such as "(Disc 1)", "(Disc 2)", "(CD1)", "(CD2)", or similar suffixes
2. WHEN multi-disk games are detected, THE ROM_Scanner SHALL group disc files belonging to the same game into a single game entry
3. THE App_Wrapper_Generator SHALL create a single app wrapper for multi-disk games that launches the first disc
4. THE App_Wrapper_Generator SHALL include metadata in the app wrapper indicating the locations of all disc files for the game
5. WHERE an emulator supports multi-disk game formats like .m3u playlists, THE App_Wrapper_Generator SHALL generate the appropriate playlist file
6. THE Metadata_Fetcher SHALL fetch metadata once per multi-disk game rather than once per disc file
7. THE Application SHALL display multi-disk games as a single entry in the ROM list with an indication of the number of discs

## Notes

- The application should prioritize simplicity and automation over advanced features
- Cover art sources may include ScreenScraper, TheGamesDB, or similar public APIs
- The app wrapper approach allows games to appear in Spotlight search and Launchpad
- Future enhancements could include playlist support, favorites, and custom categories
