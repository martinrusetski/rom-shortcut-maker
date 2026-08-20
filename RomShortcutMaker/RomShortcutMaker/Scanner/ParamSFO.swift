//
//  ParamSFO.swift
//  RomShortcutMaker
//
//  Minimal parser for Sony PARAM.SFO metadata files (PS3 extracted-disc
//  folders). Pure and defensive: every offset is bounds-checked and any
//  malformed input yields nil/empty instead of crashing — a hostile file must
//  never take the scanner down.
//
//  Format (all integers little-endian):
//    0x00  u32  magic "\0PSF" (00 50 53 46)
//    0x04  u32  version
//    0x08  u32  keyTableStart
//    0x0C  u32  dataTableStart
//    0x10  u32  entryCount
//  followed by `entryCount` 16-byte index entries:
//    u16 keyOffset, u16 dataFormat, u32 dataLen, u32 dataMaxLen, u32 dataOffset
//  Key: NUL-terminated ASCII at keyTableStart + keyOffset.
//  Value (format 0x0204, UTF-8 string): dataLen bytes at
//  dataTableStart + dataOffset, NUL-terminated.
//

import Foundation

enum ParamSFO {

    /// Bytes 00 50 53 46 read as a little-endian u32.
    private static let magic: UInt32 = 0x4653_5000

    /// dataFormat for a NUL-terminated UTF-8 string entry.
    private static let utf8Format: UInt16 = 0x0204

    /// Sanity cap on the index size so a crafted entryCount can't make us loop
    /// over gigabytes of nothing.
    private static let maxEntries = 4096

    // MARK: - API

    /// The `TITLE` string of a PARAM.SFO on disk, or nil if the file is
    /// missing, unreadable, or malformed.
    static func title(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parse(data: data)["TITLE"]
    }

    /// All UTF-8 string entries of an SFO blob (non-string formats are
    /// skipped). Returns an empty dictionary for malformed input.
    static func parse(data: Data) -> [String: String] {
        guard data.count >= 20,
              u32(data, 0) == magic,
              let keyTableStart = u32(data, 8).map(Int.init),
              let dataTableStart = u32(data, 12).map(Int.init),
              let entryCount = u32(data, 16).map(Int.init),
              entryCount <= maxEntries
        else { return [:] }

        var result: [String: String] = [:]
        for index in 0..<entryCount {
            let base = 20 + index * 16
            guard let keyOffset = u16(data, base).map(Int.init),
                  let dataFormat = u16(data, base + 2),
                  let dataLen = u32(data, base + 4).map(Int.init),
                  let dataOffset = u32(data, base + 12).map(Int.init)
            else { break }   // truncated index → keep what we have
            guard dataFormat == utf8Format else { continue }
            guard let key = asciiCString(data, at: keyTableStart + keyOffset) else { continue }

            let valueStart = dataTableStart + dataOffset
            guard valueStart >= 0, valueStart + dataLen <= data.count else { continue }
            let raw = slice(data, valueStart, dataLen).prefix { $0 != 0 }
            guard let value = String(data: Data(raw), encoding: .utf8) else { continue }
            result[key] = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    // MARK: - Bounds-checked reads

    private static func slice(_ data: Data, _ offset: Int, _ length: Int) -> Data {
        let start = data.startIndex + offset
        return data.subdata(in: start..<(start + length))
    }

    private static func u16(_ data: Data, _ offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        let start = data.startIndex + offset
        return UInt16(data[start]) | (UInt16(data[start + 1]) << 8)
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        let start = data.startIndex + offset
        return UInt32(data[start])
            | (UInt32(data[start + 1]) << 8)
            | (UInt32(data[start + 2]) << 16)
            | (UInt32(data[start + 3]) << 24)
    }

    /// NUL-terminated ASCII string starting at `offset`, or nil when out of
    /// bounds / unterminated / non-ASCII.
    private static func asciiCString(_ data: Data, at offset: Int) -> String? {
        guard offset >= 0, offset < data.count else { return nil }
        var bytes: [UInt8] = []
        var cursor = data.startIndex + offset
        while cursor < data.endIndex {
            let byte = data[cursor]
            if byte == 0 {
                return bytes.isEmpty ? nil : String(bytes: bytes, encoding: .ascii)
            }
            guard byte < 0x80 else { return nil }
            bytes.append(byte)
            cursor += 1
        }
        return nil   // ran off the end without a terminator
    }
}
