//
//  ROMScanner.swift
//  RomShortcutMaker
//
//  Walks a directory tree, identifies ROM files, and assigns each a platform
//  using extension/content inference with folder names as a final fallback.
//

import Foundation

// MARK: - DiscoveredROM

struct DiscoveredROM: Equatable {
    let url: URL                          // primary entry point to launch
    let fileSize: Int64
    let romExtension: String              // normalized, with leading dot, e.g. ".sfc"
    let platform: Platform?               // resolved by inference (nil if ambiguous)
    let candidateEmulators: [EmulatorType]
    let platformAmbiguous: Bool           // no unique extension/content/folder signal
    let detection: PlatformDetectionInfo?

    // MARK: Multi-disc / multi-file
    /// Track / disc files referenced by this entry (for change hashing).
    let memberFiles: [URL]
    /// Other launchable images of the *same* disc (e.g. a .chd alongside a .cue).
    let alternateImages: [URL]
    /// Ordered per-disc entry points for a multi-disc game that has NO existing
    /// .m3u — a playlist must be generated. Empty for single-disc games and for
    /// games that already have an .m3u (whose url points at that .m3u).
    let discPaths: [URL]
    /// Number of discs when this entry is a multi-disc playlist (generated or a
    /// pre-existing .m3u), else nil. This counts *discs*, not the flattened
    /// track/member files in `memberFiles`.
    let discCount: Int?

    // MARK: Metadata hints
    /// A better title than the filename can provide (e.g. the PARAM.SFO TITLE
    /// of a PS3 extracted-disc folder). Overrides the parsed filename title.
    let titleHint: String?
    /// Bundled artwork discovered next to the ROM (e.g. a PS3 ICON0.PNG),
    /// seeded into the artwork cache when no cached artwork exists yet.
    let artworkHint: URL?
    /// DOS-only package metadata. Nil for conventional single-file ROMs.
    let dosPackage: DOSPackageInfo?

