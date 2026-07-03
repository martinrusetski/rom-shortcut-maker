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
    let url: URL
    let fileSize: Int64
    let romExtension: String              // normalized, with leading dot, e.g. ".sfc"
    let platform: Platform?               // resolved by inference (nil if ambiguous)
    let candidateEmulators: [EmulatorType]
    let platformAmbiguous: Bool           // extension matched multiple platforms and
                                          // the folder didn't disambiguate
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

        var results: [DiscoveredROM] = []
        var lastReportedPercent = -1
        progress(0.0)

        for (index, url) in candidates.enumerated() {
            let ext = normalizedExtension(of: url)
            let fileSize = fileSize(of: url)

            var platform: Platform?
            var ambiguous = false

            if let folderPlatform = inferPlatform(for: url, root: directory) {
                // Folder name is the primary, most reliable signal — it wins even
                // when the extension is ambiguous.
                platform = folderPlatform
            } else {
                let byExtension = database.platforms(forExtension: ext)
                if byExtension.count == 1 {
                    platform = byExtension[0]
                } else if byExtension.count > 1 {
                    // Ambiguous: let the user resolve in the UI.
                    platform = nil
                    ambiguous = true
                }
            }

            results.append(DiscoveredROM(
                url: url,
                fileSize: fileSize,
                romExtension: ext,
                platform: platform,
                candidateEmulators: candidateEmulators(for: platform),
                platformAmbiguous: ambiguous
            ))

            let percent = Int(Double(index + 1) / Double(candidates.count) * 100)
            if percent != lastReportedPercent {
                progress(Double(index + 1) / Double(candidates.count))
                lastReportedPercent = percent
            }
        }

        return results
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
