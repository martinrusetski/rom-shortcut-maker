//
//  PlaylistManager.swift
//  SteamShortcutConverter
//
//  Generates .m3u playlists for multi-disc games that lack one, written to an
//  app-managed folder using absolute disc paths so the user's ROM library is
//  never modified.
//

import Foundation
import CryptoKit

protocol PlaylistWriting {
    /// Returns a playlist URL for the ordered disc images, creating/refreshing it
    /// if needed. Idempotent for the same disc set.
    func playlistURL(forDiscs discs: [URL]) throws -> URL
}

final class PlaylistManager: PlaylistWriting {

    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("RomShortcutMaker", isDirectory: true)
            .appendingPathComponent("playlists", isDirectory: true)
    }

    func playlistURL(forDiscs discs: [URL]) throws -> URL {
        let key = Self.key(forDiscs: discs)
        let url = directory.appendingPathComponent("\(key).m3u")
        let body = discs.map { $0.standardizedFileURL.path }.joined(separator: "\n") + "\n"

        // Only rewrite when the content changes.
        if let existing = try? String(contentsOf: url, encoding: .utf8), existing == body {
            return url
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try body.data(using: .utf8)!.write(to: url, options: .atomic)
        return url
    }

    /// Stable identity for a disc set: hash of the ordered, standardized paths.
    static func key(forDiscs discs: [URL]) -> String {
        let joined = discs.map { $0.standardizedFileURL.path }.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
    }
}
