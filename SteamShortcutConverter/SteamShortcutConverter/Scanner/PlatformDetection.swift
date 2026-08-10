//
//  PlatformDetection.swift
//  SteamShortcutConverter
//
//  Runtime explanation of how a ROM platform was resolved. This is deliberately
//  separate from the persisted GameEntry so a rescan can refresh evidence without
//  changing the conversion-state schema.
//

import Foundation

struct PlatformDetectionInfo: Equatable {
    let fileExtension: String
    var candidates: [Platform]
    var evidence: [String]
    var resolvedBy: String?
    let sourceDirectory: URL

    var candidateNames: String {
        candidates.map(\.displayName).joined(separator: ", ")
    }

    var summary: String {
        if let resolvedBy {
            return "Resolved by \(resolvedBy)."
        }
        if candidates.isEmpty {
            return "No unique platform signature was found."
        }
        return "Ambiguous. Possible platforms: \(candidateNames)."
    }
}
