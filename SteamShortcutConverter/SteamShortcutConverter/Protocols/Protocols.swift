//
//  Protocols.swift
//  SteamShortcutConverter
//
//  Protocol definitions for core components
//

import Foundation

// MARK: - VDF Parser Protocol

/// Protocol for parsing Steam's binary VDF (Valve Data Format) files
protocol VDFParser {
    /// Parse a shortcuts.vdf file and extract all shortcuts
    /// - Parameter fileURL: URL to the shortcuts.vdf file
    /// - Returns: Array of parsed SteamShortcut objects
    /// - Throws: Error if file cannot be read or parsed
    func parseShortcuts(from fileURL: URL) async throws -> [SteamShortcut]
    
    /// Validate that a file is a valid VDF format
    /// - Parameter fileURL: URL to the file to validate
    /// - Returns: True if the file is valid VDF format
    func validateVDFFile(at fileURL: URL) async throws -> Bool
}

// MARK: - Shortcut Filter Protocol

/// Protocol for filtering ROM-related shortcuts from all Steam shortcuts
protocol ShortcutFilter {
    /// Filter shortcuts to only include ROM-related entries
    /// - Parameter shortcuts: Array of all Steam shortcuts
    /// - Returns: Array of ROM-related shortcuts
    func filterROMShortcuts(from shortcuts: [SteamShortcut]) -> [SteamShortcut]
    
    /// Detect if a shortcut is for an emulator
    /// - Parameter shortcut: The shortcut to check
    /// - Returns: The detected emulator type, or nil if not an emulator
    func detectEmulator(for shortcut: SteamShortcut) -> EmulatorType?
}

/// Supported emulator types
enum EmulatorType: String, CaseIterable {
    // Multi-system
    case retroArch = "RetroArch"
    case openemu = "OpenEmu"
    case ares = "ares"
    case bizhawk = "BizHawk"
    case mednafen = "Mednafen"
    
    // PlayStation
    case duckstation = "DuckStation"
    case pcsx2 = "PCSX2"
    case ppsspp = "PPSSPP"
    case rpcs3 = "RPCS3"
    case epsxe = "ePSXe"
    case pcsxr = "PCSX-R"
    case pcsxredux = "PCSX-Redux"
    case play = "Play!"
    case shadps4 = "shadPS4"
    case aethersx2 = "AetherSX2"
    
    // Nintendo
    case dolphin = "Dolphin"
    case citra = "Citra"
    case cemu = "Cemu"
    case yuzu = "Yuzu"
    case ryujinx = "Ryujinx"
    case astris = "Astris"
    case mgba = "mGBA"
    case desmume = "DeSmuME"
    case melonds = "melonDS"
    case snes9x = "Snes9x"
    case bsnes = "bsnes"
    case higan = "higan"
    case mesen = "Mesen"
    case project64 = "Project64"
    case mupen64plus = "Mupen64Plus"
    case visualboyadvance = "VisualBoyAdvance"
    case azahar = "Azahar"
    case lime3ds = "Lime3DS"
    case panda3ds = "Panda3DS"
    case skyemu = "SkyEmu"
    case sameboy = "SameBoy"
    case gearboy = "Gearboy"
    case nanoboyadvance = "NanoBoyAdvance"
    
    // Sega
    case fusion = "Fusion"
    case redream = "Redream"
    case flycast = "Flycast"
    case demul = "Demul"
    case gearsystem = "Gearsystem"
    case geargrafx = "Geargrafx"
    case gearcoleco = "Gearcoleco"
    case ymir = "Ymir"
    
    // Arcade
    case mame = "MAME"
    case finalburn = "FinalBurn"
    case supermodel = "Supermodel"
    
    // Other consoles
    case xemu = "xemu"
    case xenia = "Xenia"
    case xenios = "XeniOS"
    case vita3k = "Vita3K"
    case dreampotato = "DreamPotato"
    
