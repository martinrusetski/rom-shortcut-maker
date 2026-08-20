//
//  BinaryVDFReader.swift
//  RomShortcutMaker
//
//  Low-level binary VDF file reader for Steam's binary format
//

import Foundation

/// Type markers used in Steam's binary VDF format
enum VDFTypeMarker: UInt8 {
    case sectionStart = 0x00  // Start of a section/dictionary
    case string = 0x01        // String value
    case int32 = 0x02         // 32-bit integer value
    case end = 0x08           // End of section/dictionary
}

/// Errors that can occur during VDF parsing
enum VDFReaderError: Error, LocalizedError {
    case invalidFormat(String)
    case unexpectedEndOfData
    case invalidTypeMarker(UInt8)
    case invalidUTF8String
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat(let message):
            return "Invalid VDF format: \(message)"
        case .unexpectedEndOfData:
            return "Unexpected end of data while parsing VDF"
        case .invalidTypeMarker(let marker):
            return "Invalid VDF type marker: 0x\(String(marker, radix: 16))"
        case .invalidUTF8String:
            return "Invalid UTF-8 string in VDF data"
        }
    }
}

/// Low-level binary VDF reader
/// Handles reading and parsing Steam's binary VDF format
class BinaryVDFReader {
    private var data: Data
    private var offset: Int = 0
    
    /// Initialize with binary VDF data
    /// - Parameter data: The binary VDF data to parse
    init(data: Data) {
        self.data = data
        self.offset = 0
    }
    
    /// Read the entire VDF file and return the root dictionary
    /// - Returns: Dictionary representation of the VDF data
    /// - Throws: VDFReaderError if parsing fails
    func read() throws -> [String: Any] {
        offset = 0
        return try readDictionary()
    }
    
    // MARK: - Private Reading Methods
    
    /// Read a single byte from the data
    private func readByte() throws -> UInt8 {
        guard offset < data.count else {
            throw VDFReaderError.unexpectedEndOfData
        }
        let byte = data[offset]
        offset += 1
        return byte
    }
    
    /// Read a null-terminated string from the data
    private func readNullTerminatedString() throws -> String {
        var bytes: [UInt8] = []
        
        while offset < data.count {
            let byte = data[offset]
            offset += 1
            
            if byte == 0 {
                break
            }
            bytes.append(byte)
        }
        
        guard let string = String(bytes: bytes, encoding: .utf8) else {
            throw VDFReaderError.invalidUTF8String
        }
        
        return string
    }
    
    /// Read a 32-bit integer (little-endian)
    private func readInt32() throws -> Int32 {
        guard offset + 4 <= data.count else {
            throw VDFReaderError.unexpectedEndOfData
        }
        
        // Read 4 bytes and convert to Int32 (little-endian)
        let byte0 = Int32(data[offset])
        let byte1 = Int32(data[offset + 1])
        let byte2 = Int32(data[offset + 2])
        let byte3 = Int32(data[offset + 3])
        
        let value = byte0 | (byte1 << 8) | (byte2 << 16) | (byte3 << 24)
        
        offset += 4
        return value
    }
    
    /// Read a dictionary (nested structure)
    private func readDictionary() throws -> [String: Any] {
        var dictionary: [String: Any] = [:]
        
        while offset < data.count {
            let typeMarker = try readByte()
            
            guard let marker = VDFTypeMarker(rawValue: typeMarker) else {
                throw VDFReaderError.invalidTypeMarker(typeMarker)
            }
            
            switch marker {
            case .end:
                // End of current dictionary
                return dictionary
                
            case .sectionStart:
                // Start of nested dictionary
                let key = try readNullTerminatedString()
                let nestedDict = try readDictionary()
                dictionary[key] = nestedDict
                
            case .string:
                // String value
                let key = try readNullTerminatedString()
                let value = try readNullTerminatedString()
                dictionary[key] = value
                
            case .int32:
                // 32-bit integer value
                let key = try readNullTerminatedString()
                let value = try readInt32()
                dictionary[key] = value
            }
        }
        
        // If we reach here without encountering an end marker, the data is incomplete
        throw VDFReaderError.unexpectedEndOfData
    }
}
