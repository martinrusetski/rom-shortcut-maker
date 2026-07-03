//
//  ArtworkProvider.swift
//  SteamShortcutConverter
//
//  Protocol + value types for artwork providers (SteamGridDB today, room for
//  more later).
//

import Foundation

// MARK: - Provider models

struct SGDBGame: Equatable, Codable {
    let id: Int
    let name: String
}

struct SGDBImage: Equatable, Codable {
    let id: Int
    let url: URL
    let thumb: URL?
    let score: Int?
    let mime: String?

    /// Whether this image is a PNG (by mime or url extension).
    var isPNG: Bool {
        if let mime, mime.lowercased() == "image/png" { return true }
        return url.pathExtension.lowercased() == "png"
    }
}

enum ArtworkSourceType: String, Codable, Equatable {
    case icon
    case grid
}

/// A downloaded piece of artwork plus provenance for the cache metadata.
struct FetchedArtwork: Equatable {
    let data: Data
    let sgdbGameId: Int
    let sgdbImageId: Int
    let sourceType: ArtworkSourceType
}

// MARK: - ArtworkProvider

protocol ArtworkProvider {
    func searchGame(term: String) async throws -> [SGDBGame]
    func getIcons(gameId: Int) async throws -> [SGDBImage]
    func getGrids(gameId: Int) async throws -> [SGDBImage]
    func downloadImage(url: URL) async throws -> Data
}

extension ArtworkProvider {
    /// Artwork selection strategy: search by title → best PNG icon → fall back
    /// to a grid (SGDB icon coverage is thin for retro titles) → download.
    /// Returns nil if nothing usable was found.
    func fetchArtwork(forTitle title: String) async throws -> FetchedArtwork? {
        let games = try await searchGame(term: title)
        guard let game = games.first else { return nil }

        let icons = try await getIcons(gameId: game.id)
        let pngIcons = icons.filter { $0.isPNG }.sorted { ($0.score ?? 0) > ($1.score ?? 0) }
        if let icon = pngIcons.first {
            let data = try await downloadImage(url: icon.url)
            return FetchedArtwork(data: data, sgdbGameId: game.id, sgdbImageId: icon.id, sourceType: .icon)
        }

        let grids = try await getGrids(gameId: game.id)
        if let grid = grids.sorted(by: { ($0.score ?? 0) > ($1.score ?? 0) }).first {
            let data = try await downloadImage(url: grid.url)
            return FetchedArtwork(data: data, sgdbGameId: game.id, sgdbImageId: grid.id, sourceType: .grid)
        }

        return nil
    }
}
