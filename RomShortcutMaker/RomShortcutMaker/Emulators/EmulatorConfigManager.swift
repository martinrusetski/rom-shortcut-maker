//
//  EmulatorConfigManager.swift
//  RomShortcutMaker
//
//  Persists per-emulator config (path/enabled + RetroArch cores dir) and
//  per-platform default choices, and resolves which emulator options are
//  actually runnable for a platform.
//

import Foundation

// MARK: - Persisted model

/// Per-emulator settings (a block of config.json v2's `emulators`).
struct EmulatorSetting: Codable, Equatable {
    var path: String?
    var enabled: Bool
    var coresDir: String?     // RetroArch only

    init(path: String? = nil, enabled: Bool = true, coresDir: String? = nil) {
        self.path = path
        self.enabled = enabled
        self.coresDir = coresDir
    }
}

/// The emulator-related slice of config.json v2 (the `emulators` and
/// `emulatorDefaults` blocks).
struct EmulatorConfigData: Codable, Equatable {
    var emulators: [String: EmulatorSetting]        // keyed by EmulatorType.rawValue
    var defaults: [String: EmulatorChoice]          // keyed by platform id

    init(emulators: [String: EmulatorSetting] = [:], defaults: [String: EmulatorChoice] = [:]) {
        self.emulators = emulators
        self.defaults = defaults
    }
}

// MARK: - Persistence seam

/// Persistence abstraction for the emulator config slice. In A8 this is backed
/// by the unified config.json v2; here a file/in-memory store keeps A4 testable
/// in isolation.
protocol EmulatorConfigStore {
    func load() -> EmulatorConfigData
    func save(_ data: EmulatorConfigData)
}

/// In-memory store (used by tests).
final class InMemoryEmulatorConfigStore: EmulatorConfigStore {
    private var data: EmulatorConfigData
    init(_ data: EmulatorConfigData = EmulatorConfigData()) { self.data = data }
    func load() -> EmulatorConfigData { data }
    func save(_ data: EmulatorConfigData) { self.data = data }
}

/// JSON-file store at Application Support/RomShortcutMaker/emulator-config.json.
final class FileEmulatorConfigStore: EmulatorConfigStore {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("RomShortcutMaker", isDirectory: true)
            self.fileURL = base.appendingPathComponent("emulator-config.json")
        }
    }

    func load() -> EmulatorConfigData {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(EmulatorConfigData.self, from: data) else {
            return EmulatorConfigData()
        }
        return decoded
    }

    func save(_ data: EmulatorConfigData) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: fileURL, options: .atomic)
        } catch {
            Logger.shared.error("Failed to save emulator config", error: error)
        }
    }
}

// MARK: - Resolved launch

/// A fully resolved way to launch a ROM.
struct ResolvedLaunch: Equatable {
    let emulatorPath: URL     // the emulator .app or CLI binary path
    let launchArguments: [String]
    let corePath: URL?        // resolved RetroArch core .dylib (nil for standalone)
}

// MARK: - EmulatorConfigManager

final class EmulatorConfigManager {

    private let database: SystemDatabase
    private let detector: EmulatorDetector
    private let store: EmulatorConfigStore

    private var config: EmulatorConfigData
    private var detected: [EmulatorType: [URL]] = [:]
    private var installedCores: [InstalledCore] = []
    private var didRefresh = false

    init(database: SystemDatabase, detector: EmulatorDetector, store: EmulatorConfigStore) {
        self.database = database
        self.detector = detector
        self.store = store
        self.config = store.load()
    }

    // MARK: Detection cache

    /// Re-query the detector. Call after the user installs an emulator or changes
    /// paths. Detection is cached to avoid repeated filesystem walks.
    func refreshDetection() {
        detected = detector.detectAll()
        installedCores = detector.installedCores()
        didRefresh = true
    }

    private func ensureRefreshed() {
        if !didRefresh { refreshDetection() }
    }

    // MARK: Availability & defaults

    /// All options for a platform that the user can actually run right now:
    /// standalone emulator detected/configured + enabled, OR RetroArch installed
    /// + that core present + enabled.
    func availableOptions(for platform: Platform) -> [EmulatorOption] {
        ensureRefreshed()
        var options: [EmulatorOption] = []

        // Standalone emulators (curated per platform in the database).
        for option in database.emulatorOptions(for: platform) {
            if case .standalone(let type) = option.choice {
                let installed = !(detected[type] ?? []).isEmpty || hasConfiguredPath(type)
                if installed && isEnabled(type) { options.append(option) }
            }
        }

        // RetroArch cores, discovered dynamically: any installed core whose
        // libretro systemid maps to this platform. Display names come from the
        // core's .info file — no hardcoded core filenames.
        let retroArchInstalled = !(detected[.retroArch] ?? []).isEmpty || hasConfiguredPath(.retroArch)
        if retroArchInstalled && isEnabled(.retroArch) {
            let systems = Set(database.libretroSystems(for: platform))
            if !systems.isEmpty {
                for core in installedCores where (core.systemId.map { systems.contains($0) } ?? false) {
                    options.append(EmulatorOption(
                        choice: .retroArchCore(core: core.filename),
                        displayName: core.displayName,
                        launchArguments: database.launchArguments(
                            for: .retroArchCore(core: core.filename),
                            platform: platform
                        ),
                        supportedExtensions: core.supportedExtensions,
                        supportsZIP: database.supportsZIPLaunch(for: platform)
                    ))
                }
            }
        }

        return options
    }

