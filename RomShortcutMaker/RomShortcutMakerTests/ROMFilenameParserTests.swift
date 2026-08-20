//
//  ROMFilenameParserTests.swift
//  RomShortcutMakerTests
//
//  Unit tests for ROMFilenameParser
//

import XCTest
@testable import RomShortcutMaker

final class ROMFilenameParserTests: XCTestCase {

    var parser: ROMFilenameParser!

    override func setUpWithError() throws {
        parser = ROMFilenameParser()
    }

    override func tearDownWithError() throws {
        parser = nil
    }

    // MARK: - Region tags

    func testRegionUSA() {
        let m = parser.parse(filename: "Super Mario World (USA).sfc")
        XCTAssertEqual(m.title, "Super Mario World")
        XCTAssertEqual(m.region, "USA")
        XCTAssertNil(m.discNumber)
    }

    func testGoodToolsSingleLetterRegion() {
        let m = parser.parse(filename: "Chrono Trigger (U) [!].smc")
        XCTAssertEqual(m.title, "Chrono Trigger")
        XCTAssertEqual(m.region, "USA")           // U → USA
        XCTAssertTrue(m.flags.contains("!"))
        XCTAssertNil(m.discNumber)
    }

    func testJapanLetter() {
        let m = parser.parse(filename: "Metroid (J).nes")
        XCTAssertEqual(m.title, "Metroid")
        XCTAssertEqual(m.region, "Japan")
    }

    func testWorldRegion() {
        let m = parser.parse(filename: "Sonic the Hedgehog (World).md")
        XCTAssertEqual(m.title, "Sonic the Hedgehog")
        XCTAssertEqual(m.region, "World")
    }

    func testMultiRegionList() {
        let m = parser.parse(filename: "Multi Kombat (USA, Europe).sfc")
        XCTAssertEqual(m.title, "Multi Kombat")
        XCTAssertEqual(m.region, "USA")           // first canonical region
    }

    // MARK: - Video-standard / region tags (PAL / NTSC)

    func testPALBracketStripped() {
        let m = parser.parse(filename: "Some Game [PAL].iso")
        XCTAssertEqual(m.title, "Some Game")
        XCTAssertEqual(m.region, "Europe")
    }

    func testNTSCVariantParenthetical() {
        let m = parser.parse(filename: "Some Game (NTSC-J).iso")
        XCTAssertEqual(m.title, "Some Game")
        XCTAssertEqual(m.region, "Japan")
    }

    // MARK: - Platform-name tags

    /// The parser must strip bracketed platform names so they don't leak into
    /// the title (and, downstream, poison the SteamGridDB autocomplete match).
    func testPlatformBracketTagsStripped() {
        let parser = ROMFilenameParser(platformAliases: ["gamecube", "nintendo wii"])

        let gc = parser.parse(filename: "[GameCube][PAL].Metroid.Prime.rvz")
        XCTAssertEqual(gc.title, "Metroid Prime")   // dots normalized, tags gone
        XCTAssertEqual(gc.region, "Europe")

        let wii = parser.parse(filename: "[Nintendo Wii] Super Mario Galaxy 2 [NTSC].wbfs")
        XCTAssertEqual(wii.title, "Super Mario Galaxy 2")
        XCTAssertEqual(wii.region, "USA")
    }

    /// Without injected aliases, platform names are left in the title (the
    /// parser stays conservative — it only strips what it positively knows).
    func testPlatformTagsKeptWhenNoAliases() {
        let m = parser.parse(filename: "[GameCube] Metroid Prime.rvz")
        XCTAssertEqual(m.title, "[GameCube] Metroid Prime")
    }

    // MARK: - Languages

    func testMultiLanguage() {
        let m = parser.parse(filename: "Secret of Mana (Europe) (En,Fr,De).sfc")
        XCTAssertEqual(m.title, "Secret of Mana")
        XCTAssertEqual(m.region, "Europe")
        XCTAssertEqual(m.languages, ["En", "Fr", "De"])
    }

    // MARK: - Disc / Side markers

    func testDiscMarker() {
        let m = parser.parse(filename: "Final Fantasy VII (USA) (Disc 1).chd")
        XCTAssertEqual(m.title, "Final Fantasy VII")
        XCTAssertEqual(m.region, "USA")
        XCTAssertEqual(m.discNumber, 1)
        XCTAssertNil(m.discTotal)
    }

    func testDiscOfTotal() {
        let m = parser.parse(filename: "Panzer Dragoon Saga (USA) (Disc 2 of 4).chd")
        XCTAssertEqual(m.title, "Panzer Dragoon Saga")
        XCTAssertEqual(m.discNumber, 2)
        XCTAssertEqual(m.discTotal, 4)
    }

