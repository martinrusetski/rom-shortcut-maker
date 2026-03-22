//
//  VDFValidator.swift
//  SteamShortcutConverter
//
//  Validation logic for VDF files
//

import Foundation

/// Errors that can occur during VDF validation
enum VDFValidationError: Error, LocalizedError {
    case fileNotFound(String)
    case fileNotReadable(String)
    case invalidFormat(String)
    case corruptedData(String)
    case missingShortcutsSection
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "VDF file not found at path: \(path)"
        case .fileNotReadable(let path):
            return "VDF file is not readable: \(path)"
        case .invalidFormat(let message):
            return "Invalid VDF format: \(message)"
        case .corruptedData(let message):
            return "Corrupted VDF data: \(message)"
        case .missingShortcutsSection:
            return "VDF file does not contain a 'shortcuts' section"
        }
    }
}

/// Validator for VDF files
class VDFValidator {
    
    /// Validate a VDF file at the given path
    /// - Parameter path: Path to the VDF file
    /// - Throws: VDFValidationError if validation fails
    func validateFile(at path: String) throws {
        let fileURL = URL(fileURLWithPath: path)
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: path) else {
            throw VDFValidationError.fileNotFound(path)
        }
        
        // Check if file is readable
        guard FileManager.default.isReadableFile(atPath: path) else {
            throw VDFValidationError.fileNotReadable(path)
        }
        
        // Read file data
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw VDFValidationError.fileNotReadable(path)
        }
        
        // Validate the data
        try validateData(data)
    }
    
    /// Validate VDF data
    /// - Parameter data: Binary VDF data
    /// - Throws: VDFValidationError if validation fails
    func validateData(_ data: Data) throws {
        // Check if data is empty
        guard !data.isEmpty else {
            throw VDFValidationError.invalidFormat("File is empty")
        }
        
        // Try to parse the VDF data
        let reader = BinaryVDFReader(data: data)
        let vdfData: [String: Any]
        
        do {
            vdfData = try reader.read()
        } catch let error as VDFReaderError {
            // Convert VDFReaderError to VDFValidationError
            switch error {
            case .invalidFormat(let message):
                throw VDFValidationError.invalidFormat(message)
            case .unexpectedEndOfData:
                throw VDFValidationError.corruptedData("Unexpected end of data")
            case .invalidTypeMarker(let marker):
                throw VDFValidationError.corruptedData("Invalid type marker: 0x\(String(marker, radix: 16))")
            case .invalidUTF8String:
                throw VDFValidationError.corruptedData("Invalid UTF-8 string")
            }
        } catch {
            throw VDFValidationError.corruptedData("Unknown parsing error: \(error.localizedDescription)")
        }
        
        // Validate that the VDF contains a "shortcuts" section
        guard vdfData["shortcuts"] != nil else {
            throw VDFValidationError.missingShortcutsSection
        }
        
        // Validate that the shortcuts section is a dictionary
        guard vdfData["shortcuts"] is [String: Any] else {
            throw VDFValidationError.invalidFormat("'shortcuts' section is not a dictionary")
        }
    }
}
