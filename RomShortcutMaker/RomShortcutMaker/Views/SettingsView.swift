//
//  SettingsView.swift
//  RomShortcutMaker
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
    @State private var selectedFolders: Set<String> = []

    var body: some View {
        Form {
            Section("Watched Folders") {
                List(selection: $selectedFolders) {
                    ForEach(viewModel.watchedFolders, id: \.self) { path in
                        WatchedFolderRow(path: path)
                            .tag(path)
                            .contextMenu {
                                Button("Remove", role: .destructive) {
                                    Task { await viewModel.removeWatchedFolders(Set([path])) }
                                }
                            }
                    }
                }
                .frame(height: 132)
                .overlay {
                    if viewModel.watchedFolders.isEmpty {
                        ContentUnavailableView {
                            Label("No Watched Folders", systemImage: "folder")
                        } description: {
                            Text("Add one or more folders containing ROMs.")
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        guard let url = FilePicker.chooseDirectory(title: "Add Watched Folder") else { return }
                        Task { await viewModel.addWatchedFolder(url) }
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 16, height: 16)
                    }
                    .help("Add watched folder")
                    .disabled(viewModel.isProcessing)

                    Button {
                        let paths = selectedFolders
                        selectedFolders = []
                        Task { await viewModel.removeWatchedFolders(paths) }
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 16, height: 16)
                    }
                    .help("Remove selected folders")
                    .disabled(selectedFolders.isEmpty || viewModel.isProcessing)

                    Spacer()

                    Text("\(viewModel.watchedFolders.count) watched")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Folders are scanned together into one library. Dragging a folder onto the main window adds it here.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Steam Import") {
                LabeledContent {
                    Button {
                        guard let url = FilePicker.chooseFile(
                            title: "Select Steam shortcuts.vdf",
                            extensions: ["vdf"]
                        ) else { return }
                        Task { await viewModel.importFromVDF(url: url) }
                    } label: {
                        Label("Import shortcuts.vdf…", systemImage: "square.and.arrow.down")
                    }
                    .disabled(viewModel.isProcessing)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Existing shortcuts")
                        Text("Load an existing Steam ROM library for review.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Toggle("Remove orphaned bundles", isOn: $viewModel.removeOrphanedBundles)
                    .onChange(of: viewModel.removeOrphanedBundles) { _ in viewModel.saveSettings() }
                Text("Delete generated app bundles for games no longer in your library.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("Locations") {
                LabeledContent("Output folder") {
                    Text(viewModel.outputDirectory.isEmpty ? "—" : viewModel.outputDirectory)
                        .foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Section("Detection") {
                LabeledContent("Hash database") {
                    Text(viewModel.hashDatabasePath.isEmpty ? "Not configured" : viewModel.hashDatabasePath)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack {
                    Button("Choose JSON…") {
                        if let url = FilePicker.chooseFile(title: "Choose Hash Database", extensions: ["json"]) {
                            viewModel.setHashDatabase(url: url)
                        }
                    }
                    Button("Clear") { viewModel.setHashDatabase(url: nil) }
                        .disabled(viewModel.hashDatabasePath.isEmpty)
                }
                Text("Optional exact SHA-1 matches. Unknown files are hashed only when this is configured.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct WatchedFolderRow: View {
    let path: String

    private var isAvailable: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isAvailable ? Color.accentColor : Color.secondary)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(isAvailable ? 0.10 : 0.04), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .lineLimit(1)
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if !isAvailable {
                Label("Unavailable", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
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
                        let selectedChoice = viewModel.defaultChoiceSetting(for: platform)
                            ?? options[0].choice
                        FullWidthPopupPicker(
                            options: options.map(\.choice),
                            selection: Binding(
                                get: { selectedChoice },
                                set: { viewModel.setDefaultChoice($0, for: platform) }
                            ),
                            title: { choice in
                                options.first { $0.choice == choice }?.displayName ?? "Choose…"
                            },
                            accessibilityLabel: "Default emulator for \(platform.displayName)"
                        )
                        .frame(width: 240, height: 24)
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