    func testDiskSpelling() {
        let m = parser.parse(filename: "Some Game (Disk 1 of 2).chd")
        XCTAssertEqual(m.title, "Some Game")
        XCTAssertEqual(m.discNumber, 1)
        XCTAssertEqual(m.discTotal, 2)
    }

    func testSideMarker() {
        let m = parser.parse(filename: "Cassette Game (Side B).tap")
        XCTAssertEqual(m.title, "Cassette Game")
        XCTAssertEqual(m.discNumber, 2)           // Side B → 2
    }

    // MARK: - Version tags

    func testRevisionTag() {
        let m = parser.parse(filename: "The Legend of Zelda (USA) (Rev 1).sfc")
        XCTAssertEqual(m.title, "The Legend of Zelda")
        XCTAssertEqual(m.region, "USA")
        XCTAssertEqual(m.version, "Rev 1")
    }

    func testVersionNumberTag() {
        let m = parser.parse(filename: "Doom (USA) (v1.1).gba")
        XCTAssertEqual(m.title, "Doom")
        XCTAssertEqual(m.version, "v1.1")
    }

    // MARK: - Special-status flags

    func testProtoFlag() {
        let m = parser.parse(filename: "Star Fox 2 (Proto).sfc")
        XCTAssertEqual(m.title, "Star Fox 2")
        XCTAssertTrue(m.flags.contains("proto"))
    }

    func testBetaFlag() {
        let m = parser.parse(filename: "Sonic 2 (Beta).md")
        XCTAssertEqual(m.title, "Sonic 2")
        XCTAssertTrue(m.flags.contains("beta"))
    }

    func testBracketBadDumpFlag() {
        let m = parser.parse(filename: "Mega Man [b].nes")
        XCTAssertEqual(m.title, "Mega Man")
        XCTAssertTrue(m.flags.contains("b"))
    }

    // MARK: - Conservative behavior (unknown tags kept)

    func testUnknownParentheticalKept() {
        let m = parser.parse(filename: "Some Homebrew (Aftermarket).nes")
        XCTAssertEqual(m.title, "Some Homebrew (Aftermarket)")
        XCTAssertNil(m.region)
        XCTAssertNil(m.discNumber)
    }

    func testUnknownMultiWordParentheticalKept() {
        let m = parser.parse(filename: "Weird ROM (Special Edition).gba")
        XCTAssertEqual(m.title, "Weird ROM (Special Edition)")
    }

    func testUnknownBracketKept() {
        let m = parser.parse(filename: "Cool Game [xyz123].nes")
        XCTAssertEqual(m.title, "Cool Game [xyz123]")
        XCTAssertTrue(m.flags.isEmpty)
    }

    // MARK: - Switch title-ID / version brackets

    func testSwitchTitleIDAndVersionStripped() {
        let m = parser.parse(filename: "Tomodachi Life Living the Dream [010051F0207B2000][v0].nsp")
        XCTAssertEqual(m.title, "Tomodachi Life Living the Dream")
        XCTAssertEqual(m.version, "v0")
    }

    func testSwitchUpdateFileMatchesBaseTitle() {
        let base = parser.parse(filename: "Tomodachi Life Living the Dream [010051F0207B2000][v0].nsp")
        let update = parser.parse(filename: "Tomodachi Life Living the Dream [010051F0207B2800][v131072].nsp")
        XCTAssertEqual(base.title, update.title, "base and update collapse to one title for grouping")
    }

    func testNonHexSixteenCharBracketKept() {
        // Only 16-hex-digit brackets are title IDs; other 16-char brackets stay.
        let m = parser.parse(filename: "Game [GHIJKLMNOPQRSTUV].nsp")
        XCTAssertEqual(m.title, "Game [GHIJKLMNOPQRSTUV]")
    }

    // MARK: - Underscore / whitespace normalization

    func testUnderscoreReplacement() {
        let m = parser.parse(filename: "Game_Name.gba")
        XCTAssertEqual(m.title, "Game Name")
        XCTAssertNil(m.region)
    }

    func testWhitespaceCollapse() {
        let m = parser.parse(filename: "Spaced   Out   Title (USA).nes")
        XCTAssertEqual(m.title, "Spaced Out Title")
    }

    // MARK: - Combined / raw filename

    func testRawFilenamePreserved() {
        let m = parser.parse(filename: "Super Mario World (USA).sfc")
        XCTAssertEqual(m.rawFilename, "Super Mario World (USA).sfc")
    }

    func testCombinedTags() {
        let m = parser.parse(filename: "Grand RPG (Japan) (Rev A) (Disc 1) [!].chd")
        XCTAssertEqual(m.title, "Grand RPG")
        XCTAssertEqual(m.region, "Japan")
        XCTAssertEqual(m.version, "Rev A")
        XCTAssertEqual(m.discNumber, 1)
        XCTAssertTrue(m.flags.contains("!"))
    }
}
