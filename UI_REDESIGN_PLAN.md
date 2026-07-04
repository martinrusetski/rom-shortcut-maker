# UI Redesign Plan — Rom Shortcut Maker

Implementation-ready plan for rebuilding the UI as a simple, fast, native single-window macOS utility. Written to be executed phase-by-phase by an agent. Read the whole document before starting Phase 1.

## Goal

The app is a converter, not a library manager. One window tells the whole story top to bottom: **where the ROMs are → what was found → Generate**. Everything is automatic with sensible defaults; a game the user never touches must generate correctly. Granular per-game control exists but lives behind a double-click, in a Game Properties window (the Finder "Get Info" pattern) — it never clutters the main window. No sidebars, no inspectors, no tabs.

## Design principles

1. **One window, three zones**: source bar (top), game list (middle), generate bar (bottom). The window reads as a sentence: "take these ROMs, make these apps, put them here."
2. **Automatic first.** Choosing a folder scans it immediately (no separate Scan button ceremony). Defaults resolve platform, emulator, and cached artwork with zero interaction. The main window shows only what the user must notice: title, icon, and warnings.
3. **Granular but hidden.** All per-game editing (title, platform, emulator, arguments, launch file, artwork) lives in the Game Properties window, opened by double-click / ⌘I / context menu. Well organized there — not spread across the main list.
4. **App-level config is a Settings window** (`⌘,`), not a tab: API key, per-platform emulator defaults, cache.
5. **Fast means value-typed rows.** No `@ObservedObject viewModel` in row views, no synchronous disk I/O in `body`. See Performance section — hard requirements, not polish.

## Current state audit (what's wrong)

| File | Problem |
|---|---|
| `ContentView.swift` | `TabView` — an iOS pattern. Four tabs fragment one linear flow. Single generic error alert. |
| `Views/ScanView.swift` | Header text + source-mode segmented picker + path field permanently occupy the top; flat game list squeezed below. Separate "Scan" button where choosing the folder should just scan. |
| `Views/GameRow.swift` | Each row observes the entire `MainViewModel` (any published change re-renders every row). `NSImage(contentsOf:)` does synchronous disk I/O inside `body` on every render. Inline `TextField`, `Picker`, and three menus per row make rows heavy and noisy — exactly the clutter this redesign removes. |
| `Views/ArtworkView.swift` | Nearly empty tab: title list with per-row "Fetch" buttons. Delete the concept; artwork fetching is one button plus per-row status. |
| `Views/GenerateView.swift` | A whole tab for one directory field, one toggle, one button. Becomes the bottom bar. |
| `Views/SettingsView.swift` | Settings as a tab; per-platform defaults as an unbounded `ForEach` over 67+ platforms. Becomes a Settings scene with a filtered list. |
| Missing entirely | Per-game args editing (model already supports it: `GameEntry.argsTemplate`, `GameOverride.args` — no UI). Context menus. Collapsible platform grouping. Empty states. Menu bar integration. |

## Deployment target

Stays at **macOS 13**. Nothing in this plan needs newer APIs (`DisclosureGroup`/collapsible `Section`, sheets, `Settings` scene, `List` all work on 13). Where a nicety is 14+ (e.g. `ContentUnavailableView`), use it behind `if #available` with a trivial VStack fallback, or just build the VStack.

## Main window anatomy

```
┌──────────────────────────────────────────────────────────────────┐
│  ROM Folder: [ ~/ROMs                      ] [Choose…]  [Rescan]  │  source bar
│                                        or:  [Import from Steam…]  │
├──────────────────────────────────────────────────────────────────┤
│  ▾ SNES (34)                                                      │
│    ☑ 🖼  Chrono Trigger              Snes9x                    ✓  │
│    ☑ 🖼  Super Metroid               Snes9x                    ✓  │
│  ▾ PlayStation (22)                                               │
│    ☑ 🖼  Final Fantasy VII  3 discs  DuckStation               ✓  │
│    ☑ ⬜  Vagrant Story               ⚠ No emulator                │
│  ▸ Game Boy (41)                                                  │
├──────────────────────────────────────────────────────────────────┤
│  Output: [ ~/Applications/ROMs   ] [Choose…]     [Generate  ⏎]    │  generate bar
│  142 games · 3 need attention · last generated 2:41 PM            │  status line
└──────────────────────────────────────────────────────────────────┘
```

