# Steam Shortcut to App Bundle Converter

A native macOS application that converts Steam ROM Manager shortcuts into standalone .app bundles. Launch your ROM games directly from Finder, Spotlight, or the Dock without requiring Steam to be running.

## Key Features

- **Leverages Steam ROM Manager**: Uses your existing SRM configuration (shortcuts.vdf).
- **Native App Bundles**: Generates high-fidelity .app bundles that work like any other macOS application.
- **Custom Renaming**: Rename shortcuts within the app without modifying your Steam files. Custom names are preserved across updates.
- **Incremental Updates**: Only regenerates bundles when shortcuts or names change.
- **Auto-Detection**: Automatically finds your Steam `shortcuts.vdf` file.
- **Clean & Safe**: Read-only access to Steam files; never modifies your Steam configuration.

## Installation

### Quick Install
The easiest way to install is using the installation script:
```bash
chmod +x scripts/install.sh && ./scripts/install.sh
```

The app will be installed to `/Applications/SteamShortcutConverter.app`.

### Manual Build
1. Open `SteamShortcutConverter/SteamShortcutConverter.xcodeproj` in Xcode.
2. Select the **SteamShortcutConverter** scheme and **My Mac** destination.
3. Press **⌘+R** to build and run, or **Product > Archive** for a release build.

## Quick Start

1. **Launch**: Open `SteamShortcutConverter` from your Applications folder.
2. **Load Shortcuts**: Click **Auto-Detect** to find your `shortcuts.vdf` or **Browse...** to select it manually.
3. **Select Output**: Choose where you want your .app bundles to be saved (e.g., `~/Applications/ROM Games/`).
4. **Convert**: select the games you want and click **Convert**.
5. **Play**: Your games are now native macOS apps! Launch them from Finder, Spotlight, or Launchpad.

### Renaming Games
You can rename games to clean up messy ROM filenames:
1. Click the **ellipsis (•••)** on the right side of a shortcut row.
2. Select **Rename** and type the new name.
3. A pencil icon (✏️) will appear next to renamed games.
4. Custom names persist even if you regenerate your Steam shortcuts.

## Troubleshooting

- **App won't open**: If macOS says the app is "damaged", run:
  ```bash
  xattr -cr /Applications/SteamShortcutConverter.app
  ```
- **Shortcuts not found**: Manually browse to:
  `~/Library/Application Support/Steam/userdata/[USER_ID]/config/shortcuts.vdf`
- **Games won't launch**: Ensure the emulator path and ROM file location in Steam ROM Manager are correct.

## Development

This project follows a spec-driven development approach. Detailed requirements and design specs can be found in `.kiro/specs/rom-launcher-wrapper/`.

- **Language**: Swift / SwiftUI
- **Minimum OS**: macOS 12.0 (Monterey)
- **License**: TBD
