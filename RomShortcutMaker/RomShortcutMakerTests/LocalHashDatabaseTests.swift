//
//  LocalHashDatabaseTests.swift
//  RomShortcutMakerTests
//

import XCTest
@testable import RomShortcutMaker

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

        let matches = try await LocalHashDatabase.matches(
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

        let matches = try await LocalHashDatabase.matches(
            inputs: [LocalHashInput(path: rom.path, fileSize: 5)],
            databaseURL: database
        )
        XCTAssertTrue(matches.isEmpty)
    }

    func testCapturedSizeMismatchDoesNotHashPartialOrChangedFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HashTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let rom = directory.appendingPathComponent("game.iso")
        try Data("hello".utf8).write(to: rom)
        let database = directory.appendingPathComponent("hashes.json")
        try Data("""
        [{"sha1":"aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d","platform":"ps2"}]
        """.utf8).write(to: database)

        let matches = try await LocalHashDatabase.matches(
            inputs: [LocalHashInput(path: rom.path, fileSize: 10)],
            databaseURL: database
        )
        XCTAssertTrue(matches.isEmpty)
    }

    func testMalformedDatabaseThrowsActionableError() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HashTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = directory.appendingPathComponent("hashes.json")
        try Data("not json".utf8).write(to: database)

        do {
            _ = try await LocalHashDatabase.matches(inputs: [], databaseURL: database)
            XCTFail("Expected malformed database to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Invalid hash database"))
            XCTAssertTrue(error.localizedDescription.contains(database.path))
        }
    }

    func testMissingConfiguredDatabaseThrowsActionableError() async {
        let database = URL(fileURLWithPath: "/no/such/hash-database.json")

        do {
            _ = try await LocalHashDatabase.matches(inputs: [], databaseURL: database)
            XCTFail("Expected unreadable database to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Cannot read hash database"))
            XCTAssertTrue(error.localizedDescription.contains(database.path))
        }
    }
}
