//
//  RomConfig.swift
//  SteamShortcutConverter
//
//  Config schema v2 for the ROM pipeline, plus persistence + v1→v2 migration.
//
//  Note: the per-emulator `emulators` and `emulatorDefaults` blocks from §3 are
//  owned by EmulatorConfigManager's own store (see A4); this v2 config owns the
//  rest (source mode, directories, API key, game overrides). Unifying both into
//  a single config.json is deferred to integration polish (A10).
//

import Foundation

/// A per-game override, keyed by `GameEntry.stableKey`.
struct GameOverride: Codable, Equatable {
    var customTitle: String?
    var emulator: EmulatorChoice?
    var args: String?
    var platform: String?      // platform id
    var imagePath: String?     // chosen launch image among alternates
}

/// config.json v2 (ROM pipeline slice).
struct AppConfigurationV2: Codable, Equatable {
    var version: Int
    var sourceMode: String                 // "scan" | "vdf"
    var lastScanDirectory: String?
    var outputDirectory: String?
    var removeOrphanedBundles: Bool
    var steamGridDBApiKey: String?
    var gameOverrides: [String: GameOverride]
    var lastConversionDate: Date?
    /// v1 custom names (keyed by Steam appID), preserved through migration so they
    /// can reattach on the first VDF re-import.
    var legacyCustomNames: [UInt32: String]
    /// Platform ids whose list section the user has collapsed. Persisted so the
    /// expand/collapse state survives relaunch.
    var collapsedPlatforms: Set<String>

    init(
        version: Int = 2,
        sourceMode: String = "scan",
        lastScanDirectory: String? = nil,
        outputDirectory: String? = nil,
        removeOrphanedBundles: Bool = false,
        steamGridDBApiKey: String? = nil,
        gameOverrides: [String: GameOverride] = [:],
        lastConversionDate: Date? = nil,
        legacyCustomNames: [UInt32: String] = [:],
        collapsedPlatforms: Set<String> = []
    ) {
        self.version = version
        self.sourceMode = sourceMode
        self.lastScanDirectory = lastScanDirectory
        self.outputDirectory = outputDirectory
        self.removeOrphanedBundles = removeOrphanedBundles
        self.steamGridDBApiKey = steamGridDBApiKey
        self.gameOverrides = gameOverrides
        self.lastConversionDate = lastConversionDate
        self.legacyCustomNames = legacyCustomNames
        self.collapsedPlatforms = collapsedPlatforms
    }

    // Custom decoder so newly-added fields (`collapsedPlatforms`, and any future
    // additions) don't break loading of an existing on-disk config that predates
    // them — a missing key falls back to the default rather than throwing and
    // wiping the user's whole configuration.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 2
        sourceMode = try c.decodeIfPresent(String.self, forKey: .sourceMode) ?? "scan"
        lastScanDirectory = try c.decodeIfPresent(String.self, forKey: .lastScanDirectory)
        outputDirectory = try c.decodeIfPresent(String.self, forKey: .outputDirectory)
        removeOrphanedBundles = try c.decodeIfPresent(Bool.self, forKey: .removeOrphanedBundles) ?? false
        steamGridDBApiKey = try c.decodeIfPresent(String.self, forKey: .steamGridDBApiKey)
        gameOverrides = try c.decodeIfPresent([String: GameOverride].self, forKey: .gameOverrides) ?? [:]
        lastConversionDate = try c.decodeIfPresent(Date.self, forKey: .lastConversionDate)
        legacyCustomNames = try c.decodeIfPresent([UInt32: String].self, forKey: .legacyCustomNames) ?? [:]
        collapsedPlatforms = try c.decodeIfPresent(Set<String>.self, forKey: .collapsedPlatforms) ?? []
    }

    static var `default`: AppConfigurationV2 { AppConfigurationV2() }

    /// Migrate a legacy v1 configuration. v1 keys are Steam appIDs and v2 keys are
    /// ROM-path hashes, so overrides can't be mapped directly — custom names are
    /// carried as `legacyCustomNames` and reattach on first VDF re-import.
    static func migrated(fromV1 v1: AppConfiguration) -> AppConfigurationV2 {
        AppConfigurationV2(
            version: 2,
            sourceMode: "vdf",
            lastScanDirectory: nil,
            outputDirectory: v1.outputDirectory,
            removeOrphanedBundles: v1.removeOrphanedBundles,
            steamGridDBApiKey: nil,
            gameOverrides: [:],
            lastConversionDate: v1.lastConversionDate,
            legacyCustomNames: v1.customNames
        )
    }
}

// MARK: - Store

protocol RomConfigStore {
    func load() async throws -> AppConfigurationV2
    func save(_ config: AppConfigurationV2) async throws
    func loadGameState() async throws -> GameConversionState?
    func saveGameState(_ state: GameConversionState) async throws
}

/// In-memory store (tests).
final class InMemoryRomConfigStore: RomConfigStore {
    private var config: AppConfigurationV2
    private var state: GameConversionState?

    init(config: AppConfigurationV2 = .default, state: GameConversionState? = nil) {
        self.config = config
        self.state = state
    }

    func load() async throws -> AppConfigurationV2 { config }
    func save(_ config: AppConfigurationV2) async throws { self.config = config }
    func loadGameState() async throws -> GameConversionState? { state }
    func saveGameState(_ state: GameConversionState) async throws { self.state = state }
}

/// JSON-file store with v1→v2 migration on load.
final class DefaultRomConfigStore: RomConfigStore {

    private struct VersionProbe: Codable { let version: Int? }

    private let configURL: URL
    private let stateURL: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("RomShortcutMaker", isDirectory: true)
        self.configURL = base.appendingPathComponent("config.json")
        self.stateURL = base.appendingPathComponent("game_state.json")
    }

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    func load() async throws -> AppConfigurationV2 {
        guard let data = try? Data(contentsOf: configURL) else { return .default }
        let dec = decoder()
        if let probe = try? dec.decode(VersionProbe.self, from: data), probe.version == 2 {
            return (try? dec.decode(AppConfigurationV2.self, from: data)) ?? .default
        }
        // No version field → treat as v1 and migrate.
        if let v1 = try? dec.decode(AppConfiguration.self, from: data) {
            let migrated = AppConfigurationV2.migrated(fromV1: v1)
            try? await save(migrated)
            return migrated
        }
        return .default
    }

    func save(_ config: AppConfigurationV2) async throws {
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder().encode(config).write(to: configURL, options: .atomic)
    }

    func loadGameState() async throws -> GameConversionState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? decoder().decode(GameConversionState.self, from: data)
    }

    func saveGameState(_ state: GameConversionState) async throws {
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder().encode(state).write(to: stateURL, options: .atomic)
    }
}
