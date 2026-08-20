//
//  SystemDatabase.swift
//  RomShortcutMaker
//
//  Loads and queries the curated emulator / system knowledge base from the
//  bundled `emulators.json` resource. The data lives in JSON (not Swift switch
//  statements) so it can be edited/diffed/tested without recompiling.
//

import Foundation

// MARK: - Bundle resolver

extension Bundle {
    /// Resolves the bundle that carries the app's resources. Under `swift test`
    /// (SPM) that is the generated `Bundle.module`; in the shipped app it is
    /// `Bundle.main`. `Bundle.module` only exists in the SPM build, so the
    /// selection must be a compile-time `#if`, not a runtime fallback.
    static var resolved: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }
}

// MARK: - EmulatorOption

/// A selectable way to run a platform, before checking what's installed.
struct EmulatorOption: Equatable, Hashable {
    let choice: EmulatorChoice      // .standalone(type) or .retroArchCore(core)
    let displayName: String         // "Snes9x" or "bsnes (RetroArch)"
    let launchArguments: [String]   // Structured argument templates; executable is separate.
    let launchArgumentsByExtension: [String: [String]]
    let supportedExtensions: Set<String>?
    let supportsZIP: Bool

    init(
        choice: EmulatorChoice,
        displayName: String,
        launchArguments: [String],
        launchArgumentsByExtension: [String: [String]] = [:],
        supportedExtensions: Set<String>? = nil,
        supportsZIP: Bool = false
    ) {
        self.choice = choice
        self.displayName = displayName
        self.launchArguments = launchArguments
        self.launchArgumentsByExtension = launchArgumentsByExtension
        self.supportedExtensions = supportedExtensions
        self.supportsZIP = supportsZIP
    }

    /// An omitted rule means the database has no format restriction for this
    /// option. Explicit rules are normalized with a leading dot.
    func supports(extension ext: String) -> Bool {
        let normalized = ext.lowercased().hasPrefix(".") ? ext.lowercased() : "." + ext.lowercased()
        if normalized == ".zip" {
            return supportedExtensions?.contains(normalized) ?? supportsZIP
        }
        guard let supportedExtensions else { return true }
        return supportedExtensions.contains(normalized)
    }

    func arguments(forExtension ext: String) -> [String] {
        let normalized = ext.lowercased().hasPrefix(".") ? ext.lowercased() : "." + ext.lowercased()
        return launchArgumentsByExtension[normalized] ?? launchArguments
    }
}

// MARK: - SystemDatabase

final class SystemDatabase {

    enum DatabaseError: LocalizedError {
        case resourceNotFound
        case decodeFailed(Error)
        case unknownEmulator(String)
        case unknownOptionType(String)
        case malformedOption(String)

        var errorDescription: String? {
            switch self {
            case .resourceNotFound:
                return "emulators.json resource not found in bundle."
            case .decodeFailed(let error):
                return "Failed to decode emulators.json: \(error.localizedDescription)"
            case .unknownEmulator(let id):
                return "emulators.json references unknown emulator identifier: \(id)"
            case .unknownOptionType(let type):
                return "emulators.json contains unknown emulator option type: \(type)"
            case .malformedOption(let detail):
                return "emulators.json contains a malformed emulator option: \(detail)"
            }
        }
    }

    // MARK: Decoded JSON shape

    private struct Root: Decodable {
        let version: Int
        let platforms: [PlatformRecord]
        let genericRomExtensions: [String]?
        let emulators: [EmulatorRecord]
    }

    private struct PlatformRecord: Decodable {
        let id: String
        let displayName: String
        let folderAliases: [String]
        let romExtensions: [String]
        let chdMediaTypes: [String]?
        let chdMaxLogicalBytes: UInt64?
        let emulatorOptions: [OptionRecord]
        let libretroSystems: [String]?
        let supportsSingleFileZip: Bool?
    }

    private struct OptionRecord: Decodable {
        let type: String
        let emulator: String?
        let core: String?
        let displayName: String?
        let launchArguments: [String]?
        let launchArgumentsByExtension: [String: [String]]?
        let supportedExtensions: [String]?
        let supportsZip: Bool?
    }

    private struct EmulatorRecord: Decodable {
        let id: String
        let defaultLaunchArguments: [String]
    }

    // MARK: Stored state

    private let platformRecords: [PlatformRecord]
    private let genericRomExtensions: [String]
    private let emulatorDefaultArguments: [String: [String]]

    /// Every emulator identifier referenced by the `emulators[]` block (exposed
    /// for drift testing).
    let emulatorBlockIdentifiers: [String]

    // MARK: Init

