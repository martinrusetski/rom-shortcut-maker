#!/usr/bin/env swift

import Foundation

// Test the extractExecutableName logic with real-world VDF data

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

// Test cases from user's VDF file
let testCases = [
    "\"/Applications/RetroArch.app\" -L \"/Users/martinr/Library/Application Support/RetroArch/cores/mgba_libretro.dylib\" \"/Users/martinr/ROMs/Game Boy Advance/Pokemon - Emerald Version (USA, Europe).gba\"",
    "\"/Applications/PCSX2.app/Contents/MacOS/PCSX2\" \"/Users/martinr/ROMs/PS2/game.iso\"",
    "\"/Applications/Cemu.app/Contents/MacOS/Cemu\" \"/Users/martinr/ROMs/WiiU/game.rpx\""
]

print("Testing extractExecutableName:")
print(String(repeating: "=", count: 60))

for testCase in testCases {
    let lowercased = testCase.lowercased()
    let result = extractExecutableName(from: lowercased)
    print("\nInput: \(testCase.prefix(80))...")
    print("Lowercased: \(lowercased.prefix(80))...")
    print("Result: \(result)")
    
    // Check if it matches known emulators
    let emulators = ["retroarch", "pcsx2", "cemu", "dolphin", "ppsspp"]
    let matched = emulators.filter { result.contains($0) }
    print("Matches: \(matched.isEmpty ? "NONE" : matched.joined(separator: ", "))")
}
