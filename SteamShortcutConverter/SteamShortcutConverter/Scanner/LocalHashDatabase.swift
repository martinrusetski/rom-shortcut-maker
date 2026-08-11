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

    enum DatabaseError: LocalizedError {
        case unreadable(URL, Error)
        case invalidFormat(URL, Error)

        var errorDescription: String? {
            switch self {
            case .unreadable(let url, let error):
                return "Cannot read hash database at \(url.path): \(error.localizedDescription)"
            case .invalidFormat(let url, let error):
                return "Invalid hash database at \(url.path): \(error.localizedDescription)"
            }
        }
    }

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
    private static func loadRecords(from url: URL?) throws -> [Record] {
        guard let url else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DatabaseError.unreadable(url, error)
        }
        let decoder = JSONDecoder()
        if let document = try? decoder.decode(Document.self, from: data) {
            return document.entries
        }
        do {
            return try decoder.decode([Record].self, from: data)
        } catch {
            throw DatabaseError.invalidFormat(url, error)
        }
    }

    /// Hash only the unresolved files, off the main actor. Large libraries can
    /// therefore opt into exact matching without blocking the window.
    static func matches(
        inputs: [LocalHashInput],
        databaseURL: URL?
    ) async throws -> [String: LocalHashMatch] {
        let records = try loadRecords(from: databaseURL)
        guard !records.isEmpty, !inputs.isEmpty else { return [:] }

        return await Task.detached(priority: .utility) {
            var recordsByHash: [String: [Record]] = [:]
            for record in records {
                recordsByHash[record.sha1.lowercased(), default: []].append(record)
            }

            var matches: [String: LocalHashMatch] = [:]
            for input in inputs {
                guard let digest = Self.sha1(path: input.path, expectedSize: input.fileSize),
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

    private static func sha1(path: String, expectedSize: Int64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else {
            return nil
        }
        defer { try? handle.close() }

        var hasher = Insecure.SHA1()
        var bytesRead: Int64 = 0
        do {
            while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                hasher.update(data: chunk)
                bytesRead += Int64(chunk.count)
            }
        } catch {
            return nil
        }
        guard bytesRead == expectedSize else { return nil }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
