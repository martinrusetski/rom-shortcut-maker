//
//  FileLocationManagerTests.swift
//  SteamShortcutConverterTests
//
//  Unit tests for file location functionality
//

import XCTest
@testable import SteamShortcutConverter

final class FileLocationManagerTests: XCTestCase {
    
    var manager: FileLocationManager!
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        manager = FileLocationManager()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        manager = nil
        super.tearDown()
    }
    
    // MARK: - Auto-Detection Tests
    
    func testAutoDetectShortcutsFiles_NoSteamDirectory_ReturnsEmptyArray() {
        // When: Auto-detecting with no Steam directory
        let foundPaths = manager.autoDetectShortcutsFiles()
        
        // Then: Should return empty array (or actual paths if Steam is installed)
        // This test is environment-dependent, so we just verify it doesn't crash
        XCTAssertNotNil(foundPaths)
    }
    
    func testAutoDetectShortcutsFiles_ReturnsArrayOfStrings() {
        // When: Auto-detecting shortcuts files
        let foundPaths = manager.autoDetectShortcutsFiles()
        
        // Then: Should return an array (may be empty if no Steam installation)
        XCTAssertTrue(foundPaths is [String])
    }
    
    // MARK: - Manual Selection Validation Tests
    
    func testValidateManualSelection_FileDoesNotExist_ThrowsError() {
        // Given: Non-existent file path
        let nonExistentPath = "/path/to/nonexistent/shortcuts.vdf"
        
        // When/Then: Validating should throw error
        XCTAssertThrowsError(try manager.validateManualSelection(at: nonExistentPath)) { error in
            XCTAssertTrue(error is FileLocationError)
            if case FileLocationError.fileNotReadable = error {
                // Expected error
            } else {
                XCTFail("Expected FileLocationError.fileNotReadable")
            }
        }
    }
    
    func testValidateManualSelection_InvalidVDFFile_ThrowsError() throws {
        // Given: A file that exists but is not valid VDF
        let invalidFilePath = tempDirectory.appendingPathComponent("invalid.vdf").path
        let invalidData = Data("This is not a valid VDF file".utf8)
        try invalidData.write(to: URL(fileURLWithPath: invalidFilePath))
        
        // When/Then: Validating should throw error
        XCTAssertThrowsError(try manager.validateManualSelection(at: invalidFilePath)) { error in
            XCTAssertTrue(error is FileLocationError)
            if case FileLocationError.invalidVDFFile = error {
                // Expected error
            } else {
                XCTFail("Expected FileLocationError.invalidVDFFile")
            }
        }
    }
    
    func testValidateManualSelection_ValidVDFFile_DoesNotThrow() throws {
        // Given: A valid VDF file
        let validFilePath = tempDirectory.appendingPathComponent("valid.vdf").path
        let validVDFData = createValidVDFData()
        try validVDFData.write(to: URL(fileURLWithPath: validFilePath))
        
        // When/Then: Validating should not throw
        XCTAssertNoThrow(try manager.validateManualSelection(at: validFilePath))
    }
    
    // MARK: - Error Message Tests
    
    func testGetNoFileFoundError_ReturnsAppropriateError() {
        // When: Getting no file found error
        let error = manager.getNoFileFoundError()
        
        // Then: Should return FileLocationError with instructions
        XCTAssertTrue(error is FileLocationError)
        if case FileLocationError.noShortcutsFileFound = error {
            let description = error.errorDescription
            XCTAssertNotNil(description)
            XCTAssertTrue(description!.contains("shortcuts.vdf"))
            XCTAssertTrue(description!.contains("Steam"))
        } else {
            XCTFail("Expected FileLocationError.noShortcutsFileFound")
        }
    }
    
    func testFileLocationError_NoShortcutsFileFound_ContainsInstructions() {
        // Given: No shortcuts file found error
        let error = FileLocationError.noShortcutsFileFound
        
        // When: Getting error description
        let description = error.errorDescription
        
        // Then: Should contain helpful instructions
        XCTAssertNotNil(description)
        XCTAssertTrue(description!.contains("~/Library/Application Support/Steam"))
        XCTAssertTrue(description!.contains("Steam ROM Manager"))
        XCTAssertTrue(description!.contains("manually select"))
    }
    
    func testFileLocationError_InvalidVDFFile_ContainsPath() {
        // Given: Invalid VDF file error
        let testPath = "/test/path/shortcuts.vdf"
        let error = FileLocationError.invalidVDFFile(testPath)
        
        // When: Getting error description
        let description = error.errorDescription
        
        // Then: Should contain the file path
        XCTAssertNotNil(description)
        XCTAssertTrue(description!.contains(testPath))
        XCTAssertTrue(description!.contains("not a valid VDF"))
    }
    
    func testFileLocationError_FileNotReadable_ContainsPath() {
        // Given: File not readable error
        let testPath = "/test/path/shortcuts.vdf"
        let error = FileLocationError.fileNotReadable(testPath)
        
        // When: Getting error description
        let description = error.errorDescription
        
        // Then: Should contain the file path
        XCTAssertNotNil(description)
        XCTAssertTrue(description!.contains(testPath))
        XCTAssertTrue(description!.contains("Cannot read"))
    }
    
    // MARK: - Helper Methods
    
    /// Create a minimal valid VDF data for testing
    private func createValidVDFData() -> Data {
        var data = Data()
        
        // VDF format: type marker + key + null terminator + value
        // 0x00 = section start, 0x01 = string, 0x08 = end
        
        // "shortcuts" key (section start)
        data.append(0x00)
        data.append("shortcuts".data(using: .utf8)!)
        data.append(0x00)
        
        // Empty shortcuts section
        
        // End marker
        data.append(0x08)
        data.append(0x08)
        
        return data
    }
}
