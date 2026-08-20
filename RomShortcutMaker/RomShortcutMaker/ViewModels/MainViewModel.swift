//
//  MainViewModel.swift
//  RomShortcutMaker
//
//  Orchestration layer for the ROM pipeline: scan → resolve → artwork → generate.
//  Fully dependency-injected; NO filesystem/network I/O in init (call `load()`
//  from the view's `.task {}`).
//

import Foundation
import SwiftUI
import AppKit

@MainActor
final class MainViewModel: ObservableObject {

    enum SettingsPane: Hashable {
        case general, emulators, artwork
    }

    /// A per-game field that can be individually overridden (and reset). Backs
    /// the Properties window's override dots and per-field reset buttons.
    enum OverrideField: CaseIterable {
        case title, platform, emulator, launchArguments, launchImage, dosLaunchTarget
    }

    enum SourceMode: String {
        case scan
        case vdf
    }

    enum Operation: Equatable {
        case idle
        case scanning
        case importing
        case generating
    }

    // MARK: - Published state

    @Published var games: [GameEntry] = []
    @Published var watchedFolders: [String] = []
    @Published var outputDirectory: String = ""
    @Published var sourceMode: SourceMode = .scan
    @Published var steamGridDBApiKey: String = ""
    @Published var hashDatabasePath: String = ""
    @Published var removeOrphanedBundles: Bool = false
    @Published var isProcessing: Bool = false
    @Published private(set) var operation: Operation = .idle
    @Published var progressValue: Double = 0.0
    @Published var progressMessage: String = ""
    @Published var conversionSummary: ConversionSummary?
    @Published var showingSummary: Bool = false
    @Published var lastConversionDate: Date?
    @Published var errorMessage: String?
    @Published var showingWatchedFolderPrompt: Bool = false
    @Published var settingsPane: SettingsPane = .general
    @Published var emulatorSettingsPlatformID: String?

    /// Rows the user has selected in the list (drives context-menu / ⌘I / the
    /// Properties window). Distinct from `GameEntry.isSelected`, which is the
    /// generate-me checkbox.
    @Published var selection: Set<GameEntry.ID> = []
    /// The game whose Properties window is open (nil = closed). Reused window.
    @Published var propertiesGameID: GameEntry.ID?

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
    private let filenameParser: ROMFilenameParser
    private let shortcutFilter: ShortcutFilter = DefaultShortcutFilter()

    private var config = AppConfigurationV2.default
    /// Fresh scan evidence, keyed like game overrides. Kept out of persisted
    /// GameEntry state so diagnostics can evolve independently of conversions.
    private var detectionByKey: [String: PlatformDetectionInfo] = [:]
    /// Ensures the async generation-plan task invalidates even when a mutation
    /// replaces artwork bytes at the same URL with the same file size.
    private var generationRevision = 0

