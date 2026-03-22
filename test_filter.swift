#!/usr/bin/env swift

// Quick test of the filter logic

let testPaths = [
    "\"/Applications/RetroArch.app\" -L \"/Users/martinr/Library/Application Support/RetroArch/cores/mednafen_psx_libretro.dylib\" \"/Users/martinr/Documents/ROMs/PS1/Vagrant.Story.English.chd\"",
    "\"/Applications/PCSX2.app\" \"/Users/martinr/Documents/ROMs/PS2/ICO (USA) (DVD).chd\" -batch -fullscreen -nogui",
    "\"/Applications/Cemu.app\" -f -g \"/Users/martinr/Documents/ROMs/WiiU/The Wind Waker HD (US).wua\""
]

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

print("Testing executable name extraction:")
for path in testPaths {
    let execName = extractExecutableName(from: path.lowercased())
    print("Path: \(path)")
    print("  -> Extracted: \(execName)")
    print()
}
