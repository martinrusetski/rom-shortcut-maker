//
//  DOSPackageInspector.swift
//  SteamShortcutConverter
//
//  Discovers DOS games as folders/containers and chooses a launch target only
//  when the package contains one safe, unambiguous candidate.
//

import Foundation
import ZIPFoundation

struct DOSPackageDiscovery: Equatable {
    let sourceURL: URL
    let fileSize: Int64
    let memberFiles: [URL]
    let title: String
    let package: DOSPackageInfo
}

final class DOSPackageInspector {
    static let loosePackageExtensions: Set<String> = [".dosz"]
    static let rootPackageExtensions: Set<String> = [
        ".zip", ".dosz", ".exe", ".com", ".bat", ".conf",
        ".iso", ".chd", ".cue", ".img", ".ima", ".vhd", ".jrc",
        ".ins", ".tc", ".m3u", ".m3u8"
    ]

    private static let programExtensions: Set<String> = [".exe", ".com"]
    private static let batchExtensions: Set<String> = [".bat"]
    private static let configurationExtensions: Set<String> = [".conf"]
    private static let archiveExtensions: Set<String> = [".zip", ".dosz"]
    private static let mediaExtensions: Set<String> = [
        ".iso", ".chd", ".cue", ".img", ".ima", ".vhd", ".jrc",
        ".ins", ".tc", ".m3u", ".m3u8"
    ]
    private static let utilityTerms = [
        "setup", "install", "uninstall", "uninst", "config", "configure",
        "setsound", "soundset", "benchmark", "diagnostic"
    ]

