//
//  EmulatorDetector.swift
//  SteamShortcutConverter
//
//  Finds installed emulators (standalone .app bundles + CLI binaries) and
//  enumerates installed RetroArch cores. Filesystem access is injected so the
//  detector is hermetically testable.
//

import Foundation

// MARK: - AppDiscovering

/// Filesystem listing abstraction, injected for testability.
protocol AppDiscovering {
    /// `.app` bundles located directly inside `directory`.
    func appBundles(in directory: URL) -> [URL]
    /// Executable regular files located directly inside `directory`.
    func executables(in directory: URL) -> [URL]
    /// Regular files with the given extension (no dot) located directly inside `directory`.
    func files(in directory: URL, withExtension ext: String) -> [URL]
    /// `CFBundleExecutable` from an `.app` bundle's `Info.plist`, if present.
    func infoPlistExecutable(for appBundle: URL) -> String?
    /// UTF-8 contents of a text file, or nil if it doesn't exist / can't be read.
    func readText(at url: URL) -> String?
}

final class DefaultAppDiscovering: AppDiscovering {

    func appBundles(in directory: URL) -> [URL] {
        contents(of: directory).filter { $0.pathExtension.lowercased() == "app" }
    }

    func executables(in directory: URL) -> [URL] {
        contents(of: directory, keys: [.isExecutableKey, .isRegularFileKey]).filter { url in
            let values = try? url.resourceValues(forKeys: [.isExecutableKey, .isRegularFileKey])
            return values?.isRegularFile == true && values?.isExecutable == true
        }
    }

    func files(in directory: URL, withExtension ext: String) -> [URL] {
        let normalized = ext.lowercased()
        return contents(of: directory).filter { $0.pathExtension.lowercased() == normalized }
    }

    func infoPlistExecutable(for appBundle: URL) -> String? {
        let plistURL = appBundle.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any] else { return nil }
        return dict["CFBundleExecutable"] as? String
    }

    func readText(at url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    private func contents(of directory: URL, keys: [URLResourceKey] = []) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []
    }
}

// MARK: - EmulatorMatcher

/// Strict emulator-name matching. Unlike the legacy `ShortcutFilter` (which used
/// substring `contains` and false-matched "ares" inside "software"), this only
/// matches when the pattern occurs at a word boundary in the basename.
enum EmulatorMatcher {

    static func matches(basename: String, pattern: String) -> Bool {
        let haystack = basename.lowercased()
        let needle = pattern.lowercased()
        guard !needle.isEmpty else { return false }
        if haystack == needle { return true }
        guard haystack.count > needle.count else { return false }

        let chars = Array(haystack)
        var searchStart = haystack.startIndex
        while let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            let startOffset = haystack.distance(from: haystack.startIndex, to: range.lowerBound)
            let endOffset = startOffset + needle.count
            let precededByBoundary = startOffset == 0 || !isWordCharacter(chars[startOffset - 1])
            let followedByBoundary = endOffset >= chars.count || !isWordCharacter(chars[endOffset])
            if precededByBoundary && followedByBoundary { return true }
            searchStart = haystack.index(after: range.lowerBound)
        }
        return false
    }

    /// The emulator type whose patterns strictly match any of the candidate names.
    static func match(names: [String]) -> EmulatorType? {
        for type in EmulatorType.allCases {
            for pattern in type.executablePatterns {
                for name in names where matches(basename: name, pattern: pattern) {
                    return type
                }
            }
        }
        return nil
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}

// MARK: - InstalledCore

/// A libretro core found on disk, with metadata read from its RetroArch `.info`
/// file so it can be mapped to a platform without hardcoding filenames.
struct InstalledCore: Equatable {
    let filename: String     // e.g. "mednafen_saturn_libretro.dylib"
    let url: URL             // full path to the .dylib
    let displayName: String  // from .info (display_name / corename), else derived
    let systemId: String?    // from .info `systemid`, e.g. "sega_saturn"
}

// MARK: - EmulatorDetector

final class EmulatorDetector {

    private let database: SystemDatabase
    private let fs: AppDiscovering

    /// Directories searched for `.app` bundles.
    private let appSearchDirectories: [URL]
    /// Directories searched for CLI executables.
    private let binSearchDirectories: [URL]
    /// Extra RetroArch cores directories (beyond a detected RetroArch.app).
    private let extraCoreDirectories: [URL]
    /// Extra RetroArch core-info directories (beyond a detected RetroArch.app).
    private let extraInfoDirectories: [URL]

