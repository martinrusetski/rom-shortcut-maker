# Post-redesign fixes — Round 1

Implementation-ready plan for five issues found after the single-window redesign. Each issue is an independent workstream; implement and commit them one at a time, in the order below. Read this whole document before starting.

## Ground rules

- Work in `/Users/martinr/Developer/rom-shortcut-maker`, branch `feature/rom-shortcut-maker`.
- **First action before any code change**: the working tree has staged, uncommitted changes from the UI redesign (see `git status`). Commit them as-is with message `Single-window UI redesign: NavigationSplitView shell, Game Properties window, Settings scene` (plus the standard Co-Authored-By trailer) so the fix commits stay clean. Do not modify those files as part of that commit.
- Tests: `cd RomShortcutMaker && swift test` (SPM; `Package.swift` globs all sources, so new files need no manifest edits — the `.xcodeproj` is gitignored and must not be touched). Never run `xcodebuild test`.
- Verify compilation with `swift build` inside `RomShortcutMaker/` as you go; run the full `swift test` before each commit.
- One commit per issue, message prefixed like the existing history (imperative, no ticket numbers). End commit messages with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Match existing code style: comment density, MARK sections, dependency injection, no I/O in inits. Rows in the main list must stay value-typed (they must NOT observe the ViewModel) — that's a hard performance requirement from the redesign.
- If an existing test asserts something your change legitimately alters (e.g. platform counts in `SystemDatabaseTests`), update the test with the change, not in a separate commit.

## Issue 1 — ROM list must survive relaunch

Today `MainViewModel.load()` restores config (including `lastScanDirectory`) but never rescans, so the list is empty until the user rescans manually. Also, unchecking a game's include-checkbox isn't persisted anywhere, so that state dies on rescan/relaunch too.

Changes in `ViewModels/MainViewModel.swift` and `Managers/RomConfig.swift`:

1. **Auto-rescan on launch.** At the end of `load()`, if `sourceMode == .scan`, `scanDirectory` is non-empty, and the directory exists, call `await scan()`. (VDF mode is out of scope — the .vdf path isn't persisted; leave it.) The existing progress UI already handles the in-flight state.
2. **Persist the include checkbox.** Add `var excluded: Bool?` to `GameOverride` (it's `Codable`/`Equatable`; the empty-override cleanup in `updateOverride` works because a nil field keeps `override == GameOverride()` true). In `setSelected(_:for:)`, also `updateOverride(game.stableKey) { $0.excluded = selected ? nil : true }`. In `applyOverrides()`, apply `games[index].isSelected = !(override.excluded ?? false)`.

Tests (`MainViewModelTests`): (a) `load()` with a config whose `lastScanDirectory` points at a real temp dir triggers exactly one scan (the injected `ROMScanning` mock can count calls); (b) deselect → rescan → still deselected; (c) `GameOverride` with only `excluded` set survives the encode/decode round-trip (extend `RomConfigMigrationTests` or the existing config tests).

## Issue 2 — Manual SteamGridDB matching + game names

Two sub-problems: wrong automatic matches can't be corrected, and SGDB's proper game names are thrown away (we only use icons). Design:

### Model / persistence

- Add to `GameOverride`: `var sgdbGameId: Int?` and `var sgdbGameName: String?` (name kept for display in the Properties window).

### Provider layer (`Artwork/ArtworkProvider.swift`)

Refactor the protocol extension so title-search and image-fetch are separable and the match identity is surfaced:

- `func bestMatch(forTitle title: String) async throws -> SGDBGame?` — first autocomplete hit (current behavior).
- `func fetchArtwork(for game: SGDBGame) async throws -> FetchedArtwork?` — the existing icon→grid fallback for a known game id.
- Keep `fetchArtwork(forTitle:)` as a composition of the two (existing tests keep passing), or update its call sites/tests if removing it is cleaner.

### ViewModel (`MainViewModel`)

- `fetchArtwork(for game:)`: if the game's override has `sgdbGameId`, skip the title search and fetch for that id directly. Otherwise search by title; on a successful match, record `sgdbGameId`/`sgdbGameName` in the override (so refetches stay stable) **and apply the SGDB name as the title** via the existing `setTitle` path — but only when the game has no `customTitle` override yet (never stomp a user rename). Applying via `setTitle` intentionally creates a title override, so the name persists across rescans and is resettable per-field like any other override.
- New: `func searchArtworkMatches(term: String) async -> [SGDBGame]` (returns `[]` + sets `errorMessage` on failure / missing API key).
- New: `func applyManualMatch(_ match: SGDBGame, setTitle: Bool, for game: GameEntry) async` — writes `sgdbGameId`/`sgdbGameName` to the override, optionally sets the title (this one DOES overwrite an existing custom title — it's an explicit user action), then fetches artwork for the id.
- New: `func matchedGameName(for game: GameEntry) -> String?` and a way to clear the match (`resetOverride` gains no new field enum case — instead add a `clearManualMatch(for:)` that nils both sgdb fields; keep `OverrideField` untouched since the match isn't a scanned default that can be "reset to").

### UI (`Views/GamePropertiesView.swift`, Artwork section)

- Under the existing buttons, a caption line when matched: `Matched: <sgdbGameName>` with a small "×" / "Clear" borderless button.
- New button "Match Manually…" → sheet (`SGDBMatchSheet`, new struct in the same file or its own file under `Views/`):
  - Search field pre-filled with the game title, searches on submit (calls `searchArtworkMatches`).
  - Result list of game names; single selection.
  - Toggle "Also use matched name as title", default on.
  - "Use This Match" button → `applyManualMatch` → dismiss. Cancel button. Show a spinner while searching, and a "No results" empty state.
- Disable "Match Manually…" (with `.help`) when no API key is set.

Tests: mock `ArtworkProvider` already exists for `MainViewModelTests` — add: fetch honors an override `sgdbGameId` (search must NOT be called); auto-fetch records match id + applies name only when no custom title; `applyManualMatch` overwrites title when `setTitle: true` and persists both fields; clearing the match removes both fields.

## Issue 3 — "Sega Model 2" as a distinct platform

Background (from research, for context — the JSON edit is small): MAME is the only native macOS option for Sega Model 2, and its Model 2 driver set is imperfect (a handful of games promoted to working — Virtua Fighter 2, Motor Raid, Rail Chase 2 — the rest have glitches). ElSemi's "Model 2 Emulator" is Windows-only. So MAME stays the emulator option, but the platform deserves its own identity instead of silently lumping into "Arcade": correct labeling, its own default-emulator slot, and its own folder aliases (the user's folder is literally named `Sega Model 2 Arcade`, which matches no alias today).

In `Resources/emulators.json`, add a platform record (keep `arcade` unchanged):

```json
{
  "id": "sega-model2",
  "displayName": "Sega Model 2",
  "folderAliases": ["model 2", "model2", "sega model 2", "sega model 2 arcade"],
  "romExtensions": [".zip"],
  "libretroSystems": [],
  "emulatorOptions": [
    { "type": "standalone", "emulator": "MAME" }
  ]
}
```

Check `SystemDatabaseTests` for platform-count or exhaustive-list assertions and update them. Add one test: `platform(forFolderName: "Sega Model 2 Arcade")` resolves to `sega-model2` (proves alias matching, case-insensitive).

Note `.zip` now maps to both `arcade` and `sega-model2` by extension — that's fine: folder inference is the primary signal, and the ambiguous-extension path already returns nil platform + `platformAmbiguous` when the folder doesn't disambiguate. Verify no test regresses on that.

## Issue 4 — Properties (i) button on each row

`Views/GameRow.swift`: add a trailing button to `GameListRow` after `statusView`, macOS-Settings style: `Image(systemName: "info.circle")`, `.buttonStyle(.borderless)`, `.foregroundColor(.secondary)`, `.help("Game Properties")`, plus an accessibility label. The row is value-typed — wire it via a new `let onInfo: () -> Void` callback parameter (do NOT pass the ViewModel in). In `ContentView.swift` (~line 133), pass `onInfo: { viewModel.propertiesGameID = game.id }`. Keep the existing double-click and context-menu paths.

No new tests (pure view wiring), but the project must still build.

## Issue 5 — PS3 extracted-disc folders

Real-world shape (verified on the user's disk):

```
PS3/Odin Sphere - Leifthrasir/
  PS3_DISC.SFB
  PS3_GAME/
    PARAM.SFO          ← metadata incl. real title
    ICON0.PNG          ← official icon artwork
    USRDIR/EBOOT.BIN   ← what RPCS3 launches
```

Today the scanner just finds `EBOOT.BIN` by its `.bin` extension, folder-infers PS3 from the ancestor `PS3` directory, and titles it "EBOOT". Fix by recognizing the folder as one game:

### Scanner (`Scanner/ROMScanner.swift`)

- In the enumeration loop, directories are currently skipped by the `isRegularFile` guard. Add a directory check first: a directory `D` is a **PS3 game root** if `D/PS3_GAME/PARAM.SFO` exists (also accept `D/PARAM.SFO` + `D/USRDIR/EBOOT.BIN` for the JB-rip layout where `PS3_GAME`'s contents sit at the root). When detected: record it and call `enumerator.skipDescendants()` so nothing inside (EBOOT.BIN, other .bin/.pkg files) is double-collected.
- For each PS3 game root, synthesize a `DiscoveredROM`: `url` = the `EBOOT.BIN` path, platform = PS3 (resolve via `database.platform(forFolderName: "ps3")` — do not construct a `Platform` by hand), `candidateEmulators` via the existing helper, `platformAmbiguous: false`, `fileSize` of EBOOT.BIN.
- Add two optional fields to `DiscoveredROM` (defaulted so existing call sites/tests compile): `titleHint: String?` and `artworkHint: URL?`. For PS3 roots: `titleHint` = PARAM.SFO `TITLE` value, falling back to the game-root folder name; `artworkHint` = `ICON0.PNG` if present.
- These synthesized entries bypass the sheet/playlist/grouping machinery — append them to the results directly (they're single-entry-point games with no members).

### PARAM.SFO parser

New file `Scanner/ParamSFO.swift`: a small pure parser, `static func title(of url: URL) -> String?` (or `parse(data:) -> [String: String]` for the string entries — pick the minimal shape). Format (little-endian): magic `00 50 53 46` ("\0PSF"), u32 version, u32 keyTableStart, u32 dataTableStart, u32 entryCount; then `entryCount` index entries of 16 bytes each: u16 keyOffset, u16 dataFormat, u32 dataLen, u32 dataMaxLen, u32 dataOffset. Key = NUL-terminated ASCII at `keyTableStart + keyOffset`; for format `0x0204` (UTF-8 string) the value is at `dataTableStart + dataOffset`, `dataLen` bytes, NUL-terminated — trim the NUL and any trailing whitespace/newlines. Bounds-check every offset; return nil on any malformed input (never crash on a hostile file).

### ViewModel (`MainViewModel.makeEntry` + artwork seeding)

- `makeEntry(from:)`: if `rom.titleHint` is non-nil, use it as the entry title instead of `filenameParser.parse(...)` title (still run the parser for `romMetadata`).
- Artwork seeding: after `applyCachedArtwork()` in `scan()`, for each game that has an `artworkHint` and no cached artwork, read the PNG data and store it via `artworkCache.store(originalPNG:metadata:for:)` with `sourceType: "bundled-icon"`, nil SGDB ids, then set `artworkStatus = .cached(...)`. Keep a transient `[stableKey: URL]` map from the scan result to carry the hint (DiscoveredROM → GameEntry loses it otherwise). Failure to seed is non-fatal (skip silently).

Note `stableKey` hashes the EBOOT.BIN path — stable across rescans, so overrides and artwork reattach. RPCS3 launches `EBOOT.BIN` paths directly, so the existing args template works unchanged.

Tests: (a) `ParamSFO` unit test with a fixture built in-test (assemble bytes for a minimal SFO with `TITLE`; plus truncated/garbage inputs return nil); (b) `ROMScannerTests`: build a temp tree matching the layout above (PARAM.SFO from the same fixture bytes, empty EBOOT.BIN, tiny PNG) → scan yields exactly one ROM: platform `ps3`, url ends in `EBOOT.BIN`, `titleHint` = SFO title, `artworkHint` set, and no separate "EBOOT" `.bin` entry; (c) JB-rip layout variant; (d) `MainViewModelTests`: entry title uses the hint, artwork gets seeded (in-memory/temp `ArtworkCache`).

## Acceptance checklist (run before finishing)

1. `swift test` green, `swift build` clean (both from `RomShortcutMaker/`).
2. Five fix commits + the initial redesign commit, each self-contained.
3. Grep sanity: no view passes `MainViewModel` into `GameListRow`; `GameOverride` remains the single persistence point for per-game state.
4. Leave the working tree clean (everything committed).