    private let fileManager: FileManager
    private let maximumMemberCount = 20_000

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// The conventional DOS layout is one immediate child per game beneath a
    /// folder named DOS/MS-DOS. Directories are treated as package boundaries;
    /// loose supported files remain individual packages.
    func discoverPackages(in dosRoot: URL) -> [DOSPackageDiscovery] {
        let children = (try? fileManager.contentsOfDirectory(
            at: dosRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return children
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { url in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                if values?.isDirectory == true {
                    return inspectDirectory(url)
                }
                guard values?.isRegularFile == true,
                      Self.rootPackageExtensions.contains(normalizedExtension(of: url)) else {
                    return nil
                }
                return inspectFile(url)
            }
    }

    func inspectLoosePackage(_ url: URL) -> DOSPackageDiscovery? {
        guard Self.loosePackageExtensions.contains(normalizedExtension(of: url)) else { return nil }
        return inspectFile(url)
    }

    private func inspectDirectory(_ directory: URL) -> DOSPackageDiscovery? {
        var files: [URL] = []
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator {
            guard files.count < maximumMemberCount else { break }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true { files.append(url) }
        }

        let recognized = files.filter { Self.rootPackageExtensions.contains(normalizedExtension(of: $0)) }
        guard !recognized.isEmpty else { return nil }

        let candidates = recognized.compactMap(candidate(for:))
        let utilities = candidates.filter { $0.kind == .utility }
        let launchCandidates = candidates.filter { $0.kind != .utility }
        let media = candidates.filter { $0.kind == .media }.map(\.url)
        let selected = preferredLaunchCandidate(
            from: launchCandidates,
            packageName: directory.lastPathComponent
        )?.url
        let selectedConfigurationHasAutoexec = selected.flatMap {
            normalizedExtension(of: $0) == ".conf" ? configurationHasAutoexec(at: $0) : nil
        }

        let issue: String?
        if launchCandidates.isEmpty {
            issue = "No DOS program, configuration, or disk image was found in this folder."
        } else {
            issue = nil
        }

        return DOSPackageDiscovery(
            sourceURL: directory,
            fileSize: totalSize(of: files),
            memberFiles: files,
            title: directory.lastPathComponent,
            package: DOSPackageInfo(
                kind: .folder,
                launchCandidates: launchCandidates,
                utilityCandidates: utilities,
                mediaFiles: media,
                memberCount: files.count,
                archiveExecutableCount: nil,
                configurationHasAutoexec: selectedConfigurationHasAutoexec,
                blockingIssue: issue,
                warning: selectedConfigurationHasAutoexec == false
                    ? "This configuration has no startup commands in its [autoexec] section."
                    : nil,
                selectedLaunchURL: selected
            )
        )
    }

    private func inspectFile(_ url: URL) -> DOSPackageDiscovery? {
        let ext = normalizedExtension(of: url)
        let kind: DOSPackageKind
        var archiveExecutableCount: Int?
        var issue: String?
        var warning: String?

        if Self.archiveExtensions.contains(ext) {
            kind = .archive
            switch inspectArchive(url) {
            case .success(let recognizedCount):
                archiveExecutableCount = recognizedCount
                if recognizedCount == 0 {
                    issue = "The archive contains no DOS program, configuration, or supported disk image."
                }
            case .failure(let message):
                issue = message
            }
        } else if Self.configurationExtensions.contains(ext) {
            kind = .configuration
            if !configurationHasAutoexec(at: url) {
                warning = "This configuration has no startup commands in its [autoexec] section."
            }
        } else if Self.mediaExtensions.contains(ext) {
            kind = .diskImage
        } else if Self.programExtensions.contains(ext) || Self.batchExtensions.contains(ext) {
            kind = .executable
        } else {
            return nil
        }

        let companionFiles: [URL]
        if ext == ".cue" {
            companionFiles = DiscImage.members(ofSheet: url)
        } else if ext == ".m3u" {
            companionFiles = DiscImage.entries(ofPlaylist: url)
        } else {
            companionFiles = []
        }

        return DOSPackageDiscovery(
            sourceURL: url,
            fileSize: fileSize(of: url),
            memberFiles: companionFiles,
            title: url.deletingPathExtension().lastPathComponent,
            package: DOSPackageInfo(
                kind: kind,
                launchCandidates: [],
                utilityCandidates: [],
                mediaFiles: kind == .diskImage ? [url] : [],
                memberCount: 1 + companionFiles.count,
                archiveExecutableCount: archiveExecutableCount,
                configurationHasAutoexec: kind == .configuration ? configurationHasAutoexec(at: url) : nil,
                blockingIssue: issue,
                warning: warning,
                selectedLaunchURL: kind == .archive ? nil : url
            )
        )
    }

    private enum ArchiveInspection {
        case success(Int)
        case failure(String)
    }

    private func inspectArchive(_ url: URL) -> ArchiveInspection {
        do {
            let archive = try ZIPFoundation.Archive(url: url, accessMode: .read)
            var count = 0
            var entryCount = 0
            for entry in archive {
                entryCount += 1
                guard entryCount <= maximumMemberCount else {
                    return .failure("The archive contains more than \(maximumMemberCount) entries.")
                }
                guard entry.type == .file, isVisibleArchivePath(entry.path) else { continue }
                let ext = normalizedExtension(ofPath: entry.path)
                if Self.programExtensions.contains(ext)
                    || Self.batchExtensions.contains(ext)
                    || Self.configurationExtensions.contains(ext)
                    || Self.mediaExtensions.contains(ext) {
                    count += 1
                }
            }
            return .success(count)
        } catch {
            return .failure("The archive could not be read: \(error.localizedDescription)")
        }
    }

    private func candidate(for url: URL) -> DOSLaunchCandidate? {
        let ext = normalizedExtension(of: url)
        if Self.configurationExtensions.contains(ext) {
            return DOSLaunchCandidate(url: url, kind: .configuration)
        }
        if Self.mediaExtensions.contains(ext) {
            return DOSLaunchCandidate(url: url, kind: .media)
        }
        if Self.batchExtensions.contains(ext) {
            return DOSLaunchCandidate(
                url: url,
                kind: isUtility(url) ? .utility : .batch
            )
        }
        if Self.programExtensions.contains(ext) {
            return DOSLaunchCandidate(
                url: url,
                kind: isUtility(url) ? .utility : .program
            )
        }
        return nil
    }

    private func preferredLaunchCandidate(
        from candidates: [DOSLaunchCandidate],
        packageName: String
    ) -> DOSLaunchCandidate? {
        let configs = candidates.filter { $0.kind == .configuration && configurationHasAutoexec(at: $0.url) }
        if let dosboxConfig = configs.first(where: {
            $0.url.lastPathComponent.caseInsensitiveCompare("dosbox.conf") == .orderedSame
        }) {
            return dosboxConfig
        }
        if configs.count == 1 { return configs[0] }

        let normalizedPackageName = normalizedStem(packageName)
        let namedForPackage = candidates.filter {
            $0.kind != .configuration && normalizedStem($0.url.deletingPathExtension().lastPathComponent) == normalizedPackageName
        }
        if namedForPackage.count == 1 { return namedForPackage[0] }

        let conventionalNames = Set(["start", "run", "play", "launch", "game"])
        let conventional = candidates.filter {
            conventionalNames.contains(normalizedStem($0.url.deletingPathExtension().lastPathComponent))
        }
        if conventional.count == 1 { return conventional[0] }

        let nonConfigurations = candidates.filter { $0.kind != .configuration }
        if nonConfigurations.count == 1 { return nonConfigurations[0] }
        if candidates.count == 1 { return candidates[0] }
        return nil
    }

    private func configurationHasAutoexec(at url: URL) -> Bool {
        guard normalizedExtension(of: url) == ".conf",
              let data = try? Data(contentsOf: url) else {
            return false
        }
        let text = String(decoding: data, as: UTF8.self)
        var inAutoexec = false
        for rawLine in text.split(whereSeparator: { $0.isNewline }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                inAutoexec = line.caseInsensitiveCompare("[autoexec]") == .orderedSame
                continue
            }
            if inAutoexec && !line.isEmpty && !line.hasPrefix("#") && !line.hasPrefix(";") {
                return true
            }
        }
        return false
    }

    private func isUtility(_ url: URL) -> Bool {
        let stem = normalizedStem(url.deletingPathExtension().lastPathComponent)
        return Self.utilityTerms.contains { stem.contains($0) }
    }

    private func normalizedStem(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func isVisibleArchivePath(_ path: String) -> Bool {
        !path.split(separator: "/").contains { component in
            component.hasPrefix(".") || component.caseInsensitiveCompare("__MACOSX") == .orderedSame
        }
    }

    private func totalSize(of files: [URL]) -> Int64 {
        files.reduce(0) { $0 + fileSize(of: $1) }
    }

    private func fileSize(of url: URL) -> Int64 {
        ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)) ?? 0
    }

    private func normalizedExtension(of url: URL) -> String {
        normalizedExtension(ofPath: url.path)
    }

    private func normalizedExtension(ofPath path: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ext.isEmpty ? "" : "." + ext
    }
}