    init(
        url: URL,
        fileSize: Int64,
        romExtension: String,
        platform: Platform?,
        candidateEmulators: [EmulatorType],
        platformAmbiguous: Bool,
        detection: PlatformDetectionInfo? = nil,
        memberFiles: [URL] = [],
        alternateImages: [URL] = [],
        discPaths: [URL] = [],
        discCount: Int? = nil,
        titleHint: String? = nil,
        artworkHint: URL? = nil,
        dosPackage: DOSPackageInfo? = nil
    ) {
        self.url = url
        self.fileSize = fileSize
        self.romExtension = romExtension
        self.platform = platform
        self.candidateEmulators = candidateEmulators
        self.platformAmbiguous = platformAmbiguous
        self.detection = detection
        self.memberFiles = memberFiles
        self.alternateImages = alternateImages
        self.discPaths = discPaths
        self.discCount = discCount
        self.titleHint = titleHint
        self.artworkHint = artworkHint
        self.dosPackage = dosPackage
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
    private let filenameParser: ROMFilenameParser
    private let chdInspector = CHDImageInspector()
    private let discContentInspector = DiscContentInspector()
    private let zipContentInspector: ZIPContentInspector
    private let dosPackageInspector = DOSPackageInspector()

    init(database: SystemDatabase) {
        self.database = database
        self.filenameParser = ROMFilenameParser(platformAliases: database.allFolderAliases)
        self.zipContentInspector = ZIPContentInspector(database: database)
    }

    func scan(directory: URL,
              progress: @escaping (Double) -> Void) async throws -> [DiscoveredROM] {
        discContentInspector.clearCache()

        let fileManager = FileManager.default
        let knownExtensions = database.allRomExtensions
        let dosRoots = findDOSRoots(in: directory)
        let dosRootPaths = dosRoots.map { $0.standardizedFileURL.path }
        let dosPlatform = database.allPlatforms.first { $0.id == "dos" }
        var dosGames: [DiscoveredROM] = []
        if let dosPlatform {
            dosGames = dosRoots.flatMap { root in
                dosPackageInspector.discoverPackages(in: root).map {
                    makeDOSROM(from: $0, platform: dosPlatform)
                }
            }
        }

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ScanError.directoryNotReadable(directory)
        }

        // First pass: collect candidate ROM files (so progress has a denominator).
        // PS3 extracted-disc folders are recognized as whole-directory games and
        // consumed here, so nothing inside them (EBOOT.BIN, stray .bin/.pkg
        // files) is double-collected as a loose ROM.
        var candidates: [URL] = []
        var ps3GameRoots: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            if isInsideDOSRoot(url, dosRootPaths: dosRootPaths) {
                if values?.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if values?.isDirectory == true {
                if ps3GameLayout(at: url) != nil {
                    ps3GameRoots.append(url)
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values?.isRegularFile == true else { continue }
            let ext = normalizedExtension(of: url)
            if let dosPlatform,
               let package = dosPackageInspector.inspectLoosePackage(url) {
                dosGames.append(makeDOSROM(from: package, platform: dosPlatform))
                continue
            }
            guard !ext.isEmpty, knownExtensions.contains(ext) else { continue }
            candidates.append(url)
        }

        // Synthesized single-entry-point games; they bypass the sheet/playlist/
        // grouping machinery below.
        let ps3Games = ps3GameRoots.compactMap { makePS3ROM(gameRoot: $0) }

        guard !candidates.isEmpty else {
            progress(1.0)
            return dosGames + ps3Games
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
            return dosGames + ps3Games
        }

        var results: [DiscoveredROM] = []
        let total = groups.count
        for (index, group) in groups.enumerated() {
            if let rom = makeDiscoveredROM(for: group, root: directory, membersByEntry: membersByEntry) {
                results.append(rom)
            }
            progress(Double(index + 1) / Double(total))
        }

        return results + dosGames + ps3Games
    }

    // MARK: - DOS packages

    /// Locate conventional DOS roots without allowing arbitrary host .exe files
    /// to become games. Once a DOS root is found its descendants are owned by the
    /// package inspector and are skipped by the generic ROM scanner.
    private func findDOSRoots(in root: URL) -> [URL] {
        if database.platform(forFolderName: root.lastPathComponent)?.id == "dos" {
            return [root.standardizedFileURL]
        }

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var roots: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            if database.platform(forFolderName: url.lastPathComponent)?.id == "dos" {
                roots.append(url.standardizedFileURL)
                enumerator.skipDescendants()
            }
        }
        return roots
    }

    private func isInsideDOSRoot(_ url: URL, dosRootPaths: [String]) -> Bool {
        let path = url.standardizedFileURL.path
        return dosRootPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    private func makeDOSROM(from discovery: DOSPackageDiscovery, platform: Platform) -> DiscoveredROM {
        DiscoveredROM(
            url: discovery.sourceURL,
            fileSize: discovery.fileSize,
            romExtension: normalizedExtension(of: discovery.sourceURL),
            platform: platform,
            candidateEmulators: candidateEmulators(for: platform),
            platformAmbiguous: false,
            detection: PlatformDetectionInfo(
                fileExtension: normalizedExtension(of: discovery.sourceURL),
                candidates: [platform],
                evidence: ["DOS package detected: \(discovery.package.kind.displayName)."],
                resolvedBy: "DOS package",
                sourceDirectory: discovery.package.kind == .folder
                    ? discovery.sourceURL.standardizedFileURL
                    : discovery.sourceURL.deletingLastPathComponent().standardizedFileURL
            ),
            memberFiles: discovery.memberFiles,
            titleHint: discovery.title,
            dosPackage: discovery.package
        )
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

        // Nintendo Switch: a base game plus its update/DLC files live side by side
        // in one folder and share a title. Launch the base; keep the add-ons as
        // member files rather than surfacing them as duplicate games.
        if platformId == "switch", group.count > 1 {
            let primary = group.first { SwitchTitle.contentType(ofFilename: $0.lastPathComponent) == .base }
                ?? group[0]
            let addOns = group.filter { $0 != primary }
            return DiscoveredROM(
                url: primary,
                fileSize: fileSize(of: primary),
                romExtension: normalizedExtension(of: primary),
                platform: platformInfo.platform,
                candidateEmulators: candidateEmulators(for: platformInfo.platform),
                platformAmbiguous: platformInfo.ambiguous,
                detection: platformInfo.detection,
                memberFiles: dedupe(addOns),
                alternateImages: [],
                discPaths: []
            )
        }

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
                detection: platformInfo.detection,
                memberFiles: dedupe(allMembers),
                alternateImages: [],
                discPaths: discPaths,
                discCount: discPaths.count
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
        // A pre-existing .m3u is already multi-disc; its disc count is the number
        // of playlist entries, not the flattened member files.
        let existingPlaylistDiscCount = DiscImage.isPlaylist(primary)
            ? DiscImage.entries(ofPlaylist: primary).count
            : nil
        return DiscoveredROM(
            url: primary,
            fileSize: fileSize(of: primary),
            romExtension: normalizedExtension(of: primary),
            platform: platformInfo.platform,
            candidateEmulators: candidateEmulators(for: platformInfo.platform),
            platformAmbiguous: platformInfo.ambiguous,
            detection: platformInfo.detection,
            memberFiles: dedupe(allMembers),
            alternateImages: alternates,
            discPaths: [],
            discCount: existingPlaylistDiscCount
        )
    }

    private struct PlaylistPlatformProbe {
        let candidates: [Platform]
        let evidence: [String]
        let hasConflict: Bool
    }

    private func resolvePlatform(
        for url: URL,
        root: URL
    ) -> (platform: Platform?, ambiguous: Bool, detection: PlatformDetectionInfo) {
        resolvePlatform(for: url, root: root, playlistDepth: 0)
    }

    private func resolvePlatform(
        for url: URL,
        root: URL,
        playlistDepth: Int
    ) -> (platform: Platform?, ambiguous: Bool, detection: PlatformDetectionInfo) {
        let extensionName = normalizedExtension(of: url)
        let byExtension = database.platforms(forExtension: extensionName)
        let extensionLabel = extensionName.isEmpty ? "no extension" : extensionName
        var evidence = [
            byExtension.isEmpty
                ? "Extension \(extensionLabel) has no platform mapping."
                : "Extension \(extensionLabel) candidates: \(byExtension.map(\.displayName).joined(separator: ", "))."
        ]
        var candidates = byExtension
        var archiveNeedsDisambiguation = false

        func info(
            candidates: [Platform],
            resolvedBy: String?,
            hasConflict: Bool = false
        ) -> PlatformDetectionInfo {
            var result = PlatformDetectionInfo(
                fileExtension: extensionName,
                candidates: candidates,
                evidence: evidence,
                resolvedBy: resolvedBy,
                sourceDirectory: url.deletingLastPathComponent().standardizedFileURL
            )
            result.hasConflict = hasConflict
            return result
        }

        if byExtension.count == 1 && extensionName != ".zip" {
            return (byExtension[0], false, info(
                candidates: byExtension,
                resolvedBy: "unique extension \(extensionLabel)"
            ))
        }

        if extensionName == ".zip" {
            // Arcade and Model 2 ZIPs are ROM sets whose many members are chip
            // dumps, not alternative console games. A matching folder is the
            // decisive signal and must bypass single-ROM archive inspection.
            if let folderPlatform = inferPlatform(for: url, root: root),
               byExtension.contains(where: { $0.id == folderPlatform.id }) {
                evidence.append("ZIP ROM-set folder: \(folderPlatform.displayName).")
                return (folderPlatform, false, info(
                    candidates: [folderPlatform],
                    resolvedBy: "ZIP ROM-set folder"
                ))
            }

            switch zipContentInspector.inspect(url: url) {
            case .singleROM(let member):
                evidence.append(
                    "ZIP member \(member.path) has extension \(member.fileExtension)."
                )
                candidates = member.archiveCandidates
                if member.hasUniquePlatformMeaning, let platform = candidates.first {
                    return (platform, false, info(
                        candidates: candidates,
                        resolvedBy: "ZIP member extension \(member.fileExtension)"
                    ))
                }
                archiveNeedsDisambiguation = true
                evidence.append(
                    "ZIP member extension \(member.fileExtension) requires a compatible folder signal."
                )

            case .multipleROMs(let members):
                let names = members.map(\.path).joined(separator: ", ")
                let platformIDs = Set(members.flatMap { $0.archiveCandidates.map(\.id) })
                let conflictingCandidates = database.allPlatforms.filter { platformIDs.contains($0.id) }
                evidence.append("ZIP contains multiple recognized ROMs: \(names).")
                return (nil, true, info(
                    candidates: conflictingCandidates,
                    resolvedBy: nil,
                    hasConflict: true
                ))

            case .noRecognizedROM:
                evidence.append("ZIP contains no recognized single-file console ROM.")

            case .unreadable(let reason):
                evidence.append("ZIP could not be inspected: \(reason)")
            }
        }

        if extensionName == ".m3u", playlistDepth < 4,
           let playlistProbe = inspectPlaylistPlatform(
               at: url,
               root: root,
               allowedPlatforms: byExtension,
               playlistDepth: playlistDepth
           ) {
            evidence.append(contentsOf: playlistProbe.evidence)
            if playlistProbe.hasConflict {
                return (nil, true, info(
                    candidates: playlistProbe.candidates,
                    resolvedBy: nil,
                    hasConflict: true
                ))
            }
            if playlistProbe.candidates.count == 1 {
                return (playlistProbe.candidates[0], false, info(
                    candidates: playlistProbe.candidates,
                    resolvedBy: "playlist member detection"
                ))
            }
            candidates = playlistProbe.candidates
        }

        if extensionName == ".chd", byExtension.count > 1,
           let imageInfo = chdInspector.inspect(url: url) {
            evidence.append("CHD metadata: \(imageInfo.mediaType.rawValue), \(imageInfo.logicalBytes) logical bytes.")
            let mediaPlatformIDs = Set(database.platforms(
                forCHDMediaType: imageInfo.mediaType.rawValue,
                logicalBytes: imageInfo.logicalBytes
            ).map(\.id))
            let byMedia = byExtension.filter { mediaPlatformIDs.contains($0.id) }
            if byMedia.count == 1 {
                return (byMedia[0], false, info(candidates: byMedia, resolvedBy: "CHD metadata"))
            }
            if !byMedia.isEmpty { candidates = byMedia }
        }

        if byExtension.count != 1,
           let probe = discContentInspector.inspect(url: url) {
            evidence.append(contentsOf: probe.descriptions.map { "Content signature: \($0)." })
            let contentPlatforms = database.allPlatforms.filter { probe.platformIDs.contains($0.id) }
            if contentPlatforms.count == 1 {
                return (contentPlatforms[0], false, info(
                    candidates: contentPlatforms,
                    resolvedBy: "disc content"
                ))
            }
            if !contentPlatforms.isEmpty { candidates = contentPlatforms }
        }
        // Folder names are deliberately last: they are useful organization
        // hints, but must not override a stronger extension or image signal.
        if let folderPlatform = inferPlatform(for: url, root: root) {
            if candidates.isEmpty || candidates.contains(where: { $0.id == folderPlatform.id }) {
                evidence.append("Folder fallback: \(folderPlatform.displayName).")
                return (folderPlatform, false, info(
                    candidates: [folderPlatform],
                    resolvedBy: "folder fallback"
                ))
            }
            evidence.append(
                "Folder \(folderPlatform.displayName) conflicts with stronger platform evidence."
            )
            return (nil, true, info(
                candidates: candidates,
                resolvedBy: nil,
                hasConflict: true
            ))
        }
        return (
            nil,
            archiveNeedsDisambiguation || candidates.count > 1,
            info(candidates: candidates, resolvedBy: nil)
        )
    }

    /// A playlist has no useful payload of its own. Resolve the listed disc
    /// entry points with the normal detector, then retain only platforms that
    /// remain possible for every member that produced a signal. This lets a
    /// playlist inherit extension, CHD metadata, content, or folder evidence
    /// from its discs without using their filenames as a platform heuristic.
    private func inspectPlaylistPlatform(
        at url: URL,
        root: URL,
        allowedPlatforms: [Platform],
        playlistDepth: Int
    ) -> PlaylistPlatformProbe? {
        let entries = DiscImage.entries(ofPlaylist: url)
        guard !entries.isEmpty else { return nil }

        var possibleIDs: Set<String>?
        var observedIDs = Set<String>()
        var evidence: [String] = []
        for entry in entries.prefix(4) {
            let member = resolvePlatform(
                for: entry,
                root: root,
                playlistDepth: playlistDepth + 1
            )
            evidence.append(contentsOf: member.detection.evidence.map {
                "Playlist member \(entry.lastPathComponent): \($0)"
            })

            if member.detection.hasConflict {
                evidence.append("Playlist member \(entry.lastPathComponent) has conflicting evidence.")
                return PlaylistPlatformProbe(
                    candidates: member.detection.candidates,
                    evidence: evidence,
                    hasConflict: true
                )
            }

            let memberIDs: Set<String>
            if let platform = member.platform {
                memberIDs = [platform.id]
            } else {
                memberIDs = Set(member.detection.candidates.map(\.id))
            }
            guard !memberIDs.isEmpty else { continue }
            observedIDs.formUnion(memberIDs)
            possibleIDs = possibleIDs.map { $0.intersection(memberIDs) } ?? memberIDs
            if possibleIDs?.isEmpty == true {
                evidence.append("Playlist members disagree on the platform.")
                return PlaylistPlatformProbe(
                    candidates: database.allPlatforms.filter { observedIDs.contains($0.id) },
                    evidence: evidence,
                    hasConflict: true
                )
            }
        }

        guard let possibleIDs, !possibleIDs.isEmpty else { return nil }
        let allowedIDs = Set(allowedPlatforms.map(\.id))
        let filteredIDs = allowedIDs.isEmpty
            ? possibleIDs
            : possibleIDs.intersection(allowedIDs)
        guard !filteredIDs.isEmpty else {
            evidence.append("Playlist member evidence is incompatible with the .m3u platform mappings.")
            return PlaylistPlatformProbe(
                candidates: database.allPlatforms.filter { observedIDs.contains($0.id) },
                evidence: evidence,
                hasConflict: true
            )
        }

        return PlaylistPlatformProbe(
            candidates: database.allPlatforms.filter { filteredIDs.contains($0.id) },
            evidence: evidence,
            hasConflict: false
        )
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

    /// Fallback platform inference: walk up from the ROM file toward the scan root
    /// (inclusive), returning the first ancestor directory name that matches a
    /// platform alias.
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

    // MARK: - PS3 extracted-disc folders

    /// The relevant files of a PS3 game folder, whichever layout it uses.
    private struct PS3GameLayout {
        let paramSFO: URL   // metadata incl. the real title
        let eboot: URL      // what RPCS3 launches
        let icon: URL?      // official ICON0.PNG artwork, when present
    }

    /// Recognize a directory as a PS3 game root. Standard extracted-disc layout
    /// (`D/PS3_GAME/PARAM.SFO`), or the JB-rip layout where PS3_GAME's contents
    /// sit at the root (`D/PARAM.SFO` + `D/USRDIR/EBOOT.BIN`).
    private func ps3GameLayout(at directory: URL) -> PS3GameLayout? {
        let fileManager = FileManager.default

        let gameDir = directory.appendingPathComponent("PS3_GAME", isDirectory: true)
        let discSFO = gameDir.appendingPathComponent("PARAM.SFO")
        if fileManager.fileExists(atPath: discSFO.path) {
            let icon = gameDir.appendingPathComponent("ICON0.PNG")
            return PS3GameLayout(
                paramSFO: discSFO,
                eboot: gameDir.appendingPathComponent("USRDIR", isDirectory: true)
                    .appendingPathComponent("EBOOT.BIN"),
                icon: fileManager.fileExists(atPath: icon.path) ? icon : nil
            )
        }

        let rootSFO = directory.appendingPathComponent("PARAM.SFO")
        let rootEboot = directory.appendingPathComponent("USRDIR", isDirectory: true)
            .appendingPathComponent("EBOOT.BIN")
        if fileManager.fileExists(atPath: rootSFO.path),
           fileManager.fileExists(atPath: rootEboot.path) {
            let icon = directory.appendingPathComponent("ICON0.PNG")
            return PS3GameLayout(
                paramSFO: rootSFO,
                eboot: rootEboot,
                icon: fileManager.fileExists(atPath: icon.path) ? icon : nil
            )
        }

        return nil
    }

    /// Synthesize the single entry for a PS3 game root: launched via EBOOT.BIN,
    /// titled from PARAM.SFO (falling back to the folder name), with the
    /// bundled ICON0.PNG as an artwork hint.
    private func makePS3ROM(gameRoot: URL) -> DiscoveredROM? {
        guard let layout = ps3GameLayout(at: gameRoot),
              let platform = database.platform(forFolderName: "ps3") else { return nil }
        return DiscoveredROM(
            url: layout.eboot,
            fileSize: fileSize(of: layout.eboot),
            romExtension: normalizedExtension(of: layout.eboot),
            platform: platform,
            candidateEmulators: candidateEmulators(for: platform),
            platformAmbiguous: false,
            detection: PlatformDetectionInfo(
                fileExtension: normalizedExtension(of: layout.eboot),
                candidates: [platform],
                evidence: ["PS3 extracted-disc layout detected."],
                resolvedBy: "PS3 folder structure",
                sourceDirectory: gameRoot.standardizedFileURL
            ),
            titleHint: ParamSFO.title(of: layout.paramSFO) ?? gameRoot.lastPathComponent,
            artworkHint: layout.icon
        )
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
