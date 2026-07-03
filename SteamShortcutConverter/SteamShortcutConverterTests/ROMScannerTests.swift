//
//  ROMScannerTests.swift
//  SteamShortcutConverterTests
//
//  Unit tests for ROMScanner, exercised against real temp-dir trees.
//

import XCTest
@testable import SteamShortcutConverter

final class ROMScannerTests: XCTestCase {

    var database: SystemDatabase!
    var scanner: ROMScanner!
    var tempRoot: URL!

    override func setUpWithError() throws {
        database = try SystemDatabase()
        scanner = ROMScanner(database: database)
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ROMScannerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
        tempRoot = nil
        scanner = nil
        database = nil
    }

    // MARK: - Helpers

    @discardableResult
    private func makeFile(_ relativePath: String, contents: String = "x") throws -> URL {
        let url = tempRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.data(using: .utf8)!.write(to: url)
        return url
    }

    private func scan() async throws -> [DiscoveredROM] {
        try await scanner.scan(directory: tempRoot, progress: { _ in })
    }

    private func rom(_ roms: [DiscoveredROM], named name: String) -> DiscoveredROM? {
        roms.first { $0.url.lastPathComponent == name }
    }

    // MARK: - Tests

    func testFolderNameResolvesPlatform() async throws {
        try makeFile("SNES/Chrono Trigger (USA).sfc")
        let roms = try await scan()
        let ct = rom(roms, named: "Chrono Trigger (USA).sfc")
        XCTAssertEqual(ct?.platform?.id, "snes")
        XCTAssertFalse(ct?.platformAmbiguous ?? true)
    }

    func testFolderAliasResolvesPlatform() async throws {
        try makeFile("PSX/Final Fantasy VII (Disc 1).chd")
        let roms = try await scan()
        let ff = rom(roms, named: "Final Fantasy VII (Disc 1).chd")
        XCTAssertEqual(ff?.platform?.id, "ps1")   // "psx" alias -> ps1
    }

    func testAmbiguousExtensionInNeutralFolder() async throws {
        try makeFile("Games/Mystery Disc.iso")
        let roms = try await scan()
        let disc = rom(roms, named: "Mystery Disc.iso")
        XCTAssertNotNil(disc)
        XCTAssertNil(disc?.platform)
        XCTAssertTrue(disc?.platformAmbiguous ?? false)
    }

    func testFolderWinsOverAmbiguousExtension() async throws {
        try makeFile("GameCube/Metroid Prime.iso")
        let roms = try await scan()
        let mp = rom(roms, named: "Metroid Prime.iso")
        XCTAssertEqual(mp?.platform?.id, "gamecube")
        XCTAssertFalse(mp?.platformAmbiguous ?? true)
    }

    func testUnambiguousExtensionWithoutFolder() async throws {
        try makeFile("Loose/Super Mario World.sfc")
        let roms = try await scan()
        let smw = rom(roms, named: "Super Mario World.sfc")
        XCTAssertEqual(smw?.platform?.id, "snes")   // .sfc maps to snes only
        XCTAssertFalse(smw?.platformAmbiguous ?? true)
    }

    func testNonRomFileIsSkipped() async throws {
        try makeFile("SNES/readme.txt")
        try makeFile("SNES/Zelda.sfc")
        let roms = try await scan()
        XCTAssertNil(rom(roms, named: "readme.txt"))
        XCTAssertNotNil(rom(roms, named: "Zelda.sfc"))
    }

    func testHiddenFileIsSkipped() async throws {
        try makeFile("SNES/.Secret.sfc")
        try makeFile("SNES/Visible.sfc")
        let roms = try await scan()
        XCTAssertNil(rom(roms, named: ".Secret.sfc"))
        XCTAssertEqual(roms.count, 1)
    }

    func testNestedDirectoriesAreWalked() async throws {
        try makeFile("Consoles/Nintendo/SNES/USA/Earthbound.sfc")
        let roms = try await scan()
        let eb = rom(roms, named: "Earthbound.sfc")
        XCTAssertEqual(eb?.platform?.id, "snes")
    }

    func testZipTreatedAsArcadeRom() async throws {
        try makeFile("Arcade/sf2.zip")
        let roms = try await scan()
        let sf2 = rom(roms, named: "sf2.zip")
        XCTAssertEqual(sf2?.romExtension, ".zip")
        XCTAssertEqual(sf2?.platform?.id, "arcade")
    }

    func testCandidateEmulatorsPopulatedForResolvedPlatform() async throws {
        try makeFile("SNES/Zelda.sfc")
        let roms = try await scan()
        let zelda = rom(roms, named: "Zelda.sfc")
        XCTAssertTrue(zelda?.candidateEmulators.contains(.snes9x) ?? false)
    }

