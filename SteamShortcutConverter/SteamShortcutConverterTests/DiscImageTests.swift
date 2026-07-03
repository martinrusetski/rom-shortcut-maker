//
//  DiscImageTests.swift
//  SteamShortcutConverterTests
//

import XCTest
@testable import SteamShortcutConverter

final class DiscImageTests: XCTestCase {

    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("DiscImageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        dir = nil
    }

    @discardableResult
    private func write(_ name: String, _ contents: String = "x") throws -> URL {
        let url = dir.appendingPathComponent(name)
        try contents.data(using: .utf8)!.write(to: url)
        return url
    }

    // MARK: - Cue parsing

    func testCueReferencedTracksResolveToExistingFiles() throws {
        try write("Game (Track 01).bin")
        try write("Game (Track 02).bin")
        let cue = try write("Game.cue", """
        FILE "Game (Track 01).bin" BINARY
          TRACK 01 MODE1/2352
            INDEX 01 00:00:00
        FILE "Game (Track 02).bin" BINARY
          TRACK 02 AUDIO
            INDEX 01 00:00:00
        """)
        let members = DiscImage.members(ofSheet: cue).map { $0.lastPathComponent }
        XCTAssertEqual(Set(members), ["Game (Track 01).bin", "Game (Track 02).bin"])
    }

    func testCueSkipsMissingTracks() throws {
        let cue = try write("Game.cue", "FILE \"Missing.bin\" BINARY\n  TRACK 01 MODE1/2352\n")
        XCTAssertTrue(DiscImage.members(ofSheet: cue).isEmpty)
    }

    // MARK: - M3U parsing

    func testM3UEntriesResolveRelativeAndSkipComments() throws {
        let disc1 = try write("Disc 1.cue", "FILE \"a.bin\" BINARY\n")
        let disc2 = try write("Disc 2.cue", "FILE \"b.bin\" BINARY\n")
        let m3u = try write("Game.m3u", """
        # a comment

        Disc 1.cue
        Disc 2.cue
        """)
        let entries = DiscImage.entries(ofPlaylist: m3u).map { $0.lastPathComponent }
        XCTAssertEqual(entries, ["Disc 1.cue", "Disc 2.cue"])
        _ = (disc1, disc2)
    }

    // MARK: - Preferred image

    func testSaturnPrefersCueOverChd() {
        let cue = dir.appendingPathComponent("g.cue")
        let chd = dir.appendingPathComponent("g.chd")
        XCTAssertEqual(DiscImage.preferredImage([chd, cue], platformId: "saturn"), cue)
    }

    func testPS1PrefersChdOverCue() {
        let cue = dir.appendingPathComponent("g.cue")
        let chd = dir.appendingPathComponent("g.chd")
        XCTAssertEqual(DiscImage.preferredImage([cue, chd], platformId: "ps1"), chd)
    }
}
