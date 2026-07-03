//
//  ROMScanner.swift
//  SteamShortcutConverter
//
//  Walks a directory tree, identifies ROM files, and assigns each a platform
//  using folder-first inference (the key design decision here).
//

import Foundation

// MARK: - DiscoveredROM

struct DiscoveredROM: Equatable {
    let url: URL                          // primary entry point to launch
    let fileSize: Int64
    let romExtension: String              // normalized, with leading dot, e.g. ".sfc"
    let platform: Platform?               // resolved by inference (nil if ambiguous)
    let candidateEmulators: [EmulatorType]
    let platformAmbiguous: Bool           // extension matched multiple platforms and
                                          // the folder didn't disambiguate

    // MARK: Multi-disc / multi-file
    /// Track / disc files referenced by this entry (for change hashing).
    let memberFiles: [URL]
    /// Other launchable images of the *same* disc (e.g. a .chd alongside a .cue).
    let alternateImages: [URL]
    /// Ordered per-disc entry points for a multi-disc game that has NO existing
    /// .m3u — a playlist must be generated. Empty for single-disc games and for
    /// games that already have an .m3u (whose url points at that .m3u).
    let discPaths: [URL]

    init(
        url: URL,
        fileSize: Int64,
        romExtension: String,
        platform: Platform?,
        candidateEmulators: [EmulatorType],
        platformAmbiguous: Bool,
        memberFiles: [URL] = [],
        alternateImages: [URL] = [],
        discPaths: [URL] = []
    ) {
        self.url = url
        self.fileSize = fileSize
        self.romExtension = romExtension
        self.platform = platform
        self.candidateEmulators = candidateEmulators
        self.platformAmbiguous = platformAmbiguous
        self.memberFiles = memberFiles
        self.alternateImages = alternateImages
        self.discPaths = discPaths
    }
}

// MARK: - ROMScanning

protocol ROMScanning {
    func scan(directory: URL,
              progress: @escaping (Double) -> Void) async throws -> [DiscoveredROM]
}

// MARK: - ROMScanner

final class ROMScanner: ROMScanning {

    enum ScanError: LocalizedError {
        case directoryNotReadable(URL)

        var errorDescription: String? {
            switch self {
            case .directoryNotReadable(let url):
                return "Cannot read directory: \(url.path)"
            }
        }
    }

    private let database: SystemDatabase
    private let filenameParser = ROMFilenameParser()

    init(database: SystemDatabase) {
        self.database = database
    }

    func scan(directory: URL,
              progress: @escaping (Double) -> Void) async throws -> [DiscoveredROM] {
        let fileManager = FileManager.default
        let knownExtensions = database.allRomExtensions

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ScanError.directoryNotReadable(directory)
        }

