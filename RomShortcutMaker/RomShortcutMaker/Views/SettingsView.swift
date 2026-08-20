//
//  SettingsView.swift
//  RomShortcutMaker
//
//  App-level configuration, presented as a standard macOS Settings window (⌘,)
//  with three panes. Persistence happens on change — no Save button.
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        TabView(selection: $viewModel.settingsPane) {
            GeneralPane(viewModel: viewModel)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(MainViewModel.SettingsPane.general)
            EmulatorsPane(viewModel: viewModel)
                .tabItem { Label("Emulators", systemImage: "gamecontroller") }
                .tag(MainViewModel.SettingsPane.emulators)
            ArtworkPane(viewModel: viewModel)
                .tabItem { Label("Artwork", systemImage: "photo") }
                .tag(MainViewModel.SettingsPane.artwork)
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
        let candidates: [Platform]
        if let requestedID = viewModel.emulatorSettingsPlatformID,
           let requested = viewModel.allPlatforms.first(where: { $0.id == requestedID }) {
            candidates = [requested]
        } else if !viewModel.libraryPlatforms.isEmpty, !showAll {
            candidates = viewModel.libraryPlatforms
        } else if showAll {
            candidates = viewModel.allPlatforms
        } else {
            candidates = viewModel.allPlatforms.filter {
                !viewModel.availableOptions(for: $0).isEmpty
            }
        }
        return candidates.filter { platform in
            let matchesSearch = search.isEmpty ||
                platform.displayName.localizedCaseInsensitiveContains(search)
            return matchesSearch
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search platforms", text: $search)
                    .textFieldStyle(.roundedBorder)
                if viewModel.emulatorSettingsPlatformID == nil {
                    Toggle("All Platforms", isOn: $showAll)
                } else {
                    Button("Show Library Platforms") {
                        viewModel.emulatorSettingsPlatformID = nil
                    }
                }
            }
            Text("Installed and supported emulators for your game library. Locate an app manually if it was not detected.")
                .font(.caption).foregroundColor(.secondary)

            List(platforms) { platform in
                Section(platform.displayName) {
                    let supported = viewModel.supportedOptions(for: platform)
                    let available = viewModel.availableOptions(for: platform)

                    if supported.isEmpty && available.isEmpty {
                        Text("No standalone emulator is configured for this platform. Install RetroArch and a compatible core, then check again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(supported, id: \.choice) { option in
                            EmulatorSetupRow(
                                viewModel: viewModel,
                                platform: platform,
                                option: option,
                                isAvailable: available.contains(where: { $0.choice == option.choice }),
                                isDefault: effectiveDefault(for: platform, available: available) == option.choice
                            )
                        }
                        ForEach(available.filter { installed in
                            !supported.contains(where: { $0.choice == installed.choice })
                        }, id: \.choice) { option in
                            EmulatorSetupRow(
                                viewModel: viewModel,
                                platform: platform,
                                option: option,
                                isAvailable: true,
                                isDefault: effectiveDefault(for: platform, available: available) == option.choice
                            )
                        }
                    }
                }
            }
        }
        .padding()
        .onAppear { viewModel.refreshEmulators() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshEmulators()
        }
    }

    private func effectiveDefault(for platform: Platform, available: [EmulatorOption]) -> EmulatorChoice? {
        viewModel.defaultChoiceSetting(for: platform) ?? available.first?.choice
    }
}

private struct EmulatorSetupRow: View {
    @ObservedObject var viewModel: MainViewModel
    let platform: Platform
    let option: EmulatorOption
    let isAvailable: Bool
    let isDefault: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(option.displayName)
                Text(isAvailable ? "Installed" : "Not found")
                    .font(.caption)
                    .foregroundStyle(isAvailable ? Color.secondary : Color.orange)
            }

            Spacer()

            if isAvailable {
                if isDefault {
                    Label("Default", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Button("Use as Default") {
                        viewModel.setDefaultChoice(option.choice, for: platform)
                    }
                    .controlSize(.small)
                }
            } else if case .standalone(let type) = option.choice {
                Button("Locate App…") {
                    if let url = FilePicker.chooseFile(
                        title: "Locate \(option.displayName)",
                        extensions: ["app"]
                    ) {
                        viewModel.locateEmulator(type, at: url)
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
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