    func testFileSizeReported() async throws {
        try makeFile("SNES/Big.sfc", contents: String(repeating: "A", count: 1024))
        let roms = try await scan()
        let big = rom(roms, named: "Big.sfc")
        XCTAssertEqual(big?.fileSize, 1024)
    }

    func testProgressReachesCompletion() async throws {
        try makeFile("SNES/One.sfc")
        try makeFile("SNES/Two.sfc")
        var lastProgress: Double = -1
        _ = try await scanner.scan(directory: tempRoot, progress: { lastProgress = $0 })
        XCTAssertEqual(lastProgress, 1.0, accuracy: 0.0001)
    }

    func testEmptyDirectoryYieldsNoResults() async throws {
        let roms = try await scan()
        XCTAssertTrue(roms.isEmpty)
    }

    func testExtensionMatchIsCaseInsensitive() async throws {
        try makeFile("SNES/Shout.SFC")
        let roms = try await scan()
        let shout = rom(roms, named: "Shout.SFC")
        XCTAssertEqual(shout?.romExtension, ".sfc")
        XCTAssertEqual(shout?.platform?.id, "snes")
    }

    // MARK: - Multi-file / multi-disc

    func testMultiTrackCueCollapsesToOneGameAndHidesBins() async throws {
        // Princess Crown: one disc, cue + 2 bin tracks + a chd of the same disc.
        try makeFile("Saturn/Princess Crown/Princess Crown (Japan) (Track 01).bin")
        try makeFile("Saturn/Princess Crown/Princess Crown (Japan) (Track 02).bin")
        try makeFile("Saturn/Princess Crown/Princess Crown (Japan).cue", contents: """
        FILE "Princess Crown (Japan) (Track 01).bin" BINARY
          TRACK 01 MODE1/2352
            INDEX 01 00:00:00
        FILE "Princess Crown (Japan) (Track 02).bin" BINARY
          TRACK 02 AUDIO
            INDEX 01 00:00:00
        """)
        try makeFile("Saturn/Princess Crown/Princess Crown (Japan).chd")

        let roms = try await scan()
        XCTAssertEqual(roms.count, 1, "cue+bins+chd should be one game")
        let game = roms[0]
        XCTAssertEqual(game.url.pathExtension, "cue", "Saturn prefers the cue image")
        XCTAssertTrue(game.alternateImages.contains { $0.pathExtension == "chd" })
        XCTAssertEqual(game.memberFiles.filter { $0.pathExtension == "bin" }.count, 2)
        // No .bin surfaced as its own entry.
        XCTAssertFalse(roms.contains { $0.url.pathExtension == "bin" })
    }

    func testExistingM3UIsTheSingleEntryPoint() async throws {
        // Panzer: an .m3u lists two per-disc cues; each cue references a bin.
        try makeFile("Saturn/Panzer/Panzer (Disc 1) (Track 1).bin")
        try makeFile("Saturn/Panzer/Panzer (Disc 2) (Track 1).bin")
        try makeFile("Saturn/Panzer/Panzer (Disc 1).cue",
                     contents: "FILE \"Panzer (Disc 1) (Track 1).bin\" BINARY\n  TRACK 01 MODE1/2352\n")
        try makeFile("Saturn/Panzer/Panzer (Disc 2).cue",
                     contents: "FILE \"Panzer (Disc 2) (Track 1).bin\" BINARY\n  TRACK 01 MODE1/2352\n")
        try makeFile("Saturn/Panzer/Panzer.m3u", contents: "Panzer (Disc 1).cue\nPanzer (Disc 2).cue\n")

        let roms = try await scan()
        XCTAssertEqual(roms.count, 1)
        XCTAssertEqual(roms[0].url.pathExtension, "m3u")
        XCTAssertTrue(roms[0].discPaths.isEmpty, "existing m3u needs no generated playlist")
        // The disc cues are members, not separate games.
        XCTAssertFalse(roms.contains { $0.url.pathExtension == "cue" })
    }

    func testMultiDiscWithoutM3UIsGrouped() async throws {
        // No playlist; two discs distinguished by (Disc N) markers.
        try makeFile("PSX/FF7/Final Fantasy VII (Disc 1).chd")
        try makeFile("PSX/FF7/Final Fantasy VII (Disc 2).chd")
        try makeFile("PSX/FF7/Final Fantasy VII (Disc 3).chd")

        let roms = try await scan()
        XCTAssertEqual(roms.count, 1, "three discs are one game")
        XCTAssertEqual(roms[0].platform?.id, "ps1")
        XCTAssertEqual(roms[0].discPaths.count, 3, "needs a generated playlist over 3 discs")
    }
}
