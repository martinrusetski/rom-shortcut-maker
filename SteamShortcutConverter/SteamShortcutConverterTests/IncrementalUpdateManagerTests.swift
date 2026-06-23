//
//  IncrementalUpdateManagerTests.swift
//  SteamShortcutConverterTests
//
//  Unit tests for incremental update functionality
//

import XCTest
@testable import SteamShortcutConverter

final class IncrementalUpdateManagerTests: XCTestCase {
    
    var manager: IncrementalUpdateManager!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        manager = IncrementalUpdateManager()
        // Real temp dir so previous-state bundle paths exist on disk. detectChanges
        // treats a missing bundle as .modified (regenerate), so unchanged-metadata
        // tests must point at bundles that actually exist.
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("IncrementalUpdateManagerTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        manager = nil
        super.tearDown()
    }
    
    // MARK: - New Shortcut Detection Tests
    
    func testDetectChanges_NoPreviousState_AllShortcutsAreNew() {
        // Given: Current shortcuts with no previous state
        let shortcuts = [
            createTestShortcut(appID: 1, appName: "Game 1"),
            createTestShortcut(appID: 2, appName: "Game 2"),
            createTestShortcut(appID: 3, appName: "Game 3")
        ]
        
        // When: Detecting changes
        let changes = manager.detectChanges(currentShortcuts: shortcuts, previousState: nil)
        
        // Then: All shortcuts should be marked as new
        XCTAssertEqual(changes.count, 3)
        XCTAssertEqual(changes[1]?.changeType, .new)
        XCTAssertEqual(changes[2]?.changeType, .new)
        XCTAssertEqual(changes[3]?.changeType, .new)
    }
    
    func testDetectChanges_NewShortcutAdded() {
        // Given: Previous state with 2 shortcuts, current has 3
        let previousShortcuts = [
            createTestShortcut(appID: 1, appName: "Game 1"),
            createTestShortcut(appID: 2, appName: "Game 2")
        ]
        let previousState = createTestConversionState(shortcuts: previousShortcuts)
        
        let currentShortcuts = [
            createTestShortcut(appID: 1, appName: "Game 1"),
            createTestShortcut(appID: 2, appName: "Game 2"),
            createTestShortcut(appID: 3, appName: "Game 3") // New
        ]
        
        // When: Detecting changes
        let changes = manager.detectChanges(currentShortcuts: currentShortcuts, previousState: previousState)
        
        // Then: New shortcut should be detected
        XCTAssertEqual(changes[3]?.changeType, .new)
        XCTAssertEqual(changes[1]?.changeType, .unchanged)
        XCTAssertEqual(changes[2]?.changeType, .unchanged)
    }
    
    // MARK: - Removed Shortcut Detection Tests
    
    func testDetectChanges_ShortcutRemoved() {
        // Given: Previous state with 3 shortcuts, current has 2
        let previousShortcuts = [
            createTestShortcut(appID: 1, appName: "Game 1"),
            createTestShortcut(appID: 2, appName: "Game 2"),
            createTestShortcut(appID: 3, appName: "Game 3")
        ]
        let previousState = createTestConversionState(shortcuts: previousShortcuts)
        
        let currentShortcuts = [
            createTestShortcut(appID: 1, appName: "Game 1"),
            createTestShortcut(appID: 2, appName: "Game 2")
            // Game 3 removed
        ]
        
        // When: Detecting changes
        let changes = manager.detectChanges(currentShortcuts: currentShortcuts, previousState: previousState)
        
        // Then: Removed shortcut should be detected
        XCTAssertEqual(changes[3]?.changeType, .removed)
        XCTAssertNil(changes[3]?.shortcut)
        XCTAssertNotNil(changes[3]?.previousBundlePath)
    }
    
    // MARK: - Modified Shortcut Detection Tests
    
