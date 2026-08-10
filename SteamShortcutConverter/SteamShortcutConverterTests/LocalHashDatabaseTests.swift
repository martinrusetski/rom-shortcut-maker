//
//  LocalHashDatabaseTests.swift
//  SteamShortcutConverterTests
//

import XCTest
@testable import SteamShortcutConverter

final class LocalHashDatabaseTests: XCTestCase {

    func testExactHashAndSizeMatch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HashTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let rom = directory.appendingPathComponent("game.iso")
        try Data("hello".utf8).write(to: rom)
        let database = directory.appendingPathComponent("hashes.json")
        try Data("""
        {"entries":[{"sha1":"aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d","size":5,"platform":"ps2","title":"Known Game"}]}
        """.utf8).write(to: database)

        let matches = await LocalHashDatabase.matches(
            inputs: [LocalHashInput(path: rom.path, fileSize: 5)],
            databaseURL: database
        )
        XCTAssertEqual(matches[rom.path], LocalHashMatch(platformID: "ps2", title: "Known Game"))
    }

    func testSizeMismatchDoesNotMatch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HashTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let rom = directory.appendingPathComponent("game.iso")
        try Data("hello".utf8).write(to: rom)
        let database = directory.appendingPathComponent("hashes.json")
        try Data("""
        [{"sha1":"aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d","size":6,"platform":"ps2"}]
        """.utf8).write(to: database)

        let matches = await LocalHashDatabase.matches(
            inputs: [LocalHashInput(path: rom.path, fileSize: 5)],
            databaseURL: database
        )
        XCTAssertTrue(matches.isEmpty)
    }
}