        // First pass: collect candidate ROM files (so progress has a denominator).
        var candidates: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let ext = normalizedExtension(of: url)
            guard !ext.isEmpty, knownExtensions.contains(ext) else { continue }
            candidates.append(url)
        }

        guard !candidates.isEmpty else {
            progress(1.0)
            return []
        }

        progress(0.0)

        // Resolve disc entry points: sheets (.cue/.gdi/.ccd) consume their track
        // members, and playlists (.m3u) consume the disc images they list. Only
        // true entry points survive.
        let (entryPoints, membersByEntry) = resolveEntryPoints(candidates)

        // Group entry points that belong to the same game (same folder + parsed
        // title) so multi-disc games and multi-image discs collapse into one.
        let groups = groupByGame(entryPoints)

        guard !groups.isEmpty else {
            progress(1.0)
            return []
        }

        var results: [DiscoveredROM] = []
        let total = groups.count
        for (index, group) in groups.enumerated() {
            if let rom = makeDiscoveredROM(for: group, root: directory, membersByEntry: membersByEntry) {
                results.append(rom)
            }
            progress(Double(index + 1) / Double(total))
        }

        return results
    }

    // MARK: - Entry-point resolution

    private func resolveEntryPoints(_ candidates: [URL]) -> (entryPoints: [URL], membersByEntry: [String: [URL]]) {
        var consumed = Set<String>()
        var membersByEntry: [String: [URL]] = [:]

        func key(_ url: URL) -> String { url.standardizedFileURL.path }

        // Sheets consume their track files.
        for candidate in candidates where DiscImage.isSheet(candidate) {
            let members = DiscImage.members(ofSheet: candidate)
            membersByEntry[key(candidate), default: []].append(contentsOf: members)
            for member in members { consumed.insert(key(member)) }
        }

        // Playlists consume the disc images they reference (and, transitively,
        // those discs' own track members).
        for candidate in candidates where DiscImage.isPlaylist(candidate) {
            let discs = DiscImage.entries(ofPlaylist: candidate)
            for disc in discs {
                consumed.insert(key(disc))
                membersByEntry[key(candidate), default: []].append(disc)
                if let subMembers = membersByEntry[key(disc)] {
                    membersByEntry[key(candidate), default: []].append(contentsOf: subMembers)
                    for sub in subMembers { consumed.insert(key(sub)) }
                }
            }
        }

        let entryPoints = candidates.filter { !consumed.contains(key($0)) }
        return (entryPoints, membersByEntry)
    }

    // MARK: - Grouping

    private struct GameGroupKey: Hashable {
        let directory: String
        let title: String
    }

    private func groupByGame(_ entryPoints: [URL]) -> [[URL]] {
        var order: [GameGroupKey] = []
        var groups: [GameGroupKey: [URL]] = [:]
        for url in entryPoints {
            let metadata = filenameParser.parse(filename: url.lastPathComponent)
            let key = GameGroupKey(
                directory: url.deletingLastPathComponent().standardizedFileURL.path,
                title: metadata.title.lowercased()
            )
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(url)
        }
        return order.map { groups[$0]! }
    }

    private func makeDiscoveredROM(
        for group: [URL],
        root: URL,
        membersByEntry: [String: [URL]]
    ) -> DiscoveredROM? {
        guard let first = group.first else { return nil }
        let platformInfo = resolvePlatform(for: first, root: root)
        let platformId = platformInfo.platform?.id ?? "unknown"

        // Bucket the group's entry points by disc number.
        var byDisc: [Int?: [URL]] = [:]
        var discOrder: [Int?] = []
        for url in group {
            let disc = filenameParser.parse(filename: url.lastPathComponent).discNumber
            if byDisc[disc] == nil { discOrder.append(disc) }
            byDisc[disc, default: []].append(url)
        }
        let realDiscNumbers = discOrder.compactMap { $0 }.sorted()

        func members(of url: URL) -> [URL] { membersByEntry[url.standardizedFileURL.path] ?? [] }

        // Multi-disc: two or more distinct disc numbers and no existing playlist.
        if realDiscNumbers.count >= 2 && !group.contains(where: { DiscImage.isPlaylist($0) }) {
            var discPaths: [URL] = []
            var allMembers: [URL] = []
            for number in realDiscNumbers {
                let images = byDisc[number] ?? []
                guard let preferred = DiscImage.preferredImage(images, platformId: platformId) else { continue }
                discPaths.append(preferred)
                allMembers.append(contentsOf: images)
                for image in images { allMembers.append(contentsOf: members(of: image)) }
            }
            guard let primary = discPaths.first else { return nil }
            return DiscoveredROM(
                url: primary,
                fileSize: fileSize(of: primary),
                romExtension: normalizedExtension(of: primary),
                platform: platformInfo.platform,
                candidateEmulators: candidateEmulators(for: platformInfo.platform),
                platformAmbiguous: platformInfo.ambiguous,
                memberFiles: dedupe(allMembers),
                alternateImages: [],
                discPaths: discPaths
            )
        }

        // Single disc (possibly with alternate images, e.g. .cue + .chd).
        let images = group
        guard let primary = DiscImage.preferredImage(images, platformId: platformId) ?? images.first else {
            return nil
        }
        let alternates = images.filter { $0 != primary }
        var allMembers = members(of: primary)
        for alternate in alternates { allMembers.append(contentsOf: members(of: alternate)) }
        return DiscoveredROM(
            url: primary,
            fileSize: fileSize(of: primary),
            romExtension: normalizedExtension(of: primary),
            platform: platformInfo.platform,
            candidateEmulators: candidateEmulators(for: platformInfo.platform),
            platformAmbiguous: platformInfo.ambiguous,
            memberFiles: dedupe(allMembers),
            alternateImages: alternates,
            discPaths: []
        )
    }

    private func resolvePlatform(for url: URL, root: URL) -> (platform: Platform?, ambiguous: Bool) {
        if let folderPlatform = inferPlatform(for: url, root: root) {
            return (folderPlatform, false)
        }
        let byExtension = database.platforms(forExtension: normalizedExtension(of: url))
        if byExtension.count == 1 { return (byExtension[0], false) }
        if byExtension.count > 1 { return (nil, true) }
        return (nil, false)
    }

    private func dedupe(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls where seen.insert(url.standardizedFileURL.path).inserted {
            result.append(url)
        }
        return result
    }

    // MARK: - Inference

    /// Folder-first platform inference: walk up from the ROM file toward the scan
    /// root (inclusive), returning the first ancestor directory name that matches
    /// a platform alias.
    private func inferPlatform(for fileURL: URL, root: URL) -> Platform? {
        let rootPath = root.standardizedFileURL.path
        var current = fileURL.deletingLastPathComponent().standardizedFileURL

        while current.path.hasPrefix(rootPath) {
            if let platform = database.platform(forFolderName: current.lastPathComponent) {
                return platform
            }
            if current.path == rootPath { break }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }   // reached filesystem root
            current = parent
        }
        return nil
    }

    private func candidateEmulators(for platform: Platform?) -> [EmulatorType] {
        guard let platform else { return [] }
        return database.emulatorOptions(for: platform).compactMap { option in
            if case .standalone(let type) = option.choice { return type }
            return nil
        }
    }

    // MARK: - Helpers

    private func normalizedExtension(of url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? "" : "." + ext
    }

    private func fileSize(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}
