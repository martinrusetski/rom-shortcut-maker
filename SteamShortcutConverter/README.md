# Steam Shortcut to App Bundle Converter

A native macOS application that converts Steam shortcuts (created by Steam ROM Manager) into native macOS .app bundles, allowing you to launch your ROM games directly from Finder, Spotlight, or the Dock.

## Overview

This tool reads Steam's `shortcuts.vdf` file and generates standalone macOS application bundles for each ROM game shortcut. The generated apps launch games with the exact same configuration as Steam, but without requiring Steam to be running.

## Requirements

- macOS 12.0 or later
- Xcode 14.0 or later (for building)
- Swift 5.0 or later

## Project Structure

```
SteamShortcutConverter/
├── SteamShortcutConverter/          # Main application target
│   ├── Models/                      # Core data models
│   │   └── DataModels.swift         # SteamShortcut, IconData, AppConfiguration, etc.
│   ├── Protocols/                   # Protocol definitions
│   │   └── Protocols.swift          # VDFParser, ShortcutFilter, AppBundleGenerator, etc.
│   ├── Assets.xcassets/             # App assets and icons
│   ├── ContentView.swift            # Main UI view
│   ├── SteamShortcutConverterApp.swift  # App entry point
│   └── Info.plist                   # App configuration
├── SteamShortcutConverterTests/     # Unit tests
│   ├── Fixtures/                    # Test fixtures directory
│   └── SteamShortcutConverterTests.swift
└── Package.swift                    # Swift Package Manager configuration
```

## Core Data Models

### SteamShortcut
Represents a single shortcut entry from Steam's shortcuts.vdf file with fields for app ID, name, executable path, launch options, icon data, and tags.

### IconData
Enum representing icon data, either embedded as binary data or as a file path reference.

### AppBundleConfig
Configuration for generating a single macOS app bundle, including bundle name, identifier, launch script, and icon data.

### AppConfiguration
Persistent application configuration storing VDF path, output directory, selected shortcuts, and preferences.

### ConversionState
Tracks the state of conversion operations for incremental updates.

### LaunchConfiguration
Extracted launch configuration from a Steam shortcut, including executable path, arguments, and working directory.

## Core Protocols

### VDFParser
Protocol for parsing Steam's binary VDF (Valve Data Format) files.

### ShortcutFilter
Protocol for filtering ROM-related shortcuts from all Steam shortcuts.

### AppBundleGenerator
Protocol for generating native macOS app bundles.

### ConfigurationManager
Protocol for managing application configuration persistence.

## Building

1. Open `SteamShortcutConverter.xcodeproj` in Xcode
2. Select the SteamShortcutConverter scheme
3. Build and run (⌘R)

## Testing

Run tests using:
```bash
xcodebuild test -project SteamShortcutConverter.xcodeproj -scheme SteamShortcutConverter -destination 'platform=macOS'
```

Or use Xcode's Test Navigator (⌘6) and click the test button.

## Property-Based Testing (Optional)

The project includes optional support for property-based testing using SwiftCheck. To enable:

1. Uncomment the SwiftCheck dependency in `Package.swift`
2. Add SwiftCheck to your test target dependencies
3. Run `swift package resolve` to fetch the dependency

## Development Status

This is the foundational setup for the Steam Shortcut to App Bundle Converter. The project structure, core data models, and protocols are now in place. Implementation of the actual components (VDF parser, app bundle generator, etc.) will follow in subsequent tasks.

## License

[Add your license here]

## Contributing

[Add contribution guidelines here]
