//
//  ParamSFOTests.swift
//  RomShortcutMakerTests
//
//  Unit tests for the PARAM.SFO parser, against fixture bytes assembled
//  in-test (no binary fixture files). The fixture builder is shared with
//  ROMScannerTests' PS3-folder tests.
//

import XCTest
@testable import RomShortcutMaker

// MARK: - Fixture builder (shared with ROMScannerTests)

/// Assemble a minimal, valid PARAM.SFO blob containing the given UTF-8 string
/// entries.
enum SFOFixture {

    static func make(entries: [(key: String, value: String)]) -> Data {
        let headerSize = 20
        let indexSize = entries.count * 16
        let keyTableStart = headerSize + indexSize

        var index = Data()
        var keyTable = Data()
        var dataTable = Data()
        for (key, value) in entries {
            let keyOffset = UInt16(keyTable.count)
            keyTable.append(key.data(using: .ascii)!)
            keyTable.append(0)

            let valueBytes = value.data(using: .utf8)! + Data([0])
            let dataOffset = UInt32(dataTable.count)
            index.append(le16(keyOffset))
            index.append(le16(0x0204))                       // UTF-8 string format
            index.append(le32(UInt32(valueBytes.count)))     // dataLen
            index.append(le32(UInt32(valueBytes.count)))     // dataMaxLen
            index.append(le32(dataOffset))
            dataTable.append(valueBytes)
        }

        var data = Data([0x00, 0x50, 0x53, 0x46])            // "\0PSF"
        data.append(le32(0x0101))                            // version
        data.append(le32(UInt32(keyTableStart)))
        data.append(le32(UInt32(keyTableStart + keyTable.count)))
        data.append(le32(UInt32(entries.count)))
        data.append(index)
        data.append(keyTable)
        data.append(dataTable)
        return data
    }

    private static func le16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    private static func le32(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ])
    }
}

// MARK: - Tests

final class ParamSFOTests: XCTestCase {

    func testParsesTitleEntry() {
        let sfo = SFOFixture.make(entries: [
            ("CATEGORY", "DG"),
            ("TITLE", "Odin Sphere Leifthrasir"),
            ("TITLE_ID", "BLES02194")
        ])
        let parsed = ParamSFO.parse(data: sfo)
        XCTAssertEqual(parsed["TITLE"], "Odin Sphere Leifthrasir")
        XCTAssertEqual(parsed["TITLE_ID"], "BLES02194")
        XCTAssertEqual(parsed["CATEGORY"], "DG")
    }

    func testTrimsTrailingWhitespaceAndNewlines() {
        let sfo = SFOFixture.make(entries: [("TITLE", "Some Game\n ")])
        XCTAssertEqual(ParamSFO.parse(data: sfo)["TITLE"], "Some Game")
    }

    func testTitleOfFileOnDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ParamSFOTests-\(UUID().uuidString).sfo")
        defer { try? FileManager.default.removeItem(at: url) }
        try SFOFixture.make(entries: [("TITLE", "Disk Title")]).write(to: url)
        XCTAssertEqual(ParamSFO.title(of: url), "Disk Title")
    }

    func testMissingFileReturnsNil() {
        XCTAssertNil(ParamSFO.title(of: URL(fileURLWithPath: "/no/such/PARAM.SFO")))
    }

    // MARK: Malformed input (must never crash)

    func testEmptyDataReturnsEmpty() {
        XCTAssertTrue(ParamSFO.parse(data: Data()).isEmpty)
    }

    func testWrongMagicReturnsEmpty() {
        var sfo = SFOFixture.make(entries: [("TITLE", "X")])
        sfo[0] = 0xFF
        XCTAssertTrue(ParamSFO.parse(data: sfo).isEmpty)
    }

    func testTruncatedHeaderReturnsEmpty() {
        let sfo = SFOFixture.make(entries: [("TITLE", "X")])
        XCTAssertTrue(ParamSFO.parse(data: sfo.prefix(12)).isEmpty)
    }

    func testTruncatedIndexReturnsPartial() {
        let sfo = SFOFixture.make(entries: [("TITLE", "X")])
        // Cut mid-index: header survives, the entry doesn't.
        XCTAssertNil(ParamSFO.parse(data: sfo.prefix(24))["TITLE"])
    }

    func testGarbageBytesReturnEmpty() {
        let garbage = Data((0..<256).map { UInt8($0 & 0xFF) })
        XCTAssertTrue(ParamSFO.parse(data: garbage).isEmpty)
    }

    func testOutOfBoundsDataOffsetIsSkipped() {
        var sfo = SFOFixture.make(entries: [("TITLE", "X")])
        // Rewrite the entry's dataOffset (index offset 20 + 12) to point far
        // beyond the blob.
        sfo.replaceSubrange(32..<36, with: [0xFF, 0xFF, 0xFF, 0x7F])
        XCTAssertNil(ParamSFO.parse(data: sfo)["TITLE"])
    }
}
