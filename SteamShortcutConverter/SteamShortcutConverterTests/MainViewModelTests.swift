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
    init(_ result: [DiscoveredROM]) { self.result = result }
    func scan(directory: URL, progress: @escaping (Double) -> Void) async throws -> [DiscoveredROM] {
        progress(1.0)
        return result
    }
}

final class FakeArtworkProvider: ArtworkProvider {
    func searchGame(term: String) async throws -> [SGDBGame] { [SGDBGame(id: 1, name: term)] }
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
        generator: GameBundleGenerating? = nil
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
            scanner: FakeROMScanner(roms),
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
}
