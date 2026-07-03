# UI Redesign Plan — Rom Shortcut Maker

Implementation-ready plan for rebuilding the UI as a native, fast, single-window macOS app. Written to be executed phase-by-phase by an agent. Read the whole document before starting Phase 1.

## Goal

Replace the current four-tab layout with the standard macOS "library app" anatomy: sidebar → table → inspector, one continuous flow (scan → review/fix → generate), automatic by default with granular per-game overrides available but never required. Model apps: Finder column layouts, Xcode's navigator/inspector split, Music/Photos library windows.

## Design principles (from the macOS HIG)

1. **One window, one flow.** The pipeline (scan → review → generate) is linear; splitting it across tabs hides state and forces navigation. All primary actions live in the toolbar of a single `NavigationSplitView` window.
2. **Automatic first, editable second.** Scanning must produce a fully resolved library with zero interaction (defaults from `emulators.json` + per-platform defaults + cached artwork). Editing is opt-in via the inspector; a game the user never touched must still generate correctly.
3. **Selection drives detail.** Granular per-game editing happens in a trailing inspector bound to the table selection — never inline widgets crammed into rows.
4. **Settings is a Settings window** (`⌘,`), not a tab. App-level configuration (API key, per-platform defaults, cache) does not belong in the document flow.
5. **Fast means value-typed rows.** No `@ObservedObject viewModel` in row views, no synchronous disk I/O in `body`. See Performance section — these are hard requirements, not polish.

## Current state audit (what's wrong)

| File | Problem |
|---|---|
| `ContentView.swift` | `TabView` — an iOS pattern. Four tabs fragment one linear workflow. Error handling is a single generic alert. |
| `Views/ScanView.swift` | Header text + source picker + path text field permanently occupy the top of the main screen; the game list is squeezed below. `List` of ad-hoc rows instead of a sortable `Table`. No search, no filters, no multi-select. |
| `Views/GameRow.swift` | Each row observes the entire `MainViewModel` (any published change re-renders every row). `NSImage(contentsOf:)` runs synchronous disk I/O inside `body` on every render. Inline `TextField`, `Picker`, and three menus per row make rows heavy and visually noisy. |
| `Views/ArtworkView.swift` | Nearly empty screen: a title list with per-row "Fetch" buttons. Adds no capability over a toolbar button + status column. Delete the concept. |
| `Views/GenerateView.swift` | A whole tab for one directory field, one toggle, one button. Results are dumped as text. |
| `Views/SettingsView.swift` | Settings as a tab. Per-platform defaults rendered as an unbounded `ForEach` (67+ platforms) with no grouping or search. |
| Missing entirely | Per-game args editing (model supports it: `GameEntry.argsTemplate`, `GameOverride.args` — no UI). Multi-select batch actions. Context menus. Keyboard flow. Sorting. Filtering. Empty states. Menu bar integration. |

## Prerequisite decision: minimum OS

Bump the deployment target from macOS 13 to **macOS 14**. Justification: `.inspector()` modifier (needed for the detail panel) is macOS 14+, `Table` and `@Observable` behave much better, and by mid-2026 macOS 14 is two major versions old. If macOS 13 must stay, replace `.inspector` with a manual trailing `HSplitView` panel — everything else in this plan is macOS 13-compatible — but 14 is the recommendation. Update `README.md` and the Xcode project setting.

## Target window anatomy

```
┌────────────────────────────────────────────────────────────────────────────┐
│ ⬤⬤⬤  [Scan ⌄]                    (search field)      [Fetch Art] [Generate]│ toolbar
├───────────────┬──────────────────────────────────────────────┬─────────────┤
│ LIBRARY       │  Title            Platform   Emulator   Art  │  INSPECTOR  │
│  All Games 142│  ▸ artwork thumb + title, sortable columns   │  (selected  │
│  ⚠ Needs      │  ▸ multi-select, context menus               │   game(s))  │
│    Attention 3│  ▸ status icons, not inline editors          │             │
│ PLATFORMS     │                                              │  artwork    │
│  SNES      34 │                                              │  title      │
│  PS1       22 │                                              │  platform   │
│  …            │                                              │  emulator   │
│               │                                              │  arguments  │
│               │                                              │  files      │
├───────────────┴──────────────────────────────────────────────┴─────────────┤
│ 142 games · 5 platforms · 3 need attention          Last generated: 2:41 PM │ status bar
└────────────────────────────────────────────────────────────────────────────┘
```

