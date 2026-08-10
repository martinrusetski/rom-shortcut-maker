//
//  LocalHashDatabase.swift
//  SteamShortcutConverter
//
//  Optional exact-match platform lookup. The database is user-supplied because
//  distributing full ROM hash catalogs is outside this app's scope.
//

import CryptoKit
import Foundation

struct LocalHashMatch: Equatable, Sendable {
    let platformID: String
    let title: String?
}

struct LocalHashInput: Sendable {
    let path: String
    let fileSize: Int64
}

final class LocalHashDatabase {

    private struct Record: Decodable, Sendable {
        let sha1: String
        let size: Int64?
        let platform: String
        let title: String?
    }

    private struct Document: Decodable {
        let entries: [Record]
    }

    /// Accept either `{ "entries": [...] }` or a bare array for easy use with
    /// exports from existing ROM databases.
    private static func loadRecords(from url: URL?) -> [Record] {
        guard let url, let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        if let document = try? decoder.decode(Document.self, from: data) {
            return document.entries
        }
        return (try? decoder.decode([Record].self, from: data)) ?? []
    }

    /// Hash only the unresolved files, off the main actor. Large libraries can
    /// therefore opt into exact matching without blocking the window.
    static func matches(
        inputs: [LocalHashInput],
        databaseURL: URL?
    ) async -> [String: LocalHashMatch] {
        let records = loadRecords(from: databaseURL)
        guard !records.isEmpty, !inputs.isEmpty else { return [:] }

        return await Task.detached(priority: .utility) {
            var recordsByHash: [String: [Record]] = [:]
            for record in records {
                recordsByHash[record.sha1.lowercased(), default: []].append(record)
            }

            var matches: [String: LocalHashMatch] = [:]
            for input in inputs {
                guard let digest = Self.sha1(path: input.path),
                      let candidates = recordsByHash[digest] else { continue }
                guard let record = candidates.first(where: {
                    $0.size == nil || $0.size == input.fileSize
                }) else { continue }
                matches[input.path] = LocalHashMatch(
                    platformID: record.platform,
                    title: record.title
                )
            }
            return matches
        }.value
    }

    private static func sha1(path: String) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return nil
        }
        defer { try? handle.close() }

        var hasher = Insecure.SHA1()
        while let chunk = try? handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