    /// Loads & validates the database from the bundled resource.
    convenience init(bundle: Bundle = .resolved) throws {
        guard let url = bundle.url(forResource: "emulators", withExtension: "json") else {
            throw DatabaseError.resourceNotFound
        }
        let data = try Data(contentsOf: url)
        try self.init(data: data)
    }

    /// Loads & validates the database from raw JSON data (used by tests to feed
    /// crafted fixtures, including malformed ones).
    init(data: Data) throws {
        let root: Root
        do {
            root = try JSONDecoder().decode(Root.self, from: data)
        } catch {
            throw DatabaseError.decodeFailed(error)
        }

        // Validate emulator block ids map to real EmulatorTypes.
        for record in root.emulators {
            guard EmulatorType(rawValue: record.id) != nil else {
                throw DatabaseError.unknownEmulator(record.id)
            }
            do {
                try LaunchArguments.validate(record.defaultLaunchArguments)
            } catch {
                throw DatabaseError.malformedOption(
                    "default launch arguments for \(record.id): \(error.localizedDescription)"
                )
            }
        }

        // Validate every platform option.
        for platform in root.platforms {
            for option in platform.emulatorOptions {
                if let arguments = option.launchArguments {
                    do {
                        try LaunchArguments.validate(arguments)
                    } catch {
                        throw DatabaseError.malformedOption(
                            "launch arguments in \(platform.id): \(error.localizedDescription)"
                        )
                    }
                }
                if let argumentsByExtension = option.launchArgumentsByExtension {
                    for (ext, arguments) in argumentsByExtension {
                        do {
                            try LaunchArguments.validate(arguments)
                        } catch {
                            throw DatabaseError.malformedOption(
                                "launch arguments for \(ext) in \(platform.id): \(error.localizedDescription)"
                            )
                        }
                    }
                }
                switch option.type {
                case "standalone":
                    guard let emulator = option.emulator else {
                        throw DatabaseError.malformedOption("standalone option in \(platform.id) has no emulator")
                    }
                    guard EmulatorType(rawValue: emulator) != nil else {
                        throw DatabaseError.unknownEmulator(emulator)
                    }
                case "retroArchCore":
                    guard option.core != nil else {
                        throw DatabaseError.malformedOption("retroArchCore option in \(platform.id) has no core")
                    }
                default:
                    throw DatabaseError.unknownOptionType(option.type)
                }
            }
        }

        self.platformRecords = root.platforms
        self.genericRomExtensions = root.genericRomExtensions ?? []
        var defaultArguments: [String: [String]] = [:]
        for record in root.emulators {
            defaultArguments[record.id] = record.defaultLaunchArguments
        }
        self.emulatorDefaultArguments = defaultArguments
        self.emulatorBlockIdentifiers = root.emulators.map { $0.id }
    }

    // MARK: Queries

    /// All known platforms (identity values), in database order.
    var allPlatforms: [Platform] {
        platformRecords.map { Platform(id: $0.id, displayName: $0.displayName) }
    }

    /// Every platform folder alias (lowercased), across all platforms. Used by
    /// the filename parser to recognize and strip platform-name tags like
    /// `[GameCube]` or `(Nintendo Wii)` from titles.
    var allFolderAliases: Set<String> {
        var result: Set<String> = []
        for record in platformRecords {
            for alias in record.folderAliases { result.insert(alias.lowercased()) }
        }
        return result
    }

    /// Folder fallback signal: match a (case-insensitive) directory name against
    /// platform folder aliases.
    func platform(forFolderName name: String) -> Platform? {
        let key = name.lowercased()
        for record in platformRecords {
            if record.folderAliases.contains(where: { $0.lowercased() == key }) {
                return Platform(id: record.id, displayName: record.displayName)
            }
        }
        return nil
    }

    /// Platform candidates whose ROM extensions include `ext` (surfaces
    /// collisions instead of hiding them).
    func platforms(forExtension ext: String) -> [Platform] {
        let normalized = normalizeExtension(ext)
        var result: [Platform] = []
        for record in platformRecords {
            if record.romExtensions.contains(where: { normalizeExtension($0) == normalized }) {
                result.append(Platform(id: record.id, displayName: record.displayName))
            }
        }
        return result
    }

    /// Platforms whose CHD media profile matches the image's internal metadata.
    /// A maximum logical size is used for formats that share a media type: PSP
    /// UMD images are DVDs, but cannot be larger than the UMD capacity.
    func platforms(forCHDMediaType mediaType: String, logicalBytes: UInt64) -> [Platform] {
        platformRecords.compactMap { record in
            guard record.chdMediaTypes?.contains(mediaType) == true,
                  record.chdMaxLogicalBytes.map({ logicalBytes <= $0 }) ?? true else {
                return nil
            }
            return Platform(id: record.id, displayName: record.displayName)
        }
    }

