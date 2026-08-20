//
//  BinaryVDFReaderTests.swift
//  RomShortcutMakerTests
//
//  Unit tests for BinaryVDFReader
//

import XCTest
@testable import RomShortcutMaker

final class BinaryVDFReaderTests: XCTestCase {
    
    // MARK: - Basic Reading Tests
    
    func testReadEmptyDictionary() throws {
        // Create a minimal VDF structure: just an end marker
        let data = Data([0x08]) // End marker
        
        let reader = BinaryVDFReader(data: data)
        let result = try reader.read()
        
        XCTAssertTrue(result.isEmpty, "Empty dictionary should be returned")
    }
    
    func testReadStringValue() throws {
        // Create VDF with a single string key-value pair
        // Format: 0x01 (string marker) + "key\0" + "value\0" + 0x08 (end)
        var data = Data()
        data.append(0x01) // String type marker
        data.append(contentsOf: "key".utf8)
        data.append(0x00) // Null terminator for key
        data.append(contentsOf: "value".utf8)
        data.append(0x00) // Null terminator for value
        data.append(0x08) // End marker
        
        let reader = BinaryVDFReader(data: data)
        let result = try reader.read()
        
        XCTAssertEqual(result["key"] as? String, "value")
    }
    
    func testReadInt32Value() throws {
        // Create VDF with a single int32 key-value pair
        // Format: 0x02 (int32 marker) + "count\0" + 42 (as int32) + 0x08 (end)
        var data = Data()
        data.append(0x02) // Int32 type marker
        data.append(contentsOf: "count".utf8)
        data.append(0x00) // Null terminator for key
        
        // Append int32 value (42) in little-endian
        var value: Int32 = 42
        data.append(contentsOf: withUnsafeBytes(of: &value) { Data($0) })
        
        data.append(0x08) // End marker
        
        let reader = BinaryVDFReader(data: data)
        let result = try reader.read()
        
        XCTAssertEqual(result["count"] as? Int32, 42)
    }
    
    func testReadNestedDictionary() throws {
        // Create VDF with nested dictionary
        // Format: 0x00 (section start) + "section\0" + nested content + 0x08 (end nested) + 0x08 (end root)
        var data = Data()
        data.append(0x00) // Section start marker
        data.append(contentsOf: "section".utf8)
        data.append(0x00) // Null terminator for section name
        
        // Add a string inside the nested section
        data.append(0x01) // String type marker
        data.append(contentsOf: "nested_key".utf8)
        data.append(0x00) // Null terminator
        data.append(contentsOf: "nested_value".utf8)
        data.append(0x00) // Null terminator
        
        data.append(0x08) // End nested section
        data.append(0x08) // End root
        
        let reader = BinaryVDFReader(data: data)
        let result = try reader.read()
        
        XCTAssertNotNil(result["section"])
        let section = result["section"] as? [String: Any]
        XCTAssertNotNil(section)
        XCTAssertEqual(section?["nested_key"] as? String, "nested_value")
    }
    
    func testReadMultipleValues() throws {
        // Create VDF with multiple key-value pairs
        var data = Data()
        
        // First string
        data.append(0x01)
        data.append(contentsOf: "name".utf8)
        data.append(0x00)
        data.append(contentsOf: "Test Game".utf8)
        data.append(0x00)
        
        // Int32
        data.append(0x02)
        data.append(contentsOf: "appid".utf8)
        data.append(0x00)
        var appid: Int32 = 12345
        data.append(contentsOf: withUnsafeBytes(of: &appid) { Data($0) })
        
        // Another string
        data.append(0x01)
        data.append(contentsOf: "exe".utf8)
        data.append(0x00)
        data.append(contentsOf: "/path/to/game".utf8)
        data.append(0x00)
        
        data.append(0x08) // End marker
        
        let reader = BinaryVDFReader(data: data)
        let result = try reader.read()
        
        XCTAssertEqual(result["name"] as? String, "Test Game")
        XCTAssertEqual(result["appid"] as? Int32, 12345)
        XCTAssertEqual(result["exe"] as? String, "/path/to/game")
    }
    
    // MARK: - Error Handling Tests
    
    func testUnexpectedEndOfData() {
        // Create incomplete VDF data (missing end marker)
        var data = Data()
        data.append(0x01) // String marker
        data.append(contentsOf: "key".utf8)
        data.append(0x00)
        // Missing value and end marker
        
        let reader = BinaryVDFReader(data: data)
        
        XCTAssertThrowsError(try reader.read()) { error in
            XCTAssertTrue(error is VDFReaderError)
            if case VDFReaderError.unexpectedEndOfData = error {
                // Expected error
            } else {
                XCTFail("Expected unexpectedEndOfData error")
            }
        }
    }
    
    func testInvalidTypeMarker() {
        // Create VDF with invalid type marker
        var data = Data()
        data.append(0xFF) // Invalid type marker
        
        let reader = BinaryVDFReader(data: data)
        
        XCTAssertThrowsError(try reader.read()) { error in
            XCTAssertTrue(error is VDFReaderError)
            if case VDFReaderError.invalidTypeMarker = error {
                // Expected error
            } else {
                XCTFail("Expected invalidTypeMarker error")
            }
        }
    }
    
    func testEmptyData() {
        let data = Data()
        let reader = BinaryVDFReader(data: data)
        
        XCTAssertThrowsError(try reader.read()) { error in
            XCTAssertTrue(error is VDFReaderError)
        }
    }
}
