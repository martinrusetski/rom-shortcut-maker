//
//  IncrementalUpdateManagerGameTests.swift
//  SteamShortcutConverterTests
//
//  Tests for the ROM-pipeline (GameEntry) incremental update path.
//

import XCTest
@testable import SteamShortcutConverter

final class IncrementalUpdateManagerGameTests: XCTestCase {

    var manager: IncrementalUpdateManager!
    var tempDir: URL!

    override func setUpWithError() throws {
        manager = IncrementalUpdateManager()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("IncrGameTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        manager = nil
        tempDir = nil
    }

    // MARK: - Helpers

    @discardableResult
    private func writeROM(_ name: String, bytes: [UInt8]) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    private func makeBundleDir(_ name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeEntry(rom: URL, args: String = "\"{emulator}\" \"{rom}\"") -> GameEntry {
        GameEntry(
            title: "Game",
            romPath: rom,
            romMetadata: ROMMetadata(rawFilename: rom.lastPathComponent, title: "Game"),
            platform: Platform(id: "snes", displayName: "SNES"),
            emulatorPath: URL(fileURLWithPath: "/Applications/Snes9x.app"),
            argsTemplate: args
        )
    }

    // MARK: - Detection

    func testAllNewWithoutPreviousState() throws {
        let entry = makeEntry(rom: try writeROM("a.sfc", bytes: [1, 2, 3]))
        let changes = manager.detectChanges(currentGames: [entry], previousState: nil)
        XCTAssertEqual(changes[entry.stableKey]?.changeType, .new)
    }

    func testUnchanged() throws {
        let entry = makeEntry(rom: try writeROM("a.sfc", bytes: [1, 2, 3]))
        let bundle = try makeBundleDir("Game.app")
        let state = GameConversionState(convertedGames: [
            manager.buildConvertedGame(for: entry, bundlePath: bundle.path)
        ])
        let changes = manager.detectChanges(currentGames: [entry], previousState: state)
        XCTAssertEqual(changes[entry.stableKey]?.changeType, .unchanged)
    }

    func testModifiedWhenArgsChange() throws {
        let rom = try writeROM("a.sfc", bytes: [1, 2, 3])
        let original = makeEntry(rom: rom)
        let bundle = try makeBundleDir("Game.app")
        let state = GameConversionState(convertedGames: [
            manager.buildConvertedGame(for: original, bundlePath: bundle.path)
        ])
        let changed = makeEntry(rom: rom, args: "\"{emulator}\" --fullscreen \"{rom}\"")
        let changes = manager.detectChanges(currentGames: [changed], previousState: state)
        XCTAssertEqual(changes[changed.stableKey]?.changeType, .modified)
    }

    func testModifiedWhenBundleMissing() throws {
        let entry = makeEntry(rom: try writeROM("a.sfc", bytes: [1, 2, 3]))
        let state = GameConversionState(convertedGames: [
            manager.buildConvertedGame(for: entry, bundlePath: tempDir.appendingPathComponent("Missing.app").path)
        ])
        let changes = manager.detectChanges(currentGames: [entry], previousState: state)
        XCTAssertEqual(changes[entry.stableKey]?.changeType, .modified)
    }

    func testRedumpedROMSamePathDifferentContent() throws {
        let rom = try writeROM("a.sfc", bytes: [1, 2, 3])
        let entry = makeEntry(rom: rom)
        let bundle = try makeBundleDir("Game.app")
        let state = GameConversionState(convertedGames: [
            manager.buildConvertedGame(for: entry, bundlePath: bundle.path)
        ])
        // Re-dump: same path, different content (and size).
        try Data([9, 9, 9, 9, 9]).write(to: rom)
        let changes = manager.detectChanges(currentGames: [entry], previousState: state)
        XCTAssertEqual(changes[entry.stableKey]?.changeType, .modified)
    }

    func testRemoved() throws {
        let entry = makeEntry(rom: try writeROM("a.sfc", bytes: [1, 2, 3]))
        let bundle = try makeBundleDir("Game.app")
        let state = GameConversionState(convertedGames: [
            manager.buildConvertedGame(for: entry, bundlePath: bundle.path)
        ])
        let changes = manager.detectChanges(currentGames: [], previousState: state)
        XCTAssertEqual(changes[entry.stableKey]?.changeType, .removed)
        XCTAssertEqual(changes[entry.stableKey]?.previousBundlePath, bundle.path)
    }

    func testModifiedWhenMemberFileChanges() throws {
        let cue = try writeROM("game.cue", bytes: [1, 2, 3])
        let track = try writeROM("track01.bin", bytes: [4, 4, 4])
        var entry = makeEntry(rom: cue)
        entry.additionalFiles = [track]
        let bundle = try makeBundleDir("Game.app")
        let state = GameConversionState(convertedGames: [
            manager.buildConvertedGame(for: entry, bundlePath: bundle.path)
        ])
        // Re-dump a track (entry .cue unchanged, but a member changed).
        try Data([9, 9, 9, 9, 9]).write(to: track)
        let changes = manager.detectChanges(currentGames: [entry], previousState: state)
        XCTAssertEqual(changes[entry.stableKey]?.changeType, .modified)
    }

    // MARK: - Hash caching

    func testMtimeSizeShortCircuit() throws {
        let rom = try writeROM("big.iso", bytes: Array(repeating: 0xAB, count: 4096))
        _ = manager.romFileHash(rom)
        _ = manager.romFileHash(rom)
        XCTAssertEqual(manager.romHashComputationCount, 1, "second call should hit the cache")

        // Change the file: cache must invalidate and re-hash.
        try Data(Array(repeating: 0xCD, count: 2048)).write(to: rom)
        _ = manager.romFileHash(rom)
        XCTAssertEqual(manager.romHashComputationCount, 2)
    }
}
