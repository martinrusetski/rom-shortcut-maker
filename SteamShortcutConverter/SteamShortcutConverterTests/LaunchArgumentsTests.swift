import XCTest
@testable import SteamShortcutConverter

final class LaunchArgumentsTests: XCTestCase {
    func testParseGroupsQuotedArgumentsAndPreservesEmptyArgument() throws {
        XCTAssertEqual(
            try LaunchArguments.parse(#"--system "Nintendo 64" "" {romPath}"#),
            ["--system", "Nintendo 64", "", "{romPath}"]
        )
    }

    func testFormatRoundTripsSpacesQuotesAndBackslashes() throws {
        let arguments = ["--label", "Game \"One\"", "it's", #"C:\ROMs\Game.sfc"#, ""]
        XCTAssertEqual(try LaunchArguments.parse(LaunchArguments.format(arguments)), arguments)
    }

    func testUnknownPlaceholderIsRejected() {
        XCTAssertThrowsError(try LaunchArguments.parse("--flag {rom}")) { error in
            XCTAssertEqual(error as? LaunchArgumentError, .unknownPlaceholder("{rom}"))
        }
    }

    func testUnmatchedQuoteIsRejected() {
        XCTAssertThrowsError(try LaunchArguments.parse(#"--system "Nintendo 64"#)) { error in
            XCTAssertEqual(error as? LaunchArgumentError, .unmatchedQuote)
        }
    }

    func testMalformedNestedPlaceholderIsRejected() {
        XCTAssertThrowsError(try LaunchArguments.parse("{{romPath}}"))
    }

    func testResolveExpandsEverySupportedPathPlaceholder() throws {
        let rom = URL(fileURLWithPath: "/ROMs/SNES/Chrono Trigger.sfc")
        let core = URL(fileURLWithPath: "/Cores/snes9x_libretro.dylib")
        XCTAssertEqual(
            try LaunchArguments.resolve(
                ["{romPath}", "{romDirectory}", "{romFilename}", "{romStem}", "{corePath}"],
                rom: rom,
                core: core
            ),
            [
                "/ROMs/SNES/Chrono Trigger.sfc",
                "/ROMs/SNES",
                "Chrono Trigger.sfc",
                "Chrono Trigger",
                "/Cores/snes9x_libretro.dylib"
            ]
        )
    }

    func testCorePlaceholderRequiresAResolvedCore() {
        XCTAssertThrowsError(
            try LaunchArguments.resolve(
                ["-L", "{corePath}", "{romPath}"],
                rom: URL(fileURLWithPath: "/ROMs/game.sfc"),
                core: nil
            )
        ) { error in
            XCTAssertEqual(error as? LaunchArgumentError, .missingCore)
        }
    }

    func testResolveReadsTrimmedROMReferenceContents() throws {
        let reference = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchArguments-\(UUID().uuidString).ps4")
        try "  CUSA07010\n".write(to: reference, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: reference) }

        XCTAssertEqual(
            try LaunchArguments.resolve(["-g", "{romContents}"], rom: reference, core: nil),
            ["-g", "CUSA07010"]
        )
    }

    func testResolveRejectsEmptyROMReferenceContents() throws {
        let reference = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaunchArguments-\(UUID().uuidString).psvita")
        try " \n".write(to: reference, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: reference) }

        XCTAssertThrowsError(
            try LaunchArguments.resolve(["-r", "{romContents}"], rom: reference, core: nil)
        ) { error in
            XCTAssertEqual(error as? LaunchArgumentError, .invalidROMReference)
        }
    }
}
