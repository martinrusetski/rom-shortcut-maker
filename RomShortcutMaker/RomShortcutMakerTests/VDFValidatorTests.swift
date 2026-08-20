//
//  VDFValidatorTests.swift
//  RomShortcutMakerTests
//
//  Unit tests for VDFValidator
//

import XCTest
@testable import RomShortcutMaker

final class VDFValidatorTests: XCTestCase {
    
    var validator: VDFValidator!
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        validator = VDFValidator()
        
        // Create a temporary directory for test files
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        validator = nil
        super.tearDown()
    }
    
    // MARK: - File Existence Tests
    
    func testValidateFileNotFound() {
        let nonExistentPath = "/path/to/nonexistent/file.vdf"
        
        XCTAssertThrowsError(try validator.validateFile(at: nonExistentPath)) { error in
            XCTAssertTrue(error is VDFValidationError)
            if case VDFValidationError.fileNotFound(let path) = error {
                XCTAssertEqual(path, nonExistentPath)
            } else {
                XCTFail("Expected fileNotFound error")
            }
        }
    }
    
    func testValidateFileNotReadable() throws {
        // Create a file with no read permissions
        let testFile = tempDirectory.appendingPathComponent("unreadable.vdf")
        let validData = createValidVDFData()
        try validData.write(to: testFile)
        
        // Remove read permissions (macOS specific)
        #if os(macOS)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: testFile.path
        )
        
        XCTAssertThrowsError(try validator.validateFile(at: testFile.path)) { error in
            XCTAssertTrue(error is VDFValidationError)
            if case VDFValidationError.fileNotReadable = error {
                // Expected error
            } else {
                XCTFail("Expected fileNotReadable error")
            }
        }
        
        // Restore permissions for cleanup
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: testFile.path
        )
        #endif
    }
    
    // MARK: - VDF Format Validation Tests
    
    func testValidateValidVDFFile() throws {
        // Create a valid VDF file with shortcuts section
        let testFile = tempDirectory.appendingPathComponent("valid.vdf")
        let validData = createValidVDFData()
        try validData.write(to: testFile)
        
        // Should not throw
        XCTAssertNoThrow(try validator.validateFile(at: testFile.path))
    }
    
    func testValidateEmptyFile() throws {
        let testFile = tempDirectory.appendingPathComponent("empty.vdf")
        let emptyData = Data()
        try emptyData.write(to: testFile)
        
        XCTAssertThrowsError(try validator.validateFile(at: testFile.path)) { error in
            XCTAssertTrue(error is VDFValidationError)
            if case VDFValidationError.invalidFormat(let message) = error {
                XCTAssertTrue(message.contains("empty"), "Error message should mention empty file")
            } else {
                XCTFail("Expected invalidFormat error for empty file")
            }
        }
    }
    
    func testValidateMissingShortcutsSection() throws {
        // Create VDF data without shortcuts section
        var data = Data()
        data.append(0x01) // String marker
        data.append(contentsOf: "other_key".utf8)
        data.append(0x00)
        data.append(contentsOf: "value".utf8)
        data.append(0x00)
        data.append(0x08) // End marker
        
        XCTAssertThrowsError(try validator.validateData(data)) { error in
            XCTAssertTrue(error is VDFValidationError)
            if case VDFValidationError.missingShortcutsSection = error {
                // Expected error
            } else {
                XCTFail("Expected missingShortcutsSection error")
            }
        }
    }
    
    func testValidateShortcutsSectionNotDictionary() throws {
        // Create VDF where "shortcuts" is a string instead of dictionary
        var data = Data()
        data.append(0x01) // String marker
        data.append(contentsOf: "shortcuts".utf8)
        data.append(0x00)
        data.append(contentsOf: "not a dictionary".utf8)
        data.append(0x00)
        data.append(0x08) // End marker
        
        XCTAssertThrowsError(try validator.validateData(data)) { error in
            XCTAssertTrue(error is VDFValidationError)
            if case VDFValidationError.invalidFormat(let message) = error {
                XCTAssertTrue(message.contains("not a dictionary"))
            } else {
                XCTFail("Expected invalidFormat error")
            }
        }
    }
    
    // MARK: - Corrupted Data Tests
    
    func testValidateCorruptedDataUnexpectedEnd() {
        // Create incomplete VDF data
        var data = Data()
        data.append(0x00) // Section start
        data.append(contentsOf: "shortcuts".utf8)
        data.append(0x00)
        // Missing end markers - corrupted
        
        XCTAssertThrowsError(try validator.validateData(data)) { error in
            XCTAssertTrue(error is VDFValidationError)
            if case VDFValidationError.corruptedData(let message) = error {
                XCTAssertTrue(message.contains("Unexpected end"))
            } else {
                XCTFail("Expected corruptedData error")
            }
        }
    }
    
    func testValidateCorruptedDataInvalidTypeMarker() {
        // Create VDF with invalid type marker
        var data = Data()
        data.append(0xFF) // Invalid type marker
        
        XCTAssertThrowsError(try validator.validateData(data)) { error in
            XCTAssertTrue(error is VDFValidationError)
            if case VDFValidationError.corruptedData(let message) = error {
                XCTAssertTrue(message.contains("Invalid type marker"))
            } else {
                XCTFail("Expected corruptedData error")
            }
        }
    }
    
    func testValidateCorruptedDataInvalidUTF8() {
        // Create VDF with invalid UTF-8 string
        var data = Data()
        data.append(0x01) // String marker
        data.append(contentsOf: [0xFF, 0xFE, 0xFD]) // Invalid UTF-8 bytes
        data.append(0x00)
        
        XCTAssertThrowsError(try validator.validateData(data)) { error in
            XCTAssertTrue(error is VDFValidationError)
            if case VDFValidationError.corruptedData(let message) = error {
                XCTAssertTrue(message.contains("UTF-8"))
            } else {
                XCTFail("Expected corruptedData error for invalid UTF-8")
            }
        }
    }
    
    // MARK: - Valid VDF with Shortcuts Tests
    
    func testValidateValidVDFWithEmptyShortcuts() throws {
        // Create VDF with empty shortcuts section
        var data = Data()
        data.append(0x00) // Section start
        data.append(contentsOf: "shortcuts".utf8)
        data.append(0x00)
        data.append(0x08) // End shortcuts section
        data.append(0x08) // End root
        
        // Should not throw - empty shortcuts section is valid
        XCTAssertNoThrow(try validator.validateData(data))
    }
    
    func testValidateValidVDFWithShortcuts() throws {
        let data = createValidVDFData()
        
        // Should not throw
        XCTAssertNoThrow(try validator.validateData(data))
    }
    
    // MARK: - Helper Methods
    
    /// Create valid VDF data with a shortcuts section
    private func createValidVDFData() -> Data {
        var data = Data()
        
        // Start shortcuts section
        data.append(0x00) // Section start
        data.append(contentsOf: "shortcuts".utf8)
        data.append(0x00)
        
        // Add a shortcut entry "0"
        data.append(0x00) // Section start
        data.append(contentsOf: "0".utf8)
        data.append(0x00)
        
        // Add AppName
        data.append(0x01) // String marker
        data.append(contentsOf: "AppName".utf8)
        data.append(0x00)
        data.append(contentsOf: "Test Game".utf8)
        data.append(0x00)
        
        // Add appid
        data.append(0x02) // Int32 marker
        data.append(contentsOf: "appid".utf8)
        data.append(0x00)
        var appid: Int32 = 12345
        data.append(contentsOf: withUnsafeBytes(of: &appid) { Data($0) })
        
        // Add Exe
        data.append(0x01) // String marker
        data.append(contentsOf: "Exe".utf8)
        data.append(0x00)
        data.append(contentsOf: "/path/to/emulator".utf8)
        data.append(0x00)
        
        data.append(0x08) // End shortcut entry
        data.append(0x08) // End shortcuts section
        data.append(0x08) // End root
        
        return data
    }
}
