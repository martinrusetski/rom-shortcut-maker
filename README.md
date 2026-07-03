# Rom Shortcut Maker

A native macOS application that scans your ROM directories, identifies each game and its platform, fetches artwork from SteamGridDB, and generates standalone `.app` launcher bundles that point at your installed emulators. Launch your ROM games directly from Finder, Spotlight, or the Dock — no Steam required.

Importing an existing Steam ROM Manager `shortcuts.vdf` is still supported as a secondary input path.

## Key Features

- **Direct ROM scanning**: Point it at a ROM directory and it walks the tree, identifying games and platforms. Platform is inferred folder-first (e.g. `/ROMs/SNES/…`), falling back to file extension.
- **Emulator resolution**: Detects installed standalone emulators and RetroArch cores, and offers every runnable option per game. Set a default emulator per platform, or override per game.
- **Artwork from SteamGridDB**: Fetches icons (falling back to grids for obscure titles), cached on disk and reused across re-scans.
- **Native app bundles**: Generates `.app` bundles with a single, correctly shell-escaped launch command — no double-escaping.
- **Incremental updates**: Only regenerates bundles when the ROM, emulator, arguments, or artwork change. ROM hashes are cached by mtime/size so multi-GB ISOs aren't re-hashed every scan.
- **Steam VDF import**: Bridges a legacy `shortcuts.vdf` into the same pipeline.
- **Direct distribution**: Shells out to emulators, `sips`, and `iconutil`; not sandboxed and not shipped via the Mac App Store.

## Building & Testing

- **Headless tests (canonical):** `cd SteamShortcutConverter && swift test`. Builds the logic into a library and runs the suite without launching the GUI.
- **App build:** `xcodebuild -project SteamShortcutConverter.xcodeproj -scheme SteamShortcutConverter -configuration Debug build`, or open the project in Xcode and press ⌘R.
- **Do not** run `xcodebuild test` / ⌘U — the Xcode test target is hosted in the app target and traps on launch under the test runner. Use `swift test`.
- **Minimum OS:** macOS 13.

## Quick Start

1. **Scan** tab: choose a ROM directory and click **Scan** (or switch the source selector to import a Steam `shortcuts.vdf`).
2. Review the game list: fix any titles, resolve ambiguous platforms, and pick emulators (each row lists every installed option).
3. **Settings** tab: paste a SteamGridDB API key and set default emulators per platform.
4. **Artwork** tab: click **Fetch Missing** to download icons.
5. **Generate** tab: choose an output directory and click **Generate Bundles**.
6. **Play**: your games are now native macOS apps — launch them from Finder, Spotlight, or Launchpad.

## Emulator / System Database

The curated knowledge base of platforms, folder aliases, ROM extensions, standalone emulators, and RetroArch cores lives in `SteamShortcutConverter/SteamShortcutConverter/Resources/emulators.json`. It is data, not code — add platforms/emulators/cores by editing the JSON (the test suite validates that every referenced emulator maps to a real `EmulatorType`).

## Troubleshooting

- **App won't open** ("damaged"): `xattr -cr "/path/to/Rom Shortcut Maker.app"`
- **No emulator for a game**: install the emulator (or configure its path in Settings); the row shows "No emulator" until one is available.
- **No artwork**: set a SteamGridDB API key in Settings; retro titles fall back from icons to grids.

## Development

Design and phased implementation plan: `DESIGN_PLAN.md`. Specs: `docs/specs/rom-launcher-wrapper/`.

- **Language**: Swift / SwiftUI
- **Minimum OS**: macOS 13
- **License**: TBD
