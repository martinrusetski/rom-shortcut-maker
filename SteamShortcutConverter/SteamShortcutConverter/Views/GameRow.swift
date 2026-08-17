//
//  GameRow.swift
//  SteamShortcutConverter
//
//  The main-list building blocks: a value-typed game row (checkbox · thumbnail ·
//  title · details · status), the collapsible section header, and an async
//  thumbnail loader. These views deliberately do NOT observe the ViewModel —
//  they render from the `GameEntry` value plus small callbacks, so a change to
//  one game never re-renders every row.
//

import SwiftUI
import AppKit
import ImageIO

// MARK: - Thumbnail loading

/// Off-main-thread thumbnail decoder with an in-memory cache. Decodes at the
/// requested pixel size via `CGImageSource` so a 1024px cover never costs a full
/// bitmap for a 28px row. The cache key includes the target size and the file's
/// modification time so a re-fetched artwork file (same path, new bytes)
/// invalidates automatically.
final class ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private let cache = NSCache<NSString, NSImage>()

    /// Decode a downsampled thumbnail. Safe to call off the main thread.
    func thumbnail(for url: URL, maxPixel: Int) -> NSImage? {
        let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        let key = "\(url.path)|\(maxPixel)|\(mtime)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: key)
        return image
    }
}

/// A square thumbnail that loads its image off the main thread and falls back to
/// a placeholder while loading or when there is no artwork.
struct ThumbnailView: View {
    let url: URL?
    let size: CGFloat

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.12))
                    .overlay(
                        Image(systemName: "gamecontroller")
                            .font(.system(size: size * 0.42))
                            .foregroundColor(.secondary)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { image = nil; return }
        let maxPixel = Int(size * 2)   // @2x for Retina
        let loaded = await Task.detached(priority: .utility) {
            ThumbnailLoader.shared.thumbnail(for: url, maxPixel: maxPixel)
        }.value
        image = loaded
    }
}

// MARK: - Table cells

struct GameTitleCell: View {
    let game: GameEntry
    let action: MainViewModel.GenerationAction

    var body: some View {
        HStack(spacing: 8) {
            ThumbnailView(url: artworkURL, size: 28)
                .accessibilityHidden(true)
            Text(game.title)
                .lineLimit(1)
                .truncationMode(.middle)
            GameStatusIcon(game: game, action: action)
        }
        .opacity(game.isSelected ? 1 : 0.55)
    }

    private var artworkURL: URL? {
        if case .cached(let url) = game.artworkStatus { return url }
        return nil
    }

}

private struct GameStatusIcon: View {
    let game: GameEntry
    let action: MainViewModel.GenerationAction

    var body: some View {
        Image(systemName: symbolName)
            .foregroundColor(color)
            .font(.caption)
            .help(statusDescription)
            .accessibilityLabel(statusDescription)
    }

    private var symbolName: String {
        if case .downloading = game.artworkStatus { return "arrow.down.circle" }
        switch action {
        case .create: return "plus.circle.fill"
        case .update: return "arrow.triangle.2.circlepath.circle.fill"
        case .upToDate: return "checkmark.circle"
        case .excluded: return "minus.circle"
        case .needsAttention:
            switch game.status {
            case .unknownPlatform: return "questionmark.circle.fill"
            case .needsLaunchTarget: return "cursorarrow.click.2"
            case .invalidSource, .noEmulator, .ready: return "exclamationmark.triangle.fill"
            }
        }
    }

    private var color: Color {
        if case .needsAttention = action { return .orange }
        switch action {
        case .create, .update: return .accentColor
        case .upToDate, .excluded, .needsAttention: return .secondary
        }
    }

    private var statusDescription: String {
        if case .downloading = game.artworkStatus { return "Downloading artwork" }
        switch action {
        case .create: return "New - will be created"
        case .update: return "Changed - will be updated"
        case .upToDate: return "Up to date"
        case .excluded: return "Excluded from generation"
        case .needsAttention:
            switch game.status {
            case .unknownPlatform: return "Needs attention - choose a platform"
            case .noEmulator: return "Needs attention - choose an emulator"
            case .needsLaunchTarget: return "Needs attention - choose what to launch"
            case .invalidSource: return "Needs attention - the game package is invalid"
            case .ready: return "Needs attention"
            }
        }
    }
}