    /// Ordered list of all known ways to run a platform (before checking what's
    /// installed).
    func emulatorOptions(for platform: Platform) -> [EmulatorOption] {
        guard let record = platformRecords.first(where: { $0.id == platform.id }) else {
            return []
        }
        return record.emulatorOptions.compactMap { option in
            switch option.type {
            case "standalone":
                guard let emulator = option.emulator,
                      let type = EmulatorType(rawValue: emulator) else { return nil }
                return EmulatorOption(
                    choice: .standalone(type),
                    displayName: option.displayName ?? emulator,
                    launchArguments: option.launchArguments
                        ?? emulatorDefaultArguments[type.rawValue]
                        ?? ["{romPath}"],
                    launchArgumentsByExtension: normalizedArgumentsByExtension(
                        option.launchArgumentsByExtension
                    ),
                    supportedExtensions: normalizedSupportedExtensions(option.supportedExtensions),
                    supportsZIP: option.supportsZip ?? false
                )
            case "retroArchCore":
                guard let core = option.core else { return nil }
                return EmulatorOption(
                    choice: .retroArchCore(core: core),
                    displayName: option.displayName ?? core,
                    launchArguments: option.launchArguments
                        ?? emulatorDefaultArguments["RetroArch"]
                        ?? ["-L", "{corePath}", "{romPath}"],
                    supportedExtensions: normalizedSupportedExtensions(option.supportedExtensions),
                    supportsZIP: option.supportsZip ?? false
                )
            default:
                return nil
            }
        }
    }

    private func normalizedSupportedExtensions(_ extensions: [String]?) -> Set<String>? {
        guard let extensions else { return nil }
        return Set(extensions.map(normalizeExtension))
    }

    private func normalizedArgumentsByExtension(
        _ arguments: [String: [String]]?
    ) -> [String: [String]] {
        guard let arguments else { return [:] }
        return Dictionary(uniqueKeysWithValues: arguments.map { key, value in
            (normalizeExtension(key), value)
        })
    }

    /// Resolve the curated launch profile for this exact platform/emulator pair.
    /// Platform options override the emulator-wide default where launch syntax
    /// depends on the emulated system (notably ares and MAME).
    func launchArguments(for choice: EmulatorChoice, platform: Platform) -> [String] {
        if let option = emulatorOptions(for: platform).first(where: { $0.choice == choice }) {
            return option.launchArguments
        }
        switch choice {
        case .standalone(let type):
            return emulatorDefaultArguments[type.rawValue] ?? ["{romPath}"]
        case .retroArchCore:
            return emulatorDefaultArguments["RetroArch"] ?? ["-L", "{corePath}", "{romPath}"]
        }
    }


    func launchArguments(
        for choice: EmulatorChoice,
        platform: Platform,
        romExtension: String
    ) -> [String] {
        if let option = emulatorOptions(for: platform).first(where: { $0.choice == choice }) {
            return option.arguments(forExtension: romExtension)
        }
        return launchArguments(for: choice, platform: platform)
    }

    /// The RetroArch libretro `systemid` tokens that map to a platform. Installed
    /// cores are matched to platforms by these (see EmulatorConfigManager).
    func libretroSystems(for platform: Platform) -> [String] {
        platformRecords.first(where: { $0.id == platform.id })?.libretroSystems ?? []
    }

    /// Whether a ZIP containing one cartridge-style ROM can be classified and
    /// launched for this platform. ROM-set ZIPs such as MAME are represented by
    /// a literal `.zip` entry in `romExtensions` instead.
    func supportsSingleFileZIP(for platform: Platform) -> Bool {
        platformRecords.first(where: { $0.id == platform.id })?.supportsSingleFileZip ?? false
    }

    /// RetroArch handles ZIP extraction at the frontend layer. It is safe to
    /// offer a core for platforms that use single-ROM archives, plus platforms
    /// where the ZIP itself is the native ROM-set format.
    func supportsZIPLaunch(for platform: Platform) -> Bool {
        guard let record = platformRecords.first(where: { $0.id == platform.id }) else {
            return false
        }
        return record.supportsSingleFileZip == true
            || record.romExtensions.contains { normalizeExtension($0) == ".zip" }
    }

    /// The union of all ROM extensions known to any platform (normalized,
    /// lowercased, leading dot).
    var allRomExtensions: Set<String> {
        var set: Set<String> = []
        for record in platformRecords {
            for ext in record.romExtensions {
                set.insert(normalizeExtension(ext))
            }
        }
        for ext in genericRomExtensions {
            set.insert(normalizeExtension(ext))
        }
        return set
    }

    // MARK: Helpers

    private func normalizeExtension(_ ext: String) -> String {
        let lower = ext.lowercased()
        return lower.hasPrefix(".") ? lower : "." + lower
    }
}
