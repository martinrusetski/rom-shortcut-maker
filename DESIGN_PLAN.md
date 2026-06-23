# Rom Shortcut Maker — Implementation Plan

> **Audience:** the engineer/agent implementing this. Read "Ground Rules" in full before
> writing any code. Each phase ends with **acceptance criteria** (must be green before moving
> on) and the plan has **review checkpoints** where work is handed back for human review.

---

## 0. Context & Ground Rules

### 0.1 What this project is

We are evolving the existing **SteamShortcutConverter** macOS app into **Rom Shortcut Maker**:
a tool that scans ROM directories directly, identifies games and their platforms, fetches
artwork from SteamGridDB, and generates `.app` launcher bundles that point at external
emulators. The legacy Steam `shortcuts.vdf` import becomes a secondary input path, not the
primary one.

This is **macOS only**. No Steam dependency in the primary path, no Linux/Windows.

### 0.2 This is a rewrite, not an extension

Do not be misled by phrasing like "extend" or "modify" — the new pipeline replaces the core
data model (`GameEntry` supplants `SteamShortcut` everywhere except the VDF import bridge) and
`MainViewModel` is rebuilt. The VDF parsing pipeline (`BinaryVDFReader`, `ShortcutParser`,
`VDFValidator`, `LaunchCommandParser`, `ShortcutFilter`, `FileLocationManager`) is **kept
intact** and reused only behind the import bridge. Budget accordingly: most code is new.

### 0.3 How to build and test — READ THIS

- **Tests run headlessly via SPM:** `cd SteamShortcutConverter && swift test`. This is the
  canonical test command. It builds the logic into a library and runs the suite **without
  launching the GUI**.
- **The app builds via Xcode:** `xcodebuild -project SteamShortcutConverter.xcodeproj -scheme
  SteamShortcutConverter -configuration Debug build`.
- **DO NOT run `xcodebuild test` or Xcode ⌘U.** The Xcode test target is currently hosted
  inside the app target; running it launches the GUI app, which traps on launch under the test
  runner and spams crash dialogs. Use `swift test`.
- **`Package.swift` is the test harness.** Its library target compiles the source directory
  **excluding `SteamShortcutConverterApp.swift`** (the `@main` entry). **Every new source file
  you add under `SteamShortcutConverter/SteamShortcutConverter/` is automatically picked up by
  the SPM target.** If you add a new `@main`-like or executable-only file, add it to the
  `exclude:` list. If you add test resource files, make sure they don't break the test target's
  `exclude:` list.
- **Deployment target is macOS 13** (the SPM platform and the Xcode target must stay in sync;
  the UI already uses macOS 13 APIs like `LabeledContent`).

### 0.4 Testability is mandatory — use dependency injection

A pre-existing test (`testResetConfiguration`) had to be **skipped** because `MainViewModel`
does real filesystem I/O in its initializer (auto-detecting the real Steam library), which
makes it impossible to test hermetically. **Do not repeat this pattern.**

- Every component that touches the filesystem, the network, or `Process` must take its
  collaborators via **protocol-typed initializer injection** with a production default.
- `MainViewModel` (and any new view model) must accept its managers (`ConfigurationManager`,
  scanner, emulator detector, artwork client, bundle generator) as injected dependencies so
  tests can pass fakes. No real I/O in `init`. Kick off auto-detection/loading from an explicit
  method the view calls in `.task {}` / `.onAppear`, not from `init`.
- **Un-skip `testResetConfiguration`** as part of the `MainViewModel` rewrite (Phase A8) by
  injecting fakes. This is an acceptance criterion of that phase.

### 0.5 Code conventions

- Match the existing house style: protocol per major component (`protocol X { … }` +
  `class DefaultX: X`), `async`/`await` for I/O, `Logger.shared` for logging (**never
  `print()`** — debug prints were just removed; do not reintroduce them).
- VDF/JSON key lookups that come from external data must be **case-insensitive / tolerant**
  (a real bug was just fixed where case-sensitive VDF key lookup crashed the parser).
- Treat a single path field as a single path — do **not** split paths on spaces (another bug
  just fixed). Paths with spaces are normal on macOS.

### 0.6 Rename strategy (do this in Phase A0, low-risk)

Do **not** rename the Xcode target, scheme, or SPM module — that breaks DerivedData, signing,
and `@testable import SteamShortcutConverter`. Instead:

- Change **user-facing strings** (window title, headers) to "Rom Shortcut Maker".
- Change the **generated bundle identifier prefix** from `com.steamshortcutconverter.` to
  `com.romshortcutmaker.` (this is in `MainViewModel.createAppBundleConfig`, moving to the new
  bundle generator).
