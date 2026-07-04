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
        try makeBinaryFile(relativePath, data: contents.data(using: .utf8)!)
    }

    @discardableResult
    private func makeBinaryFile(_ relativePath: String, data: Data) throws -> URL {
        let url = tempRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
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
        XCTAssertEqual(roms[0].discCount, 2, "disc count is the m3u's entries, not member files")
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
        XCTAssertEqual(roms[0].discCount, 3, "disc count matches the number of discs")
    }

    func testMultiDiscCueDiscCountCountsDiscsNotTracks() async throws {
        // Panzer Dragoon Saga: 4 discs, each a cue referencing several bin tracks,
        // no .m3u. The disc count must be 4, not the ~17 flattened member files.
        for disc in 1...4 {
            var cue = ""
            for track in 1...4 {
                let bin = "Panzer Dragoon Saga (Disc \(disc)) (Track \(track)).bin"
                try makeFile("Saturn/Panzer/\(bin)")
                cue += "FILE \"\(bin)\" BINARY\n  TRACK 0\(track) \(track == 1 ? "MODE1/2352" : "AUDIO")\n    INDEX 01 00:00:00\n"
            }
            try makeFile("Saturn/Panzer/Panzer Dragoon Saga (Disc \(disc)).cue", contents: cue)
        }

        let roms = try await scan()
        XCTAssertEqual(roms.count, 1, "four discs are one game")
        XCTAssertEqual(roms[0].discPaths.count, 4)
        XCTAssertEqual(roms[0].discCount, 4, "disc count is the number of discs, not track members")
        XCTAssertGreaterThan(roms[0].memberFiles.count, 4, "member files still flatten every track")
    }

    // MARK: - Switch base + update/DLC

    func testSwitchBaseAndUpdateCollapseToOneGame() async throws {
        // Base title ID ends in ...2000; the update is ...2800 (base + 0x800).
        try makeFile("Switch/Tomodachi Life/Tomodachi Life [010051F0207B2000][v0].nsp")
        try makeFile("Switch/Tomodachi Life/Tomodachi Life [010051F0207B2800][v131072].nsp")

        let roms = try await scan()
        XCTAssertEqual(roms.count, 1, "base + update is one game, not two duplicates")
        let game = roms[0]
        XCTAssertEqual(game.platform?.id, "switch")
        XCTAssertTrue(game.url.lastPathComponent.contains("010051F0207B2000"),
                      "the base game is the launch target")
        XCTAssertEqual(game.memberFiles.count, 1, "the update is a member file, not a game")
        XCTAssertTrue(game.memberFiles[0].lastPathComponent.contains("010051F0207B2800"))
    }

    func testSwitchBaseChosenRegardlessOfScanOrder() async throws {
        // DLC (...3000) present too; still exactly one game launched from the base.
        try makeFile("Switch/Game X/Game X [0100AAAA00003000][v0].nsp")   // DLC
        try makeFile("Switch/Game X/Game X [0100AAAA00002800][v65536].nsp") // update
        try makeFile("Switch/Game X/Game X [0100AAAA00002000][v0].nsp")   // base

        let roms = try await scan()
        XCTAssertEqual(roms.count, 1)
        XCTAssertTrue(roms[0].url.lastPathComponent.contains("0100AAAA00002000"))
        XCTAssertEqual(roms[0].memberFiles.count, 2)
    }

    // MARK: - PS3 extracted-disc folders

    func testPS3ExtractedDiscFolderIsOneGame() async throws {
        let sfo = SFOFixture.make(entries: [("TITLE", "Odin Sphere Leifthrasir")])
        try makeFile("PS3/Odin Sphere - Leifthrasir/PS3_DISC.SFB")
        try makeBinaryFile("PS3/Odin Sphere - Leifthrasir/PS3_GAME/PARAM.SFO", data: sfo)
        try makeBinaryFile("PS3/Odin Sphere - Leifthrasir/PS3_GAME/ICON0.PNG",
                           data: Data([0x89, 0x50, 0x4E, 0x47]))
        try makeFile("PS3/Odin Sphere - Leifthrasir/PS3_GAME/USRDIR/EBOOT.BIN", contents: "")

        let roms = try await scan()
        XCTAssertEqual(roms.count, 1, "the whole folder is one game")
        let game = roms[0]
        XCTAssertEqual(game.platform?.id, "ps3")
        XCTAssertEqual(game.url.lastPathComponent, "EBOOT.BIN")
        XCTAssertFalse(game.platformAmbiguous)
        XCTAssertEqual(game.titleHint, "Odin Sphere Leifthrasir")
        XCTAssertEqual(game.artworkHint?.lastPathComponent, "ICON0.PNG")
        // The EBOOT.BIN must not also surface as a loose hint-less "EBOOT"
        // .bin entry (skipDescendants consumed the folder).
        XCTAssertFalse(roms.contains { $0.titleHint == nil })
    }

    func testPS3JBRipLayoutIsDetected() async throws {
        // JB-rip: PS3_GAME's contents sit at the game root.
        let sfo = SFOFixture.make(entries: [("TITLE", "Ridge Racer 7")])
        try makeBinaryFile("PS3/RR7/PARAM.SFO", data: sfo)
        try makeFile("PS3/RR7/USRDIR/EBOOT.BIN", contents: "")

        let roms = try await scan()
        XCTAssertEqual(roms.count, 1)
        XCTAssertEqual(roms[0].platform?.id, "ps3")
        XCTAssertEqual(roms[0].url.lastPathComponent, "EBOOT.BIN")
        XCTAssertEqual(roms[0].titleHint, "Ridge Racer 7")
        XCTAssertNil(roms[0].artworkHint, "no ICON0.PNG in this rip")
    }

    func testPS3TitleFallsBackToFolderNameOnBadSFO() async throws {
        // A garbage PARAM.SFO still identifies the folder (standard layout),
        // but the title falls back to the game-root folder name.
        try makeFile("PS3/Some Game/PS3_GAME/PARAM.SFO", contents: "not an sfo")
        try makeFile("PS3/Some Game/PS3_GAME/USRDIR/EBOOT.BIN", contents: "")

        let roms = try await scan()
        XCTAssertEqual(roms.count, 1)
        XCTAssertEqual(roms[0].titleHint, "Some Game")
    }
}