    func testDetectChanges_LaunchCommandModified() {
        // Given: Previous state with a shortcut, current has same shortcut with different launch command
        let previousShortcut = createTestShortcut(
            appID: 1,
            appName: "Game 1",
            exe: "/path/to/emulator",
            launchOptions: "--option1"
        )
        let previousState = createTestConversionState(shortcuts: [previousShortcut])
        
        let currentShortcut = createTestShortcut(
            appID: 1,
            appName: "Game 1",
            exe: "/path/to/emulator",
            launchOptions: "--option2" // Changed
        )
        
        // When: Detecting changes
        let changes = manager.detectChanges(currentShortcuts: [currentShortcut], previousState: previousState)
        
        // Then: Shortcut should be marked as modified
        XCTAssertEqual(changes[1]?.changeType, .modified)
        XCTAssertNotNil(changes[1]?.previousBundlePath)
    }
    
    func testDetectChanges_IconModified() {
        // Given: Previous state with a shortcut, current has same shortcut with different icon
        let previousShortcut = createTestShortcut(
            appID: 1,
            appName: "Game 1",
            icon: .filePath("/path/to/icon1.png")
        )
        let previousState = createTestConversionState(shortcuts: [previousShortcut])
        
        let currentShortcut = createTestShortcut(
            appID: 1,
            appName: "Game 1",
            icon: .filePath("/path/to/icon2.png") // Changed
        )
        
        // When: Detecting changes
        let changes = manager.detectChanges(currentShortcuts: [currentShortcut], previousState: previousState)
        
        // Then: Shortcut should be marked as modified
        XCTAssertEqual(changes[1]?.changeType, .modified)
    }
    
    // MARK: - Unchanged Shortcut Detection Tests
    
    func testDetectChanges_ShortcutUnchanged() {
        // Given: Previous state with a shortcut, current has identical shortcut
        let shortcut = createTestShortcut(
            appID: 1,
            appName: "Game 1",
            exe: "/path/to/emulator",
            launchOptions: "--option1"
        )
        let previousState = createTestConversionState(shortcuts: [shortcut])
        
        // When: Detecting changes with same shortcut
        let changes = manager.detectChanges(currentShortcuts: [shortcut], previousState: previousState)
        
        // Then: Shortcut should be marked as unchanged
        XCTAssertEqual(changes[1]?.changeType, .unchanged)
    }
    
    // MARK: - Hash Computation Tests
    
    func testComputeLaunchCommandHash_SameCommandProducesSameHash() {
        // Given: Two identical shortcuts
        let shortcut1 = createTestShortcut(appID: 1, appName: "Game", exe: "/path/to/exe", launchOptions: "--opt")
        let shortcut2 = createTestShortcut(appID: 2, appName: "Game", exe: "/path/to/exe", launchOptions: "--opt")
        
        // When: Computing hashes
        let hash1 = manager.computeLaunchCommandHash(for: shortcut1)
        let hash2 = manager.computeLaunchCommandHash(for: shortcut2)
        
        // Then: Hashes should be identical
        XCTAssertEqual(hash1, hash2)
    }
    
    func testComputeLaunchCommandHash_DifferentCommandProducesDifferentHash() {
        // Given: Two shortcuts with different launch commands
        let shortcut1 = createTestShortcut(appID: 1, appName: "Game", exe: "/path/to/exe", launchOptions: "--opt1")
        let shortcut2 = createTestShortcut(appID: 2, appName: "Game", exe: "/path/to/exe", launchOptions: "--opt2")
        
        // When: Computing hashes
        let hash1 = manager.computeLaunchCommandHash(for: shortcut1)
        let hash2 = manager.computeLaunchCommandHash(for: shortcut2)
        
        // Then: Hashes should be different
        XCTAssertNotEqual(hash1, hash2)
    }
    
    func testComputeIconHash_NoIcon_ReturnsNil() {
        // Given: Shortcut with no icon
        let shortcut = createTestShortcut(appID: 1, appName: "Game", icon: nil)
        
        // When: Computing icon hash
        let hash = manager.computeIconHash(for: shortcut)
        
        // Then: Hash should be nil
        XCTAssertNil(hash)
    }
    
    func testComputeIconHash_SameIconProducesSameHash() {
        // Given: Two shortcuts with same icon
        let iconData = Data([0x01, 0x02, 0x03])
        let shortcut1 = createTestShortcut(appID: 1, appName: "Game", icon: .embedded(iconData))
        let shortcut2 = createTestShortcut(appID: 2, appName: "Game", icon: .embedded(iconData))
        
        // When: Computing hashes
        let hash1 = manager.computeIconHash(for: shortcut1)
        let hash2 = manager.computeIconHash(for: shortcut2)
        
        // Then: Hashes should be identical
        XCTAssertEqual(hash1, hash2)
    }
    