- Leave file-header comments and the module name as `SteamShortcutConverter` for now; a full
  module rename is out of scope and not worth the churn.

### 0.7 Distribution / sandboxing — decided

This app shells out to `sips`, `iconutil`, and launches arbitrary emulator processes. It
**cannot be sandboxed** and will **not** ship via the Mac App Store. It is directly
distributed. Therefore:
- Persisting directory paths as plain strings in `config.json` is fine (no security-scoped
  bookmarks needed).
- Do not add App Sandbox entitlements.

---

## 1. Data Model (build first, Phase A1)

The new core entity. Add to `Models/DataModels.swift` (keep `SteamShortcut` etc. for the VDF
bridge).

```swift
struct GameEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String              // Display name (custom override or parsed title)
    let romPath: URL               // Path to ROM file on disk
    var romMetadata: ROMMetadata   // Parsed from filename
    var platform: Platform         // Resolved platform (see SystemDatabase)
    var emulator: EmulatorType?    // Assigned emulator (nil = unresolved)
    var emulatorPath: URL?         // Resolved emulator executable path (nil = not found)
    var argsTemplate: String       // Argument template (defaults from emulator DB)
    var isSelected: Bool
    var artworkStatus: ArtworkStatus
    var source: GameSource

    // Stable identity for caching/overrides: derived from romPath, NOT the random UUID.
    // Use this (not `id`) as the key for gameOverrides and artwork cache.
    var stableKey: String { /* sha256 of romPath.standardizedFileURL.path */ }
}

enum ArtworkStatus: Codable, Equatable {
    case none
    case downloading
    case cached(URL)
    case failed(String)
}

enum GameSource: String, Codable { case romScan, steamVDF }

struct ROMMetadata: Codable, Equatable {
    let rawFilename: String
    let title: String
    let region: String?
    let version: String?
    let discNumber: Int?
    let discTotal: Int?
    let languages: [String]
    let flags: [String]
}
```

> **Note on identity:** `id` (UUID) is for SwiftUI `Identifiable` only. All persistence
> (overrides, artwork cache, incremental state) keys off `stableKey` (a hash of the ROM path),
> so re-scanning the same library reattaches overrides and artwork. Do not persist by `id`.

`Platform` is an enum defined by the System Database (Phase A2).

---

## 2. Phased Implementation

Each phase: **Goal → Files → Spec → Tests (acceptance) → done.** Phases are ordered by
dependency. Review checkpoints marked **🔍 REVIEW**.

---

### Phase A0 — Rename strings + bundle ID prefix

**Goal:** cosmetic rebrand without touching the module/target.

**Files:** `ContentView.swift` (header text), `MainViewModel.swift` (bundle ID prefix), any
visible "Steam Shortcut Converter" UI strings.

**Spec:** Per §0.6. Bundle ID prefix → `com.romshortcutmaker.`.

**Tests:** `swift test` stays green; `xcodebuild build` succeeds. No behavior change.

---

### Phase A1 — `GameEntry` data model + `ROMFilenameParser`

**Goal:** the new model and a tested filename parser. No I/O — pure logic, fully unit-testable.

**Files:**
- `Models/DataModels.swift` (add `GameEntry`, `ROMMetadata`, `ArtworkStatus`, `GameSource`)
- `Scanner/ROMFilenameParser.swift` (new)
- `SteamShortcutConverterTests/ROMFilenameParserTests.swift` (new)

**Spec — `ROMFilenameParser`:**

```swift
final class ROMFilenameParser {
    func parse(filename: String) -> ROMMetadata
}
```

Strip, in order, from the filename stem (extension removed first):
1. Region tags in parens: `(USA)`, `(Europe)`, `(Japan)`, `(World)`, `(USA, Europe)`,
   multi-language `(En,Fr,De)`, and single-letter GoodTools codes `(U)`, `(E)`, `(J)`.
