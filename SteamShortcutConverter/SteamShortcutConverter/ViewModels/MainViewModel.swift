//
//  MainViewModel.swift
//  SteamShortcutConverter
//
//  Orchestration layer for the ROM pipeline: scan → resolve → artwork → generate.
//  Fully dependency-injected; NO filesystem/network I/O in init (call `load()`
//  from the view's `.task {}`).
//

import Foundation
import SwiftUI

@MainActor
final class MainViewModel: ObservableObject {

    enum SourceMode: String {
        case scan
        case vdf
    }

    // MARK: - Published state

    @Published var games: [GameEntry] = []
    @Published var scanDirectory: String = ""
    @Published var outputDirectory: String = ""
    @Published var sourceMode: SourceMode = .scan
    @Published var steamGridDBApiKey: String = ""
    @Published var removeOrphanedBundles: Bool = false
    @Published var isProcessing: Bool = false
    @Published var progressValue: Double = 0.0
    @Published var progressMessage: String = ""
    @Published var conversionSummary: ConversionSummary?
    @Published var showingSummary: Bool = false
    @Published var lastConversionDate: Date?
    @Published var errorMessage: String?

    // MARK: - Dependencies

    let database: SystemDatabase
    let emulatorConfig: EmulatorConfigManager
    private let configStore: RomConfigStore
    private let scanner: ROMScanning
    private let artworkCache: ArtworkCache
    private let injectedArtworkProvider: ArtworkProvider?
    private let bundleGenerator: GameBundleGenerating
    private let incrementalManager: IncrementalUpdateManager
    private let vdfBridge: VDFToGameEntryBridge
    private let playlistManager: PlaylistWriting
    private let filenameParser = ROMFilenameParser()
    private let shortcutFilter: ShortcutFilter = DefaultShortcutFilter()

    private var config = AppConfigurationV2.default

    /// Read-only view of the current configuration (used by tests to assert
    /// override persistence without depending on async save timing).
    var currentConfiguration: AppConfigurationV2 { config }

    // MARK: - Init (no I/O)

    init(
        database: SystemDatabase,
        configStore: RomConfigStore,
        scanner: ROMScanning,
        emulatorConfig: EmulatorConfigManager,
        artworkCache: ArtworkCache,
        artworkProvider: ArtworkProvider? = nil,
        bundleGenerator: GameBundleGenerating,
        vdfBridge: VDFToGameEntryBridge,
        playlistManager: PlaylistWriting = PlaylistManager(),
        incrementalManager: IncrementalUpdateManager = IncrementalUpdateManager()
    ) {
        self.database = database
        self.configStore = configStore
        self.scanner = scanner
        self.emulatorConfig = emulatorConfig
        self.artworkCache = artworkCache
        self.injectedArtworkProvider = artworkProvider
        self.bundleGenerator = bundleGenerator
        self.vdfBridge = vdfBridge
        self.playlistManager = playlistManager
        self.incrementalManager = incrementalManager
    }

    /// Production wiring.
    convenience init() {
        // The bundled DB is a packaging invariant; trapping on absence is acceptable.
        let database = try! SystemDatabase()
        let detector = EmulatorDetector(database: database)
        let emulatorConfig = EmulatorConfigManager(
            database: database, detector: detector, store: FileEmulatorConfigStore())
        self.init(
            database: database,
            configStore: DefaultRomConfigStore(),
            scanner: ROMScanner(database: database),
            emulatorConfig: emulatorConfig,
            artworkCache: ArtworkCache(),
            artworkProvider: nil,
            bundleGenerator: DefaultAppBundleGenerator(),
            vdfBridge: VDFToGameEntryBridge(database: database)
        )
    }

    // MARK: - Lifecycle

    func load() async {
        do {
            config = try await configStore.load()
            apply(config)
            emulatorConfig.refreshDetection()
        } catch {
            errorMessage = "Failed to load configuration: \(error.localizedDescription)"
        }
    }

    private func apply(_ config: AppConfigurationV2) {
        outputDirectory = config.outputDirectory ?? ""
        scanDirectory = config.lastScanDirectory ?? ""
        removeOrphanedBundles = config.removeOrphanedBundles
        steamGridDBApiKey = config.steamGridDBApiKey ?? ""
        sourceMode = SourceMode(rawValue: config.sourceMode) ?? .scan
        lastConversionDate = config.lastConversionDate
    }

