//
//  SettingsView.swift
//  SteamShortcutConverter
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings").font(.title2).fontWeight(.semibold)

                artworkSection
                Divider()
                defaultsSection
                Divider()
                cacheSection
            }
            .padding()
        }
    }

    private var artworkSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SteamGridDB").font(.headline)
            HStack {
                SecureField("API Key", text: $viewModel.steamGridDBApiKey)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewModel.saveSettings() }
                Button("Save") { viewModel.saveSettings() }
                Link("Get API Key", destination: URL(string: "https://www.steamgriddb.com/profile/preferences/api")!)
            }
        }
    }

    private var defaultsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Default Emulator per Platform").font(.headline)
            ForEach(viewModel.allPlatforms) { platform in
                let options = viewModel.availableOptions(for: platform)
                HStack {
                    Text(platform.displayName).frame(width: 120, alignment: .leading)
                    if options.isEmpty {
                        Text("No emulator installed").foregroundColor(.secondary).font(.caption)
                    } else {
                        Picker("", selection: Binding(
                            get: { viewModel.defaultChoiceSetting(for: platform) ?? options.first?.choice },
                            set: { if let choice = $0 { viewModel.setDefaultChoice(choice, for: platform) } }
                        )) {
                            ForEach(options, id: \.choice) { option in
                                Text(option.displayName).tag(Optional(option.choice))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 240)
                    }
                    Spacer()
                }
            }
        }
    }

    private var cacheSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Artwork Cache").font(.headline)
            HStack {
                Text(byteString(viewModel.artworkCacheSize())).foregroundColor(.secondary)
                Spacer()
                Button("Clear Cache") { viewModel.clearArtworkCache() }
            }
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