Window `minWidth: 640, minHeight: 480`. Uses the standard window toolbar area only for a unified title bar look; all controls are in-content bars so the layout stays dead simple.

### Source bar (top)

- Path field (read-only display, middle-truncated) + "Choose…" (`NSOpenPanel`). **Choosing a folder immediately scans it** — no separate Scan step. "Rescan" re-runs the last directory (`⌘R`).
- "Import from Steam…" button (secondary style) replaces the source-mode segmented picker: it opens the `.vdf` picker and imports. The last-used source is remembered (existing `sourceMode` persistence), but the UI never makes the user pick a mode first.
- During scan: thin determinate `ProgressView` directly under the bar; controls disabled via `isProcessing`.

### Game list (middle)

`List` grouped by platform with collapsible sections:

- One `Section` per platform present in the scan (never all DB platforms), ordered alphabetically; games sorted by title within. Section header: platform name + count + collapse chevron. Use `DisclosureGroup`-style collapsible sections; persist collapsed-platform IDs in `AppConfigurationV2` so the state survives relaunch.
- Games with `platform.id == "unknown"` group into a final "Unknown Platform" section that is always expanded and visually flagged.
- **Row = checkbox · icon · title · minimal details · status.** Fixed contents, no inline editors:
  - Include checkbox (existing `isSelected`).
  - 28 px artwork thumbnail (async-loaded, see Performance) or placeholder.
  - Title (plain `Text` — renaming happens in Properties).
  - Small secondary details, only when noteworthy: "3 discs" for m3u, "+N files", emulator name in secondary color.
  - Trailing status: ✓ ready (subtle) / ⚠ orange "No emulator" or "Unknown platform" / artwork spinner while fetching. A game needing attention is still visible at a glance without opening anything.
- **Double-click a row → Game Properties window.** Also via context menu and `⌘I`.
- Context menu (works on selection, multi-select allowed for these): Properties (`⌘I`, single game), Fetch Artwork, Include/Exclude, Reveal in Finder, Reset Overrides.
- Row status is a computed `GameStatus` on the entry: `.ready`, `.noEmulator`, `.unknownPlatform`. Artwork-missing does not block generation (bundle falls back to a default icon) and is not "attention" — it just shows as an empty artwork well.
- Empty state (no scan yet): centered icon + "Choose a ROM folder to get started" + prominent Choose button + smaller "Import from Steam…" link-style button. Replaces the current one-liner.

### Generate bar (bottom)

