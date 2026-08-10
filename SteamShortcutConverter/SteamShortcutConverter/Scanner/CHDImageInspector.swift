//
//  CHDImageInspector.swift
//  SteamShortcutConverter
//
//  Reads the small, uncompressed CHD header and metadata chain. This identifies
//  the physical image type without relying on a filename or decompressing the
//  image payload.
//

import Foundation

enum CHDMediaType: String, Equatable {
    case cd = "cd"
    case gdrom = "gdrom"
    case dvd = "dvd"
    case hardDisk = "hardDisk"
    case unknown = "unknown"
}

struct CHDImageInfo: Equatable {
    let version: UInt32
    let logicalBytes: UInt64
    let mediaType: CHDMediaType
}

final class CHDImageInspector {

    private static let metadataHeaderSize = 16
    private static let maxMetadataEntries = 1024

    /// Inspect a CHD without reading its compressed hunks. Invalid or truncated
    /// files return nil so the scanner can retain its normal ambiguity behavior.
    func inspect(url: URL) -> CHDImageInfo? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let prefix = try? read(handle, at: 0, count: 16),
              prefix.count == 16,
              String(data: prefix.prefix(8), encoding: .ascii) == "MComprHD" else {
            return nil
        }

        let version = bigEndianUInt32(prefix, at: 12)
        let headerLength: Int
        let logicalOffset: Int
        let metadataOffset: Int
        switch version {
        case 3:
            headerLength = 120
            logicalOffset = 28
            metadataOffset = 36
        case 4:
            headerLength = 108
            logicalOffset = 28
            metadataOffset = 36
        case 5:
            headerLength = 124
            logicalOffset = 32
            metadataOffset = 48
        default:
            return nil
        }

        guard bigEndianUInt32(prefix, at: 8) == UInt32(headerLength),
              let header = try? read(handle, at: 0, count: headerLength),
              header.count == headerLength else {
            return nil
        }

        let logicalBytes = bigEndianUInt64(header, at: logicalOffset)
        var nextMetadataOffset = bigEndianUInt64(header, at: metadataOffset)
        var mediaType = CHDMediaType.unknown
        var visitedOffsets = Set<UInt64>()
        var entriesRead = 0

        while nextMetadataOffset != 0,
              entriesRead < Self.maxMetadataEntries,
              visitedOffsets.insert(nextMetadataOffset).inserted {
            guard let metadataHeader = try? read(
                handle,
                at: nextMetadataOffset,
                count: Self.metadataHeaderSize
            ), metadataHeader.count == Self.metadataHeaderSize else {
                return nil
            }

            let tag = String(data: metadataHeader.prefix(4), encoding: .ascii) ?? ""
            if let detectedType = Self.mediaType(forMetadataTag: tag) {
                mediaType = detectedType
                break
            }
            nextMetadataOffset = bigEndianUInt64(metadataHeader, at: 8)
            entriesRead += 1
        }

        return CHDImageInfo(
            version: version,
            logicalBytes: logicalBytes,
            mediaType: mediaType
        )
    }

    private static func mediaType(forMetadataTag tag: String) -> CHDMediaType? {
        switch tag {
        case "CHCD", "CHTR", "CHT2": return .cd
        case "CHGT", "CHGD": return .gdrom
        case "DVD ": return .dvd
        case "GDDD": return .hardDisk
        default: return nil
        }
    }

    private func read(_ handle: FileHandle, at offset: UInt64, count: Int) throws -> Data {
        try handle.seek(toOffset: offset)
        return try handle.read(upToCount: count) ?? Data()
    }

    private func bigEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24 |
        UInt32(data[offset + 1]) << 16 |
        UInt32(data[offset + 2]) << 8 |
        UInt32(data[offset + 3])
    }

    private func bigEndianUInt64(_ data: Data, at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value = (value << 8) | UInt64(data[offset + index])
        }
        return value
    }
}
