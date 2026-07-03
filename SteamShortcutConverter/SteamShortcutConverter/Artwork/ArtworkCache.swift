//
//  ArtworkCache.swift
//  SteamShortcutConverter
//
//  On-disk artwork cache keyed by GameEntry.stableKey (the ROM-path hash), so
//  re-scanning the same library reuses previously fetched artwork.
//
//  Layout: <base>/artwork/<stableKey>/{original.png, AppIcon.icns, metadata.json}
//

import Foundation

struct ArtworkMetadata: Codable, Equatable {
    let sgdbGameId: Int?
    let sgdbImageId: Int?
    let downloadedAt: Date
    let sourceType: String
}

final class ArtworkCache {

    private let root: URL
    private let fileManager = FileManager.default

    /// - Parameter baseDirectory: parent directory; the cache lives in
    ///   `<baseDirectory>/artwork`. Defaults to Application Support.
    init(baseDirectory: URL? = nil) {
        let base = baseDirectory ?? fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("RomShortcutMaker", isDirectory: true)
        self.root = base.appendingPathComponent("artwork", isDirectory: true)
    }

    // MARK: - Paths

    func directory(for stableKey: String) -> URL {
        root.appendingPathComponent(stableKey, isDirectory: true)
    }

    func originalURL(for stableKey: String) -> URL {
        directory(for: stableKey).appendingPathComponent("original.png")
    }

    func icnsURL(for stableKey: String) -> URL {
        directory(for: stableKey).appendingPathComponent("AppIcon.icns")
    }

    func metadataURL(for stableKey: String) -> URL {
        directory(for: stableKey).appendingPathComponent("metadata.json")
    }

    // MARK: - Presence

    func hasOriginal(for stableKey: String) -> Bool {
        fileManager.fileExists(atPath: originalURL(for: stableKey).path)
    }

    func hasICNS(for stableKey: String) -> Bool {
        fileManager.fileExists(atPath: icnsURL(for: stableKey).path)
    }

    // MARK: - Store / read

    /// Store a freshly downloaded PNG plus provenance metadata. Returns the
    /// `original.png` URL.
    @discardableResult
    func store(originalPNG data: Data, metadata: ArtworkMetadata, for stableKey: String) throws -> URL {
        let dir = directory(for: stableKey)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let original = originalURL(for: stableKey)
        try data.write(to: original, options: .atomic)
        let encoded = try JSONEncoder().encode(metadata)
        try encoded.write(to: metadataURL(for: stableKey), options: .atomic)
        return original
    }

    /// Store a converted `.icns` for a key that already has an original.
    @discardableResult
    func storeICNS(_ data: Data, for stableKey: String) throws -> URL {
        let dir = directory(for: stableKey)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let icns = icnsURL(for: stableKey)
        try data.write(to: icns, options: .atomic)
        return icns
    }

    func metadata(for stableKey: String) -> ArtworkMetadata? {
        guard let data = try? Data(contentsOf: metadataURL(for: stableKey)) else { return nil }
        return try? JSONDecoder().decode(ArtworkMetadata.self, from: data)
    }

    // MARK: - Maintenance

    /// Total size of the cache on disk, in bytes.
    func cacheSize() -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    func clear() throws {
        if fileManager.fileExists(atPath: root.path) {
            try fileManager.removeItem(at: root)
        }
    }

    /// Whether the cached artwork for an entry is older than `olderThanDays`, or
    /// missing entirely (which also counts as stale).
    func isStale(entry: GameEntry, olderThanDays days: Int) -> Bool {
        guard let metadata = metadata(for: entry.stableKey) else { return true }
        let age = Date().timeIntervalSince(metadata.downloadedAt)
        return age > Double(days) * 86_400
    }
}
