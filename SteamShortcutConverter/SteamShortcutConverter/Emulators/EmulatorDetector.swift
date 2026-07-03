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

    init(
        database: SystemDatabase,
        fs: AppDiscovering = DefaultAppDiscovering(),
        appSearchDirectories: [URL]? = nil,
        binSearchDirectories: [URL]? = nil,
        extraCoreDirectories: [URL]? = nil
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

    /// The set of installed RetroArch core filenames (e.g. "snes9x_libretro.dylib").
    func installedRetroArchCores() -> Set<String> {
        var cores: Set<String> = []
        for directory in coreDirectories() {
            for dylib in fs.files(in: directory, withExtension: "dylib") {
                let name = dylib.lastPathComponent
                if name.hasSuffix("_libretro.dylib") {
                    cores.insert(name)
                }
            }
        }
        return cores
    }

    /// Candidate RetroArch cores directories: the `cores` folder of any detected
    /// RetroArch.app, plus the configured extra directories.
    private func coreDirectories() -> [URL] {
        var directories: [URL] = []
        for retroArchURL in detectAll()[.retroArch] ?? [] {
            if retroArchURL.pathExtension.lowercased() == "app" {
                directories.append(retroArchURL.appendingPathComponent("Contents/Resources/cores"))
            } else {
                directories.append(retroArchURL.deletingLastPathComponent().appendingPathComponent("cores"))
            }
        }
        directories.append(contentsOf: extraCoreDirectories)
        return directories
    }
}
