//
//  DiscImage.swift
//  RomShortcutMaker
//
//  Optical-disc image format knowledge: which files are *entry points* vs.
//  *members* (tracks referenced by a sheet, or discs referenced by a playlist),
//  plus parsers for .cue/.gdi/.ccd sheets and .m3u playlists.
//
//  The key ambiguity: `.bin` is a CD track for Saturn/PS1 but a whole cartridge
//  ROM for Genesis. We never classify `.bin` by extension alone — a `.bin` is a
//  member only when a sibling sheet actually references it.
//

import Foundation

enum DiscImage {

    /// Sheet formats that reference external track files.
    static let sheetExtensions: Set<String> = ["cue", "gdi", "ccd", "mds"]
    /// Playlist formats that reference multiple disc entry points.
    static let playlistExtensions: Set<String> = ["m3u"]

    static func isSheet(_ url: URL) -> Bool { sheetExtensions.contains(url.pathExtension.lowercased()) }
    static func isPlaylist(_ url: URL) -> Bool { playlistExtensions.contains(url.pathExtension.lowercased()) }

    // MARK: - Sheet parsing

    /// The member (track) files a sheet references, resolved to sibling URLs that
    /// actually exist on disk.
    static func members(ofSheet url: URL) -> [URL] {
        let directory = url.deletingLastPathComponent()
        switch url.pathExtension.lowercased() {
        case "cue":
            return existing(names: cueFileNames(in: url), relativeTo: directory)
        case "gdi":
            return existing(names: gdiFileNames(in: url), relativeTo: directory)
        case "ccd":
            // .ccd has no file list; the data/subchannel live in <base>.img/.sub.
            let base = url.deletingPathExtension().lastPathComponent
            return existing(names: ["\(base).img", "\(base).sub"], relativeTo: directory)
        case "mds":
            let base = url.deletingPathExtension().lastPathComponent
            return existing(names: ["\(base).mdf"], relativeTo: directory)
        default:
            return []
        }
    }

    private static func cueFileNames(in url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let regex = try! NSRegularExpression(pattern: "(?im)^\\s*FILE\\s+(?:\"([^\"]+)\"|(\\S+))")
        let ns = text as NSString
        var names: [String] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let quoted = match.range(at: 1)
            let bare = match.range(at: 2)
            if quoted.location != NSNotFound {
                names.append(ns.substring(with: quoted))
            } else if bare.location != NSNotFound {
                names.append(ns.substring(with: bare))
            }
        }
        return names
    }

    private static func gdiFileNames(in url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var names: [String] = []
        for rawLine in text.split(whereSeparator: { $0.isNewline }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // A .gdi track line has the filename as a token; prefer a quoted one.
            if let quoted = firstQuoted(in: line) {
                names.append(quoted)
            } else {
                for token in line.split(separator: " ") {
                    let t = token.trimmingCharacters(in: .init(charactersIn: "\""))
                    if t.contains(".") && !isNumeric(t) { names.append(t) }
                }
            }
        }
        return names
    }

    // MARK: - Playlist parsing

    /// The disc entry points a playlist references, resolved to existing URLs.
    static func entries(ofPlaylist url: URL) -> [URL] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let directory = url.deletingLastPathComponent()
        var result: [URL] = []
        for rawLine in text.split(whereSeparator: { $0.isNewline }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let resolved: URL
            if line.hasPrefix("/") {
                resolved = URL(fileURLWithPath: line)
            } else {
                resolved = URL(fileURLWithPath: line, relativeTo: directory).standardizedFileURL
            }
            if FileManager.default.fileExists(atPath: resolved.path) {
                result.append(resolved)
            }
        }
        return result
    }

    // MARK: - Image preference

    /// Choose the preferred launch image among alternatives for one disc.
    /// Saturn and Dreamcast prefer sheet formats (chd support is spotty); every
    /// other system prefers a single-file `.chd`.
    static func preferredImage(_ images: [URL], platformId: String) -> URL? {
        guard !images.isEmpty else { return nil }
        let prefersSheet = (platformId == "saturn" || platformId == "dreamcast")
        func rank(_ url: URL) -> Int {
            let ext = url.pathExtension.lowercased()
            if prefersSheet {
                if sheetExtensions.contains(ext) { return 0 }
                if ext == "chd" { return 1 }
                return 2
            } else {
                if ext == "chd" { return 0 }
                if sheetExtensions.contains(ext) { return 1 }
                return 2
            }
        }
        return images.sorted { rank($0) < rank($1) }.first
    }

    // MARK: - Helpers

    private static func existing(names: [String], relativeTo directory: URL) -> [URL] {
        names.compactMap { name in
            let url = directory.appendingPathComponent(name)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }

    private static func firstQuoted(in line: String) -> String? {
        guard let start = line.firstIndex(of: "\"") else { return nil }
        let afterStart = line.index(after: start)
        guard let end = line[afterStart...].firstIndex(of: "\"") else { return nil }
        return String(line[afterStart..<end])
    }

    private static func isNumeric(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isNumber }
    }
}
