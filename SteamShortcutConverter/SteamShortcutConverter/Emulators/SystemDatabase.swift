//
//  SystemDatabase.swift
//  SteamShortcutConverter
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
        let emulators: [EmulatorRecord]
    }

    private struct PlatformRecord: Decodable {
        let id: String
        let displayName: String
        let folderAliases: [String]
        let romExtensions: [String]
        let emulatorOptions: [OptionRecord]
    }

    private struct OptionRecord: Decodable {
        let type: String
        let emulator: String?
        let core: String?
        let displayName: String?
    }

    private struct EmulatorRecord: Decodable {
        let id: String
        let argsTemplate: String
    }

    // MARK: Stored state

    private let platformRecords: [PlatformRecord]
    private let emulatorTemplates: [String: String]   // emulator id -> args template

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
        }

        // Validate every platform option.
        for platform in root.platforms {
            for option in platform.emulatorOptions {
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
        var templates: [String: String] = [:]
        for record in root.emulators {
            templates[record.id] = record.argsTemplate
        }
        self.emulatorTemplates = templates
        self.emulatorBlockIdentifiers = root.emulators.map { $0.id }
    }

    // MARK: Queries

    /// All known platforms (identity values), in database order.
    var allPlatforms: [Platform] {
        platformRecords.map { Platform(id: $0.id, displayName: $0.displayName) }
    }

    /// PRIMARY platform signal: match a (case-insensitive) directory name
    /// against platform folder aliases.
    func platform(forFolderName name: String) -> Platform? {
        let key = name.lowercased()
        for record in platformRecords {
            if record.folderAliases.contains(where: { $0.lowercased() == key }) {
                return Platform(id: record.id, displayName: record.displayName)
            }
        }
        return nil
    }

    /// SECONDARY platform signal: all platforms whose ROM extensions include
    /// `ext` (surfaces collisions instead of hiding them).
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
                    displayName: option.displayName ?? emulator
                )
            case "retroArchCore":
                guard let core = option.core else { return nil }
                return EmulatorOption(
                    choice: .retroArchCore(core: core),
                    displayName: option.displayName ?? core
                )
            default:
                return nil
            }
        }
    }

    /// The args template for a choice: the standalone emulator's template, or
    /// RetroArch's `{core}` template for a core choice.
    func argsTemplate(for choice: EmulatorChoice) -> String {
        switch choice {
        case .standalone(let type):
            return emulatorTemplates[type.rawValue] ?? "\"{emulator}\" \"{rom}\""
        case .retroArchCore:
            return emulatorTemplates["RetroArch"] ?? "\"{emulator}\" -L \"{core}\" \"{rom}\""
        }
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
        return set
    }

    // MARK: Helpers

    private func normalizeExtension(_ ext: String) -> String {
        let lower = ext.lowercased()
        return lower.hasPrefix(".") ? lower : "." + lower
    }
}
