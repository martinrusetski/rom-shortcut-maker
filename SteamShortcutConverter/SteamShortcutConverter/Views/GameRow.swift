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

// MARK: - Section header

/// Collapsible platform section header: chevron + name + count. The "unknown"
/// bucket is always expanded and gets no chevron (it's a call to action, not a
/// normal group).
struct PlatformSectionHeader: View {
    let platform: Platform
    let count: Int
    let isCollapsed: Bool
    let isUnknown: Bool
    let toggle: () -> Void

    var body: some View {
        if isUnknown {
            Label("\(platform.displayName) (\(count))", systemImage: "questionmark.folder")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.orange)
                .textCase(nil)
        } else {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    Text("\(platform.displayName)  ")
                        .font(.subheadline.weight(.semibold))
                    + Text("(\(count))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .textCase(nil)
        }
    }
}

// MARK: - Game row

/// One game in the main list. Fixed contents, no inline editors — all per-game
/// editing happens in the Game Properties window.
struct GameListRow: View {
    let game: GameEntry
    let onToggleInclude: (Bool) -> Void
    let onInfo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { game.isSelected },
                set: { onToggleInclude($0) }
            ))
            .labelsHidden()
            .help("Include in generation")
            .accessibilityLabel("Include \(game.title) in generation")

            ThumbnailView(url: artworkURL, size: 28)
                .accessibilityHidden(true)

            Text(game.title)
                .lineLimit(1)
                .truncationMode(.middle)

            details

            Spacer(minLength: 8)

            statusView

            Button(action: onInfo) {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
            .help("Game Properties")
            .accessibilityLabel("Game Properties for \(game.title)")
        }
        .padding(.vertical, 3)
    }

    private var artworkURL: URL? {
        if case .cached(let url) = game.artworkStatus { return url }
        return nil
    }

    private var discCount: Int? {
        guard game.launchPath.pathExtension.lowercased() == "m3u" else { return nil }
        return game.additionalFiles.isEmpty ? nil : game.additionalFiles.count
    }

    @ViewBuilder
    private var details: some View {
        HStack(spacing: 6) {
            if let discs = discCount {
                Text("\(discs) discs")
            } else if !game.additionalFiles.isEmpty {
                Text("+\(game.additionalFiles.count) files")
            }
            if let emulator = game.emulator?.shortDisplayName {
                Text(emulator)
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .lineLimit(1)
    }

    @ViewBuilder
    private var statusView: some View {
        if case .downloading = game.artworkStatus {
            ProgressView().controlSize(.small)
        } else {
            switch game.status {
            case .ready:
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary.opacity(0.7))
                    .help("Ready to generate")
                    .accessibilityLabel("Ready to generate")
            case .noEmulator:
                Label("No emulator", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .labelStyle(.titleAndIcon)
            case .unknownPlatform:
                Label("Unknown platform", systemImage: "questionmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .labelStyle(.titleAndIcon)
            }
        }
    }
}
