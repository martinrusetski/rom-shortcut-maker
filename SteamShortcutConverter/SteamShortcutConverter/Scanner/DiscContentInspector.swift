//
//  DiscContentInspector.swift
//  SteamShortcutConverter
//
//  Looks for strong platform signatures in uncompressed optical-image data.
//  It never examines filenames. Generic formats remain unresolved unless their
//  payload contains a signature strong enough to identify one platform.
//

import Compression
import Foundation

struct DiscContentProbe: Equatable {
    let platformIDs: [String]
    let descriptions: [String]
}

protocol DiscPrefixReading {
    func readPrefix(of url: URL, maxBytes: Int) -> Data?
}

final class DefaultDiscPrefixReader: DiscPrefixReading {
    func readPrefix(of url: URL, maxBytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: maxBytes)
    }
}

/// Reads the leading logical sectors of a CSO/CISO image. CSO is a generic
/// compressed ISO container, so the decompressed payload is inspected rather
/// than treating the extension as PSP-specific.
final class CSOPrefixReader: DiscPrefixReading {

    func readPrefix(of url: URL, maxBytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let header = try? read(handle, at: 0, count: 24),
              header.count == 24,
              String(data: header.prefix(4), encoding: .ascii) == "CISO" else {
            return nil
        }

        let headerSize = max(24, Int(littleEndianUInt32(header, at: 4)))
        let totalBytes = littleEndianUInt64(header, at: 8)
        let blockSize = Int(littleEndianUInt32(header, at: 16))
        let alignment = Int(header[21])
        guard blockSize > 0, blockSize <= 1 << 20, totalBytes > 0 else { return nil }

        let totalBlocks = (totalBytes + UInt64(blockSize) - 1) / UInt64(blockSize)
        let blocksToRead = min(
            totalBlocks,
            UInt64((maxBytes + blockSize - 1) / blockSize)
        )
        guard blocksToRead > 0,
              blocksToRead < UInt64(Int.max / 4) else { return nil }

        let indexCount = Int(blocksToRead) + 1
        guard let indexData = try? read(
            handle,
            at: UInt64(headerSize),
            count: indexCount * 4
        ), indexData.count == indexCount * 4 else {
            return nil
        }

        var output = Data()
        output.reserveCapacity(min(maxBytes, Int(min(totalBytes, UInt64(Int.max)))))
        for block in 0..<Int(blocksToRead) {
            let current = littleEndianUInt32(indexData, at: block * 4)
            let next = littleEndianUInt32(indexData, at: (block + 1) * 4)
            let currentOffset = UInt64(current & 0x7fffffff) << alignment
            let nextOffset = UInt64(next & 0x7fffffff) << alignment
            guard nextOffset >= currentOffset else { return nil }
            let compressedLength = Int(nextOffset - currentOffset)
            guard compressedLength > 0,
                  let compressed = try? read(handle, at: currentOffset, count: compressedLength),
                  compressed.count == compressedLength else {
                return nil
            }

            let isUncompressed = (current & 0x80000000) != 0
            let decoded: Data
            if isUncompressed {
                decoded = compressed
            } else {
                guard let decompressed = decompress(compressed, into: blockSize) else { return nil }
                decoded = decompressed
            }
            output.append(decoded.prefix(maxBytes - output.count))
            if output.count >= maxBytes { break }
        }
        return output
    }

    private func decompress(_ data: Data, into capacity: Int) -> Data? {
        var output = Data(repeating: 0, count: capacity)
        let decodedCount = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                guard let destinationBase = destination.baseAddress,
                      let sourceBase = source.baseAddress else { return 0 }
                return compression_decode_buffer(
                    destinationBase.assumingMemoryBound(to: UInt8.self),
                    capacity,
                    sourceBase.assumingMemoryBound(to: UInt8.self),
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decodedCount > 0 else { return nil }
        output.count = decodedCount
        return output
    }

    private func read(_ handle: FileHandle, at offset: UInt64, count: Int) throws -> Data {
        try handle.seek(toOffset: offset)
        return try handle.read(upToCount: count) ?? Data()
    }

    private func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) |
        UInt32(data[offset + 1]) << 8 |
        UInt32(data[offset + 2]) << 16 |
        UInt32(data[offset + 3]) << 24
    }

    private func littleEndianUInt64(_ data: Data, at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(data[offset + index]) << UInt64(index * 8)
        }
        return value
    }
}

/// Optional CHD payload reader. CHD metadata can identify the physical medium,
/// but platform boot signatures live in compressed hunks. MAME's `chdman` is
/// used only when installed; missing tooling simply leaves the result unresolved.
final class CHDManPrefixReader: DiscPrefixReading {

    private let executableURL: URL?

    init(executableURL: URL? = nil) {
        self.executableURL = executableURL ?? Self.findExecutable()
    }

    func readPrefix(of url: URL, maxBytes: Int) -> Data? {
        guard let executableURL else { return nil }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RomShortcutMaker-CHD-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "extractraw", "-i", url.path,
            "-o", outputURL.path,
            "-f", "-ib", String(maxBytes)
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        return try? Data(contentsOf: outputURL)
    }

    private static func findExecutable() -> URL? {
        let fileManager = FileManager.default
        var paths = [
            "/opt/homebrew/bin/chdman",
            "/usr/local/bin/chdman"
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            paths.append(contentsOf: path.split(separator: ":").map {
                String($0) + "/chdman"
            })
        }
        return paths.map(URL.init(fileURLWithPath:)).first {
            fileManager.isExecutableFile(atPath: $0.path)
        }
    }
}

final class DiscContentInspector {

