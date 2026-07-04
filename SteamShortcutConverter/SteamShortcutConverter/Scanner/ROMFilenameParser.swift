//
//  ROMFilenameParser.swift
//  SteamShortcutConverter
//
//  Parses ROM filenames (No-Intro / GoodTools / TOSEC-ish conventions) into
//  structured `ROMMetadata`. Pure logic, no I/O — fully unit-testable.
//
//  Design principle: be CONSERVATIVE. Only strip parenthetical / bracket groups
//  we positively recognize. Anything unknown is left in the title for the user
//  to edit, rather than guessing and mangling the name.
//

import Foundation

final class ROMFilenameParser {

    // MARK: - Knowledge

    /// Platform folder aliases (lowercased) recognized as strippable tags, e.g.
    /// `[GameCube]`, `(Nintendo Wii)`. Injected from the SystemDatabase so the
    /// parser and the scanner share one source of truth for platform names.
    private let platformAliases: Set<String>

    init(platformAliases: Set<String> = []) {
        self.platformAliases = platformAliases
    }

    /// Single-letter GoodTools region codes → canonical region name.
    private let regionLetters: [String: String] = [
        "U": "USA",
        "E": "Europe",
        "J": "Japan",
        "W": "World"
    ]

    /// Video-standard / region tags (lowercased) → canonical region, recognized
    /// in both parentheses and brackets, e.g. `[PAL]`, `(NTSC-U)`.
    private let regionStandards: [String: String] = [
        "pal": "Europe",
        "ntsc": "USA",
        "ntsc-u": "USA",
        "ntsc-j": "Japan",
        "ntsc-e": "Europe",
        "ntsc-c": "China",
        "secam": "Europe"
    ]

    /// Recognized region names (lowercased) for parenthetical region tags.
    private let regionNames: Set<String> = [
        "usa", "europe", "japan", "world", "germany", "france", "spain",
        "italy", "australia", "korea", "china", "brazil", "netherlands",
        "sweden", "canada", "asia", "uk", "united kingdom", "russia",
        "hong kong", "taiwan", "scandinavia", "france"
    ]

    /// Recognized two-letter language codes (lowercased).
    private let languageCodes: Set<String> = [
        "en", "fr", "de", "es", "it", "nl", "pt", "sv", "no", "da", "fi",
        "ja", "zh", "ko", "ru", "pl", "cs", "hu", "el", "tr", "ar", "he",
        "ca", "gr"
    ]

    /// Recognized special-status parenthetical tags (lowercased) → `flags`.
    private let specialTags: Set<String> = [
        "proto", "prototype", "beta", "demo", "sample", "unl"
    ]

    /// Recognized bracket flag codes (lowercased) → `flags`.
    private let bracketFlags: Set<String> = [
        "!", "b", "hack", "t", "f", "p", "o", "a"
    ]

    // MARK: - Public API

    /// Parse a ROM filename (with or without extension) into `ROMMetadata`.
    func parse(filename: String) -> ROMMetadata {
        let stem = (filename as NSString).deletingPathExtension

        var region: String?
        var version: String?
        var discNumber: Int?
        var discTotal: Int?
        var languages: [String] = []
        var flags: [String] = []

        let ns = stem as NSString
        // Match top-level (...) or [...] groups (non-nested).
        let pattern = "\\([^()]*\\)|\\[[^\\[\\]]*\\]"
        let regex = try! NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: stem, range: NSRange(location: 0, length: ns.length))

        var stripRanges: [NSRange] = []
        for match in matches {
            let full = ns.substring(with: match.range)
            let inner = String(full.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            let recognized: Bool
            if full.hasPrefix("[") {
                recognized = classifyBracket(inner, region: &region, version: &version, flags: &flags)
            } else {
                recognized = classifyParenthetical(
                    inner,
                    region: &region,
                    version: &version,
                    discNumber: &discNumber,
                    discTotal: &discTotal,
                    languages: &languages,
                    flags: &flags
                )
            }
            if recognized {
                stripRanges.append(match.range)
            }
        }

        let title = buildTitle(from: ns, removing: stripRanges)

        return ROMMetadata(
            rawFilename: filename,
            title: title,
            region: region,
            version: version,
            discNumber: discNumber,
            discTotal: discTotal,
            languages: languages,
            flags: flags
        )
    }

    // MARK: - Title assembly

    /// Reconstruct the title by removing the recognized group ranges, then
    /// normalizing underscores and whitespace.
    private func buildTitle(from ns: NSString, removing stripRanges: [NSRange]) -> String {
        var result = ""
        var cursor = 0
        for range in stripRanges {
            if range.location > cursor {
                result += ns.substring(with: NSRange(location: cursor, length: range.location - cursor))
            }
            cursor = range.location + range.length
        }
        if cursor < ns.length {
            result += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }

        var title = result.replacingOccurrences(of: "_", with: " ")
        // Scene releases use dots as word separators (e.g. "Metroid.Prime").
        // When what's left has no spaces but does have dots, treat dots as
        // spaces. Titles that already contain spaces (e.g. "Dr. Mario") keep
        // their dots.
        let stripped = title.trimmingCharacters(in: .whitespaces)
        if !stripped.contains(" ") && stripped.contains(".") {
            title = title.replacingOccurrences(of: ".", with: " ")
        }
        title = title.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return title.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
    }