    // Classic computers
    case dosbox = "DOSBox"
    case scummvm = "ScummVM"
    case basiliskii = "Basilisk II"
    case sheepshaver = "SheepShaver"
    case minivmac = "Mini vMac"
    case vice = "VICE"
    case fs_uae = "FS-UAE"
    case winuae = "WinUAE"
    case hatari = "Hatari"
    case previous = "Previous"
    case neko = "Neko Project II"
    case np2kai = "NP2kai"
    case x68000 = "XM6"
    case qemu = "QEMU"
    case pcem = "PCem"
    case box86 = "Box86"
    case box64 = "Box64"
    case clk = "CLK"
    case eightybox = "86Box"
    case virtualc64 = "VirtualC64"
    case vamiga = "vAmiga"
    case denise = "Denise"
    case stella = "Stella"
    case lisaem = "LisaEm"
    case utm = "UTM"
    case boxer = "Boxer"
    case openemulator = "OpenEmulator"
    case kegs = "KEGS"
    case sl9821 = "SL9821"
    case tsugaru = "Tsugaru"
    case spectral = "Spectral"
    case fuse = "FUSE"
    case retrovm = "RetroVM"
    case trs80gp = "TRS80GP"
    case xroar = "XRoar"
    case b2 = "b2"
    case rpcemu = "RPCEmu"
    case veesem = "veesem"
    case x16 = "X16 Emulator"
    
    /// Common executable name patterns for this emulator
    var executablePatterns: [String] {
        switch self {
        // Multi-system
        case .retroArch:
            return ["retroarch"]
        case .openemu:
            return ["openemu"]
        case .ares:
            return ["ares"]
        case .bizhawk:
            return ["bizhawk", "emuhawk"]
        case .mednafen:
            return ["mednafen"]
            
        // PlayStation
        case .duckstation:
            return ["duckstation"]
        case .pcsx2:
            return ["pcsx2"]
        case .ppsspp:
            // "PPSSPPSDL" is the macOS SDL build's bundle/executable name; the
            // word-boundary matcher won't find "ppsspp" inside it (no boundary
            // before "sdl"), so match the full name explicitly.
            return ["ppsspp", "ppssppsdl"]
        case .rpcs3:
            return ["rpcs3"]
        case .epsxe:
            return ["epsxe"]
        case .pcsxr:
            return ["pcsxr", "pcsx-r"]
        case .pcsxredux:
            return ["pcsxredux", "pcsx-redux"]
        case .play:
            return ["play!"]
        case .shadps4:
            return ["shadps4"]
        case .aethersx2:
            return ["aethersx2"]
            
        // Nintendo
        case .dolphin:
            return ["dolphin", "dolphin-emu"]
        case .citra:
            return ["citra"]
        case .cemu:
            return ["cemu"]
        case .yuzu:
            return ["yuzu"]
        case .ryujinx:
            return ["ryujinx"]
        case .astris:
            return ["astris"]
        case .mgba:
            return ["mgba"]
        case .desmume:
            return ["desmume"]
        case .melonds:
            return ["melonds"]
        case .snes9x:
            return ["snes9x"]
        case .bsnes:
            return ["bsnes"]
        case .higan:
            return ["higan"]
        case .mesen:
            return ["mesen"]
        case .project64:
            return ["project64", "pj64"]
        case .mupen64plus:
            return ["mupen64plus", "mupen64"]
        case .visualboyadvance:
            return ["visualboyadvance", "vba", "vbam"]
        case .azahar:
            return ["azahar"]
        case .lime3ds:
            return ["lime3ds", "lime"]
        case .panda3ds:
            return ["panda3ds"]
        case .skyemu:
            return ["skyemu"]
        case .sameboy:
            return ["sameboy"]
        case .gearboy:
            return ["gearboy"]
        case .nanoboyadvance:
            return ["nanoboyadvance"]
            
        // Sega
        case .fusion:
            return ["fusion", "kega"]
        case .redream:
            return ["redream"]
        case .flycast:
            return ["flycast"]
        case .demul:
            return ["demul"]
        case .gearsystem:
            return ["gearsystem"]
        case .geargrafx:
            return ["geargrafx"]
        case .gearcoleco:
            return ["gearcoleco"]
        case .ymir:
            return ["ymir"]
            
        // Arcade
        case .mame:
            return ["mame"]
        case .finalburn:
            return ["finalburn", "fbneo", "fba"]
        case .supermodel:
            return ["supermodel"]
            
        // Other consoles
        case .xemu:
            return ["xemu"]
        case .xenia:
            return ["xenia"]
        case .xenios:
            return ["xenios"]
        case .vita3k:
            return ["vita3k"]
        case .dreampotato:
            return ["dreampotato"]
            
        // Classic computers
        case .dosbox:
            return ["dosbox"]
        case .scummvm:
            return ["scummvm"]
        case .basiliskii:
            return ["basiliskii", "basilisk"]
        case .sheepshaver:
            return ["sheepshaver"]
        case .minivmac:
            return ["minivmac", "mini vmac"]
        case .vice:
            return ["vice", "x64", "x128", "xvic", "xpet", "xplus4", "xcbm"]
        case .fs_uae:
            return ["fs-uae", "fsuae"]
        case .winuae:
            return ["winuae"]
        case .hatari:
            return ["hatari"]
        case .previous:
            return ["previous"]
        case .neko:
            return ["np2", "neko project"]
        case .np2kai:
            return ["np2kai"]
        case .x68000:
            return ["xm6", "x68000"]
        case .qemu:
            return ["qemu"]
        case .pcem:
            return ["pcem"]
        case .box86:
            return ["box86"]
        case .box64:
            return ["box64"]
        case .clk:
            return ["clk"]
        case .eightybox:
            return ["86box"]
        case .virtualc64:
            return ["virtualc64"]
        case .vamiga:
            return ["vamiga"]
        case .denise:
            return ["denise"]
        case .stella:
            return ["stella"]
        case .lisaem:
            return ["lisaem"]
        case .utm:
            return ["utm"]
        case .boxer:
            return ["boxer"]
        case .openemulator:
            return ["openemulator"]
        case .kegs:
            return ["kegs"]
        case .sl9821:
            return ["sl9821"]
        case .tsugaru:
            return ["tsugaru"]
        case .spectral:
            return ["spectral"]
        case .fuse:
            return ["fuse"]
        case .retrovm:
            return ["retrovm", "retro virtual machine"]
        case .trs80gp:
            return ["trs80gp", "trs-80"]
        case .xroar:
            return ["xroar"]
        case .b2:
            return ["b2", "b-em"]
        case .rpcemu:
            return ["rpcemu"]
        case .veesem:
            return ["veesem"]
        case .x16:
            return ["x16", "commander x16"]
        }
    }
}

