# Rom Shortcut Maker

A native macOS application that scans your ROM directories, identifies each game and its platform, fetches artwork from SteamGridDB, and generates standalone `.app` launcher bundles that point at your installed emulators. Launch your ROM games directly from Finder, Spotlight, or the Dock - no Steam required.

Importing an existing Steam ROM Manager `shortcuts.vdf` is still supported as a secondary input path.

## Installation

**Homebrew (recommended):**

```sh
brew tap martinrusetski/rom-shortcut-maker https://github.com/martinrusetski/rom-shortcut-maker
brew install --cask rom-shortcut-maker
```

The cask clears the quarantine attribute automatically, so the app launches without a Gatekeeper prompt, and updates install in place with `brew upgrade`.

**Direct download:** Grab the latest `RomShortcutMaker-vX.Y.Z.dmg` from [Releases](https://github.com/martinrusetski/rom-shortcut-maker/releases), drag the app to Applications, then - because the app is ad-hoc signed rather than notarized - run once:

```sh
xattr -cr "/Applications/Rom Shortcut Maker.app"
```

Either way, once installed the app updates itself in the background (via Sparkle) - you won't need to repeat these steps for future versions.

## Key Features

- **Direct ROM scanning**: Point it at a ROM directory and it walks the tree, identifying games and platforms. Single-ROM ZIP archives are identified from their contents without extraction; ambiguous, unreadable, or multi-ROM archives stay unresolved. Arcade ROM-set ZIPs keep their folder-based behavior.
- **DOS packages**: A `DOS`, `MS-DOS`, or `MSDOS` folder treats each immediate subfolder as one game, even when it contains many executables and data files. Startup programs, autoexec-enabled DOSBox configurations, archives, and disk images are inspected explicitly; ambiguous folders ask which file to start, setup utilities remain separate, and corrupt packages are blocked with a concrete explanation. Loose `.dosz` archives are also supported outside a DOS folder.
- **Searchable game library**: Review every game in one compact table, change its platform or emulator inline, and use status icons and filters to find included, changed, or unresolved games.
- **Emulator resolution**: Detects installed standalone emulators and RetroArch cores, and offers every runnable option per game. ZIP games are offered only to emulators with confirmed ZIP support. Set a default emulator per platform, or override per game.
- **Game properties editor**: Edit the display name, platform, emulator, launch file, and advanced command template in a focused inspector. Changes are saved automatically, including title edits as you type.
- **Artwork from SteamGridDB**: Browse and choose from multiple icon results, with grid artwork as a fallback for obscure titles. Downloaded artwork is cached on disk and reused across re-scans.
- **Live generation plan**: Every selected game is labelled **New**, **Update**, **Up to date**, or **Needs Attention** before generation. The footer reports the exact number of apps that will be created or updated.
- **Native app bundles**: Generates `.app` bundles with a single, correctly shell-escaped launch command - no double-escaping.
- **Incremental updates**: Only regenerates bundles when the title, ROM, emulator, arguments, output location, or artwork change. ROM hashes are cached by mtime/size so multi-GB ISOs aren't re-hashed every scan.
- **Steam VDF import**: Bridges a legacy `shortcuts.vdf` into the same pipeline.
- **Direct distribution**: Shells out to emulators, `sips`, and `iconutil`; not sandboxed and not shipped via the Mac App Store.

## Building & Testing

- **Build system:** SwiftPM is canonical. `Package.swift` builds the whole app (`@main` included) and links Sparkle. For a GUI dev loop, open `SteamShortcutConverter/Package.swift` directly in Xcode and press ⌘R - no `.xcodeproj` needed. (The legacy `SteamShortcutConverter.xcodeproj` is untracked and no longer required.)
- **Headless tests (canonical):** `cd SteamShortcutConverter && swift test`. Runs the logic suite without launching the GUI.
- **Release build:** `./make-dmg.sh v0.1.0` assembles `Rom Shortcut Maker.app` and a DMG locally - the same steps CI runs on a tag push.
- **Minimum OS:** macOS 26.

## Quick Start

1. Add one or more **Watched Folders** in Settings. They are scanned together into one library; you can also drag a folder onto the main window to add it to the watchlist.
2. To load an existing Steam ROM library, use **Settings > General > Steam Import** and choose its `shortcuts.vdf` file.
3. Review the library table. Use search and the **Included**, **Changed**, and **Needs Attention** filters to focus the list. Clear a row's checkbox to exclude it from generation.
4. Change a game's platform or emulator directly in the table. Double-click it or click **Edit…** for title, artwork, launch, and advanced properties. Changes update the generation plan immediately.
   For a DOS folder with multiple possible startup files, open Game Properties and choose **Starts with**. The selection is saved for that package; setup and configuration utilities can be run separately from the same section.
5. In Game Properties, click **Change Artwork…** to search SteamGridDB and choose a specific icon or grid. Add your SteamGridDB API key in **Rom Shortcut Maker > Settings** if needed.
6. Choose the **Output** folder. The footer shows exactly how many apps are new, updated, current, or need attention.
7. Click **Generate _N_ Changes**. When everything is current, the action changes to **Rebuild Selected** for an explicit forced rebuild.
8. Launch the generated apps from Finder, Spotlight, the Dock, or Launchpad.

## Emulator / System Database

The curated knowledge base of platforms, folder aliases, ROM extensions, standalone emulators, and RetroArch cores lives in `SteamShortcutConverter/SteamShortcutConverter/Resources/emulators.json`. It is data, not code - add platforms/emulators/cores by editing the JSON (the test suite validates that every referenced emulator maps to a real `EmulatorType`).

## Troubleshooting

- **App won't open** ("damaged"): `xattr -cr "/path/to/Rom Shortcut Maker.app"`
- **No emulator for a game**: install the emulator (or configure its path in Settings); the row shows "No emulator" until one is available.
- **Needs Attention status**: open Game Properties and assign a recognized platform and an installed emulator before generating.
- **No artwork results**: set a SteamGridDB API key in Settings, then adjust the artwork search title if the detected game name is too specific. Retro titles can use grid results when no icon is available.

## Development

Design and phased implementation plan: `DESIGN_PLAN.md`. Specs: `docs/specs/rom-launcher-wrapper/`.

- **Language**: Swift / SwiftUI
- **Minimum OS**: macOS 26
- **License**: TBD

### Releasing

Pushing a `vX.Y.Z` tag triggers `.github/workflows/release.yml`, which runs the tests, builds and ad-hoc-signs `Rom Shortcut Maker.app`, embeds Sparkle, produces a DMG, signs it with the Sparkle EdDSA key (`SPARKLE_PRIVATE_KEY` secret), prepends an entry to `appcast.xml`, updates `Casks/rom-shortcut-maker.rb`, commits both back to `main`, and creates the GitHub Release with the DMG attached.

```sh
git tag -a v0.1.0 -m "Release notes go in the tag body (they become the release notes)"
git push origin v0.1.0
```

Sparkle auto-updates and the Homebrew cask both read from the committed `appcast.xml` / cask, so a single tag push updates every distribution channel.