    // MARK: - Classification

    /// Classify a parenthetical group's inner content. Returns true if it was
    /// recognized and should be stripped from the title.
    private func classifyParenthetical(
        _ content: String,
        region: inout String?,
        version: inout String?,
        discNumber: inout Int?,
        discTotal: inout Int?,
        languages: inout [String],
        flags: inout [String]
    ) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return false }
        let lower = trimmed.lowercased()

        // Disc / Side markers.
        if let disc = parseDisc(trimmed) {
            if discNumber == nil { discNumber = disc.number }
            if discTotal == nil { discTotal = disc.total }
            return true
        }

        // Version tags.
        if isVersion(trimmed) {
            if version == nil { version = trimmed }
            return true
        }

        // Special-status tags.
        if specialTags.contains(lower) {
            let flag = (lower == "prototype") ? "proto" : lower
            if !flags.contains(flag) { flags.append(flag) }
            return true
        }

        // Video-standard / region tags, e.g. (PAL), (NTSC-U).
        if let canonical = regionStandards[lower] {
            if region == nil { region = canonical }
            return true
        }

        // Region / language lists (comma-separated).
        let parts = trimmed
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !parts.isEmpty {
            if parts.allSatisfy({ isRegionToken($0) }) {
                if region == nil { region = canonicalRegion(parts[0]) }
                return true
            }
            if parts.allSatisfy({ languageCodes.contains($0.lowercased()) }) {
                for part in parts where !languages.contains(part) {
                    languages.append(part)
                }
                return true
            }
        }

        // Platform-name tags, e.g. (GameCube), (Nintendo Wii).
        if platformAliases.contains(lower) { return true }

        // Unrecognized: leave it in the title.
        return false
    }

    /// Classify a bracket group's inner content. Returns true if recognized.
    private func classifyBracket(
        _ content: String,
        region: inout String?,
        version: inout String?,
        flags: inout [String]
    ) -> Bool {
        let lower = content.lowercased()
        if bracketFlags.contains(lower) {
            if !flags.contains(lower) { flags.append(lower) }
            return true
        }
        // Video-standard / region tags, e.g. [PAL], [NTSC-J].
        if let canonical = regionStandards[lower] {
            if region == nil { region = canonical }
            return true
        }
        // Platform-name tags, e.g. [GameCube], [Nintendo Wii].
        if platformAliases.contains(lower) { return true }
        // Nintendo Switch title ID, e.g. [010051F0207B2000] — strip from the
        // title so a base game and its update/DLC share one display name.
        if isSwitchTitleID(content) { return true }
        // Bracketed version, e.g. [v0], [v131072] (Switch dumps).
        if isBracketVersion(content) {
            if version == nil { version = content }
            return true
        }
        return false
    }

    private func isSwitchTitleID(_ content: String) -> Bool {
        content.count == 16 && content.allSatisfy(\.isHexDigit)
    }

    private func isBracketVersion(_ content: String) -> Bool {
        content.range(of: "^v\\d+$", options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: - Token helpers

    private func isRegionToken(_ token: String) -> Bool {
        if token.count == 1, regionLetters[token.uppercased()] != nil { return true }
        return regionNames.contains(token.lowercased())
    }

    private func canonicalRegion(_ token: String) -> String {
        if token.count == 1, let full = regionLetters[token.uppercased()] { return full }
        return token
    }

    private func isVersion(_ content: String) -> Bool {
        let patterns = [
            "^Rev\\s+\\w+$",       // Rev 1, Rev A
            "^v\\d+(\\.\\d+)*$"    // v1.0, v1.2.3
        ]
        for pattern in patterns {
            if content.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                return true
            }
        }
        return false
    }

    private struct DiscInfo {
        let number: Int
        let total: Int?
    }

    private func parseDisc(_ content: String) -> DiscInfo? {
        // "Disc 1", "Disk 1 of 2"
        if let match = content.range(
            of: "^Dis[ck]\\s+(\\d+)(?:\\s+of\\s+(\\d+))?$",
            options: [.regularExpression, .caseInsensitive]
        ), match == content.startIndex..<content.endIndex {
            let ns = content as NSString
            let regex = try! NSRegularExpression(pattern: "^Dis[ck]\\s+(\\d+)(?:\\s+of\\s+(\\d+))?$", options: .caseInsensitive)
            if let result = regex.firstMatch(in: content, range: NSRange(location: 0, length: ns.length)) {
                let number = Int(ns.substring(with: result.range(at: 1))) ?? 1
                var total: Int?
                if result.range(at: 2).location != NSNotFound {
                    total = Int(ns.substring(with: result.range(at: 2)))
                }
                return DiscInfo(number: number, total: total)
            }
        }
        // "Side A", "Side B"
        if let result = content.range(
            of: "^Side\\s+([A-Z])$",
            options: [.regularExpression, .caseInsensitive]
        ), result == content.startIndex..<content.endIndex {
            let letter = content.last!.uppercased()
            if let scalar = letter.unicodeScalars.first {
                let number = Int(scalar.value) - Int(UnicodeScalar("A").value) + 1
                return DiscInfo(number: number, total: nil)
            }
        }
        return nil
    }
}