    private func persist() {
        config.outputDirectory = outputDirectory.isEmpty ? nil : outputDirectory
        config.lastScanDirectory = scanDirectory.isEmpty ? nil : scanDirectory
        config.removeOrphanedBundles = removeOrphanedBundles
        config.steamGridDBApiKey = steamGridDBApiKey.isEmpty ? nil : steamGridDBApiKey
        config.sourceMode = sourceMode.rawValue
        config.lastConversionDate = lastConversionDate
        let snapshot = config
        Task { try? await configStore.save(snapshot) }
    }

    // MARK: - Validation

    var canGenerate: Bool {
        !outputDirectory.isEmpty && games.contains { $0.isSelected && $0.emulator != nil }
    }

    var platformCount: Int {
        Set(games.map { $0.platform.id }).count
    }

    // MARK: - Scanning

    func scan() async {
        guard !scanDirectory.isEmpty else { return }
        isProcessing = true
        progressValue = 0
        progressMessage = "Scanning…"
        defer { isProcessing = false }

        do {
            let discovered = try await scanner.scan(directory: URL(fileURLWithPath: scanDirectory)) { [weak self] fraction in
                Task { @MainActor in self?.progressValue = fraction }
            }
            emulatorConfig.refreshDetection()
            games = discovered.map { makeEntry(from: $0) }
            applyOverrides()
            applyCachedArtwork()
            sourceMode = .scan
            progressMessage = "\(games.count) ROMs across \(platformCount) platforms"
            persist()
        } catch {
            errorMessage = "Scan failed: \(error.localizedDescription)"
            progressMessage = ""
        }
    }

    private func makeEntry(from rom: DiscoveredROM) -> GameEntry {
        // A multi-disc game with no existing .m3u gets a generated playlist (in
        // our app folder, absolute paths) as its launch target.
        var romPath = rom.url
        if !rom.discPaths.isEmpty {
            if let playlist = try? playlistManager.playlistURL(forDiscs: rom.discPaths) {
                romPath = playlist
            }
        }

        let metadata = filenameParser.parse(filename: rom.url.lastPathComponent)
        let platform = rom.platform ?? Platform(id: "unknown", displayName: "Unknown")
        var entry = GameEntry(
            title: metadata.title,
            romPath: romPath,
            romMetadata: metadata,
            platform: platform,
            source: .romScan,
            additionalFiles: rom.memberFiles,
            alternateImages: rom.alternateImages
        )
        if rom.platform != nil, let choice = emulatorConfig.defaultChoice(for: platform) {
            assignEmulator(&entry, choice: choice)
        }
        return entry
    }

    private func assignEmulator(_ entry: inout GameEntry, choice: EmulatorChoice) {
        entry.emulator = choice
        if let resolved = emulatorConfig.resolve(choice) {
            entry.emulatorPath = resolved.emulatorPath
            entry.argsTemplate = resolved.argsTemplate
        } else {
            entry.emulatorPath = nil
            entry.argsTemplate = database.argsTemplate(for: choice)
        }
    }

    private func applyOverrides() {
        for index in games.indices {
            guard let override = config.gameOverrides[games[index].stableKey] else { continue }
            if let title = override.customTitle { games[index].title = title }
            if let platformId = override.platform,
               let platform = database.allPlatforms.first(where: { $0.id == platformId }) {
                games[index].platform = platform
            }
            if let choice = override.emulator { assignEmulator(&games[index], choice: choice) }
            if let args = override.args { games[index].argsTemplate = args }
            if let imagePath = override.imagePath {
                games[index].launchImage = URL(fileURLWithPath: imagePath)
            }
        }
    }

    private func applyCachedArtwork() {
        for index in games.indices {
            let key = games[index].stableKey
            if artworkCache.hasICNS(for: key) || artworkCache.hasOriginal(for: key) {
                games[index].artworkStatus = .cached(artworkCache.originalURL(for: key))
            }
        }
    }

    // MARK: - VDF import

    func importFromVDF(url: URL) async {
        do {
            let data = try Data(contentsOf: url)
            let vdfData = try BinaryVDFReader(data: data).read()
            let shortcuts = try ShortcutParser().parseShortcuts(from: vdfData)
            let romShortcuts = shortcutFilter.filterROMShortcuts(from: shortcuts)
            games = vdfBridge.makeEntries(from: romShortcuts, legacyCustomNames: config.legacyCustomNames)
            applyOverrides()
            applyCachedArtwork()
            sourceMode = .vdf
            progressMessage = "\(games.count) games imported from Steam"
            persist()
        } catch {
            errorMessage = "Failed to import VDF: \(error.localizedDescription)"
        }
    }

