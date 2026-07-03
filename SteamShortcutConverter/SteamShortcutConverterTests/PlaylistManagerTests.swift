//
//  PlaylistManagerTests.swift
//  SteamShortcutConverterTests
//

import XCTest
@testable import SteamShortcutConverter

final class PlaylistManagerTests: XCTestCase {

    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("PlaylistTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        dir = nil
    }

    func testWritesM3UWithAbsolutePaths() throws {
        let manager = PlaylistManager(directory: dir)
        let discs = [
            URL(fileURLWithPath: "/ROMs/Game/Disc 1.cue"),
            URL(fileURLWithPath: "/ROMs/Game/Disc 2.cue")
        ]
        let url = try manager.playlistURL(forDiscs: discs)
        XCTAssertEqual(url.pathExtension, "m3u")
        let body = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(body, "/ROMs/Game/Disc 1.cue\n/ROMs/Game/Disc 2.cue\n")
    }

    func testIdempotentForSameDiscs() throws {
        let manager = PlaylistManager(directory: dir)
        let discs = [URL(fileURLWithPath: "/a/1.cue"), URL(fileURLWithPath: "/a/2.cue")]
        let first = try manager.playlistURL(forDiscs: discs)
        let second = try manager.playlistURL(forDiscs: discs)
        XCTAssertEqual(first, second)
    }

    func testDifferentDiscSetsGetDifferentPlaylists() throws {
        let manager = PlaylistManager(directory: dir)
        let a = try manager.playlistURL(forDiscs: [URL(fileURLWithPath: "/a/1.cue")])
        let b = try manager.playlistURL(forDiscs: [URL(fileURLWithPath: "/b/1.cue")])
        XCTAssertNotEqual(a, b)
    }
}
