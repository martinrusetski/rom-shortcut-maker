//
//  VDFToGameEntryBridge.swift
//  SteamShortcutConverter
//
//  Maps legacy Steam shortcuts (SteamShortcut) into the ROM pipeline's GameEntry,
//  reusing the existing (now-fixed) VDF parser/filter/launch-parser.
//

import Foundation

final class VDFToGameEntryBridge {

    private let database: SystemDatabase
    private let filter: ShortcutFilter
    private let launchParser: LaunchCommandParser
    private let filenameParser: ROMFilenameParser

    init(
        database: SystemDatabase,
        filter: ShortcutFilter = DefaultShortcutFilter(),
        launchParser: LaunchCommandParser = LaunchCommandParser(),
        filenameParser: ROMFilenameParser = ROMFilenameParser()
    ) {
        self.database = database
        self.filter = filter
        self.launchParser = launchParser
        self.filenameParser = filenameParser
    }

    func makeEntries(from shortcuts: [SteamShortcut], legacyCustomNames: [UInt32: String] = [:]) -> [GameEntry] {
        shortcuts.compactMap { makeEntry(from: $0, legacyCustomNames: legacyCustomNames) }
    }

    /// Map one shortcut. Returns nil if no ROM argument can be identified.
    func makeEntry(from shortcut: SteamShortcut, legacyCustomNames: [UInt32: String] = [:]) -> GameEntry? {
        guard let config = try? launchParser.parseLaunchConfiguration(from: shortcut),
              let romPath = romArgument(in: config) else {
            return nil
        }

        let romURL = URL(fileURLWithPath: romPath)
        let title = legacyCustomNames[shortcut.appID] ?? shortcut.appName
        let metadata = filenameParser.parse(filename: romURL.lastPathComponent)
        let platform = database.platforms(forExtension: "." + romURL.pathExtension).first
            ?? Platform(id: "unknown", displayName: "Unknown")

        let detected = filter.detectEmulator(for: shortcut)
        let emulator: EmulatorChoice? = detected.map { .standalone($0) }
        let argsTemplate = emulator.map { database.argsTemplate(for: $0) } ?? "\"{emulator}\" \"{rom}\""

        return GameEntry(
            title: title,
            romPath: romURL,
            romMetadata: metadata,
            platform: platform,
            emulator: emulator,
            emulatorPath: URL(fileURLWithPath: config.executablePath),
            argsTemplate: argsTemplate,
            artworkStatus: .none,
            source: .steamVDF
        )
    }

    /// The ROM is the last path-like argument that isn't a flag or a libretro core.
    private func romArgument(in config: LaunchConfiguration) -> String? {
        config.arguments.filter { arg in
            !arg.hasPrefix("-") &&
            !arg.hasSuffix(".dylib") &&
            !arg.contains("_libretro") &&
            (arg.contains("/") || arg.contains("."))
        }.last
    }
}
