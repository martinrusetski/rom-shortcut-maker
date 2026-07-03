//
//  ArtworkView.swift
//  SteamShortcutConverter
//

import SwiftUI

struct ArtworkView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Artwork").font(.title2).fontWeight(.semibold)

            if viewModel.steamGridDBApiKey.isEmpty {
                Label("Set a SteamGridDB API key in Settings to fetch artwork.",
                      systemImage: "key")
                    .foregroundColor(.orange)
            }

            HStack {
                Button("Fetch Missing") {
                    Task { await viewModel.fetchMissingArtwork() }
                }
                .disabled(viewModel.steamGridDBApiKey.isEmpty || viewModel.games.isEmpty)
                Spacer()
            }

            if viewModel.isProcessing {
                ProgressView(value: viewModel.progressValue)
            }

            Divider()

            if viewModel.games.isEmpty {
                Spacer()
                Text("Scan some games first.").foregroundColor(.secondary)
                Spacer()
            } else {
                List(viewModel.games) { game in
                    HStack {
                        Text(game.title)
                        Spacer()
                        Button("Fetch") { Task { await viewModel.fetchArtwork(for: game) } }
                            .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding()
    }
}