    private let reader: DiscPrefixReading
    private let csoReader: DiscPrefixReading
    private let chdReader: DiscPrefixReading
    private let chdMetadataInspector = CHDImageInspector()
    private let maxProbeBytes = 8 * 1024 * 1024
    private var cache: [String: DiscContentProbe] = [:]
    private var chdCache: [String: DiscContentProbe] = [:]

    init(
        reader: DiscPrefixReading = DefaultDiscPrefixReader(),
        csoReader: DiscPrefixReading = CSOPrefixReader(),
        chdReader: DiscPrefixReading = CHDManPrefixReader()
    ) {
        self.reader = reader
        self.csoReader = csoReader
        self.chdReader = chdReader
    }

    /// Inspect an entry point or a sheet's first data members. Sheets are only
    /// used to locate payload files; their syntax is not treated as a platform
    /// signal by itself.
    func inspect(url: URL) -> DiscContentProbe? {
        inspect(url: url, depth: 0)
    }

    /// A scanner instance is reused between rescans. Cached probes are valid
    /// only for one scan because a ROM may have been replaced at the same path.
    func clearCache() {
        cache.removeAll(keepingCapacity: true)
        chdCache.removeAll(keepingCapacity: true)
    }

    private func inspect(url: URL, depth: Int) -> DiscContentProbe? {
        let sources: [URL]
        switch url.pathExtension.lowercased() {
        case "cue", "gdi", "ccd", "mds":
            sources = DiscImage.members(ofSheet: url).filter {
                $0.pathExtension.lowercased() != "sub"
            }
        case "m3u":
            guard depth < 4 else { return nil }
            var ids: [String] = []
            var descriptions: [String] = []
            for entry in DiscImage.entries(ofPlaylist: url).prefix(4) {
                guard let nested = inspect(url: entry, depth: depth + 1) else { continue }
                for (index, platformID) in nested.platformIDs.enumerated()
                    where !ids.contains(platformID) {
                    ids.append(platformID)
                    descriptions.append(nested.descriptions[index])
                }
            }
            guard !ids.isEmpty else { return nil }
            return DiscContentProbe(platformIDs: ids, descriptions: descriptions)
        case "chd":
            let cacheKey = url.standardizedFileURL.path
            if let cached = chdCache[cacheKey] { return cached }
            guard chdMetadataInspector.inspect(url: url) != nil else { return nil }
            guard let data = chdReader.readPrefix(of: url, maxBytes: maxProbeBytes) else { return nil }
            let matches = signatures(in: data)
            guard !matches.isEmpty else { return nil }
            let result = DiscContentProbe(
                platformIDs: matches.map(\.platformID),
                descriptions: matches.map(\.description)
            )
            chdCache[cacheKey] = result
            return result
        case "cso":
            guard let data = csoReader.readPrefix(of: url, maxBytes: maxProbeBytes) else { return nil }
            let matches = signatures(in: data)
            guard !matches.isEmpty else { return nil }
            return DiscContentProbe(
                platformIDs: matches.map(\.platformID),
                descriptions: matches.map(\.description)
            )
        default:
            sources = [url]
        }

        let cacheKey = sources.map(\.standardizedFileURL.path).joined(separator: "\n")
        if let cached = cache[cacheKey] { return cached }

        var ids: [String] = []
        var descriptions: [String] = []
        for source in sources.prefix(4) {
            guard let data = reader.readPrefix(of: source, maxBytes: maxProbeBytes) else { continue }
            let matches = signatures(in: data)
            for match in matches where !ids.contains(match.platformID) {
                ids.append(match.platformID)
                descriptions.append(match.description)
            }
        }

        guard !ids.isEmpty else { return nil }
        let result = DiscContentProbe(platformIDs: ids, descriptions: descriptions)
        cache[cacheKey] = result
        return result
    }

    private struct Signature {
        let platformID: String
        let marker: String
        let description: String
    }

    private let signatures = [
        Signature(platformID: "ps2", marker: "CDVDGEN", description: "PS2 DVD generator signature"),
        Signature(platformID: "ps2", marker: "DVD-ROM GENERATOR", description: "PS2 DVD generator signature"),
        Signature(platformID: "ps1", marker: "MKPSXISO", description: "PlayStation disc-builder signature"),
        Signature(platformID: "ps1", marker: "BOOT = CDROM:SLPS_", description: "PlayStation SLPS boot ID"),
        Signature(platformID: "ps1", marker: "BOOT = CDROM:SCPS_", description: "PlayStation SCPS boot ID"),
        Signature(platformID: "ps1", marker: "BOOT = CDROM:SCES_", description: "PlayStation SCES boot ID"),
        Signature(platformID: "ps1", marker: "BOOT = CDROM:SLES_", description: "PlayStation SLES boot ID"),
        Signature(platformID: "ps1", marker: "BOOT = CDROM:SLUS_", description: "PlayStation SLUS boot ID"),
        Signature(platformID: "psp", marker: "UMD_DATA.BIN", description: "PSP UMD filesystem signature"),
        Signature(platformID: "psp", marker: "PSP_GAME", description: "PSP game directory signature"),
        Signature(platformID: "ps3", marker: "PS3_GAME", description: "PS3 game directory signature"),
        Signature(platformID: "saturn", marker: "SEGASATURN", description: "Sega Saturn boot signature"),
        Signature(platformID: "dreamcast", marker: "SEGA SEGAKATANA", description: "Dreamcast GD-ROM boot signature")
    ]

    private func signatures(in data: Data) -> [Signature] {
        let uppercased = Data(data.map { byte in
            (97...122).contains(byte) ? byte - 32 : byte
        })
        return signatures.filter { uppercased.range(of: Data($0.marker.utf8)) != nil }
    }
}
