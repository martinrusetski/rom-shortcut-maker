# Rom Shortcut Maker — Implementation Plan

> **Audience:** the engineer/agent implementing this. Read "Ground Rules" in full before
> writing any code. Each phase ends with **acceptance criteria** (must be green before moving
> on) and the plan has **review checkpoints** where work is handed back for human review.

---

## 0. Context & Ground Rules

### 0.1 What this project is

This project evolved the original **SteamShortcutConverter** macOS app into **Rom Shortcut Maker**:
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

- **Tests run headlessly via SPM:** `cd RomShortcutMaker && swift test`. This is the
  canonical test command. It builds the logic into a library and runs the suite **without
  launching the GUI**.
- **The app builds via SwiftPM:** run `swift build` in `RomShortcutMaker/`, or open
  `RomShortcutMaker/Package.swift` in Xcode and press ⌘R. The legacy `.xcodeproj` is untracked
  and is not a maintained build system.
- **Use `swift test` for tests.** The SwiftPM executable target contains the `@main` entry and
  all source files under `RomShortcutMaker/RomShortcutMaker/`; the test target imports that
  module directly. If you add test resource files, keep the test target's `exclude:` list valid.
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

### 0.6 Rename strategy (completed)

The package, executable target, test target, source folders, and entry point now use
`RomShortcutMaker`. User-facing strings use "Rom Shortcut Maker", and generated bundle
identifiers use the `com.romshortcutmaker.` prefix.

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
    var emulator: EmulatorChoice?  // Assigned emulator choice (nil = unresolved)
    var emulatorPath: URL?         // Resolved executable path (the RetroArch binary, for cores)
    var argsTemplate: String       // Argument template (defaults from emulator DB)
    var isSelected: Bool
    var artworkStatus: ArtworkStatus
    var source: GameSource

    // Stable identity for caching/overrides: derived from romPath, NOT the random UUID.
    // Use this (not `id`) as the key for gameOverrides and artwork cache.
    var stableKey: String { /* sha256 of romPath.standardizedFileURL.path */ }
}