Implemented as `NavigationSplitView { sidebar } detail: { table }` with `.inspector(isPresented:)` on the detail. Window `minWidth: 900, minHeight: 560`. Sidebar collapsible; inspector toggled by toolbar button and `⌥⌘I`.

### Sidebar

- Section **Library**: "All Games" (count badge) and "Needs Attention" (count badge, only shown when count > 0).
- Section **Platforms**: one row per platform *present in the current scan* (never all 67 DB platforms), with SF Symbol + count. Selecting filters the table.
- Sidebar selection is a `LibraryFilter` enum: `.all`, `.needsAttention`, `.platform(Platform.ID)`.
- Use `List(selection:)` with `.listStyle(.sidebar)`; badges via `.badge(count)`.

### Game table (the core view)

Use SwiftUI `Table` with `@State selection: Set<GameEntry.ID>` and `SortComparator` bindings. Columns:

| Column | Content | Notes |
|---|---|---|
| (checkbox) | include-in-generate toggle | narrow, fixed width |
| Title | 28 px artwork thumbnail + title text | default sort; thumbnail loads async (see Performance) |
| Platform | platform display name | plain text; unknown platform shows `⚠ Unknown` in orange |
| Emulator | current emulator display name | plain text; `⚠ None` in orange when unresolved |
| Artwork | status glyph: `—` / spinner / ✓ / ⚠ | fixed narrow width |
| File | filename only (not full path) | secondary color; full path in tooltip; hide-able |

Rules:

