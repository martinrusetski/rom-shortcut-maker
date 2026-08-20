//
//  ZIPContentInspector.swift
//  RomShortcutMaker
//
//  Reads ZIP directory metadata to find single-file cartridge ROMs without
//  extracting archive contents to disk.
//

import Foundation
import ZIPFoundation

struct ZIPROMMember: Equatable {
    let path: String
    let fileExtension: String
    let allCandidates: [Platform]
    let archiveCandidates: [Platform]

    /// An inner extension is decisive only when it has one platform meaning in
    /// the full database. For example, `.bin` remains ambiguous even if Genesis
    /// is the only platform for which we currently allow single-ROM ZIPs.
    var hasUniquePlatformMeaning: Bool {
        allCandidates.count == 1 && archiveCandidates.count == 1
    }
}

enum ZIPInspectionResult: Equatable {
    case noRecognizedROM
    case singleROM(ZIPROMMember)
    case multipleROMs([ZIPROMMember])
    case unreadable(String)
}

final class ZIPContentInspector {
    private let database: SystemDatabase
    private let maximumEntryCount = 10_000

    init(database: SystemDatabase) {
        self.database = database
    }

    func inspect(url: URL) -> ZIPInspectionResult {
        do {
            let archive = try ZIPFoundation.Archive(url: url, accessMode: .read)
            var recognized: [ZIPROMMember] = []
            var entryCount = 0

            for entry in archive {
                entryCount += 1
                guard entryCount <= maximumEntryCount else {
                    return .unreadable("ZIP contains more than \(maximumEntryCount) entries.")
                }
                guard entry.type == .file,
                      let filename = visibleFilename(in: entry.path) else {
                    continue
                }

                let ext = normalizedExtension(of: filename)
                guard !ext.isEmpty else { continue }

                let allCandidates = database.platforms(forExtension: ext)
                guard !allCandidates.isEmpty else { continue }
                let archiveCandidates = allCandidates.filter {
                    database.supportsSingleFileZIP(for: $0)
                }

                recognized.append(ZIPROMMember(
                    path: entry.path,
                    fileExtension: ext,
                    allCandidates: allCandidates,
                    archiveCandidates: archiveCandidates
                ))

                // One archive cannot be launched deterministically once a
                // second recognized ROM is present. No further listing work is
                // needed to establish that conflict.
                if recognized.count == 2 {
                    return .multipleROMs(recognized)
                }
            }

            if let member = recognized.first, !member.archiveCandidates.isEmpty {
                return .singleROM(member)
            }
            return .noRecognizedROM
        } catch {
            return .unreadable(error.localizedDescription)
        }
    }

    private func visibleFilename(in path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let last = components.last else { return nil }
        if components.contains(where: {
            let component = String($0)
            return component.hasPrefix(".")
                || component.caseInsensitiveCompare("__MACOSX") == .orderedSame
        }) {
            return nil
        }
        let filename = String(last)
        return filename
    }

    private func normalizedExtension(of filename: String) -> String {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        return ext.isEmpty ? "" : "." + ext
    }
}