/// How a ROM is launched: either a standalone emulator, or RetroArch with a
/// specific core. A platform can have several valid choices (e.g. Snes9x.app,
/// RetroArch+snes9x core, RetroArch+bsnes core) and which ones are usable
/// depends on what the user has installed. This is why the assignment is a
/// choice, not a bare EmulatorType — "RetroArch" alone is ambiguous when more
/// than one core can run the system.
enum EmulatorChoice: Codable, Equatable, Hashable {
    case standalone(EmulatorType)
    case retroArchCore(core: String)   // e.g. "snes9x_libretro.dylib"
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
- `RomShortcutMakerTests/ROMFilenameParserTests.swift` (new)

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
- `RomShortcutMakerTests/SystemDatabaseTests.swift` (new)
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
      "emulatorOptions": [
        { "type": "standalone",    "emulator": "Snes9x" },
        { "type": "standalone",    "emulator": "bsnes" },
        { "type": "retroArchCore", "core": "snes9x_libretro.dylib", "displayName": "Snes9x (RetroArch)" },
        { "type": "retroArchCore", "core": "bsnes_libretro.dylib",  "displayName": "bsnes (RetroArch)" }
      ]
    },
    {
      "id": "wiiu",
      "displayName": "Wii U",
      "folderAliases": ["wiiu", "wii u"],
      "romExtensions": [".wua", ".wud", ".wux", ".rpx"],
      "emulatorOptions": [
        { "type": "standalone", "emulator": "Cemu" }
      ]
    }
  ],
  "emulators": [
    { "id": "Snes9x",    "argsTemplate": "\"{emulator}\" \"{rom}\"" },
    { "id": "bsnes",     "argsTemplate": "\"{emulator}\" \"{rom}\"" },
    { "id": "RetroArch", "argsTemplate": "\"{emulator}\" -L \"{core}\" \"{rom}\"" }
  ]
}
```

**Model rationale (read this — it drives several phases):** A platform owns an **ordered list of
emulator options**. Each option is *either* `standalone` (references an `EmulatorType`) *or*
`retroArchCore` (references a specific core `.dylib`). This is deliberately many-to-many:
- A system may list **several standalone emulators** (the user picks which one they have/prefer).
- A system may list **several RetroArch cores** (RA has more than one core per system).
- A system may have **no RetroArch option at all** (e.g. `wiiu` → Cemu only). Do **not** assume
  RetroArch can run everything — only list a `retroArchCore` option when a real core exists.
- Order = preference. Auto-assignment (Phase A4) picks the first option that is actually
  installed + enabled; the user can override.

- `emulator`/`id` values must match an `EmulatorType.rawValue`. A `SystemDatabaseTests` test
  **asserts every `standalone` option and every `emulators[]` id maps to a real `EmulatorType`**
  (catches drift).
- `folderAliases` are lowercased directory-name tokens for folder-based platform inference
  (Phase A3) — the **primary** platform signal.
- Seed the platform list from the table below. The "options (preference order)" column is a
  starting point — add more standalone emulators and cores per system as you populate the JSON.
  "RA: —" means no RetroArch core for that system (standalone only).

| Platform id | display | options (preference order) | extensions |
|---|---|---|---|
| nes | NES | Mesen; RA: mesen, nestopia, fceumm | .nes .fds .unf |
| snes | SNES | Snes9x; bsnes; RA: snes9x, bsnes | .smc .sfc .fig .bs |
| gb | Game Boy | SameBoy; RA: gambatte, sameboy | .gb .gbc |
| gba | GBA | mGBA; NanoBoyAdvance; RA: mgba | .gba .agb |
| n64 | N64 | ares; Mupen64Plus; RA: mupen64plus_next, parallel_n64 | .n64 .z64 .v64 |
| nds | DS | melonDS; DeSmuME; RA: melonds, desmume | .nds .dsi |
| 3ds | 3DS | Azahar; Lime3DS; RA: citra | .3ds .cia .cci .cxi |
| gamecube | GameCube | Dolphin; RA: dolphin | .iso .gcm .rvz .ciso |
| wii | Wii | Dolphin; RA: dolphin | .iso .wbfs .rvz .wad |
| ps1 | PS1 | DuckStation; RA: swanstation, beetle_psx | .cue .chd .bin .m3u .pbp |
| ps2 | PS2 | PCSX2; Play!; RA: pcsx2 | .iso .chd .cso .bin |
| psp | PSP | PPSSPP; RA: ppsspp | .iso .cso .chd .pbp |
| ps3 | PS3 | RPCS3 (RA: —) | .iso .pkg |
| genesis | Genesis | ares; RA: genesis_plus_gx, blastem | .md .smd .gen .bin |
| saturn | Saturn | Mednafen; RA: beetle_saturn, kronos | .cue .chd .m3u .ccd |
| dreamcast | Dreamcast | Flycast; Redream; RA: flycast | .cdi .chd .gdi .cue |
| arcade | Arcade | MAME; RA: fbneo, mame | .zip |
| dos | DOS | DOSBox; RA: dosbox_pure | .exe .bat .conf .dosz |
| wiiu | Wii U | Cemu (RA: —) | .wua .wud .wux .rpx |
| switch | Switch | Ryujinx (RA: —) | .nsp .xci .nro .nca |

**`SystemDatabase` API:**

```swift
/// A selectable way to run a platform, before checking what's installed.
struct EmulatorOption: Equatable, Hashable {
    let choice: EmulatorChoice      // .standalone(type) or .retroArchCore(core)
    let displayName: String         // "Snes9x" or "bsnes (RetroArch)"
}