    init(
        database: SystemDatabase,
        fs: AppDiscovering = DefaultAppDiscovering(),
        appSearchDirectories: [URL]? = nil,
        binSearchDirectories: [URL]? = nil,
        extraCoreDirectories: [URL]? = nil,
        extraInfoDirectories: [URL]? = nil
    ) {
        self.database = database
        self.fs = fs
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.appSearchDirectories = appSearchDirectories ?? [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications")
        ]
        self.binSearchDirectories = binSearchDirectories ?? [
            URL(fileURLWithPath: "/opt/homebrew/bin"),
            URL(fileURLWithPath: "/usr/local/bin")
        ]
        self.extraCoreDirectories = extraCoreDirectories ?? [
            home.appendingPathComponent("Library/Application Support/RetroArch/cores")
        ]
        self.extraInfoDirectories = extraInfoDirectories ?? [
            home.appendingPathComponent("Library/Application Support/RetroArch/info")
        ]
    }

    /// All detected emulators (standalone + the RetroArch app itself), mapping
    /// each type to the paths where it was found.
    func detectAll() -> [EmulatorType: [URL]] {
        var result: [EmulatorType: [URL]] = [:]

        for directory in appSearchDirectories {
            for appURL in fs.appBundles(in: directory) {
                let bundleName = appURL.deletingPathExtension().lastPathComponent
                var names = [bundleName]
                if let executable = fs.infoPlistExecutable(for: appURL) {
                    names.append(executable)
                }
                if let type = EmulatorMatcher.match(names: names) {
                    result[type, default: []].append(appURL)
                }
            }
        }

        for directory in binSearchDirectories {
            for executableURL in fs.executables(in: directory) {
                let name = executableURL.lastPathComponent
                if let type = EmulatorMatcher.match(names: [name]) {
                    result[type, default: []].append(executableURL)
                }
            }
        }

        return result
    }

    /// The installed libretro cores (`*_libretro.dylib`), each mapped to its
    /// platform via the sibling RetroArch `.info` metadata file.
    func installedCores() -> [InstalledCore] {
        let infoDirectories = self.infoDirectories()
        var cores: [InstalledCore] = []
        var seen = Set<String>()
        for directory in coreDirectories() {
            for dylib in fs.files(in: directory, withExtension: "dylib") {
                let filename = dylib.lastPathComponent
                guard filename.hasSuffix("_libretro.dylib"), seen.insert(filename).inserted else { continue }
                let base = String(filename.dropLast(".dylib".count))   // "<name>_libretro"
                let info = readCoreInfo(base: base, in: infoDirectories)
                cores.append(InstalledCore(
                    filename: filename,
                    url: dylib,
                    displayName: info.displayName ?? prettyCoreName(base),
                    systemId: info.systemId
                ))
            }
        }
        return cores
    }

    // MARK: - Core info

    private func readCoreInfo(base: String, in directories: [URL]) -> (displayName: String?, systemId: String?) {
        for directory in directories {
            let infoURL = directory.appendingPathComponent("\(base).info")
            guard let text = fs.readText(at: infoURL) else { continue }
            let display = infoField("display_name", in: text) ?? infoField("corename", in: text)
            let systemId = infoField("systemid", in: text)
            return (display, systemId)
        }
        return (nil, nil)
    }

    private func infoField(_ key: String, in text: String) -> String? {
        let pattern = "(?m)^\\s*\(key)\\s*=\\s*\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        let value = ns.substring(with: match.range(at: 1))
        return value.isEmpty ? nil : value
    }

    private func prettyCoreName(_ base: String) -> String {
        base.replacingOccurrences(of: "_libretro", with: "")
            .replacingOccurrences(of: "_", with: " ")
    }

    /// Candidate RetroArch cores directories: the `cores` folder of any detected
    /// RetroArch.app, plus the configured extra directories.
    private func coreDirectories() -> [URL] {
        directoriesForRetroArchSubfolder("cores", extras: extraCoreDirectories)
    }

    /// Candidate RetroArch core-info directories.
    private func infoDirectories() -> [URL] {
        directoriesForRetroArchSubfolder("info", extras: extraInfoDirectories)
    }

    private func directoriesForRetroArchSubfolder(_ subfolder: String, extras: [URL]) -> [URL] {
        var directories: [URL] = []
        for retroArchURL in detectAll()[.retroArch] ?? [] {
            if retroArchURL.pathExtension.lowercased() == "app" {
                directories.append(retroArchURL.appendingPathComponent("Contents/Resources/\(subfolder)"))
            } else {
                directories.append(retroArchURL.deletingLastPathComponent().appendingPathComponent(subfolder))
            }
        }
        directories.append(contentsOf: extras)
        return directories
    }
}