    // MARK: - Per-game mutations (persisted)

    func setSelected(_ selected: Bool, for game: GameEntry) {
        updateGame(game.id) { $0.isSelected = selected }
    }

    func setTitle(_ title: String, for game: GameEntry) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        updateGame(game.id) { $0.title = trimmed }
        updateOverride(game.stableKey) { $0.customTitle = trimmed.isEmpty ? nil : trimmed }
    }

    func setEmulatorChoice(_ choice: EmulatorChoice, for game: GameEntry) {
        updateGame(game.id) { self.assignEmulator(&$0, choice: choice) }
        updateOverride(game.stableKey) { $0.emulator = choice }
    }

    func setPlatform(_ platform: Platform, for game: GameEntry) {
        updateGame(game.id) {
            $0.platform = platform
            if let choice = self.emulatorConfig.defaultChoice(for: platform) {
                self.assignEmulator(&$0, choice: choice)
            }
        }
        updateOverride(game.stableKey) { $0.platform = platform.id }
    }

    func setLaunchImage(_ url: URL, for game: GameEntry) {
        updateGame(game.id) { $0.launchImage = url }
        updateOverride(game.stableKey) { $0.imagePath = (url == game.romPath) ? nil : url.path }
    }

    func availableOptions(for game: GameEntry) -> [EmulatorOption] {
        emulatorConfig.availableOptions(for: game.platform)
    }

    // MARK: - Per-platform default

    func availableOptions(for platform: Platform) -> [EmulatorOption] {
        emulatorConfig.availableOptions(for: platform)
    }

    func defaultChoiceSetting(for platform: Platform) -> EmulatorChoice? {
        emulatorConfig.defaultChoiceSetting(for: platform)
    }

    var allPlatforms: [Platform] { database.allPlatforms }

    func setDefaultChoice(_ choice: EmulatorChoice, for platform: Platform) {
        emulatorConfig.setDefaultChoice(choice, for: platform)
        for index in games.indices where games[index].platform == platform {
            // Only games without a per-game emulator override follow the default.
            if config.gameOverrides[games[index].stableKey]?.emulator == nil {
                assignEmulator(&games[index], choice: choice)
            }
        }
    }

    // MARK: - Artwork

    private func artworkProvider() -> ArtworkProvider? {
        if let injectedArtworkProvider { return injectedArtworkProvider }
        guard !steamGridDBApiKey.isEmpty else { return nil }
        return SteamGridDBClient(apiKey: steamGridDBApiKey)
    }

    func fetchArtwork(for game: GameEntry) async {
        guard let provider = artworkProvider() else {
            errorMessage = "Set a SteamGridDB API key in Settings first."
            return
        }
        updateGame(game.id) { $0.artworkStatus = .downloading }
        do {
            if let fetched = try await provider.fetchArtwork(forTitle: game.title) {
                let metadata = ArtworkMetadata(
                    sgdbGameId: fetched.sgdbGameId,
                    sgdbImageId: fetched.sgdbImageId,
                    downloadedAt: Date(),
                    sourceType: fetched.sourceType.rawValue
                )
                let url = try artworkCache.store(originalPNG: fetched.data, metadata: metadata, for: game.stableKey)
                updateGame(game.id) { $0.artworkStatus = .cached(url) }
            } else {
                updateGame(game.id) { $0.artworkStatus = .failed("No artwork found") }
            }
        } catch {
            updateGame(game.id) { $0.artworkStatus = .failed(error.localizedDescription) }
        }
    }

    func fetchMissingArtwork() async {
        for game in games where game.isSelected && isArtworkMissing(game) {
            await fetchArtwork(for: game)
        }
    }

    private func isArtworkMissing(_ game: GameEntry) -> Bool {
        switch game.artworkStatus {
        case .cached: return false
        default: return true
        }
    }

    func artworkCacheSize() -> Int64 { artworkCache.cacheSize() }

    func clearArtworkCache() {
        try? artworkCache.clear()
        for index in games.indices { games[index].artworkStatus = .none }
    }

    func saveSettings() { persist() }

    // MARK: - Generation

    func generate() async {
        guard !outputDirectory.isEmpty else {
            errorMessage = "Select an output directory first."
            return
        }
        isProcessing = true
        progressValue = 0
        conversionSummary = nil
        showingSummary = false
        defer { isProcessing = false }

        let outputURL = URL(fileURLWithPath: outputDirectory)
        let selected = games.filter { $0.isSelected }
        let previousState = try? await configStore.loadGameState()
        let changes = incrementalManager.detectChanges(currentGames: selected, previousState: previousState)

        var removed = 0
        if let deleted = try? incrementalManager.cleanupOrphanedGameBundles(
            changes: changes, removeOrphaned: removeOrphanedBundles) {
            removed = deleted.count
        }

        // Precompute unique bundle identifiers across the batch.
        let ids = DefaultAppBundleGenerator.bundleIdentifiers(
            for: selected.map { (title: $0.title, stableKey: $0.stableKey) })
        var idByKey: [String: String] = [:]
        for (game, id) in zip(selected, ids) { idByKey[game.stableKey] = id }

        var created = 0, updated = 0, skipped = 0
        var errors: [ConversionError] = []
        var warnings: [ConversionWarning] = []
        var records: [ConvertedGame] = []

        for (index, game) in selected.enumerated() {
            progressValue = Double(index + 1) / Double(selected.count)
            progressMessage = game.title
            guard let change = changes[game.stableKey] else { continue }

            if change.changeType == .unchanged {
                skipped += 1
                if let previous = previousState?.convertedGames.first(where: { $0.stableKey == game.stableKey }) {
                    records.append(previous)
                }
                continue
            }

            guard let choice = game.emulator, let resolved = emulatorConfig.resolve(choice) else {
                warnings.append(ConversionWarning(
                    shortcutName: game.title, type: .missingEmulator,
                    message: "No installed emulator for \(game.platform.displayName)."))
                continue
            }

            if change.changeType == .modified, let oldPath = change.previousBundlePath,
               FileManager.default.fileExists(atPath: oldPath) {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: oldPath))
            }

            let bundle = ResolvedGameBundle(
                bundleName: sanitizeBundleName(game.title),
                bundleIdentifier: idByKey[game.stableKey] ?? "com.romshortcutmaker.game",
                displayName: game.title,
                executablePath: resolved.emulatorPath,
                argsTemplate: resolved.argsTemplate,
                romPath: game.launchPath,
                corePath: resolved.corePath,
                iconICNS: artworkCache.hasICNS(for: game.stableKey) ? artworkCache.icnsURL(for: game.stableKey) : nil,
                iconOriginalPNG: artworkCache.hasOriginal(for: game.stableKey) ? artworkCache.originalURL(for: game.stableKey) : nil,
                outputDirectory: outputURL
            )

            do {
                let bundleURL = try await bundleGenerator.generateAppBundle(for: bundle)
                if change.changeType == .new { created += 1 } else { updated += 1 }
                records.append(incrementalManager.buildConvertedGame(for: game, bundlePath: bundleURL.path))
            } catch {
                errors.append(ConversionError(shortcutName: game.title, message: error.localizedDescription))
            }
        }

        try? await configStore.saveGameState(GameConversionState(convertedGames: records))
        lastConversionDate = Date()
        persist()

        conversionSummary = ConversionSummary(
            bundlesCreated: created, bundlesUpdated: updated,
            bundlesSkipped: skipped, bundlesRemoved: removed,
            errors: errors, warnings: warnings)
        showingSummary = true
        progressValue = 1.0
        progressMessage = "Done"
    }

    // MARK: - Reset

    func resetConfiguration() async {
        config = .default
        apply(config)
        games = []
        lastConversionDate = nil
        errorMessage = nil
        try? await configStore.save(config)
    }

    // MARK: - Helpers

    private func updateGame(_ id: UUID, _ transform: (inout GameEntry) -> Void) {
        guard let index = games.firstIndex(where: { $0.id == id }) else { return }
        transform(&games[index])
    }

    private func updateOverride(_ key: String, _ transform: (inout GameOverride) -> Void) {
        var override = config.gameOverrides[key] ?? GameOverride()
        transform(&override)
        if override == GameOverride() {
            config.gameOverrides.removeValue(forKey: key)
        } else {
            config.gameOverrides[key] = override
        }
        persist()
    }

    private func sanitizeBundleName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: ":/\\")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "Game" : cleaned
    }
}
