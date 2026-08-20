//
//  DiscContentInspectorTests.swift
//  RomShortcutMakerTests
//

import XCTest
@testable import RomShortcutMaker

private final class FakeDiscPrefixReader: DiscPrefixReading {
    let data: Data?

    init(_ data: Data?) { self.data = data }

    func readPrefix(of url: URL, maxBytes: Int) -> Data? { data }
}

final class DiscContentInspectorTests: XCTestCase {

    func testPS2Signature() {
        let inspector = DiscContentInspector(reader: FakeDiscPrefixReader(Data("CDVDGEN".utf8)))
        let result = inspector.inspect(url: URL(fileURLWithPath: "/tmp/disc.iso"))
        XCTAssertEqual(result?.platformIDs, ["ps2"])
        XCTAssertEqual(result?.descriptions, ["PS2 DVD generator signature"])
    }

    func testPlayStationBootIDSignature() {
        let inspector = DiscContentInspector(reader: FakeDiscPrefixReader(Data("BOOT = cdrom:SLPS_020.38;1".utf8)))
        let result = inspector.inspect(url: URL(fileURLWithPath: "/tmp/disc.iso"))
        XCTAssertEqual(result?.platformIDs, ["ps1"])
    }

    func testMultipleSignaturesArePreservedForAmbiguityHandling() {
        let data = Data("PSP_GAME\0PS3_GAME".utf8)
        let inspector = DiscContentInspector(reader: FakeDiscPrefixReader(data))
        let result = inspector.inspect(url: URL(fileURLWithPath: "/tmp/disc.iso"))
        XCTAssertEqual(result?.platformIDs, ["psp", "ps3"])
    }

    func testWeakOrUnknownDataProducesNoMatch() {
        let inspector = DiscContentInspector(reader: FakeDiscPrefixReader(Data("PLAYSTATION".utf8)))
        XCTAssertNil(inspector.inspect(url: URL(fileURLWithPath: "/tmp/disc.iso")))
    }

    func testCSOPayloadIsInspectedInsteadOfAssumedToBePSP() {
        let inspector = DiscContentInspector(
            reader: FakeDiscPrefixReader(nil),
            csoReader: FakeDiscPrefixReader(Data("PSP_GAME".utf8)),
            chdReader: FakeDiscPrefixReader(nil)
        )
        let result = inspector.inspect(url: URL(fileURLWithPath: "/tmp/disc.cso"))
        XCTAssertEqual(result?.platformIDs, ["psp"])
    }
}
