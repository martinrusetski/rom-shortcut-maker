//
//  ROMScannerTests.swift
//  SteamShortcutConverterTests
//
//  Unit tests for ROMScanner, exercised against real temp-dir trees.
//

import XCTest
import ZIPFoundation
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

    @discardableResult
    private func makeCHD(
        _ relativePath: String,
        metadataTag: String,
        logicalBytes: UInt64
    ) throws -> URL {
        var data = Data(repeating: 0, count: 141)
        data.replaceSubrange(0..<8, with: Data("MComprHD".utf8))

        func putBE32(_ value: UInt32, at offset: Int) {
            data[offset] = UInt8((value >> 24) & 0xff)
            data[offset + 1] = UInt8((value >> 16) & 0xff)
            data[offset + 2] = UInt8((value >> 8) & 0xff)
            data[offset + 3] = UInt8(value & 0xff)
        }
        func putBE64(_ value: UInt64, at offset: Int) {
            for index in 0..<8 {
                data[offset + index] = UInt8((value >> UInt64(56 - index * 8)) & 0xff)
            }
        }

        putBE32(124, at: 8)
        putBE32(5, at: 12)
        putBE64(logicalBytes, at: 32)
        putBE64(124, at: 48)
        putBE32(4096, at: 56)
        putBE32(2048, at: 60)
        data.replaceSubrange(124..<128, with: Data(metadataTag.utf8))
        data[131] = 1 // metadata length is a 24-bit value in the low bytes
        data[140] = 0 // one-byte metadata payload
        return try makeBinaryFile(relativePath, data: data)
    }

    @discardableResult
    private func makeUncompressedCSO(_ relativePath: String, marker: String) throws -> URL {
        var data = Data(repeating: 0, count: 2_080)
        data.replaceSubrange(0..<4, with: Data("CISO".utf8))

        func putLE32(_ value: UInt32, at offset: Int) {
            data[offset] = UInt8(value & 0xff)
            data[offset + 1] = UInt8((value >> 8) & 0xff)
            data[offset + 2] = UInt8((value >> 16) & 0xff)
            data[offset + 3] = UInt8((value >> 24) & 0xff)
        }

        putLE32(2_048, at: 8)
        putLE32(2_048, at: 16)
        putLE32(0x80000020, at: 24)
        putLE32(0x80000820, at: 28)
        data.replaceSubrange(32..<32 + marker.utf8.count, with: Data(marker.utf8))
        return try makeBinaryFile(relativePath, data: data)
    }

    @discardableResult
    private func makeZIP(_ relativePath: String, entries: [(path: String, data: Data)]) throws -> URL {
        let url = tempRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let archive = try ZIPFoundation.Archive(url: url, accessMode: .create)
        for entry in entries {
            try archive.addEntry(
                with: entry.path,
                type: .file,
                uncompressedSize: Int64(entry.data.count),
                provider: { position, size in
                    let lowerBound = Int(position)
                    return entry.data.subdata(in: lowerBound..<(lowerBound + size))
                }
            )
        }
        return url
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

    func testUniqueExtensionBeatsConflictingFolder() async throws {
        try makeFile("PS2/Super Mario World.sfc")
        let roms = try await scan()
        let game = rom(roms, named: "Super Mario World.sfc")
        XCTAssertEqual(game?.platform?.id, "snes")
        XCTAssertFalse(game?.platformAmbiguous ?? true)
    }

    func testUnambiguousExtensionWithoutFolder() async throws {
        try makeFile("Loose/Super Mario World.sfc")
        let roms = try await scan()
        let smw = rom(roms, named: "Super Mario World.sfc")
        XCTAssertEqual(smw?.platform?.id, "snes")   // .sfc maps to snes only
        XCTAssertFalse(smw?.platformAmbiguous ?? true)
    }

    func testNeutralMDSIsDiscoveredWithoutGuessingPlatform() async throws {
        try makeFile("Loose/Mystery Disc.mds")
        let roms = try await scan()
        let disc = rom(roms, named: "Mystery Disc.mds")
        XCTAssertNotNil(disc)
        XCTAssertNil(disc?.platform)
        XCTAssertFalse(disc?.platformAmbiguous ?? true)
    }

    func testMDSUsesFolderPlatformWhenAvailable() async throws {
        try makeFile("PS2/Mystery Disc.mds")
        let roms = try await scan()
        let disc = rom(roms, named: "Mystery Disc.mds")
        XCTAssertEqual(disc?.platform?.id, "ps2")
        XCTAssertFalse(disc?.platformAmbiguous ?? true)
    }

    func testCHDInternalDVDMetadataResolvesPS2WithoutFolder() async throws {
        try makeCHD(
            "Loose/DiscImage.chd",
            metadataTag: "DVD ",
            logicalBytes: 4_617_273_344
        )
        let roms = try await scan()
        let game = rom(roms, named: "DiscImage.chd")
        XCTAssertEqual(game?.platform?.id, "ps2")
        XCTAssertFalse(game?.platformAmbiguous ?? true)
    }

    func testCHDContentBeatsConflictingFolder() async throws {
        try makeCHD(
            "PS1/DiscImage.chd",
            metadataTag: "DVD ",
            logicalBytes: 4_617_273_344
        )
        let roms = try await scan()
        let game = rom(roms, named: "DiscImage.chd")
        XCTAssertEqual(game?.platform?.id, "ps2")
        XCTAssertFalse(game?.platformAmbiguous ?? true)
    }

    func testISOContentSignatureResolvesPS2WithoutFolder() async throws {
        try makeBinaryFile("Loose/Disc.iso", data: Data("CDVDGEN".utf8))
        let roms = try await scan()
        let game = rom(roms, named: "Disc.iso")
        XCTAssertEqual(game?.platform?.id, "ps2")
        XCTAssertFalse(game?.platformAmbiguous ?? true)
        XCTAssertTrue(game?.detection?.evidence.contains { $0.contains("PS2 DVD") } ?? false)
    }

    func testRescanInvalidatesContentDetectionCache() async throws {
        try makeBinaryFile("Loose/Disc.iso", data: Data("CDVDGEN".utf8))
        var game = rom(try await scan(), named: "Disc.iso")
        XCTAssertEqual(game?.platform?.id, "ps2")

        try makeBinaryFile("Loose/Disc.iso", data: Data("PS3_GAME".utf8))
        game = rom(try await scan(), named: "Disc.iso")
        XCTAssertEqual(game?.platform?.id, "ps3")
        XCTAssertEqual(game?.detection?.resolvedBy, "disc content")
    }

    func testMDFPayloadSignatureResolvesPSPForGenericMDS() async throws {
        try makeFile("Loose/Disc.mds")
        try makeBinaryFile("Loose/Disc.mdf", data: Data("PSP_GAME".utf8))
        let roms = try await scan()
        let game = rom(roms, named: "Disc.mds")
        XCTAssertEqual(game?.platform?.id, "psp")
        XCTAssertFalse(game?.platformAmbiguous ?? true)
    }

    func testCSOPayloadSignatureResolvesPSPWithoutFolder() async throws {
        try makeUncompressedCSO("Loose/Disc.cso", marker: "PSP_GAME")
        let roms = try await scan()
        let game = rom(roms, named: "Disc.cso")
        XCTAssertEqual(game?.platform?.id, "psp")
        XCTAssertFalse(game?.platformAmbiguous ?? true)
    }

    func testUnknownDetectionRetainsCandidatesAndEvidence() async throws {
        try makeFile("Loose/Mystery.iso")
        let roms = try await scan()
        let game = rom(roms, named: "Mystery.iso")
        XCTAssertNil(game?.platform)
        XCTAssertEqual(game?.detection?.candidates.count, 8)
        XCTAssertTrue(game?.detection?.summary.contains("Possible platforms") ?? false)
        XCTAssertTrue(game?.detection?.evidence.contains { $0.contains(".iso") } ?? false)
    }

    func testCHDInternalCDMetadataRemainsAmbiguousWithoutFolder() async throws {
        try makeCHD("Loose/DiscImage.chd", metadataTag: "CHT2", logicalBytes: 700_000_000)
        let roms = try await scan()
        let game = rom(roms, named: "DiscImage.chd")
        XCTAssertNotNil(game)
        XCTAssertNil(game?.platform)
        XCTAssertTrue(game?.platformAmbiguous ?? false)
    }

    func testFolderCannotOverrideContradictoryCHDMetadata() async throws {
        try makeCHD("Dreamcast/DiscImage.chd", metadataTag: "CHT2", logicalBytes: 700_000_000)
        let game = rom(try await scan(), named: "DiscImage.chd")

        XCTAssertNil(game?.platform)
        XCTAssertTrue(game?.platformAmbiguous ?? false)
        XCTAssertTrue(game?.detection?.hasConflict ?? false)
        XCTAssertTrue(game?.detection?.evidence.contains {
            $0.contains("conflicts with stronger platform evidence")
        } ?? false)
    }

    func testNonRomFileIsSkipped() async throws {
        try makeFile("SNES/readme.txt")
        try makeFile("SNES/Zelda.sfc")
        let roms = try await scan()
        XCTAssertNil(rom(roms, named: "readme.txt"))
        XCTAssertNotNil(rom(roms, named: "Zelda.sfc"))
    }

    func testScummVMReferenceAndAtariSTFolderAreRecognized() async throws {
        try makeFile("ScummVM/Monkey Island/Monkey Island.scummvm", contents: "scumm:monkey\n")
        try makeFile("Atari ST/Another World.st")
        let roms = try await scan()

        XCTAssertEqual(rom(roms, named: "Monkey Island.scummvm")?.platform?.id, "scummvm")
        XCTAssertEqual(rom(roms, named: "Another World.st")?.platform?.id, "atarist")
    }

    func testXbox360FolderResolvesISOAndXEX() async throws {
        try makeFile("Xbox 360/Lost Odyssey.iso")
        try makeFile("Xbox 360/Arcade Game.xex")
        let roms = try await scan()

        XCTAssertEqual(rom(roms, named: "Lost Odyssey.iso")?.platform?.id, "xbox360")
        XCTAssertEqual(rom(roms, named: "Arcade Game.xex")?.platform?.id, "xbox360")
    }

    func testThreeDOFolderRecognizesOperaFormats() async throws {
        try makeFile("3DO/Road Rash.bin")
        let game = rom(try await scan(), named: "Road Rash.bin")

        XCTAssertEqual(game?.platform?.id, "3do")
        XCTAssertFalse(game?.platformAmbiguous ?? true)
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

    func testSingleROMZIPUsesInnerExtension() async throws {
        try makeZIP(
            "Genesis/Beyond Oasis (USA).zip",
            entries: [("Beyond Oasis (USA).md", Data(repeating: 0x42, count: 64))]
        )

        let game = rom(try await scan(), named: "Beyond Oasis (USA).zip")
        XCTAssertEqual(game?.romExtension, ".zip")
        XCTAssertEqual(game?.platform?.id, "genesis")
        XCTAssertFalse(game?.platformAmbiguous ?? true)
        XCTAssertTrue(game?.detection?.resolvedBy?.contains("ZIP member extension") == true)
    }

    func testSingleROMZIPCanResolveWithoutPlatformFolder() async throws {
        try makeZIP(
            "Loose/Chrono Trigger.zip",
            entries: [("Chrono Trigger.sfc", Data(repeating: 0x24, count: 64))]
        )

        let game = rom(try await scan(), named: "Chrono Trigger.zip")
        XCTAssertEqual(game?.platform?.id, "snes")
        XCTAssertFalse(game?.platformAmbiguous ?? true)
    }

    func testAmbiguousZIPMemberUsesCompatibleFolder() async throws {
        try makeZIP(
            "Genesis/Ambiguous.zip",
            entries: [("Ambiguous.bin", Data(repeating: 0x17, count: 64))]
        )

        let game = rom(try await scan(), named: "Ambiguous.zip")
        XCTAssertEqual(game?.platform?.id, "genesis")
        XCTAssertFalse(game?.platformAmbiguous ?? true)
    }

    func testAmbiguousZIPMemberWithoutFolderStaysAmbiguous() async throws {
        try makeZIP(
            "Loose/Ambiguous.zip",
            entries: [("Ambiguous.bin", Data(repeating: 0x17, count: 64))]
        )

        let game = rom(try await scan(), named: "Ambiguous.zip")
        XCTAssertNil(game?.platform)
        XCTAssertTrue(game?.platformAmbiguous ?? false)
        XCTAssertEqual(game?.detection?.candidates.map(\.id), ["genesis"])
    }

    func testMultipleROMZIPIsAConflict() async throws {
        try makeZIP(
            "Genesis/Collection.zip",
            entries: [
                ("Game One.md", Data(repeating: 0x01, count: 32)),
                ("Game Two.md", Data(repeating: 0x02, count: 32))
            ]
        )

        let game = rom(try await scan(), named: "Collection.zip")
        XCTAssertNil(game?.platform)
        XCTAssertTrue(game?.platformAmbiguous ?? false)
        XCTAssertTrue(game?.detection?.hasConflict ?? false)
        XCTAssertTrue(game?.detection?.evidence.contains { $0.contains("multiple recognized ROMs") } == true)
    }

    func testZIPWithCartridgeROMAndDiscImageIsAConflict() async throws {
        try makeZIP(
            "Genesis/Mixed Collection.zip",
            entries: [
                ("Game.md", Data(repeating: 0x01, count: 32)),
                ("Other Game.iso", Data(repeating: 0x02, count: 32))
            ]
        )

        let game = rom(try await scan(), named: "Mixed Collection.zip")
        XCTAssertNil(game?.platform)
        XCTAssertTrue(game?.platformAmbiguous ?? false)
        XCTAssertTrue(game?.detection?.hasConflict ?? false)
    }

    func testArcadeROMSetDoesNotUseConsoleMemberInference() async throws {
        try makeZIP(
            "Arcade/sf2.zip",
            entries: [("sf2_30g.bin", Data(repeating: 0x30, count: 64))]
        )

        let game = rom(try await scan(), named: "sf2.zip")
        XCTAssertEqual(game?.platform?.id, "arcade")
        XCTAssertFalse(game?.platformAmbiguous ?? true)
        XCTAssertEqual(game?.detection?.resolvedBy, "ZIP ROM-set folder")
    }

    func testUnreadableZIPDoesNotCrashOrGuessFromFolder() async throws {
        try makeFile("Genesis/Broken.zip", contents: "not a zip archive")

        let game = rom(try await scan(), named: "Broken.zip")
        XCTAssertNil(game?.platform)
        XCTAssertTrue(game?.platformAmbiguous ?? false)
        XCTAssertTrue(game?.detection?.evidence.contains { $0.contains("could not be inspected") } == true)
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

    func testM3URecursivelyInspectsNestedCuePayload() async throws {
        try makeFile("Loose/Disc 1.bin", contents: "SEGASATURN")
        try makeFile("Loose/Disc 1.cue", contents: "FILE \"Disc 1.bin\" BINARY\n")
        try makeFile("Loose/Panzer Dragoon Saga.m3u", contents: "Disc 1.cue\n")

        let roms = try await scan()
        let game = rom(roms, named: "Panzer Dragoon Saga.m3u")
        XCTAssertEqual(game?.platform?.id, "saturn")
        XCTAssertFalse(game?.platformAmbiguous ?? true)
    }

    func testM3UInheritsUniqueMemberExtension() async throws {
        try makeFile("Loose/Disc 1.gdi", contents: "1\n0 0 4 2352 \"track.bin\" 0\n")
        try makeFile("Loose/Panzer Dragoon.m3u", contents: "Disc 1.gdi\n")

        let roms = try await scan()
        let game = rom(roms, named: "Panzer Dragoon.m3u")
        XCTAssertEqual(game?.platform?.id, "dreamcast")
        XCTAssertEqual(game?.detection?.resolvedBy, "playlist member detection")
    }

    func testM3UInheritsCHDMetadataFromDiscMembers() async throws {
        try makeCHD(
            "Loose/Game (Disc 1).chd",
            metadataTag: "DVD ",
            logicalBytes: 4_617_273_344
        )
        try makeCHD(
            "Loose/Game (Disc 2).chd",
            metadataTag: "DVD ",
            logicalBytes: 4_617_273_344
        )
        try makeFile(
            "Loose/Game.m3u",
            contents: "Game (Disc 1).chd\nGame (Disc 2).chd\n"
        )

        let roms = try await scan()
        let game = rom(roms, named: "Game.m3u")
        XCTAssertEqual(game?.platform?.id, "ps2")
        XCTAssertTrue(game?.detection?.evidence.contains {
            $0.contains("CHD metadata")
        } ?? false)
    }

    func testM3UWithContradictoryMembersRemainsAmbiguous() async throws {
        try makeFile("Loose/Disc 1.gdi", contents: "1\n0 0 4 2352 \"track.bin\" 0\n")
        try makeFile("Loose/Disc 2.bin", contents: "SEGASATURN")
        try makeFile("Loose/Disc 2.cue", contents: "FILE \"Disc 2.bin\" BINARY\n")
        try makeFile("Loose/Mixed.m3u", contents: "Disc 1.gdi\nDisc 2.cue\n")

        let game = rom(try await scan(), named: "Mixed.m3u")
        XCTAssertNil(game?.platform)
        XCTAssertTrue(game?.platformAmbiguous ?? false)
        XCTAssertTrue(game?.detection?.hasConflict ?? false)
        XCTAssertTrue(game?.detection?.evidence.contains {
            $0.contains("Playlist members disagree")
        } ?? false)
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

    // MARK: - DOS packages

    /// A complete five-byte DOS .COM program: move 4C00h into AX, then invoke
    /// interrupt 21h to terminate successfully. It is executable fixture data,
    /// not a renamed text placeholder.
    private var minimalDOSCOM: Data {
        Data([0xB8, 0x00, 0x4C, 0xCD, 0x21])
    }

    func testDOSFolderBecomesOneGameAndSelectsNamedProgram() async throws {
        try makeBinaryFile("DOS/Doom/DOOM.COM", data: minimalDOSCOM)
        try makeFile("DOS/Doom/SETUP.EXE")

        let roms = try await scan()
        let game = try XCTUnwrap(rom(roms, named: "Doom"))
        let package = try XCTUnwrap(game.dosPackage)

        XCTAssertEqual(roms.count, 1)
        XCTAssertEqual(game.platform?.id, "dos")
        XCTAssertEqual(game.url.lastPathComponent, "Doom")
        XCTAssertEqual(package.kind, .folder)
        XCTAssertEqual(package.selectedLaunchURL?.lastPathComponent, "DOOM.COM")
        XCTAssertEqual(package.utilityCandidates.map(\.url.lastPathComponent), ["SETUP.EXE"])
        XCTAssertEqual(game.memberFiles.count, 2)
    }

    func testDOSFolderRequiresChoiceWhenStartupIsAmbiguous() async throws {
        try makeFile("MS-DOS/Ambiguous/ONE.EXE")
        try makeFile("MS-DOS/Ambiguous/TWO.EXE")

        let roms = try await scan()
        let game = try XCTUnwrap(rom(roms, named: "Ambiguous"))
        let package = try XCTUnwrap(game.dosPackage)
        XCTAssertNil(package.selectedLaunchURL)
        XCTAssertTrue(package.requiresLaunchSelection)
        XCTAssertEqual(package.launchCandidates.count, 2)
    }

    func testDOSBoxConfigurationWithAutoexecWinsOverPrograms() async throws {
        try makeFile("DOS/Configured/dosbox.conf", contents: """
        [sdl]
        fullscreen=true
        [autoexec]
        mount c .
        c:
        GAME.EXE
        """)
        try makeFile("DOS/Configured/GAME.EXE")
        try makeFile("DOS/Configured/ALTERNATE.EXE")

        let roms = try await scan()
        let game = try XCTUnwrap(rom(roms, named: "Configured"))
        XCTAssertEqual(game.dosPackage?.selectedLaunchURL?.lastPathComponent, "dosbox.conf")
        XCTAssertEqual(game.dosPackage?.configurationHasAutoexec, true)
    }

    func testDOSConfigurationWithoutAutoexecIsRunnableButWarned() async throws {
        try makeFile("DOS/Manual/dosbox.conf", contents: "[sdl]\nfullscreen=true\n")

        let roms = try await scan()
        let game = try XCTUnwrap(rom(roms, named: "Manual"))
        XCTAssertEqual(game.dosPackage?.selectedLaunchURL?.lastPathComponent, "dosbox.conf")
        XCTAssertEqual(game.dosPackage?.configurationHasAutoexec, false)
        XCTAssertNotNil(game.dosPackage?.warning)
        XCTAssertNil(game.dosPackage?.blockingIssue)
    }

    func testLooseDOSZUsesRealArchiveInspection() async throws {
        try makeZIP("Loose/Commander Keen.dosz", entries: [
            ("KEEN/KEEN.COM", minimalDOSCOM),
            ("KEEN/README.TXT", Data("fixture".utf8))
        ])

        let roms = try await scan()
        let game = try XCTUnwrap(rom(roms, named: "Commander Keen.dosz"))
        XCTAssertEqual(game.platform?.id, "dos")
        XCTAssertEqual(game.dosPackage?.kind, .archive)
        XCTAssertEqual(game.dosPackage?.archiveExecutableCount, 1)
        XCTAssertNil(game.dosPackage?.blockingIssue)
    }

    func testCorruptDOSArchiveIsRetainedWithBlockingIssue() async throws {
        try makeFile("DOS/Broken.dosz", contents: "not a zip")

        let roms = try await scan()
        let game = try XCTUnwrap(rom(roms, named: "Broken.dosz"))
        XCTAssertEqual(game.dosPackage?.kind, .archive)
        XCTAssertNotNil(game.dosPackage?.blockingIssue)
    }

    func testDOSCuePackageKeepsCompanionTrack() async throws {
        try makeFile("DOS/CD Game/game.cue", contents: """
        FILE "track.bin" BINARY
          TRACK 01 MODE1/2352
            INDEX 01 00:00:00
        """)
        try makeBinaryFile("DOS/CD Game/track.bin", data: Data(repeating: 0, count: 32))

        let roms = try await scan()
        let game = try XCTUnwrap(rom(roms, named: "CD Game"))
        XCTAssertEqual(game.dosPackage?.selectedLaunchURL?.lastPathComponent, "game.cue")
        XCTAssertTrue(game.memberFiles.contains { $0.lastPathComponent == "track.bin" })
    }

    func testArbitraryExecutableOutsideDOSRootIsIgnored() async throws {
        try makeFile("Downloads/WindowsTool.exe")
        let roms = try await scan()
        XCTAssertTrue(roms.isEmpty)
    }

    // MARK: - Modern platform reference files

    func testPS4ReferenceFileUsesFolderAndExtensionSignals() async throws {
        try makeFile("PS4/Sonic Mania.ps4", contents: "CUSA07010\n")

        let roms = try await scan()
        let game = try XCTUnwrap(rom(roms, named: "Sonic Mania.ps4"))
        XCTAssertEqual(game.platform?.id, "ps4")
        XCTAssertEqual(game.candidateEmulators, [.shadps4QtLauncher, .shadps4])
    }

    func testVitaReferenceFileIsDetected() async throws {
        try makeFile("PS Vita/Gravity Rush.psvita", contents: "PCSF00024\n")

        let roms = try await scan()
        let game = try XCTUnwrap(rom(roms, named: "Gravity Rush.psvita"))
        XCTAssertEqual(game.platform?.id, "psvita")
        XCTAssertEqual(game.candidateEmulators, [.vita3k])
    }

    func testXboxISOResolvesFromFolder() async throws {
        try makeFile("Xbox/Jet Set Radio Future.iso")

        let roms = try await scan()
        let game = try XCTUnwrap(rom(roms, named: "Jet Set Radio Future.iso"))
        XCTAssertEqual(game.platform?.id, "xbox")
        XCTAssertEqual(game.candidateEmulators, [.xemu])
    }
}
