import XCTest
@testable import RomShortcutMaker

final class GameBundleSafetyTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("BundleSafety-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func bundle(args: [String] = ["{romPath}"], rom: String = "/ROMs/game.sfc",
                        previous: String? = nil, name: String = "Game") -> ResolvedGameBundle {
        ResolvedGameBundle(bundleName: name, bundleIdentifier: "com.romshortcutmaker.game",
            displayName: name, executablePath: URL(fileURLWithPath: "/Applications/Snes9x.app"),
            launchArguments: args, romPath: URL(fileURLWithPath: rom), outputDirectory: directory,
            previousBundlePath: previous)
    }

    func testFailedReplacementPreservesOldLauncherAndRemovesStagingFiles() async throws {
        let url = try await DefaultAppBundleGenerator().generateAppBundle(for: bundle())
        let script = url.appendingPathComponent("Contents/MacOS/launch.sh")
        let original = try Data(contentsOf: script)
        let failing = DefaultAppBundleGenerator(defaultShortcutIconURL: directory.appendingPathComponent("missing.icns"))
        do {
            _ = try await failing.generateAppBundle(for: bundle(args: ["--changed", "{romPath}"]))
            XCTFail("The missing required resource must fail staging")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: script), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["Game.app"])
    }

    func testSuccessfulReplacementInstallsCompleteNewBundle() async throws {
        let generator = DefaultAppBundleGenerator()
        let url = try await generator.generateAppBundle(for: bundle())
        let obsolete = url.appendingPathComponent("obsolete-resource")
        try Data([1]).write(to: obsolete)
        let replacement = try await generator.generateAppBundle(for: bundle(args: ["--changed", "{romPath}"]))
        XCTAssertEqual(replacement.path, url.path)
        XCTAssertTrue(try String(contentsOf: url.appendingPathComponent("Contents/MacOS/launch.sh"), encoding: .utf8).contains("--changed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: obsolete.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["Game.app"])
    }

    func testFailedAtomicCommitLeavesDestinationIntact() throws {
        let destination = directory.appendingPathComponent("existing.app")
        try Data("original".utf8).write(to: destination)
        XCTAssertThrowsError(try GameBundleDestination.commit(
            staged: directory.appendingPathComponent("missing.app"), destination: destination, replacing: true))
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "original")
    }

    func testUnrelatedAppCannotBeOverwrittenEvenWithRecordedPath() async throws {
        let url = directory.appendingPathComponent("Game.app")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let sentinel = url.appendingPathComponent("user-file")
        try Data("keep".utf8).write(to: sentinel)
        do {
            _ = try await DefaultAppBundleGenerator().generateAppBundle(for: bundle(previous: url.path))
            XCTFail("An unrelated app must be preserved")
        } catch {}
        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "keep")
    }

    func testAnotherGamesLauncherCannotBeOverwritten() async throws {
        let generator = DefaultAppBundleGenerator()
        let url = try await generator.generateAppBundle(for: bundle())
        let original = try Data(contentsOf: url.appendingPathComponent("Contents/MacOS/launch.sh"))
        do {
            _ = try await generator.generateAppBundle(for: bundle(rom: "/ROMs/other.sfc", previous: url.path))
            XCTFail("A recorded path cannot override another game's ownership marker")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("Contents/MacOS/launch.sh")), original)
    }

    func testRecordedLegacyLauncherCanBeUpdated() async throws {
        let generator = DefaultAppBundleGenerator()
        let url = try await generator.generateAppBundle(for: bundle())
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as! [String: Any]
        plist.removeValue(forKey: GameBundleDestination.gameKey)
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL)
        _ = try await generator.generateAppBundle(for: bundle(args: ["--updated"], previous: url.path))
        XCTAssertTrue(GameBundleDestination.isOwned(url, by: bundle().stableKey, recordedPath: nil))
    }

    func testXMLCharactersProduceValidLauncherMetadata() async throws {
        let url = try await DefaultAppBundleGenerator().generateAppBundle(for: bundle(name: "A & B <Game>"))
        let plist = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")), format: nil) as! [String: Any]
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "A & B <Game>")
    }

    private func entry(_ title: String, path: String) -> GameEntry {
        GameEntry(title: title, romPath: URL(fileURLWithPath: path),
            romMetadata: ROMMetadata(rawFilename: path, title: title),
            platform: Platform(id: "snes", displayName: "SNES"))
    }

    func testNamesHandleDuplicateSanitizedAndCaseInsensitiveCollisions() {
        let games = [entry("Doom", path: "/a"), entry("doom", path: "/b"),
                     entry("A/B", path: "/c"), entry("A:B", path: "/d")]
        let names = GameBundleDestination.names(for: games, previousState: nil, outputDirectory: directory)
        XCTAssertEqual(Set(names.values.map { $0.lowercased() }).count, 4)
        XCTAssertEqual(names, GameBundleDestination.names(for: games.reversed(), previousState: nil, outputDirectory: directory))
    }

    func testSavedNamesRemainStableWhenAnotherGameIsExcludedOrDisappears() throws {
        let games = [entry("Doom", path: "/a"), entry("Doom", path: "/b")]
        let names = GameBundleDestination.names(for: games, previousState: nil, outputDirectory: directory)
        let manager = IncrementalUpdateManager()
        let records = games.map { manager.buildConvertedGame(for: $0,
            bundlePath: directory.appendingPathComponent(names[$0.stableKey]! + ".app").path) }
        let state = GameConversionState(convertedGames: records)
        XCTAssertEqual(GameBundleDestination.names(for: [games[0]], previousState: state,
            outputDirectory: directory)[games[0].stableKey], names[games[0].stableKey])
    }

    func testExistingUnrelatedAppGetsADifferentDestination() throws {
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("Game.app"), withIntermediateDirectories: true)
        let game = entry("Game", path: "/a")
        let names = GameBundleDestination.names(for: [game], previousState: nil, outputDirectory: directory)
        XCTAssertNotEqual(names[game.stableKey], "Game")
    }

    func testCleanupUsesTrashAndProtectsActivePaths() async throws {
        let game = bundle()
        let url = try await DefaultAppBundleGenerator().generateAppBundle(for: game)
        var trashed: [URL] = []
        let trash = directory.appendingPathComponent("Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let manager = IncrementalUpdateManager(trashBundle: {
            trashed.append($0)
            try FileManager.default.moveItem(at: $0, to: trash.appendingPathComponent($0.lastPathComponent))
        })
        let changes = [game.stableKey: GameChange(entry: nil, changeType: .removed, previousBundlePath: url.path)]
        let protected = manager.cleanupOrphanedGameBundles(changes: changes, removeOrphaned: true,
            protectedPaths: [GameBundleDestination.pathKey(url)])
        XCTAssertTrue(protected.removedKeys.isEmpty)
        XCTAssertTrue(trashed.isEmpty)
        let result = manager.cleanupOrphanedGameBundles(changes: changes, removeOrphaned: true)
        XCTAssertEqual(result.removedKeys, [game.stableKey])
        XCTAssertEqual(trashed.map(\.path), [url.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.appendingPathComponent("Game.app/Contents/MacOS/launch.sh").path))
    }

    func testFailedTrashAndUnownedAppsRemainTracked() async throws {
        let url = try await DefaultAppBundleGenerator().generateAppBundle(for: bundle())
        let manager = IncrementalUpdateManager(trashBundle: { _ in throw CocoaError(.fileWriteNoPermission) })
        let changes = [bundle().stableKey: GameChange(entry: nil, changeType: .removed, previousBundlePath: url.path)]
        let result = manager.cleanupOrphanedGameBundles(changes: changes, removeOrphaned: true)
        XCTAssertTrue(result.removedKeys.isEmpty)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let unowned = ["different-key": GameChange(entry: nil, changeType: .removed, previousBundlePath: url.path)]
        let refused = manager.cleanupOrphanedGameBundles(changes: unowned, removeOrphaned: true)
        XCTAssertTrue(refused.removedKeys.isEmpty)
        XCTAssertEqual(refused.errors.count, 1)
    }

    func testPermissionFailureDuringInspectionDoesNotForgetTheLauncher() async throws {
        let locked = directory.appendingPathComponent("Locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let url = locked.appendingPathComponent("Game.app")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }
        if FileManager.default.isExecutableFile(atPath: locked.path) {
            throw XCTSkip("This user bypasses directory permission checks")
        }
        let manager = IncrementalUpdateManager(trashBundle: { _ in XCTFail("Unreadable paths must not reach Trash") })
        let changes = ["game": GameChange(entry: nil, changeType: .removed, previousBundlePath: url.path)]
        let result = manager.cleanupOrphanedGameBundles(changes: changes, removeOrphaned: true)
        XCTAssertTrue(result.removedKeys.isEmpty)
        XCTAssertEqual(result.errors.count, 1)
    }

    func testOwnedDestinationIsRecoveredAfterHistoryWriteFailure() async throws {
        let game = entry("Game", path: "/ROMs/game.sfc")
        _ = try await DefaultAppBundleGenerator().generateAppBundle(for: bundle())
        let names = GameBundleDestination.names(for: [game], previousState: nil, outputDirectory: directory)
        XCTAssertEqual(names[game.stableKey], "Game", "Retry the owned app instead of accumulating suffixed duplicates")
    }
}