2. Version tags: `(Rev 1)`, `(Rev A)`, `(v1.0)`, `(v1.2)`.
3. Disc markers: `(Disc 1)`, `(Disk 1 of 2)`, `(Side A)` → populate `discNumber`/`discTotal`.
4. Bracket flags: `[!]`, `[b]`, `[hack]`, `[t]`, `[f]`, `[p]`, `[o]`, `[a]` → into `flags`.
5. Special tags: `(Proto)`, `(Beta)`, `(Demo)`, `(Sample)`, `(Unl)` → into `flags`.
6. Languages parsed from region/language tags → `languages`.
7. Remaining unrecognized parenthetical text: leave it in the title (conservative — do **not**
   strip what you don't recognize; the user can edit).
8. Replace underscores with spaces; collapse repeated whitespace; trim.

**Tests (acceptance):** Cover each convention from this table, plus edge cases:

| Input | Expected title | region | disc |
|---|---|---|---|
| `Super Mario World (USA).sfc` | `Super Mario World` | USA | nil |
| `Final Fantasy VII (USA) (Disc 1).chd` | `Final Fantasy VII` | USA | 1 |
| `Chrono Trigger (U) [!].smc` | `Chrono Trigger` | USA | nil |
| `Some Homebrew (Aftermarket).nes` | `Some Homebrew (Aftermarket)` | nil | nil |
| `Game_Name.gba` | `Game Name` | nil | nil |

At least 12 test cases. Conservative behavior on unknown tags is explicitly tested.

---

### Phase A2 — Emulator + System Database (JSON-backed)

**Goal:** the curated knowledge base. **Externalized to a bundled JSON resource — NOT giant
Swift `switch` statements.** This is a deliberate decision: the data changes often (new
emulators, cores) and must be editable/diffable/testable without recompiling enum bodies.

**Files:**
- `Resources/emulators.json` (new — bundled resource)
- `Emulators/SystemDatabase.swift` (new — loads + queries the JSON)
- `Protocols/Protocols.swift` (keep `EmulatorType` enum as the canonical list of *identifiers*
  and its `executablePatterns` for detection; the rich metadata moves to JSON keyed by the enum
  `rawValue`)
- `SteamShortcutConverterTests/SystemDatabaseTests.swift` (new)
- `Resources/` must be declared in **both** `Package.swift` (as a target resource) **and** the
  Xcode target (Copy Bundle Resources). Load via `Bundle.module` in SPM context and
  `Bundle.main` in app context — provide a small `Bundle` resolver that tries `.module` then
  `.main` so the same code works under `swift test` and in the app.

**`emulators.json` schema:**

```json
{
  "version": 1,
  "platforms": [
    {
      "id": "snes",
      "displayName": "SNES",
      "folderAliases": ["snes", "super nintendo", "sfc", "super famicom"],
      "romExtensions": [".smc", ".sfc", ".fig", ".bs", ".swc", ".st"],
      "primaryEmulator": "Snes9x",
      "retroArchCore": "snes9x_libretro.dylib"
    }
  ],
  "emulators": [
    {
      "id": "Snes9x",
      "argsTemplate": "\"{emulator}\" \"{rom}\"",
      "retroArchCore": null
    },
    {
      "id": "RetroArch",
      "argsTemplate": "\"{emulator}\" -L \"{core}\" \"{rom}\""
    }
  ]
}
```

- `id` in `emulators[]` must match an `EmulatorType.rawValue`. A `SystemDatabaseTests` test
  **asserts every `EmulatorType` case has a JSON entry and vice versa** (catches drift).
- `folderAliases` are lowercased directory-name tokens used for folder-based platform
  inference (Phase A3) — this is the **primary** platform signal.
- Populate the platform table from the list below (extend `romExtensions` as needed). Start
  with the mainstream platforms; niche systems can map to RetroArch cores.

| Platform id | display | primary emu | RA core | extensions |
|---|---|---|---|---|
| nes | NES | Mesen | mesen_libretro | .nes .fds .unf |
| snes | SNES | Snes9x | snes9x_libretro | .smc .sfc .fig .bs |
| gb | Game Boy | SameBoy | gambatte_libretro | .gb .gbc |
| gba | GBA | mGBA | mgba_libretro | .gba .agb |
| n64 | N64 | Mupen64Plus | mupen64plus_next_libretro | .n64 .z64 .v64 |
| nds | DS | melonDS | melonds_libretro | .nds .dsi |
| 3ds | 3DS | Azahar | citra_libretro | .3ds .cia .cci .cxi |
| gamecube | GameCube | Dolphin | dolphin_libretro | .iso .gcm .rvz .ciso |
| wii | Wii | Dolphin | dolphin_libretro | .iso .wbfs .rvz .wad |
| ps1 | PS1 | DuckStation | swanstation_libretro | .cue .chd .bin .m3u .pbp |
| ps2 | PS2 | PCSX2 | pcsx2_libretro | .iso .chd .cso .bin |
| psp | PSP | PPSSPP | ppsspp_libretro | .iso .cso .chd .pbp |
| ps3 | PS3 | RPCS3 | — | .iso .pkg |
| genesis | Genesis | ares | genesis_plus_gx_libretro | .md .smd .gen .bin |
| saturn | Saturn | Mednafen | beetle_saturn_libretro | .cue .chd .m3u .ccd |
| dreamcast | Dreamcast | Flycast | flycast_libretro | .cdi .chd .gdi .cue |
| arcade | Arcade | MAME | fbneo_libretro | .zip |
| dos | DOS | DOSBox | dosbox_pure_libretro | .exe .bat .conf .dosz |
| wiiu | Wii U | Cemu | — | .wua .wud .wux .rpx |
| switch | Switch | Ryujinx | — | .nsp .xci .nro .nca |

**`SystemDatabase` API:**

```swift
final class SystemDatabase {
    init(bundle: Bundle = .resolved)        // loads & validates emulators.json
    func platform(forFolderName name: String) -> Platform?    // PRIMARY signal
    func platforms(forExtension ext: String) -> [Platform]    // secondary signal
    func emulators(forExtension ext: String) -> [EmulatorType]
    func primaryEmulator(for platform: Platform) -> EmulatorType?
    func retroArchCore(for platform: Platform) -> String?
    func argsTemplate(for emulator: EmulatorType) -> String
    var allRomExtensions: Set<String> { get }
}
```

`Platform` is a struct decoded from JSON (`id`, `displayName`, …), `Equatable`/`Hashable`.

**Tests (acceptance):**
- JSON loads under `swift test` (via `Bundle.resolved`).
- Enum↔JSON completeness check (no drift).
- `platform(forFolderName: "Super Nintendo")` → snes (case-insensitive, alias match).
- `platforms(forExtension: ".iso")` returns the multiple collision candidates (gamecube, wii,
  ps2, psp, ps3) — proving collisions are surfaced, not hidden.
- `argsTemplate(for: .retroArch)` contains `{core}`.

**🔍 REVIEW CHECKPOINT 1 — after A1+A2.** Hand back: the model, the parser, the JSON DB, and
their tests. This validates the foundational data shapes before the scanner/UI depend on them.

---

### Phase A3 — `ROMScanner` with folder-first platform inference

**Goal:** walk a directory, identify ROMs, and assign each a platform. **Platform inference
priority is the key design decision here.**

**Files:**
- `Scanner/ROMScanner.swift` (new)
- `SteamShortcutConverterTests/ROMScannerTests.swift` (new)

**Spec:**

```swift
struct DiscoveredROM: Equatable {
    let url: URL
    let fileSize: Int64
    let romExtension: String
    let platform: Platform?          // resolved by inference (see below)
    let candidateEmulators: [EmulatorType]
    let platformAmbiguous: Bool      // true if extension matched multiple platforms
                                     // and folder didn't disambiguate
}

protocol ROMScanning {
    func scan(directory: URL,
              progress: @escaping (Double) -> Void) async throws -> [DiscoveredROM]
}
final class ROMScanner: ROMScanning { init(database: SystemDatabase) { … } }
```

**Platform inference priority (implement in this exact order):**
1. **Folder name (PRIMARY).** Walk up from the ROM file; for each ancestor directory name
   (lowercased), check `database.platform(forFolderName:)`. First match wins. This is how real
   ROM libraries are organized (`/ROMs/SNES/…`) and is the single most reliable signal.
2. **Extension, when unambiguous (SECONDARY).** If the folder gave nothing and the extension
   maps to exactly one platform, use it.
3. **Extension + ambiguous.** If the extension maps to multiple platforms (`.iso`, `.bin`,
   `.cue`, `.chd`, `.zip`), set `platform = nil` (or best-guess) and `platformAmbiguous = true`.
   Do **not** rely on file-size heuristics as a primary mechanism — they are unreliable; at most
   use size as a tiebreak hint and still mark ambiguous. The UI lets the user resolve.
4. **No extension match:** skip the file (not a ROM).

Use `FileManager.enumerator` with `.skipsHiddenFiles`. Report progress periodically (not per
file — see global "no progress spam" guidance). Match extensions case-insensitively against
`database.allRomExtensions`.

**Archive handling (`.zip` only for now):** if a `.zip` is encountered, treat the archive
itself as the ROM (report it with `romExtension == ".zip"`, platform = arcade if folder/db
says so). Deep inspection of zip contents is **deferred** — do not implement libcompression
peeking yet. `.7z` is out of scope.

**Multi-disc:** detection/grouping is **deferred to a later phase**. For now, each disc file is
its own `DiscoveredROM`; `ROMFilenameParser` already extracts disc numbers into metadata.

**Tests (acceptance):** Build a temp directory tree on disk in the test:
- `/tmp/.../SNES/Chrono Trigger (USA).sfc` → platform snes (folder match).
- `/tmp/.../PSX/Final Fantasy VII (Disc 1).chd` → platform ps1 (folder alias "psx" → ps1; add
  that alias to JSON).
- A `.iso` in a folder named `Games` (no platform alias) → `platformAmbiguous == true`,
  `platform == nil`.
- A `.iso` in a folder named `GameCube` → platform gamecube (folder wins over ambiguity).
- A `.txt` file → not returned.
- Nested dirs and a hidden file are handled.

---

### Phase A4 — `EmulatorDetector` + `EmulatorConfigManager`

**Goal:** find installed emulators and persist per-emulator config.

**Files:**
- `Emulators/EmulatorDetector.swift` (new)
- `Emulators/EmulatorConfigManager.swift` (new)
- Tests for both (new). Detector tests inject a fake filesystem lister so they're hermetic.

**`EmulatorDetector` spec:**

```swift
protocol AppDiscovering { func appBundles(in dir: URL) -> [URL]; func executables(in dir: URL) -> [URL] }
final class EmulatorDetector {
    init(database: SystemDatabase, fs: AppDiscovering = DefaultAppDiscovering())
    func detectAll() -> [EmulatorType: [URL]]
}
```

Search `/Applications`, `~/Applications`, `/opt/homebrew/bin`, `/usr/local/bin`. For `.app`
bundles, read `CFBundleExecutable` from `Contents/Info.plist`. Match basenames against
`EmulatorType.executablePatterns` using the **strict matcher from below**, not loose
`contains`.

> **Detection bug to avoid:** the existing `ShortcutFilter` matches emulator patterns with
> substring `contains`, which false-matches (`"ares"` in "software", `"fuse"` in "confuser",
> `"b2"`, `"clk"`). For the new detector, match on the **executable basename equal to or
> word-bounded by** the pattern (e.g. exact stem match, or stem with known suffixes like
> `-emu`, version numbers). Add tests proving `"software"` does not match `ares` and
> `"RetroArch"` does match `retroarch`.

**`EmulatorConfigManager` spec:** persists the `emulators` block of `config.json` v2 (see §3).
Per-emulator: `path`, `args`, `enabled`, plus RetroArch's `coresDir` + `corePreferences`.
Provides resolution: given a `GameEntry`, return the resolved `emulatorPath`, `argsTemplate`,
and (for RetroArch) the `{core}` path. Injected `ConfigurationManager`.

**Emulator resolution flow** (used by the scan → entry mapping):
1. Candidate emulators from `database.emulators(forExtension:)`, filtered to enabled.
2. One match → assign. Multiple → prefer `database.primaryEmulator(for: platform)`, else first
   enabled. Zero → `emulator = nil` (UI shows "no emulator" badge; entry not generatable).
3. User can override per-entry in the UI.

**Tests (acceptance):** strict matching (no false positives), detection of an `.app` via a faked
`Info.plist`, resolution picks primary emulator on extension collision, missing emulator yields
`nil` not a crash.

**🔍 REVIEW CHECKPOINT 2 — after A3+A4.** Hand back the scanner + emulator subsystems. This is
where the riskiest heuristics live (platform inference, detection matching); review before the
UI is built on top.

---

### Phase A5 — `SteamGridDBClient` + `ArtworkCache`

**Goal:** fetch and cache artwork.

**Files:**
- `Artwork/ArtworkProvider.swift` (protocol, for future providers)
- `Artwork/SteamGridDBClient.swift`
- `Artwork/ArtworkCache.swift`
- Tests: client tests inject a fake `URLProtocol`/`URLSession` (no real network in `swift
  test`). Cache tests use a temp dir.

**`SteamGridDBClient` spec:** REST client for `https://www.steamgriddb.com/api/v2`. Inject
`URLSession`. Bearer-token auth from the configured API key.
- `searchGame(term:) -> [SGDBGame]` (autocomplete/search endpoint — text search, **not**
  platform-filtered; SGDB platform IDs don't map to retro consoles).
- `getIcons(gameId:) -> [SGDBImage]` and `getGrids(gameId:) -> [SGDBImage]`.
- `downloadImage(url:) -> Data`.
- **Rate limiting:** client-side throttle max 1 req/s; on HTTP 429 sleep `Retry-After` and
  retry **once**; otherwise surface the error. No infinite retry.

**Artwork selection strategy (important — SGDB icon coverage is thin for retro titles):**
1. Search by `GameEntry.title`. Use top result (SGDB relevance).
2. Try `getIcons` filtered to `image/png`, sorted by score. If results exist, use top.
3. **Fallback:** if no icon-type assets (common for retro/obscure games), fall back to
   `getGrids` (or logo) and use that image as the icon source. Document this fallback.
4. User override (Phase A9): manual search, pick result, or supply a local file.

**`ArtworkCache` spec:** stored at
`~/Library/Application Support/RomShortcutMaker/artwork/<stableKey>/`:
- `original.png` (raw download), `AppIcon.icns` (converted), `metadata.json`
  (`{ sgdbGameId, sgdbImageId, downloadedAt, sourceType }`).
- Keyed by `GameEntry.stableKey` (ROM-path hash) so re-scans reuse artwork.
- `cacheSize() -> Int64`, `clear()`, `isStale(entry:olderThanDays:)`.

**Tests (acceptance):** rate-limit throttle respected (mock clock or injected delay), 429
retry-once behavior, search/parse against canned JSON fixtures, icon→grid fallback path, cache
read/write/clear in temp dir, cache key stability across two `GameEntry`s with same ROM path.

---

### Phase A6 — `BundleGenerator` for `GameEntry` + arg templates

**Goal:** generate external-reference `.app` bundles from `GameEntry`, resolving the
`{emulator}`/`{rom}`/`{core}` template.

**Files:**
- `Generators/AppBundleGenerator.swift` (refactor existing `DefaultAppBundleGenerator`)
- Update `AppBundleGeneratorTests.swift`.

**Spec:**
- Add an input path that takes a resolved game (emulator path, rom path, args template, icon
  source) and produces the bundle. Keep the existing `AppBundleConfig` path working for the VDF
  bridge, or have the bridge build the same resolved inputs — your call, but **don't break the
  existing AppBundleGenerator tests**.
- **Template resolution:** expand `{emulator}` → emulator executable path, `{rom}` → ROM path,
  `{core}` → RetroArch core `.dylib` path (from `EmulatorConfigManager`). Produce the launch
  command, then write `Contents/MacOS/launch.sh`.
- **Collapse the double-escaping.** Today `MainViewModel.buildLaunchScript` quotes/escapes and
  then `AppBundleGenerator.escapeShellCommand` re-escapes — two escapers on one string, a latent
  bug. The new path builds the command **once** from structured pieces (executable + args
  array) with a single, well-tested shell-escaping function. Add tests for paths with spaces,
  `$`, backticks, and quotes.
- Bundle ID: `com.romshortcutmaker.<sanitized-title>`; ensure uniqueness (if two titles
  sanitize equal, disambiguate with a short `stableKey` suffix).
- Icon: convert from the artwork cache's `original.png` (reuse the existing sips/iconutil
  `.icns` pipeline) or copy the pre-converted `AppIcon.icns`.

**Tests (acceptance):** template expansion for a standalone emulator and for RetroArch (with
`{core}`); single-escaping correctness for nasty paths; bundle structure (Info.plist,
launch.sh chmod 755, icon) on disk in a temp dir; bundle-ID uniqueness on title collision.

---

### Phase A7 — `IncrementalUpdateManager` extended for ROMs

**Goal:** change detection keyed on ROM + emulator + args + artwork.

**Files:** `Managers/IncrementalUpdateManager.swift` (extend), update its tests.

**Spec:** Add a `GameEntry`-based change-detection path. The change signature hashes:
- ROM path **and** ROM file SHA256 (detect a re-dumped ROM at the same path),
- resolved emulator path (+ version if cheaply available),
- the resolved args template,
- artwork cache reference (icon identity).

Keep the existing `SteamShortcut` path for the VDF bridge. **Preserve the existing
"regenerate if the bundle is missing on disk" behavior** — the tests now create real bundle
dirs to exercise the unchanged path (don't regress that).

> **Performance note:** hashing large ROM files (multi-GB ISOs) on every scan is expensive.
> Hash lazily/incrementally: cache `(path, mtime, size) → sha256` and only re-hash when
> mtime/size changes. Add a test for the mtime/size short-circuit.

**Tests (acceptance):** new/modified/unchanged/removed for `GameEntry`; re-dumped ROM (same
path, different hash) → modified; changed args → modified; mtime/size cache short-circuits
re-hash.

---

### Phase A8 — `MainViewModel` rewrite (with DI) + VDF bridge

**Goal:** the orchestration layer for the scan→resolve→artwork→generate pipeline, **fully
dependency-injected and testable**, plus the legacy VDF import bridged to `GameEntry`.

**Files:**
- `ViewModels/MainViewModel.swift` (rewrite)
- `Managers/VDFToGameEntryBridge.swift` (new)
- `Managers/ConfigurationManager.swift` (extend for config v2 + migration)
- Update `MainViewModelTests.swift` and **un-skip `testResetConfiguration`** using injected
  fakes.

**Spec:**
- `MainViewModel.init` takes injected protocols: `ConfigurationManager`, `ROMScanning`,
  `EmulatorDetector`, `EmulatorConfigManager`, `SystemDatabase`, artwork client/cache, bundle
  generator, and (for the bridge) the VDF pipeline. Provide a convenience `init()` wiring the
  production defaults for the app. **No filesystem/network I/O in `init`** — expose
  `func load() async` that the view calls from `.task {}`.
- State: `@Published var games: [GameEntry]`, scan directory, output directory, source mode,
  progress, summary. Selection/override mutations persist via `EmulatorConfigManager` /
  `ConfigurationManager` keyed by `stableKey`.
- **VDF bridge** maps `SteamShortcut` → `GameEntry` per this table; it reuses the existing,
  now-fixed parser/filter/launch-parser:

  | SteamShortcut | GameEntry |
  |---|---|
  | `appName` | `title` |
  | `exe` (+ `LaunchCommandParser`) | `emulatorPath`, detected `EmulatorType` |
  | `LaunchOptions` ROM arg | `romPath` |
  | embedded `icon` | `artworkStatus = .cached(...)` if it converts; else `.none` |

- **Config v2 migration:** read a v1 `config.json` (`customNames` keyed by `appID`,
  `selectedShortcutIDs`) and migrate to v2 (`gameOverrides` keyed by `stableKey`). Since v1
  keys are Steam appIDs and v2 keys are ROM-path hashes, migration can only map entries when the
  VDF is re-imported; document that custom names reattach on first VDF re-import. Write a
  migration test with a v1 fixture.

**Tests (acceptance):** the whole pipeline with fakes (inject a fake scanner returning known
`DiscoveredROM`s, fake detector, fake artwork client) → assert `games` populated, selection/
override persistence, generate summary counts. **`testResetConfiguration` un-skipped and
passing** with injected fakes (no real Steam access). VDF bridge mapping test. Config migration
test.

**🔍 REVIEW CHECKPOINT 3 — after A8.** The entire non-UI pipeline is now testable end-to-end
with fakes. Hand back for review before building the UI.

---

### Phase A9 — UI

**Goal:** replace the single-window UI with the scan/artwork/generate/settings flow.

**Files (new):** `Views/GameRow.swift`, `Views/ScanView.swift`, `Views/ArtworkView.swift`,
`Views/GenerateView.swift`; extend `Views/SettingsView.swift`; rework `ContentView.swift` into a
tabbed layout. Delete `Views/ShortcutRow.swift` once `GameRow` replaces it.

**Spec (concise — match existing SwiftUI style):**
- **Tabs:** Scan · Artwork · Generate · Settings (gear).
- **Scan tab:** ROM directory picker, Scan button, progress, results count ("247 ROMs across 12
  platforms"). Source selector: "Scan ROM Directory" vs "Import from Steam VDF" (persisted).
- **Game list / `GameRow`:** checkbox; 32×32 artwork thumb (placeholder/spinner/cached);
  inline-editable title (persists to `gameOverrides` by `stableKey`); platform badge; emulator
  dropdown (enabled compatible emulators; shows "No emulator" when unresolved); truncated ROM
  path (full in tooltip); artwork status indicator (✓ cached / ↓ pending / — none / ⚠ failed,
  click to retry); **ambiguous-platform badge** with a platform picker when
  `platformAmbiguous`.
- **Artwork tab:** "Fetch Missing", "Re-fetch All", per-game search popover (SGDB results as
  thumbs), "Use Local Image…", drag-and-drop onto a row, 256×256 preview. Downloads are
  **bounded-concurrency** and respect the 1 req/s throttle.
- **Generate tab:** output dir picker, bundle-name preview, "Remove orphaned bundles" toggle,
  progress, summary panel ("Created 12, Updated 3, Skipped 5, Removed 1, 2 errors").
- **Settings tab:** SGDB API key (secure field) + "Get API Key" link; per-emulator path/args/
  enabled + "Auto-detect All" + "Add Custom"; RetroArch path/cores dir/per-platform core prefs;
  artwork cache size + "Clear Cache"; "Import from Steam shortcuts.vdf"; default output dir.

**Tests:** UI isn't unit-tested, but the view model driving it is (A8). Acceptance for this
phase is **manual**: app builds (`xcodebuild build`), launches, scans a sample ROM dir,
resolves emulators, fetches artwork, generates a working bundle.

**🔍 REVIEW CHECKPOINT 4 — after A9.** Full core app. Hand back for end-to-end human review +
manual testing.

---

### Phase A10 — Integration polish

Wire incremental updates into the generate flow, orphan cleanup, error/warning surfacing, empty
states, and a final pass on logging (all via `Logger.shared`). Run the full `swift test` suite
and a manual end-to-end. Update README features.

---

## 3. Config schema (`config.json` v2)

```json
{
  "version": 2,
  "sourceMode": "scan",
  "lastScanDirectory": "/Users/x/ROMs",
  "outputDirectory": "/Users/x/Games",
  "removeOrphanedBundles": true,
  "steamGridDBApiKey": "…",
  "emulators": {
    "Snes9x":   { "path": "/Applications/Snes9x.app", "args": "\"{emulator}\" \"{rom}\"", "enabled": true },
    "RetroArch":{ "path": "/Applications/RetroArch.app", "args": "\"{emulator}\" -L \"{core}\" \"{rom}\"", "enabled": true,
                  "coresDir": "/Applications/RetroArch.app/Contents/Resources/cores",
                  "corePreferences": { "snes": "snes9x_libretro.dylib", "gba": "mgba_libretro.dylib" } }
  },
  "gameOverrides": {
    "<stableKey>": { "customTitle": "Chrono Trigger", "emulator": "Snes9x", "args": null, "platform": "snes" }
  },
  "lastConversionDate": "2026-06-04T12:00:00Z"
}
```

`gameOverrides` is keyed by `stableKey` (ROM-path hash), **not** UUID or Steam appID.

---

## 4. PART B — Self-Contained Bundles (DEFERRED — do not start without sign-off)

Embeds emulator + ROM inside the `.app`. **Do not begin until the core app (A0–A10) is complete,
reviewed, and stable.** Before investing, there is a **mandatory prototype gate**:

> **⚠ Code-signing blocker — prototype this FIRST.** On Apple Silicon, rewriting a signed
> emulator binary with `install_name_tool` **invalidates its code signature**, and the kernel
> refuses to execute invalidly-signed arm64 binaries. The bundle will not launch unless you
> **ad-hoc re-sign** every rewritten binary/dylib (`codesign -s - --force`) after
> `install_name_tool`. Before building any of B1–B7, prototype this loop on **one** emulator:
> copy it → `otool -L` → copy non-system dylibs → `install_name_tool -change` →
> `codesign -s - --force` → launch and confirm it runs. If this loop doesn't work reliably,
> Part B's design must change regardless of effort spent elsewhere.

The bundle structure, `GameLauncher` compiled-Swift stub (handles App Translocation, keeps Dock
presence via `waitUntilExit`), `DylibResolver`, per-emulator stripping strategy,
`SelfContainedBundleGenerator`, and the emulator-update mechanism are designed as in the prior
draft — but all gated behind the prototype above and a separate review. Risks: dylib dependency
trees (manageable for `.app` emulators, painful for Homebrew CLI builds; document `.app`
emulators as the supported case), RetroArch asset stripping vs. user expectations, disk space
warnings, and licensing (we copy binaries the user already installed; we don't distribute
emulators).

---

## 5. Implementation order & review gates (summary)

| # | Phase | Review gate |
|---|---|---|
| A0 | Rename strings + bundle ID | — |
| A1 | `GameEntry` + `ROMFilenameParser` | 🔍 RC1 (with A2) |
| A2 | JSON emulator/System DB | 🔍 RC1 |
| A3 | `ROMScanner` (folder-first) | 🔍 RC2 (with A4) |
| A4 | `EmulatorDetector` + config | 🔍 RC2 |
| A5 | SteamGridDB client + cache | — |
| A6 | Bundle generator (templates) | — |
| A7 | Incremental update (ROM hashing) | — |
| A8 | `MainViewModel` rewrite + VDF bridge | 🔍 RC3 |
| A9 | UI | 🔍 RC4 |
| A10 | Integration polish | final |
| B* | Self-contained bundles | DEFERRED + prototype gate |

**Every phase must leave `swift test` green and `xcodebuild build` succeeding.** New logic gets
unit tests runnable headlessly. Components touching I/O are dependency-injected. Stop at each
🔍 checkpoint and hand back for review.
```
