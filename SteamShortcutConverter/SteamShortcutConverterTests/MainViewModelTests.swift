//
//  MainViewModelTests.swift
//  SteamShortcutConverterTests
//
//  Tests for the rewritten (DI, ROM-pipeline) MainViewModel using fakes — no
//  real Steam access, network, or GUI.
//

import XCTest
@testable import SteamShortcutConverter

// MARK: - Fakes

final class FakeROMScanner: ROMScanning {
    var result: [DiscoveredROM]
    private(set) var scanCallCount = 0
    init(_ result: [DiscoveredROM]) { self.result = result }
    func scan(directory: URL, progress: @escaping (Double) -> Void) async throws -> [DiscoveredROM] {
        scanCallCount += 1
        progress(1.0)
        return result
    }
}

final class FakeArtworkProvider: ArtworkProvider {
    let match: SGDBGame
    private(set) var searchCallCount = 0
    init(match: SGDBGame = SGDBGame(id: 99, name: "Best Match")) { self.match = match }
    func searchGame(term: String) async throws -> [SGDBGame] {
        searchCallCount += 1
        return [match]
    }
    func getIcons(gameId: Int) async throws -> [SGDBImage] {
        [SGDBImage(id: 11, url: URL(string: "https://x/icon.png")!, thumb: nil, score: 5, mime: "image/png")]
    }
    func getGrids(gameId: Int) async throws -> [SGDBImage] { [] }
    func downloadImage(url: URL) async throws -> Data { Data([0x89, 0x50, 0x4E, 0x47]) }
}

