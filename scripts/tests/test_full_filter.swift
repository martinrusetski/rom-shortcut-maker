#!/usr/bin/env swift

import Foundation

// Copy of the filter logic to test

enum EmulatorType: String, CaseIterable {
    case retroArch = "RetroArch"
    case dolphin = "Dolphin"
    case pcsx2 = "PCSX2"
    case ppsspp = "PPSSPP"
    case citra = "Citra"
    case ryujinx = "Ryujinx"
    case mgba = "mGBA"
    case desmume = "DeSmuME"
    case openemu = "OpenEmu"
    case yuzu = "Yuzu"
    case cemu = "Cemu"
    
    var executablePatterns: [String] {
        switch self {
        case .retroArch:
            return ["retroarch"]
        case .dolphin:
            return ["dolphin", "dolphin-emu"]
        case .pcsx2:
            return ["pcsx2"]
        case .ppsspp:
            return ["ppsspp"]
        case .citra:
            return ["citra"]
        case .ryujinx:
            return ["ryujinx"]
        case .mgba:
            return ["mgba"]
        case .desmume:
            return ["desmume"]
        case .openemu:
            return ["openemu"]
        case .yuzu:
            return ["yuzu"]
        case .cemu:
            return ["cemu"]
        }
    }
}

func extractExecutableName(from path: String) -> String {
    var processedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    
    // If the path starts with a quote, extract just the quoted part
    if processedPath.hasPrefix("\"") {
        // Find the closing quote
        if let endQuoteIndex = processedPath.dropFirst().firstIndex(of: "\"") {
            processedPath = String(processedPath[processedPath.index(after: processedPath.startIndex)..<endQuoteIndex])
        }
    } else {
        // No quotes - split on space to get just the executable path
        if let spaceIndex = processedPath.firstIndex(of: " ") {
            processedPath = String(processedPath[..<spaceIndex])
        }
    }
    
    // Remove .app extension if present
    if processedPath.hasSuffix(".app") {
        processedPath = String(processedPath.dropLast(4))
    }
    
    // Get the last path component
    let components = processedPath.split(separator: "/")
    guard let lastComponent = components.last else {
        return path
    }
    
    return String(lastComponent)
}

func detectEmulatorFromPath(_ path: String) -> EmulatorType? {
    // Normalize path for case-insensitive matching
    let lowercasedPath = path.lowercased()
    
    // Extract the executable name from the path
    let executableName = extractExecutableName(from: lowercasedPath)
    
    print("  lowercased: \(lowercasedPath.prefix(80))")
    print("  extracted: \(executableName)")
    
    // Check each emulator type for pattern matches
    for emulatorType in EmulatorType.allCases {
        for pattern in emulatorType.executablePatterns {
            print("    checking pattern '\(pattern)' against '\(executableName)'")
            if executableName.contains(pattern.lowercased()) {
                print("    MATCH!")
                return emulatorType
            }
        }
    }
    
    return nil
}

// Test with real VDF data
let testCases = [
    ("Vagrant Story", "\"/Applications/RetroArch.app\" -L \"/Users/martinr/Library/Application Support/RetroArch/cores/mednafen_psx_libretro.dylib\" \"/Users/martinr/Documents/ROMs/PS1/Vagrant.Story.English.chd\""),
    ("Zelda ALTTP", "\"/Applications/RetroArch.app\" -L \"/Users/martinr/Library/Application Support/RetroArch/cores/bsnes_mercury_balanced_libretro.dylib\" \"/Users/martinr/Documents/ROMs/SNES/Legend of Zelda, The - A Link to the Past (USA).zip\""),
    ("ICO", "\"/Applications/PCSX2.app\" \"/Users/martinr/Documents/ROMs/PS2/ICO (USA) (DVD).chd\" -batch -fullscreen -nogui"),
    ("Zelda Wind Waker HD", "\"/Applications/Cemu.app\" -f -g \"/Users/martinr/Documents/ROMs/WiiU/The Wind Waker HD (US).wua\""),
    ("Zelda BOTW", "\"/Applications/Cemu.app\" -f -g \"/Users/martinr/Documents/ROMs/WiiU/Breath of the Wild.wua\"")
]

print("Testing full filter logic:")
print(String(repeating: "=", count: 80))

for (name, exe) in testCases {
    print("\nGame: \(name)")
    print("exe: \(exe.prefix(80))...")
    let emulator = detectEmulatorFromPath(exe)
    print("Result: \(emulator?.rawValue ?? "NO MATCH")")
    print(String(repeating: "-", count: 80))
}
