//
//  GameRow.swift
//  SteamShortcutConverter
//
//  A single game row: selection, artwork thumb, editable title, platform badge,
//  emulator picker, and artwork status.
//

import SwiftUI
import AppKit

struct GameRow: View {
    @ObservedObject var viewModel: MainViewModel
    let game: GameEntry

    @State private var titleText: String = ""

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { game.isSelected },
                set: { viewModel.setSelected($0, for: game) }
            ))
            .labelsHidden()

            thumbnail
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                TextField("Title", text: $titleText, onCommit: {
                    viewModel.setTitle(titleText, for: game)
                })
                .textFieldStyle(.plain)
                .font(.body)

                HStack(spacing: 6) {
                    Text(game.launchPath.path)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(game.launchPath.path)
                    if game.launchPath.pathExtension.lowercased() == "m3u" {
                        Label("multi-disc", systemImage: "opticaldisc")
                            .font(.caption2).foregroundColor(.secondary)
                            .labelStyle(.titleAndIcon)
                    } else if !game.additionalFiles.isEmpty {
                        Text("+\(game.additionalFiles.count) files")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
            }

            Spacer(minLength: 8)

            imageSwitcher

            platformBadge

            emulatorPicker
                .frame(width: 200)

            artworkStatus
                .frame(width: 20)
        }
        .padding(.vertical, 4)
        .onAppear { titleText = game.title }
        .onChange(of: game.title) { titleText = $0 }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var thumbnail: some View {
        if case .cached(let url) = game.artworkStatus, let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .cornerRadius(4)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.15))
                .overlay(Image(systemName: "gamecontroller").font(.caption).foregroundColor(.secondary))
        }
    }

    @ViewBuilder
    private var imageSwitcher: some View {
        if !game.alternateImages.isEmpty {
            let allImages = [game.romPath] + game.alternateImages
            Menu {
                ForEach(allImages, id: \.self) { image in
                    Button {
                        viewModel.setLaunchImage(image, for: game)
                    } label: {
                        if image == game.launchPath {
                            Label(image.pathExtension.uppercased(), systemImage: "checkmark")
                        } else {
                            Text(image.pathExtension.uppercased())
                        }
                    }
                }
            } label: {
                Text(".\(game.launchPath.pathExtension.lowercased())")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Choose which disc image to launch")
        }
    }

    @ViewBuilder
    private var platformBadge: some View {
        if game.platform.id == "unknown" {
            // Ambiguous platform — let the user resolve it.
            Menu {
                ForEach(viewModel.allPlatforms) { platform in
                    Button(platform.displayName) { viewModel.setPlatform(platform, for: game) }
                }
            } label: {
                Label("Set platform", systemImage: "questionmark.circle")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Platform could not be determined — pick one")
        } else {
            Text(game.platform.displayName)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.15))
                .cornerRadius(4)
        }
    }

    @ViewBuilder
    private var emulatorPicker: some View {
        let options = viewModel.availableOptions(for: game)
        if options.isEmpty {
            Label("No emulator", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundColor(.orange)
        } else {
            Picker("", selection: Binding(
                get: { game.emulator },
                set: { if let choice = $0 { viewModel.setEmulatorChoice(choice, for: game) } }
            )) {
                ForEach(options, id: \.choice) { option in
                    Text(option.displayName).tag(Optional(option.choice))
                }
            }
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var artworkStatus: some View {
        switch game.artworkStatus {
        case .none:
            Image(systemName: "minus").foregroundColor(.secondary)
        case .downloading:
            ProgressView().controlSize(.small)
        case .cached:
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .failed:
            Button {
                Task { await viewModel.fetchArtwork(for: game) }
            } label: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            }
            .buttonStyle(.plain)
            .help("Artwork fetch failed — click to retry")
        }
    }
}
