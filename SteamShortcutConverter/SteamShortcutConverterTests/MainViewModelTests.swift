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
    enum Failure: Error { case unavailable }

    var result: [DiscoveredROM]
    var resultsByDirectory: [String: [DiscoveredROM]] = [:]
    var failingDirectories: Set<String> = []
    private(set) var scanCallCount = 0
    private(set) var scannedDirectories: [String] = []
    init(_ result: [DiscoveredROM]) { self.result = result }
    func scan(directory: URL, progress: @escaping (Double) -> Void) async throws -> [DiscoveredROM] {
        scanCallCount += 1
        scannedDirectories.append(directory.standardizedFileURL.path)
        if failingDirectories.contains(directory.standardizedFileURL.path) {
            throw Failure.unavailable
        }
        progress(1.0)
        return resultsByDirectory[directory.standardizedFileURL.path] ?? result
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

final class MultipleArtworkProvider: ArtworkProvider {
    private(set) var downloadedURL: URL?

    func searchGame(term: String) async throws -> [SGDBGame] {
        [SGDBGame(id: 7, name: "Matched Game")]
    }

    func getIcons(gameId: Int) async throws -> [SGDBImage] {
        [
            SGDBImage(id: 1, url: URL(string: "https://x/low.png")!, thumb: nil, score: 1, mime: "image/png"),
            SGDBImage(id: 2, url: URL(string: "https://x/high.png")!, thumb: nil, score: 9, mime: "image/png")
        ]
    }

    func getGrids(gameId: Int) async throws -> [SGDBImage] {
        [SGDBImage(id: 3, url: URL(string: "https://x/grid.jpg")!, thumb: nil, score: 5, mime: "image/jpeg")]
    }

    func downloadImage(url: URL) async throws -> Data {
        downloadedURL = url
        return Data([0x89, 0x50, 0x4E, 0x47])
    }
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

final class CountingRomConfigStore: RomConfigStore {
    private let lock = NSLock()
    private var config: AppConfigurationV2 = .default
    private var state: GameConversionState?
    private var saves = 0

    var saveCount: Int { withLock { saves } }

    func resetSaveCount() {
        withLock { saves = 0 }
    }

    func load() async throws -> AppConfigurationV2 { withLock { config } }

    func save(_ config: AppConfigurationV2) async throws {
        withLock {
            self.config = config
            saves += 1
        }
    }

    func loadGameState() async throws -> GameConversionState? { withLock { state } }

    func saveGameState(_ state: GameConversionState) async throws {
        withLock { self.state = state }
    }

    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
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

    private func unknownROM(_ path: String, fileSize: Int64 = 10) -> DiscoveredROM {
        let url = URL(fileURLWithPath: path)
        return DiscoveredROM(
            url: url,
            fileSize: fileSize,
            romExtension: ".mds",
            platform: nil,
            candidateEmulators: [],
            platformAmbiguous: false,
            detection: PlatformDetectionInfo(
                fileExtension: ".mds",
                candidates: [],
                evidence: ["Extension .mds has no platform mapping."],
                resolvedBy: nil,
                sourceDirectory: url.deletingLastPathComponent()
            )
        )
    }

    private func dosFolderROM(_ path: String, selected: String? = nil, issue: String? = nil) -> DiscoveredROM {
        let folder = URL(fileURLWithPath: path)
        let one = folder.appendingPathComponent("ONE.EXE")
        let two = folder.appendingPathComponent("TWO.EXE")
        return DiscoveredROM(
            url: folder,
            fileSize: 20,
            romExtension: "",
            platform: Platform(id: "dos", displayName: "DOS"),
            candidateEmulators: [.dosbox],
            platformAmbiguous: false,
            memberFiles: [one, two],
            titleHint: folder.lastPathComponent,
            dosPackage: DOSPackageInfo(
                kind: .folder,
                launchCandidates: [
                    DOSLaunchCandidate(url: one, kind: .program),
                    DOSLaunchCandidate(url: two, kind: .program)
                ],
                utilityCandidates: [],
                mediaFiles: [],
                memberCount: 2,
                archiveExecutableCount: nil,
                configurationHasAutoexec: nil,
                blockingIssue: issue,
                warning: nil,
                selectedLaunchURL: selected.map { folder.appendingPathComponent($0) }
            )
        )
    }

    private func makeViewModel(
        roms: [DiscoveredROM],
        store: RomConfigStore = InMemoryRomConfigStore(),
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
        viewModel.watchedFolders = ["/ROMs"]
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

    /// Persisted watched folders should be rescanned on load so the list is not
    /// empty after relaunch.
    func testLoadRescansPersistedFolders() async throws {
        let dir = tempDir.appendingPathComponent("library")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = AppConfigurationV2(sourceMode: "scan", watchedFolders: [dir.path])
        let scanner = FakeROMScanner([snesROM("/ROMs/SNES/Zelda.sfc")])
        let vm = makeViewModel(roms: [], store: InMemoryRomConfigStore(config: config), scanner: scanner)
        await vm.load()
        XCTAssertEqual(scanner.scanCallCount, 1)
        XCTAssertEqual(vm.games.count, 1)
    }

    /// An unavailable watched folder must not populate the library or crash.
    func testLoadDoesNotScanMissingWatchedFolder() async {
        let config = AppConfigurationV2(sourceMode: "scan", watchedFolders: ["/no/such/dir"])
        let scanner = FakeROMScanner([snesROM("/ROMs/SNES/Zelda.sfc")])
        scanner.failingDirectories = ["/no/such/dir"]
        let vm = makeViewModel(roms: [], store: InMemoryRomConfigStore(config: config), scanner: scanner)
        await vm.load()
        XCTAssertEqual(scanner.scanCallCount, 1)
        XCTAssertTrue(vm.games.isEmpty)
    }

    func testLoadPromptsWhenWatchlistIsEmpty() async {
        let vm = makeViewModel(roms: [], store: InMemoryRomConfigStore())
        await vm.load()
        XCTAssertTrue(vm.showingWatchedFolderPrompt)
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

    func testScanCombinesMultipleWatchedFolders() async {
        let scanner = FakeROMScanner([])
        scanner.resultsByDirectory = [
            "/ROMs/One": [snesROM("/ROMs/One/Zelda.sfc")],
            "/ROMs/Two": [snesROM("/ROMs/Two/Chrono Trigger.sfc")]
        ]
        let vm = makeViewModel(roms: [], scanner: scanner)
        vm.watchedFolders = ["/ROMs/One", "/ROMs/Two"]

        await vm.scan()

        XCTAssertEqual(scanner.scannedDirectories, ["/ROMs/One", "/ROMs/Two"])
        XCTAssertEqual(Set(vm.games.map(\.title)), ["Zelda", "Chrono Trigger"])
    }

    func testScanDeduplicatesROMsFromOverlappingWatchedFolders() async {
        let duplicate = snesROM("/ROMs/Shared/Zelda.sfc")
        let scanner = FakeROMScanner([duplicate])
        let vm = makeViewModel(roms: [], scanner: scanner)
        vm.watchedFolders = ["/ROMs", "/ROMs/Shared"]

        await vm.scan()

        XCTAssertEqual(scanner.scanCallCount, 2)
        XCTAssertEqual(vm.games.count, 1)
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

    func testDOSStatusDistinguishesStartupChoiceFromInvalidPackage() async {
        let ambiguous = makeViewModel(roms: [dosFolderROM("/ROMs/DOS/Ambiguous")])
        await ambiguous.scan()
        XCTAssertEqual(ambiguous.games[0].status, .needsLaunchTarget)

        let invalid = makeViewModel(roms: [
            dosFolderROM("/ROMs/DOS/Broken", issue: "No DOS program was found.")
        ])
        await invalid.scan()
        XCTAssertEqual(invalid.games[0].status, .invalidSource)
    }

    func testDOSStartupSelectionPersistsAcrossRescan() async {
        let source = dosFolderROM("/ROMs/DOS/Ambiguous")
        let scanner = FakeROMScanner([source])
        let vm = makeViewModel(roms: [], scanner: scanner)
        await vm.scan()

        let target = source.dosPackage!.launchCandidates[1].url
        vm.setDOSLaunchTarget(target, for: vm.games[0])
        XCTAssertEqual(vm.games[0].launchPath, target)
        XCTAssertEqual(
            vm.currentConfiguration.gameOverrides[vm.games[0].stableKey]?.dosLaunchTargetPath,
            target.path
        )

        await vm.scan()
        XCTAssertEqual(vm.games[0].launchPath, target)
        XCTAssertNotEqual(vm.games[0].status, .needsLaunchTarget)
    }

    func testConfigDecodesMissingNewFields() throws {
        let legacyJSON = """
        {"version":2,"sourceMode":"scan","removeOrphanedBundles":false}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AppConfigurationV2.self, from: legacyJSON)
        XCTAssertEqual(decoded.folderPlatformRules, [:])
        XCTAssertNil(decoded.hashDatabasePath)
        XCTAssertEqual(decoded.version, 2)
    }

    // MARK: - Unknown platform workflow

    func testFolderPlatformRuleResolvesUnknownAndSurvivesRescan() async {
        let store = InMemoryRomConfigStore()
        let vm = makeViewModel(
            roms: [unknownROM("/ROMs/Loose/Mystery.mds")],
            store: store
        )
        await vm.scan()
        XCTAssertEqual(vm.games[0].platform.id, "unknown")
        XCTAssertEqual(vm.detectionInfo(for: vm.games[0])?.summary,
                       "No unique platform signature was found.")

        let ps2 = Platform(id: "ps2", displayName: "PS2")
        vm.setFolderPlatformRule(ps2, for: vm.games[0])
        XCTAssertEqual(vm.games[0].platform, ps2)
        XCTAssertEqual(vm.currentConfiguration.folderPlatformRules["/ROMs/Loose"], "ps2")

        await vm.scan()
        XCTAssertEqual(vm.games[0].platform, ps2)
    }

    func testBatchPlatformAssignmentPersistsPerGameOverrides() async {
        let vm = makeViewModel(roms: [
            unknownROM("/ROMs/Loose/One.mds"),
            unknownROM("/ROMs/Loose/Two.mds")
        ])
        await vm.scan()
        let ps2 = Platform(id: "ps2", displayName: "PS2")
        vm.setPlatform(ps2, for: vm.games)

        XCTAssertTrue(vm.games.allSatisfy { $0.platform == ps2 })
        XCTAssertTrue(vm.games.allSatisfy {
            vm.currentConfiguration.gameOverrides[$0.stableKey]?.platform == "ps2"
        })
    }

    func testBatchPlatformAssignmentPersistsOnlyOnce() async {
        let store = CountingRomConfigStore()
        let vm = makeViewModel(roms: [
            unknownROM("/ROMs/Loose/One.mds"),
            unknownROM("/ROMs/Loose/Two.mds"),
            unknownROM("/ROMs/Loose/Three.mds")
        ], store: store)
        await vm.scan()
        await waitForSaves(in: store, minimum: 1)
        store.resetSaveCount()

        vm.setPlatform(Platform(id: "ps2", displayName: "PS2"), for: vm.games)
        await waitForSaves(in: store, minimum: 1)
        try? await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(store.saveCount, 1)
    }

    func testScanUsesConfiguredLocalHashMatch() async throws {
        let romURL = tempDir.appendingPathComponent("Known.iso")
        try Data("hello".utf8).write(to: romURL)
        let databaseURL = tempDir.appendingPathComponent("hashes.json")
        try Data("""
        [{"sha1":"aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d","size":5,"platform":"ps2","title":"Known Game"}]
        """.utf8).write(to: databaseURL)

        let vm = makeViewModel(
            roms: [unknownROM(romURL.path, fileSize: 5)],
            store: InMemoryRomConfigStore()
        )
        vm.hashDatabasePath = databaseURL.path
        await vm.scan()

        XCTAssertEqual(vm.games[0].platform.id, "ps2")
        XCTAssertEqual(vm.games[0].title, "Known Game")
        XCTAssertEqual(vm.detectionInfo(for: vm.games[0])?.resolvedBy, "local hash database")
    }

    func testScanSurfacesMalformedHashDatabase() async throws {
        let databaseURL = tempDir.appendingPathComponent("hashes.json")
        try Data("not json".utf8).write(to: databaseURL)
        let vm = makeViewModel(roms: [unknownROM("/ROMs/Loose/Mystery.mds")])
        vm.hashDatabasePath = databaseURL.path

        await vm.scan()

        XCTAssertTrue(vm.errorMessage?.contains("Invalid hash database") ?? false)
    }

    private func waitForSaves(in store: CountingRomConfigStore, minimum: Int) async {
        for _ in 0..<100 where store.saveCount < minimum {
            await Task.yield()
        }
    }

    // MARK: - Launch argument override round-trip

    func testSetCustomLaunchArgumentsPersistsAndResets() async throws {
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")])
        await vm.scan()
        let game = vm.games[0]
        let original = game.launchArguments

        try vm.setCustomLaunchArguments("--fullscreen {romPath}", for: game)
        XCTAssertEqual(vm.games[0].launchArguments, ["--fullscreen", "{romPath}"])
        XCTAssertEqual(
            vm.currentConfiguration.gameOverrides[game.stableKey]?.launchArguments,
            ["--fullscreen", "{romPath}"]
        )
        XCTAssertTrue(vm.hasOverride(.launchArguments, for: vm.games[0]))

        // Reset restores the emulator default and drops the override.
        vm.resetOverride(.launchArguments, for: vm.games[0])
        XCTAssertEqual(vm.games[0].launchArguments, original)
        XCTAssertFalse(vm.hasOverride(.launchArguments, for: vm.games[0]))
        XCTAssertNil(vm.currentConfiguration.gameOverrides[game.stableKey]?.launchArguments)
    }

    func testEmptyCustomLaunchArgumentsClearsOverride() async throws {
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")])
        await vm.scan()
        let game = vm.games[0]
        try vm.setCustomLaunchArguments("{romPath}", for: game)
        XCTAssertTrue(vm.hasOverride(.launchArguments, for: vm.games[0]))
        try vm.setCustomLaunchArguments("", for: vm.games[0])
        XCTAssertFalse(vm.hasOverride(.launchArguments, for: vm.games[0]))
    }

    func testChangingEmulatorClearsCustomArgumentsAndUsesNewProfile() async throws {
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")])
        await vm.scan()
        let game = vm.games[0]
        try vm.setCustomLaunchArguments("--custom {romPath}", for: game)

        vm.setEmulatorChoice(.standalone(.bsnes), for: vm.games[0])

        XCTAssertEqual(vm.games[0].launchArguments, ["--fullscreen", "{romPath}"])
        XCTAssertNil(vm.currentConfiguration.gameOverrides[game.stableKey]?.launchArguments)
        XCTAssertFalse(vm.hasOverride(.launchArguments, for: vm.games[0]))
    }

    func testUnknownLaunchPlaceholderDoesNotMutateGame() async {
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")])
        await vm.scan()
        let original = vm.games[0].launchArguments

        XCTAssertThrowsError(
            try vm.setCustomLaunchArguments("--custom {rom}", for: vm.games[0])
        )
        XCTAssertEqual(vm.games[0].launchArguments, original)
        XCTAssertFalse(vm.hasOverride(.launchArguments, for: vm.games[0]))
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

    func testArtworkPickerReturnsAllCandidatesAndAppliesExactSelection() async {
        let provider = MultipleArtworkProvider()
        let vm = makeViewModel(
            roms: [snesROM("/ROMs/SNES/Zelda.sfc")],
            provider: provider)
        await vm.scan()
        let game = vm.games[0]
        let match = SGDBGame(id: 7, name: "Matched Game")

        let candidates = await vm.artworkCandidates(for: match)

        XCTAssertEqual(candidates.map(\.image.id), [2, 1, 3], "icons are score-sorted before grid fallbacks")
        await vm.applyArtworkCandidate(
            candidates[1], match: match, setTitle: false, for: game)
        XCTAssertEqual(provider.downloadedURL, URL(string: "https://x/low.png"))
        XCTAssertEqual(vm.currentConfiguration.gameOverrides[game.stableKey]?.sgdbGameId, 7)
        XCTAssertEqual(vm.currentConfiguration.gameOverrides[game.stableKey]?.sgdbGameName, "Matched Game")
    }

    // MARK: - Generation preview

    func testPreviewCountsNewGamesAsCreate() async {
        let vm = makeViewModel(roms: [
            snesROM("/ROMs/SNES/Zelda.sfc"),
            snesROM("/ROMs/SNES/Metroid.sfc")
        ])
        await vm.scan()
        let plan = await vm.generationPlan()
        XCTAssertEqual(plan.created, 2)
        XCTAssertEqual(plan.updated, 0)
        XCTAssertEqual(plan.upToDate, 0)
    }

    func testPreviewCountsUnchangedAfterGenerate() async {
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")])
        await vm.scan()
        vm.outputDirectory = tempDir.path
        await vm.generate()
        let plan = await vm.generationPlan()
        XCTAssertEqual(plan.created, 0)
        XCTAssertEqual(plan.upToDate, 1, "an already-generated, unchanged game is up to date")
    }

    func testPreviewExcludesUnselectedGames() async {
        let vm = makeViewModel(roms: [
            snesROM("/ROMs/SNES/Zelda.sfc"),
            snesROM("/ROMs/SNES/Metroid.sfc")
        ])
        await vm.scan()
        vm.setSelected(false, for: vm.games[0])
        let plan = await vm.generationPlan()
        XCTAssertEqual(plan.created, 1, "only the still-selected game counts")
        XCTAssertEqual(plan.excluded, 1)
    }

    func testPlanUpdatesAfterRename() async {
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")])
        await vm.scan()
        vm.outputDirectory = tempDir.path
        await vm.generate()

        vm.setTitle("The Legend of Zelda", for: vm.games[0])
        let plan = await vm.generationPlan()

        XCTAssertEqual(plan.updated, 1)
        XCTAssertEqual(plan.action(for: vm.games[0]), .update)
    }

    func testPlanUpdatesAfterOutputDirectoryChanges() async {
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")])
        await vm.scan()
        vm.outputDirectory = tempDir.path
        await vm.generate()

        vm.setOutputDirectory(tempDir.appendingPathComponent("Another Output"))
        let plan = await vm.generationPlan()

        XCTAssertEqual(plan.updated, 1)
    }

    // MARK: - Scale

    func testScanHandles500Entries() async {
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

    }

    // MARK: - Reset all overrides

    func testResetOverridesRestoresDefaults() async throws {
        let vm = makeViewModel(roms: [snesROM("/ROMs/SNES/Zelda.sfc")])
        await vm.scan()
        let game = vm.games[0]
        let defaultTitle = game.title

        vm.setTitle("Custom", for: game)
        try vm.setCustomLaunchArguments("--x {romPath}", for: vm.games[0])
        XCTAssertTrue(vm.anyOverrides(vm.games[0]))

        vm.resetOverrides(for: vm.games[0])
        XCTAssertEqual(vm.games[0].title, defaultTitle)
        XCTAssertFalse(vm.anyOverrides(vm.games[0]))
        XCTAssertNil(vm.currentConfiguration.gameOverrides[game.stableKey])
    }
}
