# Rom Shortcut Maker

Rom Shortcut Maker is a native macOS app that turns your ROM library into individual Mac apps. It scans your game folders, matches each game with an installed emulator, finds artwork through SteamGridDB, and creates launchers you can open from Finder, Spotlight, Launchpad, or the Dock - without adding the games to Steam.

## Features

- **Direct ROM scanning** - add one or more folders and combine them into a single searchable library.
- **Automatic platform detection** - recognizes games from their folder structure, file extensions, disc formats, and supported ZIP contents.
- **Installed emulator discovery** - finds compatible standalone emulators and RetroArch cores, with per-platform defaults and per-game overrides.
- **Game properties** - change a title, platform, emulator, launch file, command template, or inclusion status before creating anything.
- **SteamGridDB artwork** - automatically match artwork or search and choose a specific icon or grid image.
- **Native Mac launchers** - creates a separate `.app` bundle for each included game.
- **Incremental updates** - shows which launchers are new, changed, current, or need attention and rebuilds only what changed.
- **Steam ROM Manager import** - optionally import an existing `shortcuts.vdf` library as a starting point.
- **Automatic updates** - new versions are delivered in the app through Sparkle.

## Requirements

- macOS 26 or later
- Apple Silicon Mac
- At least one supported emulator for the games you want to launch
- A free SteamGridDB API key if you want automatic artwork

Rom Shortcut Maker does not include emulators, games, console firmware, or BIOS files.

## Installation

### Homebrew (recommended)

```sh
brew tap martinrusetski/tap
brew trust martinrusetski/tap
brew install --cask martinrusetski/tap/rom-shortcut-maker
```

The `brew trust` step allows Homebrew to load the cask from this non-official tap. Homebrew installs the app in `/Applications` and clears its quarantine attribute automatically. Update it later with:

```sh
brew upgrade --cask martinrusetski/tap/rom-shortcut-maker
```

### DMG

Download the latest DMG from [Releases](https://github.com/martinrusetski/rom-shortcut-maker/releases), open it, and drag **Rom Shortcut Maker** to **Applications**.

The app is ad-hoc signed but not notarized, so macOS may block the first launch. Open Terminal and run:

```sh
xattr -cr "/Applications/Rom Shortcut Maker.app"
```

Then open the app normally. You can also use **System Settings > Privacy & Security > Open Anyway**.

## Usage

1. Open **Rom Shortcut Maker > Settings** and add the folders containing your ROMs under **Watched Folders**. You can also drag a folder onto the main window.
2. Open **Emulators** in Settings. The app detects installed standalone emulators and RetroArch cores; choose a default for each platform when more than one option is available.
3. Add your SteamGridDB API key under **Artwork** if you want artwork to be downloaded automatically.
4. Review the library. Search or filter the list, clear the checkbox beside any game you do not want, and change its platform or emulator when needed.
5. Double-click a game to edit its title, launch settings, or artwork. Games marked **Needs Attention** must be resolved before their launchers can be created.
6. Choose an **Output** folder and click **Create Shortcuts**.
7. Open the generated apps from your output folder like any other Mac app.

The app remembers your library settings and only recreates launchers whose ROM, emulator, arguments, output location, title, or artwork changed.

## Special Library Formats

- **DOS games** - place each game in its own subfolder inside a folder named `DOS`, `MS-DOS`, or `MSDOS`. Rom Shortcut Maker inspects the package and lets you choose the startup program when it cannot determine one safely.
- **PlayStation 4** - install the game in shadPS4, then add a `.ps4` text file containing its CUSA serial. The filename becomes the shortcut name.
- **PlayStation Vita** - install the game in Vita3K, then add a `.psvita` text file containing its title ID.
- **ScummVM** - add a `.scummvm` text file containing the full ScummVM game ID inside the game's data folder.
- **Multi-disc games** - supported playlist and disc-set formats are passed to compatible emulators using their required launch behavior.

Emulator compatibility varies by platform and game. Rom Shortcut Maker only offers emulator choices it can identify and launch with a supported command format.

## Troubleshooting

- **The app is reported as damaged** - clear quarantine with `xattr -cr "/Applications/Rom Shortcut Maker.app"`.
- **No emulator appears for a game** - install a compatible emulator, then click **Check Again** under **Settings > Emulators**. You can also configure a custom app location there.
- **A game needs attention** - open its properties and assign a recognized platform, compatible emulator, and launch file when required.
- **Artwork is missing** - add a SteamGridDB API key under **Settings > Artwork**, then open the game's properties and choose **Change Artwork...**.
- **A ZIP is unresolved** - archives containing no recognized ROM or more than one possible ROM are intentionally left unresolved. Extract or reorganize the archive before rescanning.

## License

[MIT](LICENSE)