final class SystemDatabase {
    init(bundle: Bundle = .resolved)        // loads & validates emulators.json
    func platform(forFolderName name: String) -> Platform?    // PRIMARY signal
    func platforms(forExtension ext: String) -> [Platform]    // secondary signal
    func emulatorOptions(for platform: Platform) -> [EmulatorOption]   // ordered, all known
    func argsTemplate(for choice: EmulatorChoice) -> String  // standalone emu template,
                                                             // or RetroArch's {core} template
    var allRomExtensions: Set<String> { get }
}
```

`Platform` is a struct decoded from JSON (`id`, `displayName`, …), `Equatable`/`Hashable`.

**Tests (acceptance):**
- JSON loads under `swift test` (via `Bundle.resolved`).
- Drift check: every `standalone` option and `emulators[]` id maps to a real `EmulatorType`.
- `platform(forFolderName: "Super Nintendo")` → snes (case-insensitive, alias match).
- `platforms(forExtension: ".iso")` returns the multiple collision candidates (gamecube, wii,
  ps2, psp, ps3) — proving collisions are surfaced, not hidden.
- `emulatorOptions(for: snes)` returns the ordered list including both standalone and core
  options; `emulatorOptions(for: wiiu)` contains **no** RetroArch option.
- `argsTemplate(for: .retroArchCore(...))` contains `{core}`; `argsTemplate(for:
  .standalone(.snes9x))` does not.

**🔍 REVIEW CHECKPOINT 1 — after A1+A2.** Hand back: the model, the parser, the JSON DB, and
their tests. This validates the foundational data shapes before the scanner/UI depend on them.

---

### Phase A3 — `ROMScanner` with folder-first platform inference

**Goal:** walk a directory, identify ROMs, and assign each a platform. **Platform inference
priority is the key design decision here.**

**Files:**
- `Scanner/ROMScanner.swift` (new)
- `RomShortcutMakerTests/ROMScannerTests.swift` (new)

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

**RetroArch cores must be enumerated too.** When RetroArch is detected (or its path is
configured), scan its cores directory (`coresDir`, default
`…/RetroArch.app/Contents/Resources/cores`, also `~/Library/Application Support/RetroArch/cores`)
for `*_libretro.dylib` files. Expose the set of installed core filenames:

```swift
func detectAll() -> [EmulatorType: [URL]]   // standalone + the RetroArch app itself
func installedRetroArchCores() -> Set<String>   // e.g. ["snes9x_libretro.dylib", ...]
```

A `retroArchCore` option is "available" only when **RetroArch is installed AND that core file
is present**. This is what keeps the UI from offering cores the user can't actually run.

> **Detection bug to avoid:** the existing `ShortcutFilter` matches emulator patterns with
> substring `contains`, which false-matches (`"ares"` in "software", `"fuse"` in "confuser",
> `"b2"`, `"clk"`). For the new detector, match on the **executable basename equal to or
> word-bounded by** the pattern (e.g. exact stem match, or stem with known suffixes like
> `-emu`, version numbers). Add tests proving `"software"` does not match `ares` and
> `"RetroArch"` does match `retroarch`.

**`EmulatorConfigManager` spec:** persists the `emulators` and `emulatorDefaults` blocks of
`config.json` v2 (see §3). Per-emulator: `path`, `args`, `enabled`, plus RetroArch's `coresDir`.
Per-platform default choices live in `emulatorDefaults`. Provides the `availableOptions(for:)` /
`defaultChoice(for:)` resolution above, and given a resolved `EmulatorChoice` returns the
`emulatorPath`, `argsTemplate`, and (for a `retroArchCore` choice) the `{core}` `.dylib` path
(from `coresDir` + core filename). Injected `ConfigurationManager` + `EmulatorDetector`.

**Emulator resolution flow** (used by the scan → entry mapping). The `EmulatorConfigManager`
exposes:

```swift
// All options for a platform that the user can actually run right now.
func availableOptions(for platform: Platform) -> [EmulatorOption]
// The choice to assign automatically: per-platform default if set, else first available.
func defaultChoice(for platform: Platform) -> EmulatorChoice?
```

1. Start from `database.emulatorOptions(for: platform)` (ordered, all known).
2. Filter to **available** = standalone emulator detected + enabled, OR RetroArch installed +
   that core present + enabled. This is `availableOptions(for:)`.
3. Assign `defaultChoice(for:)`: the user's **per-platform default** if one is set in config
   (`emulatorDefaults`, see §3), otherwise the first available option.
4. Zero available → `emulator = nil` (UI shows a "No emulator installed" badge with guidance;
   entry isn't generatable until resolved).
5. The user overrides **per-game** (picks any available option for that ROM) or sets/changes the
   **per-platform default** (applies to all games of that platform that haven't been overridden).

**Tests (acceptance):** strict matching (no false positives, e.g. "software" ✗ `ares`, "RetroArch"
✓ `retroarch`); detection of an `.app` via a faked `Info.plist`; RetroArch core enumeration from
a faked cores dir; `availableOptions` includes both a standalone and an installed core, and
**excludes** a core whose file is absent; `defaultChoice` honors a configured per-platform
default and otherwise falls back to first-available; platform with nothing installed yields
`nil`, not a crash.

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
  | `exe` (+ `LaunchCommandParser`) | `emulatorPath`, `emulator = .standalone(detectedType)` (a VDF shortcut already points at one concrete executable) |
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
  inline-editable title (persists to `gameOverrides` by `stableKey`); platform badge; **emulator
  dropdown listing every *available* option for the platform** — each standalone emulator and
  each installed RetroArch core as a separate, labeled entry (e.g. "Snes9x", "bsnes",
  "Snes9x (RetroArch)", "bsnes (RetroArch)"); shows "No emulator installed" when none are
  available; selecting one sets a per-game override. Truncated ROM path (full in tooltip);
  artwork status indicator (✓ cached / ↓ pending / — none / ⚠ failed, click to retry);
  **ambiguous-platform badge** with a platform picker when `platformAmbiguous`.
- **Artwork tab:** "Fetch Missing", "Re-fetch All", per-game search popover (SGDB results as
  thumbs), "Use Local Image…", drag-and-drop onto a row, 256×256 preview. Downloads are
  **bounded-concurrency** and respect the 1 req/s throttle.
- **Generate tab:** output dir picker, bundle-name preview, "Remove orphaned bundles" toggle,
  progress, summary panel ("Created 12, Updated 3, Skipped 5, Removed 1, 2 errors").
- **Settings tab:** SGDB API key (secure field) + "Get API Key" link; per-emulator path/args/
  enabled + "Auto-detect All" + "Add Custom"; RetroArch path + cores dir; **a per-platform
  "default emulator" picker** (lists available options for each platform; sets
  `emulatorDefaults` so all non-overridden games of that platform use it); artwork cache size +
  "Clear Cache"; "Import from Steam shortcuts.vdf"; default output dir.

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
                  "coresDir": "/Applications/RetroArch.app/Contents/Resources/cores" }
  },
  "emulatorDefaults": {
    "snes": { "type": "standalone",    "emulator": "Snes9x" },
    "gba":  { "type": "retroArchCore", "core": "mgba_libretro.dylib" }
  },
  "gameOverrides": {
    "<stableKey>": {
      "customTitle": "Chrono Trigger",
      "emulator": { "type": "standalone", "emulator": "Snes9x" },
      "args": null,
      "platform": "snes"
    }
  },
  "lastConversionDate": "2026-06-04T12:00:00Z"
}
```

- `emulatorDefaults` is keyed by **platform id** and stores the user's per-platform default
  `EmulatorChoice` (encoded as a tagged object: `standalone`+`emulator`, or `retroArchCore`+
  `core`). Applied to every game of that platform that has no per-game override.
- `gameOverrides` is keyed by `stableKey` (ROM-path hash), **not** UUID or Steam appID. Its
  `emulator` field is a per-game `EmulatorChoice` override (same tagged encoding).

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