    // MARK: - Orphaned Bundle Cleanup Tests
    
    func testCleanupOrphanedBundles_RemoveOrphanedDisabled_NoBundlesDeleted() throws {
        // Given: Changes with removed shortcuts, but cleanup disabled
        let changes: [UInt32: ShortcutChange] = [
            1: ShortcutChange(shortcut: nil, changeType: .removed, previousBundlePath: "/path/to/bundle.app")
        ]
        
        // When: Cleaning up with removeOrphaned = false
        let deletedPaths = try manager.cleanupOrphanedBundles(changes: changes, removeOrphaned: false)
        
        // Then: No bundles should be deleted
        XCTAssertEqual(deletedPaths.count, 0)
    }
    
    func testCleanupOrphanedBundles_RemoveOrphanedEnabled_BundlesDeleted() throws {
        // Given: Changes with removed shortcuts and cleanup enabled
        let tempDir = FileManager.default.temporaryDirectory
        let bundlePath = tempDir.appendingPathComponent("TestBundle.app").path
        
        // Create a temporary bundle directory
        try FileManager.default.createDirectory(atPath: bundlePath, withIntermediateDirectories: true)
        
        let changes: [UInt32: ShortcutChange] = [
            1: ShortcutChange(shortcut: nil, changeType: .removed, previousBundlePath: bundlePath)
        ]
        
        // When: Cleaning up with removeOrphaned = true
        let deletedPaths = try manager.cleanupOrphanedBundles(changes: changes, removeOrphaned: true)
        
        // Then: Bundle should be deleted
        XCTAssertEqual(deletedPaths.count, 1)
        XCTAssertEqual(deletedPaths[0], bundlePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bundlePath))
    }
    
    // MARK: - ConvertedShortcut Building Tests
    
    func testBuildConvertedShortcut_CreatesCorrectRecord() {
        // Given: A shortcut and bundle path
        let shortcut = createTestShortcut(
            appID: 123,
            appName: "Test Game",
            exe: "/path/to/emulator",
            launchOptions: "--option"
        )
        let bundlePath = "/output/Test Game.app"
        
        // When: Building converted shortcut record
        let record = manager.buildConvertedShortcut(for: shortcut, bundlePath: bundlePath)
        
        // Then: Record should have correct values
        XCTAssertEqual(record.appID, 123)
        XCTAssertEqual(record.appName, "Test Game")
        XCTAssertEqual(record.bundlePath, bundlePath)
        XCTAssertNotNil(record.launchCommandHash)
        XCTAssertFalse(record.launchCommandHash.isEmpty)
    }
    
    // MARK: - Helper Methods
    
    private func createTestShortcut(
        appID: UInt32,
        appName: String,
        exe: String = "/path/to/emulator",
        startDir: String? = nil,
        launchOptions: String? = nil,
        icon: IconData? = nil,
        tags: [String] = []
    ) -> SteamShortcut {
        return SteamShortcut(
            appID: appID,
            appName: appName,
            exe: exe,
            startDir: startDir,
            launchOptions: launchOptions,
            icon: icon,
            tags: tags
        )
    }
    
    private func createTestConversionState(shortcuts: [SteamShortcut]) -> ConversionState {
        let convertedShortcuts = shortcuts.map { shortcut -> ConvertedShortcut in
            // Create the bundle directory on disk so detectChanges sees it as
            // existing and compares metadata rather than flagging it for regeneration.
            let bundlePath = tempDir.appendingPathComponent("\(shortcut.appName).app").path
            try? FileManager.default.createDirectory(
                atPath: bundlePath, withIntermediateDirectories: true)
            return manager.buildConvertedShortcut(for: shortcut, bundlePath: bundlePath)
        }
        
        return ConversionState(
            timestamp: Date(),
            sourceVDFPath: "/path/to/shortcuts.vdf",
            convertedShortcuts: convertedShortcuts
        )
    }
}