final class FakeGameBundleGenerator: GameBundleGenerating {
    private(set) var generatedCount = 0
    func generateAppBundle(for game: ResolvedGameBundle) async throws -> URL {
        generatedCount += 1
        let url = game.outputDirectory.appendingPathComponent(game.bundleName + ".app")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@MainActor
final class MainViewModelTests: XCTestCase {

    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VMTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    // MARK: - Builders

    private func snesROM(_ path: String) -> DiscoveredROM {
        DiscoveredROM(
            url: URL(fileURLWithPath: path),
            fileSize: 10,
            romExtension: ".sfc",
            platform: Platform(id: "snes", displayName: "SNES"),
            candidateEmulators: [.snes9x],
            platformAmbiguous: false
        )
    }

    private func makeViewModel(
        roms: [DiscoveredROM],
        store: InMemoryRomConfigStore = InMemoryRomConfigStore(),
        provider: ArtworkProvider? = nil,
        generator: GameBundleGenerating? = nil,
        scanner: FakeROMScanner? = nil
    ) -> MainViewModel {
        let database = try! SystemDatabase()
        let fs = FakeAppDiscovering()
        let appsDir = URL(fileURLWithPath: "/FakeApps")
        fs.appsByDir[appsDir.path] = [
            appsDir.appendingPathComponent("Snes9x.app"),
            appsDir.appendingPathComponent("RetroArch.app")
        ]
        let detector = EmulatorDetector(
            database: database, fs: fs,
            appSearchDirectories: [appsDir], binSearchDirectories: [],
            extraCoreDirectories: [], extraInfoDirectories: [])
        let emulatorConfig = EmulatorConfigManager(
            database: database, detector: detector, store: InMemoryEmulatorConfigStore())
        let viewModel = MainViewModel(
            database: database,
            configStore: store,
            scanner: scanner ?? FakeROMScanner(roms),
            emulatorConfig: emulatorConfig,
            artworkCache: ArtworkCache(baseDirectory: tempDir.appendingPathComponent("artcache")),
            artworkProvider: provider,
            bundleGenerator: generator ?? FakeGameBundleGenerator(),
            vdfBridge: VDFToGameEntryBridge(database: database),
            playlistManager: PlaylistManager(directory: tempDir.appendingPathComponent("playlists"))
        )
        // The fake scanner ignores the directory, but scan() guards on it.
        viewModel.scanDirectory = "/ROMs"
        return viewModel
    }

    private func multiDiscROM(discs: [String]) -> DiscoveredROM {
        let urls = discs.map { URL(fileURLWithPath: $0) }
        return DiscoveredROM(
            url: urls[0],
            fileSize: 10,
            romExtension: ".chd",
            platform: Platform(id: "ps1", displayName: "PS1"),
            candidateEmulators: [.duckstation],
            platformAmbiguous: false,
            memberFiles: urls,
            alternateImages: [],
            discPaths: urls
        )
    }

    // MARK: - Load

    func testLoadAppliesConfig() async {
        let config = AppConfigurationV2(outputDirectory: "/tmp/out", removeOrphanedBundles: true, steamGridDBApiKey: "abc")
        let vm = makeViewModel(roms: [], store: InMemoryRomConfigStore(config: config))
        await vm.load()
        XCTAssertEqual(vm.outputDirectory, "/tmp/out")
        XCTAssertTrue(vm.removeOrphanedBundles)
        XCTAssertEqual(vm.steamGridDBApiKey, "abc")
    }

    /// A persisted scan directory that exists on disk should be rescanned on
    /// `load()` so the list isn't empty after relaunch — exactly one scan.
    func testLoadRescansPersistedDirectory() async throws {
        let dir = tempDir.appendingPathComponent("library")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = AppConfigurationV2(sourceMode: "scan", lastScanDirectory: dir.path)
        let scanner = FakeROMScanner([snesROM("/ROMs/SNES/Zelda.sfc")])
        let vm = makeViewModel(roms: [], store: InMemoryRomConfigStore(config: config), scanner: scanner)
        await vm.load()
        XCTAssertEqual(scanner.scanCallCount, 1)
        XCTAssertEqual(vm.games.count, 1)
    }

    /// A missing persisted directory must not trigger a scan (and must not crash).
    func testLoadDoesNotRescanMissingDirectory() async {
        let config = AppConfigurationV2(sourceMode: "scan", lastScanDirectory: "/no/such/dir")
        let scanner = FakeROMScanner([snesROM("/ROMs/SNES/Zelda.sfc")])
        let vm = makeViewModel(roms: [], store: InMemoryRomConfigStore(config: config), scanner: scanner)
        await vm.load()
        XCTAssertEqual(scanner.scanCallCount, 0)
        XCTAssertTrue(vm.games.isEmpty)
    }

    /// Un-checking a game persists as an `excluded` override and survives a rescan.
    func testDeselectionSurvivesRescan() async {
        let store = InMemoryRomConfigStore()
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")], store: store)
        await vm.scan()
        vm.setSelected(false, for: vm.games[0])
        XCTAssertEqual(vm.currentConfiguration.gameOverrides[vm.games[0].stableKey]?.excluded, true)
        await vm.scan()
        XCTAssertFalse(vm.games[0].isSelected, "exclusion persists across a rescan")
    }

    // MARK: - Scan

    func testScanPopulatesGames() async {
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Chrono Trigger (USA).sfc")])
        await vm.scan()
        XCTAssertEqual(vm.games.count, 1)
        XCTAssertEqual(vm.games.first?.title, "Chrono Trigger")
        XCTAssertEqual(vm.games.first?.platform.id, "snes")
    }

    func testScanAssignsDefaultEmulator() async {
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")])
        await vm.scan()
        XCTAssertEqual(vm.games.first?.emulator, .standalone(.snes9x))
        XCTAssertNotNil(vm.games.first?.emulatorPath)
    }

    // MARK: - Overrides persist

    func testSetTitlePersistsOverride() async {
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")])
        await vm.scan()
        let game = vm.games[0]
        vm.setTitle("Custom Zelda", for: game)
        XCTAssertEqual(vm.games[0].title, "Custom Zelda")
        XCTAssertEqual(vm.currentConfiguration.gameOverrides[game.stableKey]?.customTitle, "Custom Zelda")
    }

    func testSelectionToggle() async {
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")])
        await vm.scan()
        let game = vm.games[0]
        vm.setSelected(false, for: game)
        XCTAssertFalse(vm.games[0].isSelected)
    }

    // MARK: - Generate

    func testGenerateSummaryCounts() async {
        let generator = FakeGameBundleGenerator()
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")], generator: generator)
        await vm.scan()
        vm.outputDirectory = tempDir.path
        await vm.generate()
        XCTAssertEqual(vm.conversionSummary?.bundlesCreated, 1)
        XCTAssertEqual(generator.generatedCount, 1)
    }

    func testGenerateSkipsUnchangedOnSecondRun() async {
        let store = InMemoryRomConfigStore()
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")], store: store)
        await vm.scan()
        vm.outputDirectory = tempDir.path
        await vm.generate()
        XCTAssertEqual(vm.conversionSummary?.bundlesCreated, 1)
        // Second run: nothing changed, bundle exists on disk → skipped.
        await vm.generate()
        XCTAssertEqual(vm.conversionSummary?.bundlesSkipped, 1)
        XCTAssertEqual(vm.conversionSummary?.bundlesCreated, 0)
    }

    // MARK: - Artwork

    func testFetchArtworkCachesAndMarksCached() async {
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")], provider: FakeArtworkProvider())
        await vm.scan()
        await vm.fetchArtwork(for: vm.games[0])
        if case .cached = vm.games[0].artworkStatus {
            // expected
        } else {
            XCTFail("expected cached artwork, got \(vm.games[0].artworkStatus)")
        }
    }

    /// Auto-fetch records the match id/name and adopts the SGDB name as the title
    /// when the game has no custom title yet.
    func testAutoFetchRecordsMatchAndAppliesName() async {
        let provider = FakeArtworkProvider(match: SGDBGame(id: 77, name: "Chrono Trigger"))
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/ct.sfc")], provider: provider)
        await vm.scan()
        let key = vm.games[0].stableKey
        await vm.fetchArtwork(for: vm.games[0])
        XCTAssertEqual(provider.searchCallCount, 1)
        XCTAssertEqual(vm.currentConfiguration.gameOverrides[key]?.sgdbGameId, 77)
        XCTAssertEqual(vm.currentConfiguration.gameOverrides[key]?.sgdbGameName, "Chrono Trigger")
        XCTAssertEqual(vm.games[0].title, "Chrono Trigger", "SGDB name adopted as title")
        XCTAssertEqual(vm.matchedGameName(for: vm.games[0]), "Chrono Trigger")
    }

    /// Auto-fetch must never overwrite a user's custom title, though it still
    /// records the match.
    func testAutoFetchDoesNotStompCustomTitle() async {
        let provider = FakeArtworkProvider(match: SGDBGame(id: 77, name: "SGDB Name"))
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/ct.sfc")], provider: provider)
        await vm.scan()
        vm.setTitle("My Custom", for: vm.games[0])
        let key = vm.games[0].stableKey
        await vm.fetchArtwork(for: vm.games[0])
        XCTAssertEqual(vm.games[0].title, "My Custom", "custom rename preserved")
        XCTAssertEqual(vm.currentConfiguration.gameOverrides[key]?.sgdbGameId, 77)
    }

    /// A pinned match id makes fetch go straight to the id — no title search.
    func testFetchHonorsPinnedMatchIdWithoutSearching() async {
        let provider = FakeArtworkProvider()
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")], provider: provider)
        await vm.scan()
        await vm.applyManualMatch(SGDBGame(id: 5, name: "Manual"), setTitle: false, for: vm.games[0])
        XCTAssertEqual(provider.searchCallCount, 0, "manual match skips the title search")
        XCTAssertEqual(vm.currentConfiguration.gameOverrides[vm.games[0].stableKey]?.sgdbGameId, 5)
        // A subsequent plain fetch also honors the pinned id.
        await vm.fetchArtwork(for: vm.games[0])
        XCTAssertEqual(provider.searchCallCount, 0)
    }

    /// applyManualMatch with setTitle overwrites an existing custom title and
    /// persists both match fields.
    func testApplyManualMatchOverwritesTitle() async {
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")], provider: FakeArtworkProvider())
        await vm.scan()
        vm.setTitle("Old", for: vm.games[0])
        await vm.applyManualMatch(SGDBGame(id: 3, name: "New Name"), setTitle: true, for: vm.games[0])
        let key = vm.games[0].stableKey
        XCTAssertEqual(vm.games[0].title, "New Name")
        XCTAssertEqual(vm.currentConfiguration.gameOverrides[key]?.sgdbGameId, 3)
        XCTAssertEqual(vm.currentConfiguration.gameOverrides[key]?.sgdbGameName, "New Name")
    }

    /// Clearing a match removes both match fields.
    func testClearManualMatchRemovesFields() async {
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")], provider: FakeArtworkProvider())
        await vm.scan()
        await vm.applyManualMatch(SGDBGame(id: 3, name: "X"), setTitle: false, for: vm.games[0])
        let key = vm.games[0].stableKey
        XCTAssertNotNil(vm.currentConfiguration.gameOverrides[key]?.sgdbGameId)
        vm.clearManualMatch(for: vm.games[0])
        XCTAssertNil(vm.currentConfiguration.gameOverrides[key]?.sgdbGameId)
        XCTAssertNil(vm.currentConfiguration.gameOverrides[key]?.sgdbGameName)
    }

    // MARK: - PS3 hints

    /// A scanner title hint (PARAM.SFO TITLE) beats the filename-derived title,
    /// and a bundled ICON0.PNG gets seeded into the artwork cache.
    func testPS3TitleHintAndArtworkSeeding() async throws {
        let icon = tempDir.appendingPathComponent("ICON0.PNG")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: icon)
        let ps3ROM = DiscoveredROM(
            url: URL(fileURLWithPath: "/ROMs/PS3/Odin Sphere/PS3_GAME/USRDIR/EBOOT.BIN"),
            fileSize: 10,
            romExtension: ".bin",
            platform: Platform(id: "ps3", displayName: "PS3"),
            candidateEmulators: [.rpcs3],
            platformAmbiguous: false,
            titleHint: "Odin Sphere Leifthrasir",
            artworkHint: icon
        )
        let vm = makeViewModel(roms: [ps3ROM])
        await vm.scan()
        XCTAssertEqual(vm.games.count, 1)
        XCTAssertEqual(vm.games[0].title, "Odin Sphere Leifthrasir", "hint wins over 'EBOOT'")
        guard case .cached = vm.games[0].artworkStatus else {
            return XCTFail("expected seeded artwork, got \(vm.games[0].artworkStatus)")
        }
        XCTAssertTrue(vm.hasArtwork(vm.games[0]))
    }

    /// A missing hint file is non-fatal: the scan succeeds, artwork stays absent.
    func testMissingArtworkHintIsSkippedSilently() async {
        let ps3ROM = DiscoveredROM(
            url: URL(fileURLWithPath: "/ROMs/PS3/X/PS3_GAME/USRDIR/EBOOT.BIN"),
            fileSize: 10,
            romExtension: ".bin",
            platform: Platform(id: "ps3", displayName: "PS3"),
            candidateEmulators: [.rpcs3],
            platformAmbiguous: false,
            titleHint: "X",
            artworkHint: URL(fileURLWithPath: "/no/such/ICON0.PNG")
        )
        let vm = makeViewModel(roms: [ps3ROM])
        await vm.scan()
        XCTAssertEqual(vm.games.count, 1)
        if case .cached = vm.games[0].artworkStatus {
            XCTFail("nothing should have been seeded from a missing file")
        }
    }

    // MARK: - Multi-disc

    func testMultiDiscScanGeneratesPlaylist() async {
        let vm = makeViewModel(roms: [multiDiscROM(discs: [
            "/ROMs/PSX/FF7/FF7 (Disc 1).chd",
            "/ROMs/PSX/FF7/FF7 (Disc 2).chd",
            "/ROMs/PSX/FF7/FF7 (Disc 3).chd"
        ])])
        await vm.scan()
        XCTAssertEqual(vm.games.count, 1)
        XCTAssertEqual(vm.games[0].romPath.pathExtension, "m3u", "multi-disc game launches via a generated playlist")
        XCTAssertEqual(vm.games[0].additionalFiles.count, 3)
    }

    // MARK: - Reset (un-skipped, hermetic)

    func testResetConfiguration() async {
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")])
        await vm.scan()
        vm.outputDirectory = "/some/output"
        vm.removeOrphanedBundles = true
        vm.lastConversionDate = Date()

        await vm.resetConfiguration()

        XCTAssertTrue(vm.outputDirectory.isEmpty)
        XCTAssertFalse(vm.removeOrphanedBundles)
        XCTAssertNil(vm.lastConversionDate)
        XCTAssertTrue(vm.games.isEmpty)
    }

    // MARK: - ConversionSummary value type

    func testConversionSummaryTotals() {
        let summary = ConversionSummary(bundlesCreated: 5, bundlesUpdated: 3, bundlesSkipped: 2, bundlesRemoved: 1)
        XCTAssertEqual(summary.totalBundles, 8)
        XCTAssertFalse(summary.hasIssues)
    }

    // MARK: - Grouping & sorting

    private func rom(platformID: String, display: String, path: String) -> DiscoveredROM {
        DiscoveredROM(
            url: URL(fileURLWithPath: path),
            fileSize: 10,
            romExtension: ".sfc",
            platform: Platform(id: platformID, displayName: display),
            candidateEmulators: [.snes9x],
            platformAmbiguous: false
        )
    }

    func testGroupedGamesSortsPlatformsAndTitles() async {
        let vm = makeViewModel(roms: [
            rom(platformID: "snes", display: "SNES", path: "/ROMs/SNES/Super Metroid.sfc"),
            rom(platformID: "snes", display: "SNES", path: "/ROMs/SNES/Chrono Trigger.sfc"),
            rom(platformID: "gb", display: "Game Boy", path: "/ROMs/GB/Tetris.gb")
        ])
        await vm.scan()
        let grouped = vm.groupedGames
        // Platforms alphabetical by display name: "Game Boy" before "SNES".
        XCTAssertEqual(grouped.map { $0.platform.displayName }, ["Game Boy", "SNES"])
        // Titles sorted within a group.
        let snes = grouped.first { $0.platform.id == "snes" }!
        XCTAssertEqual(snes.games.map { $0.title }, ["Chrono Trigger", "Super Metroid"])
    }

    func testGroupedGamesPutsUnknownLast() async {
        // A nil-platform ROM becomes the "unknown" bucket in makeEntry.
        let unknown = DiscoveredROM(
            url: URL(fileURLWithPath: "/ROMs/mystery.bin"),
            fileSize: 10, romExtension: ".bin",
            platform: nil, candidateEmulators: [], platformAmbiguous: true)
        let vm = makeViewModel(roms: [
            rom(platformID: "snes", display: "SNES", path: "/ROMs/SNES/Zelda.sfc"),
            unknown
        ])
        await vm.scan()
        XCTAssertEqual(vm.groupedGames.count, 2)
        XCTAssertEqual(vm.groupedGames.last?.platform.id, "unknown")
    }

    // MARK: - GameStatus

    func testStatusReadyWhenEmulatorAssigned() async {
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")])
        await vm.scan()
        XCTAssertEqual(vm.games[0].status, .ready)
        XCTAssertEqual(vm.needsAttentionCount, 0)
    }

    func testStatusUnknownPlatform() {
        let entry = GameEntry(
            title: "Mystery",
            romPath: URL(fileURLWithPath: "/ROMs/mystery.bin"),
            romMetadata: ROMMetadata(rawFilename: "mystery.bin", title: "Mystery"),
            platform: Platform(id: "unknown", displayName: "Unknown"))
        XCTAssertEqual(entry.status, .unknownPlatform)
    }

    func testStatusNoEmulatorForKnownPlatform() {
        let entry = GameEntry(
            title: "Zelda",
            romPath: URL(fileURLWithPath: "/ROMs/SNES/Zelda.sfc"),
            romMetadata: ROMMetadata(rawFilename: "Zelda.sfc", title: "Zelda"),
            platform: Platform(id: "snes", displayName: "SNES"),
            emulator: nil)
        XCTAssertEqual(entry.status, .noEmulator)
    }

    // MARK: - Collapsed-state persistence

    func testToggleCollapsedPersists() async {
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")])
        await vm.scan()
        vm.toggleCollapsed("snes")
        XCTAssertTrue(vm.collapsedPlatforms.contains("snes"))
        XCTAssertTrue(vm.currentConfiguration.collapsedPlatforms.contains("snes"),
                      "toggling writes the collapsed set into the config that gets persisted")
        vm.toggleCollapsed("snes")
        XCTAssertFalse(vm.collapsedPlatforms.contains("snes"))
        XCTAssertFalse(vm.currentConfiguration.collapsedPlatforms.contains("snes"))
    }

    /// The custom decoder must default `collapsedPlatforms` to empty when loading
    /// an on-disk config that predates the field, rather than failing to decode.
    func testConfigDecodesWithoutCollapsedPlatformsField() throws {
        let legacyJSON = """
        {"version":2,"sourceMode":"scan","removeOrphanedBundles":false}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfigurationV2.self, from: legacyJSON)
        XCTAssertEqual(decoded.collapsedPlatforms, [])
        XCTAssertEqual(decoded.version, 2)
    }

    // MARK: - Args override round-trip

    func testSetArgsTemplatePersistsAndResets() async {
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")])
        await vm.scan()
        let game = vm.games[0]
        let original = game.argsTemplate

        vm.setArgsTemplate("{emulator} --fullscreen {rom}", for: game)
        XCTAssertEqual(vm.games[0].argsTemplate, "{emulator} --fullscreen {rom}")
        XCTAssertEqual(vm.currentConfiguration.gameOverrides[game.stableKey]?.args,
                       "{emulator} --fullscreen {rom}")
        XCTAssertTrue(vm.hasOverride(.args, for: vm.games[0]))

        // Reset restores the emulator default and drops the override.
        vm.resetOverride(.args, for: vm.games[0])
        XCTAssertEqual(vm.games[0].argsTemplate, original)
        XCTAssertFalse(vm.hasOverride(.args, for: vm.games[0]))
        XCTAssertNil(vm.currentConfiguration.gameOverrides[game.stableKey]?.args)
    }

    func testSetArgsTemplateEmptyClearsOverride() async {
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")])
        await vm.scan()
        let game = vm.games[0]
        vm.setArgsTemplate("{emulator} {rom}", for: game)
        XCTAssertTrue(vm.hasOverride(.args, for: vm.games[0]))
        vm.setArgsTemplate("", for: vm.games[0])
        XCTAssertFalse(vm.hasOverride(.args, for: vm.games[0]))
    }

    // MARK: - Custom artwork override

    func testSetCustomArtworkCachesAndRemoves() async throws {
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")])
        await vm.scan()
        let game = vm.games[0]

        // A tiny real PNG on disk to import as custom artwork.
        let pngURL = tempDir.appendingPathComponent("cover.png")
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try rep.representation(using: .png, properties: [:])!.write(to: pngURL)

        vm.setCustomArtwork(url: pngURL, for: game)
        guard case .cached = vm.games[0].artworkStatus else {
            return XCTFail("expected cached artwork after setting a custom file")
        }
        XCTAssertTrue(vm.hasArtwork(vm.games[0]))

        vm.removeArtwork(for: vm.games[0])
        XCTAssertFalse(vm.hasArtwork(vm.games[0]))
        if case .cached = vm.games[0].artworkStatus {
            XCTFail("artwork should be cleared after removeArtwork")
        }
    }

    // MARK: - Generation preview

    func testPreviewCountsNewGamesAsCreate() async {
        let vm = makeViewModel(roms: [
            snesROM("/ROMs/SNES/Zelda.sfc"),
            snesROM("/ROMs/SNES/Metroid.sfc")
        ])
        await vm.scan()
        let preview = await vm.previewChanges()
        XCTAssertEqual(preview.created, 2)
        XCTAssertEqual(preview.updated, 0)
        XCTAssertEqual(preview.unchanged, 0)
    }

    func testPreviewCountsUnchangedAfterGenerate() async {
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")])
        await vm.scan()
        vm.outputDirectory = tempDir.path
        await vm.generate()
        let preview = await vm.previewChanges()
        XCTAssertEqual(preview.created, 0)
        XCTAssertEqual(preview.unchanged, 1, "an already-generated, unchanged game is a skip")
    }

    func testPreviewExcludesUnselectedGames() async {
        let vm = makeViewModel(roms: [
            snesROM("/ROMs/SNES/Zelda.sfc"),
            snesROM("/ROMs/SNES/Metroid.sfc")
        ])
        await vm.scan()
        vm.setSelected(false, for: vm.games[0])
        let preview = await vm.previewChanges()
        XCTAssertEqual(preview.created, 1, "only the still-selected game counts")
    }

    // MARK: - Scale

    func testGroupedGamesHandles500Entries() async {
        let platforms = [
            ("snes", "SNES"), ("gb", "Game Boy"), ("ps1", "PlayStation"),
            ("n64", "Nintendo 64"), ("genesis", "Genesis")
        ]
        var roms: [DiscoveredROM] = []
        for i in 0..<500 {
            let (id, name) = platforms[i % platforms.count]
            roms.append(DiscoveredROM(
                url: URL(fileURLWithPath: "/ROMs/\(id)/Game \(String(format: "%03d", i)).rom"),
                fileSize: 10, romExtension: ".rom",
                platform: Platform(id: id, displayName: name),
                candidateEmulators: [], platformAmbiguous: false))
        }
        let vm = makeViewModel(roms: roms)
        await vm.scan()
        XCTAssertEqual(vm.games.count, 500)

        let grouped = vm.groupedGames
        XCTAssertEqual(grouped.count, platforms.count)
        XCTAssertEqual(grouped.reduce(0) { $0 + $1.games.count }, 500)
        // Platforms alphabetical by display name.
        XCTAssertEqual(grouped.map { $0.platform.displayName },
                       ["Game Boy", "Genesis", "Nintendo 64", "PlayStation", "SNES"])
        // Titles sorted (natural order) within a group.
        let first = grouped[0].games.map { $0.title }
        XCTAssertEqual(first, first.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    // MARK: - Reset all overrides

    func testResetOverridesRestoresDefaults() async {
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")])
        await vm.scan()
        let game = vm.games[0]
        let defaultTitle = game.title

        vm.setTitle("Custom", for: game)
        vm.setArgsTemplate("{emulator} --x {rom}", for: vm.games[0])
        XCTAssertTrue(vm.anyOverrides(vm.games[0]))

        vm.resetOverrides(for: vm.games[0])
        XCTAssertEqual(vm.games[0].title, defaultTitle)
        XCTAssertFalse(vm.anyOverrides(vm.games[0]))
        XCTAssertNil(vm.currentConfiguration.gameOverrides[game.stableKey])
    }
}