    /// Format-aware availability for a specific launch image. ZIP support is
    /// opt-in; other formats preserve the existing allow-list behavior.
    func availableOptions(for platform: Platform, romExtension: String) -> [EmulatorOption] {
        availableOptions(for: platform).filter { $0.supports(extension: romExtension) }
    }

    /// The choice to assign automatically: the per-platform default if set and
    /// still available, otherwise the first available option.
    func defaultChoice(for platform: Platform) -> EmulatorChoice? {
        let available = availableOptions(for: platform)
        if let configured = config.defaults[platform.id],
           available.contains(where: { $0.choice == configured }) {
            return configured
        }
        return available.first?.choice
    }

    func defaultChoice(for platform: Platform, romExtension: String) -> EmulatorChoice? {
        let available = availableOptions(for: platform, romExtension: romExtension)
        if let configured = config.defaults[platform.id],
           available.contains(where: { $0.choice == configured }) {
            return configured
        }
        return available.first?.choice
    }

    // MARK: Resolution

    /// Resolve a choice to concrete launch inputs, or nil if it isn't runnable.
    func resolve(_ choice: EmulatorChoice, for platform: Platform) -> ResolvedLaunch? {
        resolve(choice, for: platform, romExtension: "")
    }

    func resolve(
        _ choice: EmulatorChoice,
        for platform: Platform,
        romExtension: String
    ) -> ResolvedLaunch? {
        switch choice {
        case .standalone(let type):
            guard let path = emulatorPath(for: type) else { return nil }
            return ResolvedLaunch(
                emulatorPath: path,
                launchArguments: database.launchArguments(
                    for: choice,
                    platform: platform,
                    romExtension: romExtension
                ),
                corePath: nil
            )
        case .retroArchCore(let core):
            guard let path = emulatorPath(for: .retroArch) else { return nil }
            // Prefer the core's actual on-disk location (cores usually live in
            // Application Support, not the .app bundle).
            let corePath = installedCores.first(where: { $0.filename == core })?.url
                ?? coresDirectory().appendingPathComponent(core)
            return ResolvedLaunch(
                emulatorPath: path,
                launchArguments: database.launchArguments(
                    for: choice,
                    platform: platform,
                    romExtension: romExtension
                ),
                corePath: corePath
            )
        }
    }

    // MARK: Mutations (persisted)

    func setEnabled(_ enabled: Bool, for type: EmulatorType) {
        var setting = config.emulators[type.rawValue] ?? EmulatorSetting()
        setting.enabled = enabled
        config.emulators[type.rawValue] = setting
        persist()
    }

    func setPath(_ path: String?, for type: EmulatorType) {
        var setting = config.emulators[type.rawValue] ?? EmulatorSetting()
        setting.path = path
        config.emulators[type.rawValue] = setting
        persist()
    }

    func setCoresDir(_ path: String?) {
        var setting = config.emulators[EmulatorType.retroArch.rawValue] ?? EmulatorSetting()
        setting.coresDir = path
        config.emulators[EmulatorType.retroArch.rawValue] = setting
        persist()
    }

    func setDefaultChoice(_ choice: EmulatorChoice?, for platform: Platform) {
        config.defaults[platform.id] = choice
        persist()
    }

    func defaultChoiceSetting(for platform: Platform) -> EmulatorChoice? {
        config.defaults[platform.id]
    }

    func setting(for type: EmulatorType) -> EmulatorSetting? {
        config.emulators[type.rawValue]
    }

    // MARK: Helpers

    private func persist() {
        store.save(config)
    }

    private func isEnabled(_ type: EmulatorType) -> Bool {
        config.emulators[type.rawValue]?.enabled ?? true
    }

    private func hasConfiguredPath(_ type: EmulatorType) -> Bool {
        if let path = config.emulators[type.rawValue]?.path { return !path.isEmpty }
        return false
    }

    private func emulatorPath(for type: EmulatorType) -> URL? {
        if let path = config.emulators[type.rawValue]?.path, !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        ensureRefreshed()
        return detected[type]?.first
    }

    private func coresDirectory() -> URL {
        if let path = config.emulators[EmulatorType.retroArch.rawValue]?.coresDir, !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        if let retroArch = emulatorPath(for: .retroArch) {
            if retroArch.pathExtension.lowercased() == "app" {
                return retroArch.appendingPathComponent("Contents/Resources/cores")
            }
            return retroArch.deletingLastPathComponent().appendingPathComponent("cores")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/RetroArch/cores")
    }
}