// MARK: - App Bundle Generator Protocol

/// Protocol for generating native macOS app bundles
protocol AppBundleGenerator {
    /// Generate a macOS app bundle from configuration
    /// - Parameter config: Configuration for the app bundle
    /// - Returns: URL to the generated app bundle
    /// - Throws: Error if bundle generation fails
    func generateAppBundle(with config: AppBundleConfig) async throws -> URL
    
    /// Convert icon data to .icns format
    /// - Parameters:
    ///   - iconData: The icon data to convert
    ///   - outputURL: URL where the .icns file should be saved
    /// - Throws: Error if conversion fails
    func convertIcon(_ iconData: IconData, to outputURL: URL) async throws
}

// MARK: - Configuration Manager Protocol

/// Protocol for managing application configuration persistence
protocol ConfigurationManager {
    /// Load the application configuration
    /// - Returns: The loaded configuration, or default if none exists
    func loadConfiguration() async throws -> AppConfiguration
    
    /// Save the application configuration
    /// - Parameter configuration: The configuration to save
    /// - Throws: Error if save fails
    func saveConfiguration(_ configuration: AppConfiguration) async throws
    
    /// Load the conversion state
    /// - Returns: The last conversion state, or nil if none exists
    func loadConversionState() async throws -> ConversionState?
    
    /// Save the conversion state
    /// - Parameter state: The conversion state to save
    /// - Throws: Error if save fails
    func saveConversionState(_ state: ConversionState) async throws
    
    /// Validate that a configuration is valid
    /// - Parameter configuration: The configuration to validate
    /// - Returns: True if the configuration is valid
    func validateConfiguration(_ configuration: AppConfiguration) async -> Bool
}
