//
//  SettingsView.swift
//  SteamShortcutConverter
//
//  App-level configuration, presented as a standard macOS Settings window (⌘,)
//  with three panes. Persistence happens on change — no Save button.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        TabView {
            GeneralPane(viewModel: viewModel)
                .tabItem { Label("General", systemImage: "gearshape") }
            EmulatorsPane(viewModel: viewModel)
                .tabItem { Label("Emulators", systemImage: "gamecontroller") }
            ArtworkPane(viewModel: viewModel)
                .tabItem { Label("Artwork", systemImage: "photo") }
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Remove orphaned bundles", isOn: $viewModel.removeOrphanedBundles)
                    .onChange(of: viewModel.removeOrphanedBundles) { _ in viewModel.saveSettings() }
                Text("Delete generated app bundles for games no longer in your library.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("Locations") {
                LabeledContent("Last ROM folder") {
                    Text(viewModel.scanDirectory.isEmpty ? "—" : viewModel.scanDirectory)
                        .foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                }
                LabeledContent("Output folder") {
                    Text(viewModel.outputDirectory.isEmpty ? "—" : viewModel.outputDirectory)
                        .foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Emulators

private struct EmulatorsPane: View {
    @ObservedObject var viewModel: MainViewModel

    @State private var search: String = ""
    @State private var showAll: Bool = false

    private var platforms: [Platform] {
        viewModel.allPlatforms.filter { platform in
            let matchesSearch = search.isEmpty ||
                platform.displayName.localizedCaseInsensitiveContains(search)
            let hasOption = !viewModel.availableOptions(for: platform).isEmpty
            return matchesSearch && (showAll || hasOption)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search platforms", text: $search)
                    .textFieldStyle(.roundedBorder)
                Toggle("Show all", isOn: $showAll)
            }
            Text("Default emulator per platform. Only installed platforms are shown unless \"Show all\" is on.")
                .font(.caption).foregroundColor(.secondary)

            List(platforms) { platform in
                let options = viewModel.availableOptions(for: platform)
                HStack {
                    Text(platform.displayName)
                    Spacer()
                    if options.isEmpty {
                        Text("Not installed").foregroundColor(.secondary).font(.caption)
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
                }
            }
        }
        .padding()
    }
}

// MARK: - Artwork

private struct ArtworkPane: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        Form {
            Section("SteamGridDB") {
                SecureField("API Key", text: $viewModel.steamGridDBApiKey)
                    .onChange(of: viewModel.steamGridDBApiKey) { _ in viewModel.saveSettings() }
                Link("Get API Key",
                     destination: URL(string: "https://www.steamgriddb.com/profile/preferences/api")!)
                    .font(.caption)
            }
            Section("Cache") {
                LabeledContent("Size") {
                    Text(ByteCountFormatter.string(fromByteCount: viewModel.artworkCacheSize(), countStyle: .file))
                        .foregroundColor(.secondary)
                }
                Button("Clear Cache") { viewModel.clearArtworkCache() }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