    /// Pre-override snapshot of each entry, captured right after a scan/import
    /// (default title, resolved platform, default emulator, default args). Used
    /// to restore a field when the user resets its override — no persistence
    /// change needed, and the original scanned platform isn't lost.
    private var defaultEntries: [String: GameEntry] = [:]

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
        self.filenameParser = ROMFilenameParser(platformAliases: database.allFolderAliases)
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
        // Restore watched libraries automatically. VDF imports are intentionally
        // transient because their source path is not persisted.
        if sourceMode == .scan, !watchedFolders.isEmpty {
            await scan()
        } else if watchedFolders.isEmpty {
            showingWatchedFolderPrompt = true
        }
    }

    private func apply(_ config: AppConfigurationV2) {
        outputDirectory = config.outputDirectory ?? ""
        watchedFolders = config.watchedFolders
        removeOrphanedBundles = config.removeOrphanedBundles
        steamGridDBApiKey = config.steamGridDBApiKey ?? ""
        hashDatabasePath = config.hashDatabasePath ?? ""
        sourceMode = SourceMode(rawValue: config.sourceMode) ?? .scan
        lastConversionDate = config.lastConversionDate
        detectionByKey = [:]
    }

    private func persist() {
        config.outputDirectory = outputDirectory.isEmpty ? nil : outputDirectory
        config.watchedFolders = watchedFolders
        config.removeOrphanedBundles = removeOrphanedBundles
        config.steamGridDBApiKey = steamGridDBApiKey.isEmpty ? nil : steamGridDBApiKey
        config.hashDatabasePath = hashDatabasePath.isEmpty ? nil : hashDatabasePath
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

    // MARK: - List status

    /// How many games are not `.ready` (no emulator / unknown platform). Surfaced
    /// in the status line so a problem is noticeable without opening anything.
    var needsAttentionCount: Int {
        games.filter { $0.status != .ready }.count
    }

    var platformsNeedingEmulators: [Platform] {
        var seen: Set<String> = []
        return games.compactMap { game in
            guard game.status == .noEmulator, seen.insert(game.platform.id).inserted else {
                return nil
            }
            return game.platform
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    var shouldShowNoCompatibleEmulatorsBanner: Bool {
        !platformsNeedingEmulators.isEmpty && !games.contains { $0.status == .ready }
    }

    // MARK: - Scanning

    func addWatchedFolder(_ url: URL) async {
        guard !isProcessing else { return }
        let path = url.standardizedFileURL.path
        guard !watchedFolders.contains(path) else {
            showingWatchedFolderPrompt = false
            return
        }
        watchedFolders.append(path)
        showingWatchedFolderPrompt = false
        persist()
        await scan()
    }

    func removeWatchedFolders(_ paths: Set<String>) async {
        guard !isProcessing, !paths.isEmpty else { return }
        watchedFolders.removeAll { paths.contains($0) }
        for path in paths {
            config.folderPlatformRules = config.folderPlatformRules.filter {
                $0.key != path && !$0.key.hasPrefix(path + "/")
            }
        }
        if watchedFolders.isEmpty {
            games = []
            detectionByKey = [:]
            selection = []
            progressMessage = ""
            sourceMode = .scan
            persist()
        } else {
            persist()
            await scan()
        }
    }

    func scan() async {
        guard !isProcessing, !watchedFolders.isEmpty else { return }
        isProcessing = true
        operation = .scanning
        progressValue = 0
        progressMessage = "Scanning"
        // Drop any previous run's summary so the status line doesn't show stale
        // "created N" counts for a different library.
        conversionSummary = nil
        showingSummary = false
        defer {
            isProcessing = false
            operation = .idle
        }

        do {
            var discovered: [DiscoveredROM] = []
            var discoveredPaths: Set<String> = []
            var unavailableCount = 0
            var lastScanError: Error?
            let folderCount = Double(watchedFolders.count)
            for (index, folder) in watchedFolders.enumerated() {
                do {
                    let folderROMs = try await scanner.scan(directory: URL(fileURLWithPath: folder)) { [weak self] fraction in
                        let overallProgress = (Double(index) + fraction) / folderCount
                        Task { @MainActor in self?.progressValue = overallProgress }
                    }
                    for rom in folderROMs {
                        let path = rom.url.standardizedFileURL.path
                        if discoveredPaths.insert(path).inserted {
                            discovered.append(rom)
                        }
                    }
                } catch {
                    unavailableCount += 1
                    lastScanError = error
                    progressValue = Double(index + 1) / folderCount
                }
            }
            if unavailableCount == watchedFolders.count, let lastScanError {
                throw lastScanError
            }
            if unavailableCount == watchedFolders.count {
                throw ROMScanner.ScanError.directoryNotReadable(URL(fileURLWithPath: watchedFolders[0]))
            }
            let hashInputs = discovered.compactMap { rom -> LocalHashInput? in
                guard rom.platform == nil else { return nil }
                return LocalHashInput(
                    path: rom.url.standardizedFileURL.path,
                    fileSize: rom.fileSize
                )
            }
            let hashMatches = try await LocalHashDatabase.matches(
                inputs: hashInputs,
                databaseURL: hashDatabasePath.isEmpty ? nil : URL(fileURLWithPath: hashDatabasePath)
            )
            emulatorConfig.refreshDetection()
            games = discovered.map {
                makeEntry(
                    from: $0,
                    hashMatch: hashMatches[$0.url.standardizedFileURL.path]
                )
            }
            detectionByKey = Dictionary(uniqueKeysWithValues: zip(games, discovered).compactMap { game, rom in
                let hashMatch = hashMatches[rom.url.standardizedFileURL.path]
                guard let detection = enrichedDetection(rom.detection, hashMatch: hashMatch) else { return nil }
                return (game.stableKey, detection)
            })
            applyFolderPlatformRules(to: &games)
            captureDefaults()
            applyOverrides()
            applyCachedArtwork()
            seedArtworkHints(from: discovered)
            sourceMode = .scan
            progressMessage = "\(games.count) ROMs across \(platformCount) platforms"
            if unavailableCount > 0 {
                progressMessage += " · \(unavailableCount) folder unavailable"
            }
            persist()
        } catch {
            errorMessage = "Scan failed: \(error.localizedDescription)"
            progressMessage = ""
        }
    }

    private func makeEntry(from rom: DiscoveredROM, hashMatch: LocalHashMatch? = nil) -> GameEntry {
        // A multi-disc game with no existing .m3u gets a generated playlist (in
        // our app folder, absolute paths) as its launch target.
        var romPath = rom.url
        if !rom.discPaths.isEmpty {
            if let playlist = try? playlistManager.playlistURL(forDiscs: rom.discPaths) {
                romPath = playlist
            }
        }

        // The parser still runs for romMetadata, but a scanner-provided title
        // hint (e.g. a PS3 PARAM.SFO TITLE) beats the filename-derived title.
        let metadata = filenameParser.parse(filename: rom.url.lastPathComponent)
        let hashPlatform = hashMatch.flatMap { match in
            database.allPlatforms.first { $0.id == match.platformID }
        }
        let platform = rom.platform ?? hashPlatform ?? Platform(id: "unknown", displayName: "Unknown")
        var entry = GameEntry(
            title: rom.titleHint ?? hashMatch?.title ?? metadata.title,
            romPath: romPath,
            romMetadata: metadata,
            platform: platform,
            source: .romScan,
            additionalFiles: rom.memberFiles,
            alternateImages: rom.alternateImages,
            discCount: rom.discCount,
            dosPackage: rom.dosPackage
        )
        if platform.id != "unknown",
           entry.dosPackage?.blockingIssue == nil,
           entry.dosPackage?.requiresLaunchSelection != true,
           let choice = emulatorConfig.defaultChoice(for: platform, romExtension: entry.launchPath.pathExtension) {
            assignEmulator(&entry, choice: choice)
        }
        return entry
    }

    private func enrichedDetection(
        _ detection: PlatformDetectionInfo?,
        hashMatch: LocalHashMatch?
    ) -> PlatformDetectionInfo? {
        guard var detection,
              let hashMatch,
              let platform = database.allPlatforms.first(where: { $0.id == hashMatch.platformID }) else {
            return detection
        }
        detection.candidates = [platform]
        detection.evidence.append("Exact local hash database match.")
        detection.resolvedBy = "local hash database"
        return detection
    }

    private func assignEmulator(_ entry: inout GameEntry, choice: EmulatorChoice) {
        entry.emulator = choice
        if let resolved = emulatorConfig.resolve(
            choice,
            for: entry.platform,
            romExtension: entry.launchPath.pathExtension
        ) {
            entry.emulatorPath = resolved.emulatorPath
            entry.launchArguments = resolved.launchArguments
        } else {
            entry.emulatorPath = nil
            entry.launchArguments = database.launchArguments(
                for: choice,
                platform: entry.platform,
                romExtension: entry.launchPath.pathExtension
            )
        }
    }

    private func applyOverrides() {
        for index in games.indices {
            guard let override = config.gameOverrides[games[index].stableKey] else { continue }
            if let title = override.customTitle { games[index].title = title }
            if let targetPath = override.dosLaunchTargetPath,
               var package = games[index].dosPackage,
               package.launchCandidates.contains(where: {
                   $0.url.standardizedFileURL.path == URL(fileURLWithPath: targetPath).standardizedFileURL.path
               }) {
                package.selectedLaunchURL = URL(fileURLWithPath: targetPath)
                games[index].dosPackage = package
                if let choice = emulatorConfig.defaultChoice(
                    for: games[index].platform,
                    romExtension: games[index].launchPath.pathExtension
                ) {
                    assignEmulator(&games[index], choice: choice)
                }
            }
            if let platformId = override.platform,
               let platform = database.allPlatforms.first(where: { $0.id == platformId }) {
                games[index].platform = platform
                if let choice = emulatorConfig.defaultChoice(
                    for: platform,
                    romExtension: games[index].launchPath.pathExtension
                ) {
                    assignEmulator(&games[index], choice: choice)
                } else {
                    clearEmulator(&games[index])
                }
            }
            if let choice = override.emulator { assignEmulator(&games[index], choice: choice) }
            if let launchArguments = override.launchArguments {
                games[index].launchArguments = launchArguments
            }
            if let imagePath = override.imagePath {
                games[index].launchImage = URL(fileURLWithPath: imagePath)
            }
            games[index].isSelected = !(override.excluded ?? false)
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

    /// Seed bundled artwork (e.g. a PS3 ICON0.PNG) into the cache for games
    /// that have an artwork hint and no cached artwork yet. The hint lives on
    /// `DiscoveredROM` (GameEntry doesn't carry it), so a transient
    /// stableKey → URL map bridges the two. Failure to seed is non-fatal.
    private func seedArtworkHints(from discovered: [DiscoveredROM]) {
        var hintsByKey: [String: URL] = [:]
        for (rom, game) in zip(discovered, games) {
            if let hint = rom.artworkHint { hintsByKey[game.stableKey] = hint }
        }
        guard !hintsByKey.isEmpty else { return }

        for index in games.indices {
            let key = games[index].stableKey
            guard let hint = hintsByKey[key] else { continue }
            if case .cached = games[index].artworkStatus { continue }   // cache wins
            guard let png = try? Data(contentsOf: hint) else { continue }
            let metadata = ArtworkMetadata(
                sgdbGameId: nil, sgdbImageId: nil, downloadedAt: Date(), sourceType: "bundled-icon")
            guard let url = try? artworkCache.store(originalPNG: png, metadata: metadata, for: key) else {
                continue
            }
            games[index].artworkStatus = .cached(url)
        }
    }

    // MARK: - VDF import

    func importFromVDF(url: URL) async {
        isProcessing = true
        operation = .importing
        progressMessage = "Importing from Steam"
        defer {
            isProcessing = false
            operation = .idle
        }
        conversionSummary = nil
        showingSummary = false
        do {
            let data = try Data(contentsOf: url)
            let vdfData = try BinaryVDFReader(data: data).read()
            let shortcuts = try ShortcutParser().parseShortcuts(from: vdfData)
            let romShortcuts = shortcutFilter.filterROMShortcuts(from: shortcuts)
            games = vdfBridge.makeEntries(from: romShortcuts, legacyCustomNames: config.legacyCustomNames)
            detectionByKey = [:]
            captureDefaults()
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
        updateOverride(game.stableKey) { $0.excluded = selected ? nil : true }
    }

    func setTitle(_ title: String, for game: GameEntry) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        updateGame(game.id) { $0.title = trimmed }
        updateOverride(game.stableKey) { $0.customTitle = trimmed.isEmpty ? nil : trimmed }
    }

    /// Update title-backed UI immediately without performing a disk save for
    /// every keystroke. The Properties view debounces `saveTitleDraft()` and
    /// calls `setTitle` on focus loss for final whitespace normalization.
    func setTitleDraft(_ title: String, for game: GameEntry) {
        updateGame(game.id) { $0.title = title }
        mutateOverride(game.stableKey) { $0.customTitle = title.isEmpty ? nil : title }
    }

    func saveTitleDraft() {
        persist()
    }

    func setOutputDirectory(_ url: URL) {
        outputDirectory = url.path
        persist()
    }

    func setEmulatorChoice(_ choice: EmulatorChoice, for game: GameEntry) {
        updateGame(game.id) { self.assignEmulator(&$0, choice: choice) }
        updateOverride(game.stableKey) {
            $0.emulator = choice
            $0.launchArguments = nil
        }
    }

    func setPlatform(_ platform: Platform, for game: GameEntry) {
        applyPlatform(platform, toGameID: game.id)
        updateOverride(game.stableKey) {
            $0.platform = platform.id
            $0.emulator = nil
            $0.launchArguments = nil
        }
    }

    /// Assign a platform override to several games, used by the Unknown bucket's
    /// batch action.
    func setPlatform(_ platform: Platform, for games: [GameEntry]) {
        guard !games.isEmpty else { return }
        for game in games {
            applyPlatform(platform, toGameID: game.id)
            mutateOverride(game.stableKey) {
                $0.platform = platform.id
                $0.emulator = nil
                $0.launchArguments = nil
            }
        }
        persist()
    }

    /// Persist an explicit fallback rule for a source folder and apply it to
    /// unresolved games below that folder. Stronger automatic detections and
    /// explicit per-game overrides are left untouched.
    func setFolderPlatformRule(_ platform: Platform, for game: GameEntry) {
        let directory = detectionByKey[game.stableKey]?.sourceDirectory
            ?? game.romPath.deletingLastPathComponent().standardizedFileURL
        config.folderPlatformRules[directory.path] = platform.id
        applyFolderPlatformRules(to: &games)
        persist()
    }

    /// Detection evidence used by the Unknown diagnostics view.
    func detectionInfo(for game: GameEntry) -> PlatformDetectionInfo? {
        detectionByKey[game.stableKey]
    }

    func setLaunchImage(_ url: URL, for game: GameEntry) {
        updateGame(game.id) { $0.launchImage = url }
        updateOverride(game.stableKey) { $0.imagePath = (url == game.romPath) ? nil : url.path }
    }

    func setDOSLaunchTarget(_ url: URL, for game: GameEntry) {
        guard let package = game.dosPackage,
              package.launchCandidates.contains(where: {
                  $0.url.standardizedFileURL.path == url.standardizedFileURL.path
              }) else { return }

        updateGame(game.id) { entry in
            guard var updatedPackage = entry.dosPackage else { return }
            updatedPackage.selectedLaunchURL = url
            entry.dosPackage = updatedPackage
            if let choice = self.emulatorConfig.defaultChoice(
                for: entry.platform,
                romExtension: url.pathExtension
            ) {
                self.assignEmulator(&entry, choice: choice)
            } else {
                self.clearEmulator(&entry)
            }
        }
        updateOverride(game.stableKey) { override in
            let baseTarget = self.defaultEntries[game.stableKey]?.dosPackage?.selectedLaunchURL
            override.dosLaunchTargetPath = baseTarget?.standardizedFileURL == url.standardizedFileURL
                ? nil
                : url.path
            override.emulator = nil
            override.launchArguments = nil
        }
    }

    func availableOptions(for game: GameEntry) -> [EmulatorOption] {
        emulatorConfig.availableOptions(for: game.platform, romExtension: game.launchPath.pathExtension)
    }

    // MARK: - Per-platform default

    func availableOptions(for platform: Platform) -> [EmulatorOption] {
        emulatorConfig.availableOptions(for: platform)
    }

    func supportedOptions(for platform: Platform) -> [EmulatorOption] {
        emulatorConfig.supportedOptions(for: platform)
    }

    var libraryPlatforms: [Platform] {
        var seen: Set<String> = []
        return games.compactMap { game in
            guard game.platform.id != "unknown", seen.insert(game.platform.id).inserted else {
                return nil
            }
            return game.platform
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    func openEmulatorSettings(for platform: Platform? = nil) {
        emulatorSettingsPlatformID = platform?.id
        settingsPane = .emulators
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func locateEmulator(_ type: EmulatorType, at url: URL) {
        emulatorConfig.setPath(url.standardizedFileURL.path, for: type)
        refreshEmulators()
    }

    func refreshEmulators() {
        emulatorConfig.refreshDetection()
        for index in games.indices {
            let game = games[index]
            let overrideChoice = config.gameOverrides[game.stableKey]?.emulator
            let choice = overrideChoice ?? emulatorConfig.defaultChoice(
                for: game.platform,
                romExtension: game.launchPath.pathExtension
            )
            if let choice,
               emulatorConfig.availableOptions(
                   for: game.platform,
                   romExtension: game.launchPath.pathExtension
               ).contains(where: { $0.choice == choice }) {
                assignEmulator(&games[index], choice: choice)
            } else {
                clearEmulator(&games[index])
            }
        }
        generationRevision += 1
    }

    func defaultChoiceSetting(for platform: Platform) -> EmulatorChoice? {
        emulatorConfig.defaultChoiceSetting(for: platform)
    }

    var allPlatforms: [Platform] { database.allPlatforms }

    var allPlatformsIncludingUnknown: [Platform] {
        [Platform(id: "unknown", displayName: "Unknown")] + database.allPlatforms
    }

    func setDefaultChoice(_ choice: EmulatorChoice, for platform: Platform) {
        emulatorConfig.setDefaultChoice(choice, for: platform)
        for index in games.indices where games[index].platform == platform {
            // Only games without a per-game emulator override follow the default.
            if config.gameOverrides[games[index].stableKey]?.emulator == nil {
                if availableOptions(for: games[index]).contains(where: { $0.choice == choice }) {
                    assignEmulator(&games[index], choice: choice)
                } else if games[index].emulator == choice {
                    clearEmulator(&games[index])
                }
            }
        }
    }

    // MARK: - Artwork

    private func artworkProvider() -> ArtworkProvider? {
        if let injectedArtworkProvider { return injectedArtworkProvider }
        guard !steamGridDBApiKey.isEmpty else { return nil }
        return SteamGridDBClient(apiKey: steamGridDBApiKey)
    }

    /// Whether artwork can be fetched (a provider is available — API key set, or
    /// an injected provider in tests). Drives disabled state in the UI.
    var canFetchArtwork: Bool { artworkProvider() != nil }

    func fetchArtwork(for game: GameEntry) async {
        guard let provider = artworkProvider() else {
            errorMessage = "Set a SteamGridDB API key in Settings first."
            return
        }
        updateGame(game.id) { $0.artworkStatus = .downloading }
        do {
            let existing = config.gameOverrides[game.stableKey]
            let fetched: FetchedArtwork?
            if let pinnedId = existing?.sgdbGameId {
                // A pinned match (manual, or a previously recorded automatic hit)
                // skips the title search so refetches stay on the same game.
                fetched = try await provider.fetchArtwork(
                    for: SGDBGame(id: pinnedId, name: existing?.sgdbGameName ?? game.title))
            } else if let match = try await provider.bestMatch(forTitle: game.title) {
                let hadCustomTitle = existing?.customTitle != nil
                // Record the match so future refetches are stable.
                updateOverride(game.stableKey) {
                    $0.sgdbGameId = match.id
                    $0.sgdbGameName = match.name
                }
                // Adopt the proper game name as the title, but never stomp an
                // existing user rename. setTitle persists it as a title override.
                if !hadCustomTitle {
                    setTitle(match.name, for: game)
                }
                fetched = try await provider.fetchArtwork(for: match)
            } else {
                fetched = nil
            }

            if let fetched {
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

    /// Search SteamGridDB for candidate games to match manually. Returns `[]` and
    /// sets `errorMessage` on failure or when no provider is configured.
    func searchArtworkMatches(term: String) async -> [SGDBGame] {
        guard let provider = artworkProvider() else {
            errorMessage = "Set a SteamGridDB API key in Settings first."
            return []
        }
        do {
            return try await provider.searchGame(term: term)
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            return []
        }
    }

    /// Load every selectable icon for a match, followed by grid artwork as a
    /// fallback. Automatic fetching still chooses the highest-scoring icon.
    func artworkCandidates(for match: SGDBGame) async -> [SGDBArtworkCandidate] {
        guard let provider = artworkProvider() else {
            errorMessage = "Set a SteamGridDB API key in Settings first."
            return []
        }
        do {
            let icons = try await provider.getIcons(gameId: match.id)
                .filter { $0.isPNG }
                .sorted { ($0.score ?? 0) > ($1.score ?? 0) }
                .map { SGDBArtworkCandidate(image: $0, sourceType: .icon) }
            let grids = try await provider.getGrids(gameId: match.id)
                .sorted { ($0.score ?? 0) > ($1.score ?? 0) }
                .map { SGDBArtworkCandidate(image: $0, sourceType: .grid) }
            return icons + grids
        } catch {
            errorMessage = "Artwork search failed: \(error.localizedDescription)"
            return []
        }
    }

    /// Apply the exact SteamGridDB asset selected by the user.
    func applyArtworkCandidate(
        _ candidate: SGDBArtworkCandidate,
        match: SGDBGame,
        setTitle: Bool,
        for game: GameEntry
    ) async {
        guard let provider = artworkProvider() else {
            errorMessage = "Set a SteamGridDB API key in Settings first."
            return
        }
        updateGame(game.id) { $0.artworkStatus = .downloading }
        do {
            let data = try await provider.downloadImage(url: candidate.image.url)
            let metadata = ArtworkMetadata(
                sgdbGameId: match.id,
                sgdbImageId: candidate.image.id,
                downloadedAt: Date(),
                sourceType: candidate.sourceType.rawValue)
            let url = try artworkCache.store(originalPNG: data, metadata: metadata, for: game.stableKey)
            updateOverride(game.stableKey) {
                $0.sgdbGameId = match.id
                $0.sgdbGameName = match.name
            }
            if setTitle { self.setTitle(match.name, for: game) }
            updateGame(game.id) { $0.artworkStatus = .cached(url) }
        } catch {
            updateGame(game.id) { $0.artworkStatus = .failed(error.localizedDescription) }
        }
    }

    /// Pin a user-chosen SteamGridDB match: record its id/name, optionally adopt
    /// its name as the title (an explicit action, so this DOES overwrite an
    /// existing custom title), then fetch artwork for the pinned id.
    func applyManualMatch(_ match: SGDBGame, setTitle: Bool, for game: GameEntry) async {
        updateOverride(game.stableKey) {
            $0.sgdbGameId = match.id
            $0.sgdbGameName = match.name
        }
        if setTitle {
            self.setTitle(match.name, for: game)
        }
        await fetchArtwork(for: game)
    }

    /// The pinned SteamGridDB match name for a game, if any.
    func matchedGameName(for game: GameEntry) -> String? {
        config.gameOverrides[game.stableKey]?.sgdbGameName
    }

    /// Clear a pinned match so the next fetch searches by title again. Leaves the
    /// title and other override fields untouched (the match isn't a scanned
    /// default, so it has no `OverrideField` reset case).
    func clearManualMatch(for game: GameEntry) {
        updateOverride(game.stableKey) {
            $0.sgdbGameId = nil
            $0.sgdbGameName = nil
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

    func setHashDatabase(url: URL?) {
        hashDatabasePath = url?.path ?? ""
        persist()
    }

    // MARK: - Per-game overrides & Properties

    private func captureDefaults() {
        defaultEntries = Dictionary(games.map { ($0.stableKey, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The live entry for a given id (Properties window reads this).
    func game(id: GameEntry.ID) -> GameEntry? {
        games.first { $0.id == id }
    }

    /// Nicely formatted emulator name (curated DB display name when available).
    func emulatorDisplayName(for game: GameEntry) -> String? {
        guard let choice = game.emulator else { return nil }
        if let option = availableOptions(for: game).first(where: { $0.choice == choice }) {
            return option.displayName
        }
        return choice.shortDisplayName
    }

    /// Parse and store a per-game arguments-only override. Empty text restores
    /// the curated platform/emulator profile.
    func setCustomLaunchArguments(_ text: String, for game: GameEntry) throws {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resetOverride(.launchArguments, for: game)
            return
        }
        let arguments = try LaunchArguments.parse(text)
        let core = game.emulator.flatMap {
            emulatorConfig.resolve(
                $0,
                for: game.platform,
                romExtension: game.launchPath.pathExtension
            )?.corePath
        }
        _ = try LaunchArguments.resolve(arguments, rom: game.launchPath, core: core)
        updateGame(game.id) { $0.launchArguments = arguments }
        updateOverride(game.stableKey) { $0.launchArguments = arguments }
    }

    func launchArgumentsText(for game: GameEntry) -> String {
        LaunchArguments.format(game.launchArguments)
    }

    func resolvedLaunchPreview(for game: GameEntry) -> String {
        guard let choice = game.emulator,
              let resolved = emulatorConfig.resolve(
                  choice,
                  for: game.platform,
                  romExtension: game.launchPath.pathExtension
              ) else {
            return "No runnable emulator selected"
        }
        do {
            let arguments = try LaunchArguments.resolve(
                game.launchArguments,
                rom: game.launchPath,
                core: resolved.corePath
            )
            var command: [String]
            if resolved.emulatorPath.pathExtension.lowercased() == "app" {
                command = ["/usr/bin/open", "-a", resolved.emulatorPath.path]
                if !arguments.isEmpty {
                    command.append("--args")
                    command.append(contentsOf: arguments)
                }
            } else {
                command = [resolved.emulatorPath.path] + arguments
            }
            return LaunchArguments.format(command)
        } catch {
            return error.localizedDescription
        }
    }

    /// Launch the game immediately with the same structured arguments used by
    /// generated bundles. This is only invoked from the explicit Test Launch button.
    func canTestLaunch(_ game: GameEntry, launchURL: URL) -> Bool {
        !emulatorConfig.availableOptions(
            for: game.platform,
            romExtension: launchURL.pathExtension
        ).isEmpty
    }

    func testLaunch(_ game: GameEntry, launchURL: URL? = nil) {
        let target = launchURL ?? game.launchPath
        let choice: EmulatorChoice?
        if launchURL != nil {
            let compatible = emulatorConfig.availableOptions(
                for: game.platform,
                romExtension: target.pathExtension
            )
            choice = compatible.contains(where: { $0.choice == game.emulator })
                ? game.emulator
                : emulatorConfig.defaultChoice(
                    for: game.platform,
                    romExtension: target.pathExtension
                )
        } else {
            choice = game.emulator
        }
        guard let choice,
              let resolved = emulatorConfig.resolve(
                  choice,
                  for: game.platform,
                  romExtension: target.pathExtension
              ) else {
            errorMessage = "No runnable emulator is selected."
            return
        }
        do {
            let arguments = try LaunchArguments.resolve(
                launchURL == nil ? game.launchArguments : resolved.launchArguments,
                rom: target,
                core: resolved.corePath
            )
            if resolved.emulatorPath.pathExtension.lowercased() == "app" {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.arguments = arguments
                NSWorkspace.shared.openApplication(
                    at: resolved.emulatorPath,
                    configuration: configuration
                ) { [weak self] _, error in
                    if let error {
                        Task { @MainActor in
                            self?.errorMessage = "Test launch failed: \(error.localizedDescription)"
                        }
                    }
                }
            } else {
                let process = Process()
                process.executableURL = resolved.emulatorPath
                process.arguments = arguments
                try process.run()
            }
        } catch {
            errorMessage = "Test launch failed: \(error.localizedDescription)"
        }
    }

    // MARK: Custom artwork

    /// Whether the game has cached artwork (fetched or user-supplied).
    func hasArtwork(_ game: GameEntry) -> Bool {
        if case .cached = game.artworkStatus { return true }
        return artworkCache.hasOriginal(for: game.stableKey)
    }

    /// Use a user-chosen image file as the game's artwork. Re-encodes to PNG so
    /// the cache's `original.png` is always a real PNG regardless of the source
    /// format the bundle generator can convert.
    func setCustomArtwork(url: URL, for game: GameEntry) {
        do {
            guard let png = Self.pngData(from: url) else {
                errorMessage = "Couldn't read that image."
                return
            }
            let metadata = ArtworkMetadata(
                sgdbGameId: nil, sgdbImageId: nil, downloadedAt: Date(), sourceType: "custom")
            let stored = try artworkCache.store(originalPNG: png, metadata: metadata, for: game.stableKey)
            updateGame(game.id) { $0.artworkStatus = .cached(stored) }
        } catch {
            errorMessage = "Couldn't set artwork: \(error.localizedDescription)"
        }
    }

    func removeArtwork(for game: GameEntry) {
        try? artworkCache.remove(for: game.stableKey)
        updateGame(game.id) { $0.artworkStatus = .none }
    }

    private static func pngData(from url: URL) -> Data? {
        guard let image = NSImage(contentsOf: url),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: Override introspection & reset

    func hasOverride(_ field: OverrideField, for game: GameEntry) -> Bool {
        guard let override = config.gameOverrides[game.stableKey] else { return false }
        switch field {
        case .title:       return override.customTitle != nil
        case .platform:    return override.platform != nil
        case .emulator:    return override.emulator != nil
        case .launchArguments: return override.launchArguments != nil
        case .launchImage: return override.imagePath != nil
        case .dosLaunchTarget: return override.dosLaunchTargetPath != nil
        }
    }

    var anyOverrides: (GameEntry) -> Bool {
        { game in self.config.gameOverrides[game.stableKey] != nil }
    }

    /// Restore a single field to its post-scan default and drop that part of the
    /// override.
    func resetOverride(_ field: OverrideField, for game: GameEntry) {
        let base = defaultEntries[game.stableKey]
        updateGame(game.id) { entry in
            switch field {
            case .title:
                entry.title = base?.title ?? entry.romMetadata.title
            case .platform:
                if let base { entry.platform = base.platform }
                // Re-resolve the default emulator for the restored platform.
                if let choice = self.emulatorConfig.defaultChoice(
                    for: entry.platform,
                    romExtension: entry.launchPath.pathExtension
                ) {
                    self.assignEmulator(&entry, choice: choice)
                } else {
                    self.clearEmulator(&entry)
                }
            case .emulator:
                if let choice = self.emulatorConfig.defaultChoice(
                    for: entry.platform,
                    romExtension: entry.launchPath.pathExtension
                ) {
                    self.assignEmulator(&entry, choice: choice)
                } else {
                    self.clearEmulator(&entry)
                }
            case .launchArguments:
                if let choice = entry.emulator {
                    entry.launchArguments = self.database.launchArguments(
                        for: choice,
                        platform: entry.platform,
                        romExtension: entry.launchPath.pathExtension
                    )
                } else {
                    entry.launchArguments = []
                }
            case .launchImage:
                entry.launchImage = base?.launchImage
            case .dosLaunchTarget:
                entry.dosPackage = base?.dosPackage
                if entry.dosPackage?.requiresLaunchSelection == true {
                    self.clearEmulator(&entry)
                } else if let choice = self.emulatorConfig.defaultChoice(
                    for: entry.platform,
                    romExtension: entry.launchPath.pathExtension
                ) {
                    self.assignEmulator(&entry, choice: choice)
                }
            }
        }
        updateOverride(game.stableKey) { override in
            switch field {
            case .title:       override.customTitle = nil
            case .platform:
                override.platform = nil
                override.emulator = nil
                override.launchArguments = nil
            case .emulator:
                override.emulator = nil
                override.launchArguments = nil
            case .launchArguments: override.launchArguments = nil
            case .launchImage: override.imagePath = nil
            case .dosLaunchTarget:
                override.dosLaunchTargetPath = nil
                override.emulator = nil
                override.launchArguments = nil
            }
        }
    }

    /// Restore every overridden field to its post-scan default and clear the
    /// whole override. Artwork (cache-backed, not a GameOverride) is untouched.
    func resetOverrides(for game: GameEntry) {
        if let base = defaultEntries[game.stableKey] {
            updateGame(game.id) { entry in
                entry.title = base.title
                entry.platform = base.platform
                entry.emulator = base.emulator
                entry.emulatorPath = base.emulatorPath
                entry.launchArguments = base.launchArguments
                entry.launchImage = base.launchImage
                entry.dosPackage = base.dosPackage
            }
        }
        config.gameOverrides.removeValue(forKey: game.stableKey)
        persist()
    }

    // MARK: - Generation preview

    /// The authoritative action for a game in the next generation run.
    enum GenerationAction: Equatable {
        case create
        case update
        case upToDate
        case needsAttention
        case excluded
    }

    /// One generation plan drives the table, output summary, and generator.
    struct GenerationPlan: Equatable {
        var created = 0
        var updated = 0
        var upToDate = 0
        var needsAttention = 0
        var excluded = 0
        var removed = 0
        var actions: [String: GenerationAction] = [:]

        var pendingCount: Int { created + updated }
        var selectedCount: Int { created + updated + upToDate + needsAttention }
        var isUpToDate: Bool { pendingCount == 0 && needsAttention == 0 && selectedCount > 0 }

        func action(for game: GameEntry) -> GenerationAction {
            actions[game.stableKey] ?? (game.isSelected ? .needsAttention : .excluded)
        }
    }

    /// A cheap signature of every input that can affect the generation plan.
    var generationSignature: Int {
        var hasher = Hasher()
        for game in games {
            hasher.combine(game.stableKey)
            hasher.combine(game.isSelected)
            hasher.combine(game.title)
            hasher.combine(game.platform.id)
            hasher.combine(game.emulator?.signatureToken)
            hasher.combine(game.emulatorPath?.path)
            hasher.combine(game.launchArguments)
            hasher.combine(game.launchPath.path)
            if case .cached(let url) = game.artworkStatus {
                hasher.combine(url.path)
                if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) {
                    hasher.combine(values.contentModificationDate)
                    hasher.combine(values.fileSize)
                }
            }
        }
        hasher.combine(outputDirectory)
        hasher.combine(lastConversionDate)
        hasher.combine(removeOrphanedBundles)
        hasher.combine(generationRevision)
        return hasher.finalize()
    }

    /// Non-mutating dry run: mirrors `generate()`'s change classification so the
    /// label matches what generate then does. A new/modified game with no
    /// emulator is NOT counted (generate skips it with a warning).
    func generationPlan() async -> GenerationPlan {
        let selected = games.filter { $0.isSelected }
        let previousState = try? await configStore.loadGameState()
        return makeGenerationPlan(previousState: previousState, selected: selected)
    }

    private func makeGenerationPlan(
        previousState: GameConversionState?,
        selected: [GameEntry]
    ) -> GenerationPlan {
        let outputURL = outputDirectory.isEmpty ? nil : URL(fileURLWithPath: outputDirectory)
        let changes = incrementalManager.detectChanges(
            currentGames: selected,
            previousState: previousState,
            outputDirectory: outputURL)
        var plan = GenerationPlan()

        for game in games where !game.isSelected {
            plan.excluded += 1
            plan.actions[game.stableKey] = .excluded
        }

        for game in selected {
            guard let change = changes[game.stableKey] else { continue }
            guard game.status == .ready else {
                plan.needsAttention += 1
                plan.actions[game.stableKey] = .needsAttention
                continue
            }
            switch change.changeType {
            case .unchanged:
                plan.upToDate += 1
                plan.actions[game.stableKey] = .upToDate
            case .new:
                plan.created += 1
                plan.actions[game.stableKey] = .create
            case .modified:
                plan.updated += 1
                plan.actions[game.stableKey] = .update
            case .removed:
                break
            }
        }
        if removeOrphanedBundles {
            plan.removed = changes.values.filter { $0.changeType == .removed }.count
        }
        return plan
    }

    // MARK: - Generation

    func generate(forceRebuild: Bool = false) async {
        guard !outputDirectory.isEmpty else {
            errorMessage = "Select an output directory first."
            return
        }
        isProcessing = true
        operation = .generating
        progressValue = 0
        conversionSummary = nil
        showingSummary = false
        defer {
            isProcessing = false
            operation = .idle
        }

        let outputURL = URL(fileURLWithPath: outputDirectory)
        let selected = games.filter { $0.isSelected }
        let previousState = try? await configStore.loadGameState()
        let changes = incrementalManager.detectChanges(
            currentGames: selected,
            previousState: previousState,
            outputDirectory: outputURL)

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

            if change.changeType == .unchanged && !forceRebuild {
                skipped += 1
                if let previous = previousState?.convertedGames.first(where: { $0.stableKey == game.stableKey }) {
                    records.append(previous)
                }
                continue
            }

            guard let choice = game.emulator,
                  let resolved = emulatorConfig.resolve(
                      choice,
                      for: game.platform,
                      romExtension: game.launchPath.pathExtension
                  ) else {
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
                bundleName: DefaultAppBundleGenerator.sanitizedBundleName(game.title),
                bundleIdentifier: idByKey[game.stableKey] ?? "com.romshortcutmaker.game",
                displayName: game.title,
                executablePath: resolved.emulatorPath,
                launchArguments: game.launchArguments,
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

    private func applyFolderPlatformRules(to games: inout [GameEntry]) {
        guard !config.folderPlatformRules.isEmpty else { return }

        for index in games.indices {
            let game = games[index]
            guard game.platform.id == "unknown",
                  config.gameOverrides[game.stableKey]?.platform == nil,
                  let detection = detectionByKey[game.stableKey],
                  let rule = matchingFolderRule(for: detection.sourceDirectory),
                  let platform = database.allPlatforms.first(where: { $0.id == rule.platformID }) else {
                continue
            }

            games[index].platform = platform
            if let choice = emulatorConfig.defaultChoice(
                for: platform,
                romExtension: games[index].launchPath.pathExtension
            ) {
                assignEmulator(&games[index], choice: choice)
            }
            var updatedDetection = detection
            updatedDetection.candidates = [platform]
            updatedDetection.evidence.append("Explicit folder rule: \(platform.displayName).")
            updatedDetection.resolvedBy = "explicit folder rule"
            detectionByKey[game.stableKey] = updatedDetection
        }
    }

    private func clearEmulator(_ entry: inout GameEntry) {
        entry.emulator = nil
        entry.emulatorPath = nil
        entry.launchArguments = []
    }

    private func applyPlatform(_ platform: Platform, toGameID id: GameEntry.ID) {
        updateGame(id) {
            $0.platform = platform
            if let choice = self.emulatorConfig.defaultChoice(
                for: platform,
                romExtension: $0.launchPath.pathExtension
            ) {
                self.assignEmulator(&$0, choice: choice)
            } else {
                self.clearEmulator(&$0)
            }
        }
    }

    private func matchingFolderRule(for sourceDirectory: URL) -> (path: String, platformID: String)? {
        let sourcePath = sourceDirectory.standardizedFileURL.path
        let candidateRoots = watchedFolders
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
            .filter { isPath(sourcePath, inside: $0) }
        guard let scanRoot = candidateRoots.max(by: { $0.count < $1.count }) else {
            return nil
        }
        var current = sourceDirectory.standardizedFileURL
        while isPath(current.path, inside: scanRoot) {
            if let platformID = config.folderPlatformRules[current.path] {
                return (current.path, platformID)
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return nil
    }

    private func isPath(_ path: String, inside root: String) -> Bool {
        path == root || root == "/" || path.hasPrefix(root + "/")
    }

    private func updateGame(_ id: UUID, _ transform: (inout GameEntry) -> Void) {
        guard let index = games.firstIndex(where: { $0.id == id }) else { return }
        transform(&games[index])
        generationRevision &+= 1
    }

    private func updateOverride(_ key: String, _ transform: (inout GameOverride) -> Void) {
        mutateOverride(key, transform)
        persist()
    }

    private func mutateOverride(_ key: String, _ transform: (inout GameOverride) -> Void) {
        var override = config.gameOverrides[key] ?? GameOverride()
        transform(&override)
        if override == GameOverride() {
            config.gameOverrides.removeValue(forKey: key)
        } else {
            config.gameOverrides[key] = override
        }
    }

}
