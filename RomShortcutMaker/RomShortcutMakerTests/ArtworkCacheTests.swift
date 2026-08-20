//
//  ArtworkCacheTests.swift
//  RomShortcutMakerTests
//
//  Tests for ArtworkCache (temp-dir backed).
//

import XCTest
@testable import RomShortcutMaker

final class ArtworkCacheTests: XCTestCase {

    var base: URL!
    var cache: ArtworkCache!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArtworkCacheTests-\(UUID().uuidString)")
        cache = ArtworkCache(baseDirectory: base)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
        cache = nil
        base = nil
    }

    private func makeEntry(rom: String) -> GameEntry {
        GameEntry(
            title: "Test",
            romPath: URL(fileURLWithPath: rom),
            romMetadata: ROMMetadata(rawFilename: "Test.sfc", title: "Test"),
            platform: Platform(id: "snes", displayName: "SNES")
        )
    }

    private func metadata(daysAgo: Double) -> ArtworkMetadata {
        ArtworkMetadata(
            sgdbGameId: 1, sgdbImageId: 2,
            downloadedAt: Date().addingTimeInterval(-daysAgo * 86_400),
            sourceType: "icon"
        )
    }

    func testStoreAndReadBack() throws {
        let key = "abc123"
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        try cache.store(originalPNG: png, metadata: metadata(daysAgo: 0), for: key)

        XCTAssertTrue(cache.hasOriginal(for: key))
        XCTAssertEqual(try Data(contentsOf: cache.originalURL(for: key)), png)
        XCTAssertEqual(cache.metadata(for: key)?.sgdbImageId, 2)
    }

    func testCacheKeyStableAcrossEntriesWithSameROMPath() throws {
        let a = makeEntry(rom: "/ROMs/SNES/Chrono Trigger.sfc")
        let b = makeEntry(rom: "/ROMs/SNES/Chrono Trigger.sfc")
        XCTAssertEqual(a.stableKey, b.stableKey)
        XCTAssertEqual(cache.directory(for: a.stableKey), cache.directory(for: b.stableKey))
    }

    func testCacheSizeAndClear() throws {
        let key = "sizetest"
        try cache.store(originalPNG: Data(repeating: 0xAB, count: 512), metadata: metadata(daysAgo: 0), for: key)
        XCTAssertGreaterThan(cache.cacheSize(), 512)   // original + metadata
        try cache.clear()
        XCTAssertEqual(cache.cacheSize(), 0)
        XCTAssertFalse(cache.hasOriginal(for: key))
    }

    func testStoreICNS() throws {
        let key = "icnskey"
        try cache.store(originalPNG: Data([1, 2, 3]), metadata: metadata(daysAgo: 0), for: key)
        try cache.storeICNS(Data([4, 5, 6]), for: key)
        XCTAssertTrue(cache.hasICNS(for: key))
    }

    func testIsStale() throws {
        let fresh = makeEntry(rom: "/ROMs/fresh.sfc")
        let old = makeEntry(rom: "/ROMs/old.sfc")
        let missing = makeEntry(rom: "/ROMs/missing.sfc")

        try cache.store(originalPNG: Data([1]), metadata: metadata(daysAgo: 0), for: fresh.stableKey)
        try cache.store(originalPNG: Data([1]), metadata: metadata(daysAgo: 30), for: old.stableKey)

        XCTAssertFalse(cache.isStale(entry: fresh, olderThanDays: 7))
        XCTAssertTrue(cache.isStale(entry: old, olderThanDays: 7))
        XCTAssertTrue(cache.isStale(entry: missing, olderThanDays: 7))   // missing = stale
    }
}
