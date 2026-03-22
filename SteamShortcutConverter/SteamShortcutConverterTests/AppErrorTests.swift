//
//  AppErrorTests.swift
//  SteamShortcutConverterTests
//
//  Tests for AppError types and error display
//

import XCTest
@testable import SteamShortcutConverter

final class AppErrorTests: XCTestCase {
    
    // MARK: - Error Description Tests
    
    func testFileNotFoundErrorDescription() {
        let error = AppError.fileNotFound(path: "/path/to/file.vdf")
        XCTAssertEqual(error.errorDescription, "File not found: /path/to/file.vdf")
    }
    
    func testInvalidVDFFormatErrorDescription() {
        let error = AppError.invalidVDFFormat(path: "/path/to/shortcuts.vdf")
        XCTAssertTrue(error.errorDescription?.contains("Invalid VDF format") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("/path/to/shortcuts.vdf") ?? false)
    }
    
    func testOutputDirectoryNotWritableErrorDescription() {
        let error = AppError.outputDirectoryNotWritable(path: "/readonly/path")
        XCTAssertTrue(error.errorDescription?.contains("Cannot write to output directory") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("/readonly/path") ?? false)
    }
    
    func testConversionFailedErrorDescription() {
        let error = AppError.conversionFailed(shortcutName: "Super Mario Bros", reason: "Emulator not found")
        XCTAssertTrue(error.errorDescription?.contains("Super Mario Bros") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("Emulator not found") ?? false)
    }
    
    func testConfigurationErrorDescription() {
        let error = AppError.configurationError(message: "Invalid config file")
        XCTAssertTrue(error.errorDescription?.contains("Configuration error") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("Invalid config file") ?? false)
    }
    
    // MARK: - Actionable Message Tests
    
    func testFileNotFoundActionableMessage() {
        let error = AppError.fileNotFound(path: "/path/to/file.vdf")
        XCTAssertTrue(error.actionableMessage.contains("Browse"))
    }
    
    func testInvalidVDFFormatActionableMessage() {
        let error = AppError.invalidVDFFormat(path: "/path/to/shortcuts.vdf")
        XCTAssertTrue(error.actionableMessage.contains("Steam ROM Manager"))
    }
    
    func testOutputDirectoryNotWritableActionableMessage() {
        let error = AppError.outputDirectoryNotWritable(path: "/readonly/path")
        XCTAssertTrue(error.actionableMessage.contains("different output directory"))
    }
    
    func testConversionFailedActionableMessage() {
        let error = AppError.conversionFailed(shortcutName: "Game", reason: "Error")
        XCTAssertTrue(error.actionableMessage.contains("emulator") || error.actionableMessage.contains("ROM"))
    }
    
    func testConfigurationErrorActionableMessage() {
        let error = AppError.configurationError(message: "Invalid")
        XCTAssertTrue(error.actionableMessage.contains("Reset") || error.actionableMessage.contains("configuration"))
    }
    
    // MARK: - Equatable Tests
    
    func testErrorEquality() {
        let error1 = AppError.fileNotFound(path: "/path/to/file.vdf")
        let error2 = AppError.fileNotFound(path: "/path/to/file.vdf")
        let error3 = AppError.fileNotFound(path: "/different/path.vdf")
        
        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }
    
    func testDifferentErrorTypesNotEqual() {
        let error1 = AppError.fileNotFound(path: "/path")
        let error2 = AppError.invalidVDFFormat(path: "/path")
        
        XCTAssertNotEqual(error1, error2)
    }
}
