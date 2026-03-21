# Steam Shortcut to App Bundle Converter

A native macOS application that converts Steam ROM Manager shortcuts into standalone .app bundles.

## Overview

This tool reads Steam's shortcuts.vdf file (populated by Steam ROM Manager) and generates native macOS .app bundles for your ROM games. Launch games directly from Finder, Spotlight, or the Dock without requiring Steam to be running.

## Why This Approach?

Instead of rebuilding Steam ROM Manager's functionality (ROM scanning, emulator detection, metadata fetching), this tool simply converts SRM's output into macOS app bundles. Let SRM do the heavy lifting, we just transform the result.

## Key Features

- **Leverages Steam ROM Manager**: Uses your existing SRM configuration
- **Native App Bundles**: Launch games from Finder, Spotlight, or Launchpad
- **High Fidelity**: Preserves exact launch commands from Steam
- **Auto-Detection**: Automatically finds your shortcuts.vdf file
- **Incremental Updates**: Efficiently handles changes to Steam shortcuts
- **Read-Only**: Never modifies Steam files

## Workflow

1. Configure and run Steam ROM Manager (as you normally would)
2. SRM populates Steam with your ROM shortcuts
3. Run this tool to convert shortcuts to .app bundles
4. Launch games from anywhere on macOS

## Development

This project follows a spec-driven development approach. See `.kiro/specs/rom-launcher-wrapper/` for:
- `requirements.md` - 11 detailed requirements
- `design.md` - Architecture and 8 correctness properties

For the original "full app" specs (archived), see `.kiro/specs/rom-launcher-wrapper/archive/`

## Technology Stack

- **Language**: Swift
- **Framework**: SwiftUI (macOS 12+)
- **VDF Parsing**: Binary format parser for Steam's shortcuts.vdf

## License

TBD