- **No inline editors in cells.** Rename via double-click on the title cell only (standard macOS table rename) or via inspector. Everything else edits in the inspector or context menu.
- `.searchable` scoped to title + filename, bound to the toolbar search field.
- Context menu (works on multi-selection): Set Emulator ▸ (submenu of options valid for the selection's platforms), Set Platform ▸ (only when any selected game is unknown), Fetch Artwork, Include/Exclude from Generate, Reveal in Finder, Copy Launch Command (debug aid), Reset Overrides.
- Empty states (`ContentUnavailableView`): no scan yet → app icon + "Choose a ROM folder to scan" + prominent button; search/filter with no matches → standard "No Results".
- Row status is a computed `GameStatus` on the entry: `.ready`, `.noEmulator`, `.unknownPlatform`, `.artworkMissing`. "Needs Attention" = `noEmulator || unknownPlatform`. Artwork-missing does NOT block generation and does not count as attention (bundle falls back to default icon), but shows in the Artwork column.

### Inspector (per-game granular editing — the centerpiece)

Bound to table selection. Three states:

1. **No selection**: `ContentUnavailableView` "Select a game to edit its settings."
2. **Single selection** — a `Form` with `.formStyle(.grouped)`:
   - **Artwork** (top): large thumbnail (~140 px). Buttons: "Fetch" (re-query SGDB), "Choose File…" (`NSOpenPanel`, png/jpg), and drag-and-drop image onto the well. Stretch (Phase 4): a candidate strip showing multiple SGDB results to pick from — requires extending `SteamGridDBClient` to return N candidates instead of 1; skip if the client change exceeds ~a day.
   - **Title**: text field. Committing writes `setTitle` (already persists via `GameOverride.customTitle`).
   - **Platform**: `Picker` over `viewModel.allPlatforms`. Changing it re-resolves the default emulator (existing `setPlatform` behavior).
   - **Emulator**: `Picker` over `availableOptions(for:)`. Show "(platform default)" suffix on the option matching the platform default. Empty options → warning label + "Open Settings" button.
   - **Arguments**: `TextField` (monospaced) editing `argsTemplate`, persisted to `GameOverride.args` via a new `setArgsTemplate(_:for:)` on the ViewModel. Below it, a caption listing the supported template tokens — read the authoritative token list from `Generators/AppBundleGenerator.swift` and render it verbatim (do not invent tokens). A "Reset to Default" button appears whenever an override exists (i.e. `GameOverride.args != nil`); it clears the override and restores `database.argsTemplate(for:)`.
   - **Launch File**: for multi-image games, the existing alternate-image picker (`.cue` vs `.chd`, etc.) as a `Picker`; for multi-disc, show disc list read-only with the `.m3u` note. Show full ROM path (selectable, middle-truncated) + "Reveal in Finder".
   - **Override indicator**: any field whose value comes from a `GameOverride` gets a small filled dot next to its label (like Xcode's build settings bold). A "Reset All Overrides" button at the bottom.
3. **Multi-selection**: compact form with only the batch-safe fields: Emulator picker (options = intersection of valid options across selected platforms), Include/Exclude toggle, Fetch Artwork button, Reset Overrides. Header: "N games selected".

### Toolbar

- **Leading**: "Scan" split/menu button — primary click rescans the last directory; menu: "Scan Folder…" (`NSOpenPanel`), "Rescan ⌘R", "Import Steam Library (.vdf)…". This absorbs the whole Scan tab and the source-mode picker.
- **Center**: search field (`.searchable` placement).
- **Trailing**: "Fetch Artwork" (fetches missing for all included games; disabled without API key — tooltip explains), "Generate" (`.buttonStyle(.borderedProminent)` — the one prominent button in the window), inspector toggle.
- Progress: during scan/fetch/generate, show a determinate `ProgressView` + message in the **status bar** (bottom), not in the content area. Do not block the table; disable mutating actions via `isProcessing`.

### Generate flow

1. Click Generate (or `⌘⇧G` / File ▸ Generate). If no output directory is set, prompt with `NSOpenPanel` first (then it persists as before).
2. **Confirmation sheet** — this is where "automatic with sensible defaults" earns trust. Run `incrementalManager.detectChanges` in preview mode and show: "3 new, 2 updated, 137 unchanged, 1 will be removed" plus a warning list of included games that will be skipped (no emulator). Toggle for "Remove orphaned bundles" lives here (in addition to Settings). Buttons: Cancel / Generate.
3. Progress in the status bar. On completion, **results sheet**: summary counts, per-game errors/warnings in a scrollable list, "Reveal in Finder" for the output folder. Replace the current text-dump `summaryPanel`.
4. This requires refactoring `MainViewModel.generate()` to expose a `previewChanges()` step; keep the existing generation logic intact.

### Settings window (`Settings` scene, ⌘,)

Standard `TabView` settings style with three panes:

- **General**: output directory (path + Choose…), "Remove orphaned bundles" default, last-scan directory display.
- **Emulators**: per-platform default emulator table — but only platforms with ≥1 installed option shown by default, with a "Show all platforms" toggle; searchable. This replaces the unbounded ForEach.
- **Artwork**: SteamGridDB API key (`SecureField`, save on change — drop the explicit Save button), "Get API Key" link, cache size + Clear Cache.

Move `SettingsView` content here; the settings tab dies. Remove `saveSettings()` UI coupling — persist on change.

### Menu bar & keyboard

Add a `.commands` block:

| Menu | Item | Shortcut |
|---|---|---|
| File | Scan Folder… | ⌘O |
| File | Rescan | ⌘R |
| File | Import Steam Library… | — |
| File | Generate Bundles… | ⌘⇧G |
| Edit | Find | ⌘F (focus search) |
| View | Show/Hide Inspector | ⌥⌘I |
| View | Needs Attention filter | — |

Delete/backspace on selection = Exclude from generate (not destructive). Space = QuickLook the ROM file (stretch, Phase 4, via `QLPreviewPanel`).

## ViewModel / state changes

Keep `MainViewModel` and its DI/tests intact; add UI state rather than rewriting:

- `@Published var selection: Set<GameEntry.ID>`, `@Published var filter: LibraryFilter`, `@Published var searchText: String`, `@Published var sortOrder: [KeyPathComparator<GameEntry>]`.
- `var visibleGames: [GameEntry]` — filter + search + sort applied. Table binds to this.
- `GameEntry.status: GameStatus` computed property (see table section) + `var needsAttentionCount: Int`.
- New mutation: `setArgsTemplate(_:for:)` writing `GameOverride.args` (mirror `setTitle`). New: `setSelected`/`setEmulatorChoice` batch variants taking `Set<GameEntry.ID>`.
- New: `previewChanges() -> GenerationPreview` extracted from `generate()`.
- New: `hasOverride(_ field: OverrideField, for: GameEntry) -> Bool` and `resetOverrides(for:)` for the inspector's override dots / reset buttons.
- Add `swift test` coverage for: `visibleGames` filtering/sorting, `GameStatus` derivation, args override set/reset round-trip, batch emulator assignment, `previewChanges` counts. UI itself stays untested (consistent with repo policy: `swift test` headless, no ⌘U).

## Performance requirements (hard)

1. **Rows must not observe the ViewModel.** Table rows render from the `GameEntry` value only. All mutations flow through the selection → inspector → viewModel path. This fixes the current all-rows-rerender-on-any-change bug.
2. **Async thumbnails.** Replace `NSImage(contentsOf:)` in `body` with a `ThumbnailLoader` (actor or `ObservableObject`): `NSCache<NSString, NSImage>` keyed by `stableKey`, decode at target size (32 px table / 280 px inspector @2x) off the main thread via `CGImageSource` with `kCGImageSourceThumbnailMaxPixelSize`, placeholder while loading. Invalidate a key when its artwork changes.
3. **No per-row `Picker`/`Menu`.** They allocate `NSPopUpButton`-equivalent machinery per row; a 500-game library must scroll at 120 Hz.
4. Verify with a 500-entry synthetic library (generator script or fixture) before calling Phase 1 done.

## Implementation phases

Each phase compiles, passes `swift test`, and is independently committable. Build with `xcodebuild -project SteamShortcutConverter.xcodeproj -scheme SteamShortcutConverter -configuration Debug build`; never `xcodebuild test`.

### Phase 1 — Window scaffold (structure without new features)
- Bump min OS to 14. Replace `TabView` with `NavigationSplitView` + sidebar + `Table` + toolbar + status bar. Port existing capabilities: scan (toolbar menu), VDF import (menu item), search, sort, multi-select, include-checkbox column, generate button (existing flow, no sheets yet). Empty states. Delete `ScanView`, `ArtworkView`, `GenerateView` as tabs (fold their logic in). ViewModel additions: `filter`, `searchText`, `sortOrder`, `selection`, `visibleGames`, `GameStatus`.
- **Accept when**: full scan→generate flow works in the new shell; sidebar filters work; search works; old tab files deleted; tests green.

### Phase 2 — Inspector
- `.inspector` panel with single-selection form: artwork well (fetch/choose file/drag-drop), title, platform, emulator, args editor with token help + reset, launch-file section, override dots, reset-all. Multi-selection batch form. New ViewModel mutations (`setArgsTemplate`, batch ops, `hasOverride`, `resetOverrides`) with tests.
- **Accept when**: every per-game property editable via inspector; overrides persist across rescan (existing `stableKey` mechanism); tests cover new mutations.

### Phase 3 — Settings scene, menus, generate sheets
- `Settings` scene (3 panes), delete settings tab. `.commands` menu items + shortcuts. Generate confirmation sheet (with `previewChanges()`) and results sheet. Status-bar progress. Context menus on the table.
- **Accept when**: ⌘, opens Settings; generate shows preview and results sheets; all shortcuts in the table above work.

### Phase 4 — Polish & speed
- `ThumbnailLoader` with cache + downsampling (if not already done in Phase 1 — do the simple async version in Phase 1, the cached/downsampled version here). Drag-and-drop a folder onto the window to scan it. 500-game performance validation. Accessibility pass (labels on glyph-only controls, focus order). Stretch: SGDB multi-candidate artwork picker, QuickLook on space.
- **Accept when**: smooth scroll with 500 entries; VoiceOver can operate toolbar and inspector.

## HIG references for the implementing agent

Consult before styling each region — do not improvise metrics:

- Layout/anatomy: https://developer.apple.com/design/human-interface-guidelines/layout
- Sidebars: https://developer.apple.com/design/human-interface-guidelines/sidebars
- Inspectors: https://developer.apple.com/design/human-interface-guidelines/inspectors
- Toolbars: https://developer.apple.com/design/human-interface-guidelines/toolbars
- Settings windows: https://developer.apple.com/design/human-interface-guidelines/settings
- Search fields: https://developer.apple.com/design/human-interface-guidelines/search-fields
- SwiftUI `Table`: https://developer.apple.com/documentation/swiftui/table
- SwiftUI `.inspector`: https://developer.apple.com/documentation/swiftui/view/inspector(ispresented:content:)

## Out of scope (do not do while executing this plan)

- Game name fetching / hash-based identification (separate feature, separate plan).
- SGDB client rework beyond the optional multi-candidate fetch in Phase 4.
- Any change to bundle generation, scanning, or the emulator database.
- App icon / branding.
- Localization.