- Output directory (path display + Choose…) and the **Generate** button — the one `.borderedProminent` button in the window, `keyboardShortcut(.defaultAction)`. Disabled with a tooltip explaining why when `!canGenerate`.
- Status line beneath: "142 games · 3 need attention · last generated 2:41 PM". While generating, this line becomes the progress ("Generating Chrono Trigger… 34/142") with a determinate bar. No modal progress.
- Next to Generate, a live preview label computed from `incrementalManager.detectChanges` (debounced): "will create 3, update 2, skip 137". This is the trust signal that automation is doing the right thing, without a confirmation sheet.
- After generation, a compact **results sheet** only if there were errors or warnings (list of per-game messages + "Reveal in Finder"); on a clean run, just update the status line ("Created 3, updated 2 · 2:41 PM") and bounce the Dock icon if in background. Replaces the text-dump `summaryPanel`.
- "Remove orphaned bundles" toggle moves to Settings (it's a policy, not a per-run choice).

## Game Properties window (the power-user surface)

Opened per game via double-click / `⌘I` / context menu. A resizable utility **window** (not a sheet — the user may want to compare against the list), one at a time is fine (reuse the window, swap content when another game is opened). Title: the game's name.

Layout: header + grouped `Form` (`.formStyle(.grouped)` on 13+):

- **Header**: large artwork thumbnail (~96 px) + editable title field + platform · filename caption.
- **Artwork** section: artwork well with buttons "Fetch from SteamGridDB", "Choose File…" (png/jpg via `NSOpenPanel`), drag-and-drop image onto the well, "Remove". Status/error text for failed fetches.
- **Platform & Emulator** section:
  - Platform: `Picker` over `viewModel.allPlatforms`. Changing it re-resolves the default emulator (existing `setPlatform` behavior).
  - Emulator: `Picker` over `availableOptions(for:)`, with "(platform default)" suffix on the default option. Empty → warning + "Open Settings" button.
- **Launch** section (the granular part, clearly organized):
  - Arguments: monospaced `TextField` editing `argsTemplate`, persisted via a new `setArgsTemplate(_:for:)` → `GameOverride.args`. Beneath it, a caption listing supported template tokens — read the authoritative token list from `Generators/AppBundleGenerator.swift` and render it verbatim (do not invent tokens).
  - Launch file: for multi-image games, `Picker` over `romPath + alternateImages` (existing `setLaunchImage`); for multi-disc, read-only disc list with the `.m3u` note.
  - Full ROM path (selectable, middle-truncated) + "Reveal in Finder".
- **Override handling**: any field backed by a `GameOverride` shows a small filled dot next to its label; each such field gets a per-field "Reset" (↩︎) button, plus "Reset All Overrides" at the bottom. Requires new ViewModel helpers `hasOverride(_:for:)` and `resetOverrides(for:)`.
- All edits apply immediately (no OK/Cancel) — same live-mutation model the app already uses; the main list updates behind the window.

## Settings window (`Settings` scene, `⌘,`)

Three panes (standard settings `TabView` style):

- **General**: "Remove orphaned bundles" default; last scan/output directory display.
- **Emulators**: per-platform default emulator list — only platforms with ≥1 installed option shown by default, "Show all" toggle, search field. Replaces the unbounded 67-row ForEach.
- **Artwork**: SteamGridDB API key (`SecureField`, persist on change — delete the explicit Save button), "Get API Key" link, cache size + "Clear Cache".

The Settings tab and `saveSettings()` UI coupling die; persistence happens on change.

## Menu bar & keyboard

`.commands` block, deliberately short:

| Menu | Item | Shortcut |
|---|---|---|
| File | Choose ROM Folder… | ⌘O |
| File | Rescan | ⌘R |
| File | Import from Steam… | — |
| File | Generate Bundles | — (Generate button is `.defaultAction`) |
| File | Game Properties | ⌘I (enabled with selection) |

Delete/backspace on a selected row = Exclude from generate (non-destructive, unchecks the box).

## ViewModel / state changes

Keep `MainViewModel`, its DI, and existing tests intact; add rather than rewrite:

- `@Published var selection: Set<GameEntry.ID>`; `@Published var collapsedPlatforms: Set<String>` (persisted in `AppConfigurationV2`); `@Published var propertiesGameID: GameEntry.ID?` (drives the Properties window).
- `var groupedGames: [(platform: Platform, games: [GameEntry])]` — grouping + sorting for the list.
- `GameEntry.status: GameStatus` computed (`.ready` / `.noEmulator` / `.unknownPlatform`) + `var needsAttentionCount: Int`.
- New mutations: `setArgsTemplate(_:for:)` (writes `GameOverride.args`, mirroring `setTitle`), `setCustomArtwork(url:for:)`, `removeArtwork(for:)`, `hasOverride(_ field:for:)`, `resetOverride(_ field:for:)`, `resetOverrides(for:)`.
- Extract `previewChanges() -> GenerationPreview` (counts of new/updated/unchanged/removed) from `generate()` for the live preview label; `generate()` reuses it.
- Scan-on-choose: choosing a directory sets `scanDirectory` and immediately calls `scan()`.
- `swift test` coverage for: grouping/sorting, `GameStatus` derivation, args override set/reset round-trip, custom artwork override, `previewChanges` counts, collapsed-state persistence. UI stays untested (repo policy: headless `swift test`, never `xcodebuild test`).

## Performance requirements (hard)

1. **Rows must not observe the ViewModel.** Rows render from the `GameEntry` value plus small callbacks (toggle include, open properties). All other mutations flow through the Properties window → viewModel. Fixes the current all-rows-rerender-on-any-change bug.
2. **Async thumbnails.** Replace `NSImage(contentsOf:)` in `body` with a `ThumbnailLoader`: `NSCache<NSString, NSImage>` keyed by `stableKey`, decoded at target size (28 px list / 96 px properties, @2x) off the main thread via `CGImageSource` + `kCGImageSourceThumbnailMaxPixelSize`, placeholder while loading, key invalidated when artwork changes.
3. **No `Picker`/`Menu`/`TextField` in rows.** Rows are static content + one checkbox.
4. Validate with a 500-entry synthetic library (fixture or generator script) before calling Phase 1 done.

## Implementation phases

Each phase compiles, passes `swift test`, and is independently committable. Build with `xcodebuild -project SteamShortcutConverter.xcodeproj -scheme SteamShortcutConverter -configuration Debug build`; never `xcodebuild test`.

### Phase 1 — Single-window rework
Replace `TabView` with the three-zone window: source bar (choose-scans-immediately, Import from Steam button, progress), grouped collapsible game list with the new minimal rows (value-typed, async thumbnails — simple async version now, cache/downsample polish in Phase 4), generate bar with status line. Empty state. Delete `ScanView`, `ArtworkView`, `GenerateView` (fold logic in). ViewModel: `groupedGames`, `GameStatus`, `collapsedPlatforms`, selection, scan-on-choose.
**Accept when**: full scan→generate flow works in the new shell; sections collapse and persist; old tab files deleted; a game with no emulator is visibly flagged; tests green.

### Phase 2 — Game Properties window
The per-game window with header, Artwork, Platform & Emulator, and Launch sections; args editor with token help; override dots + per-field and reset-all; open via double-click / ⌘I / context menu. New ViewModel mutations with tests. Context menu on rows.
**Accept when**: every per-game property is editable via Properties; overrides persist across rescan (existing `stableKey` mechanism); args round-trip covered by tests.

### Phase 3 — Settings scene, menus, generate polish
`Settings` scene (3 panes), delete the settings tab. `.commands` menu items. Live "will create N, update M" preview label via `previewChanges()`. Errors-only results sheet. Move orphaned-bundles toggle to Settings.
**Accept when**: `⌘,` opens Settings; preview label matches what generate then does; clean runs finish with no modal.

### Phase 4 — Polish & speed
`ThumbnailLoader` cache + downsampling finalized; drag-and-drop a folder onto the window to scan it; drag-and-drop image onto Properties artwork well; 500-game scroll validation; accessibility pass (labels on glyph-only controls, focus order).
**Accept when**: smooth scrolling with 500 entries; VoiceOver can operate both windows.

## HIG references for the implementing agent

Consult before styling each region — do not improvise metrics:

- Layout: https://developer.apple.com/design/human-interface-guidelines/layout
- Lists and tables: https://developer.apple.com/design/human-interface-guidelines/lists-and-tables
- Panels / utility windows: https://developer.apple.com/design/human-interface-guidelines/panels
- Settings windows: https://developer.apple.com/design/human-interface-guidelines/settings
- Buttons (prominence — one prominent button per window): https://developer.apple.com/design/human-interface-guidelines/buttons
- Progress indicators: https://developer.apple.com/design/human-interface-guidelines/progress-indicators

## Out of scope (do not do while executing this plan)

- Game name fetching / hash-based identification (separate feature, separate plan).
- SteamGridDB client rework (multi-candidate artwork picker etc.).
- Any change to bundle generation, scanning, or the emulator database.
- Sidebars, inspectors, or any library-manager chrome — explicitly rejected.
- App icon / branding. Localization.
