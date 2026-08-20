//
//  SwitchTitle.swift
//  RomShortcutMaker
//
//  Nintendo Switch title-ID knowledge. A Switch game folder often holds several
//  files that are all one game: the base application plus separate update
//  (patch) and DLC (add-on content) NSPs. They're distinguished by the 64-bit
//  title ID embedded in the filename, e.g.
//
//      Tomodachi Life [010051F0207B2000][v0].nsp        ← base
//      Tomodachi Life [010051F0207B2800][v131072].nsp   ← update
//
//  The content type lives in the low 13 bits of the title ID:
//    * base   → 0x000
//    * update → 0x800   (base + 0x800)
//    * DLC    → 0x1000…0x1FFF (base + 0x1000 + index)
//

import Foundation

enum SwitchTitle {

    enum ContentType {
        case base
        case update
        case dlc
    }

    /// The 16-hex-digit title ID embedded in a filename, if present.
    static func titleID(inFilename filename: String) -> UInt64? {
        let stem = (filename as NSString).deletingPathExtension as NSString
        let regex = try! NSRegularExpression(pattern: "\\[([0-9A-Fa-f]{16})\\]")
        guard let match = regex.firstMatch(in: stem as String,
                                           range: NSRange(location: 0, length: stem.length)) else {
            return nil
        }
        return UInt64(stem.substring(with: match.range(at: 1)), radix: 16)
    }

    /// Classify a title ID by its low 13 bits.
    static func contentType(of titleID: UInt64) -> ContentType {
        switch titleID & 0x1FFF {
        case 0x000: return .base
        case 0x800: return .update
        default:    return .dlc   // 0x1000…0x1FFF
        }
    }

    /// Classify a filename directly. Files with no recognizable title ID are
    /// treated as `.base` (a homebrew .nro or an oddly named dump is the thing
    /// we'd launch, not an add-on).
    static func contentType(ofFilename filename: String) -> ContentType {
        guard let id = titleID(inFilename: filename) else { return .base }
        return contentType(of: id)
    }
}
