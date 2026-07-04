//
//  GamePropertiesView.swift
//  SteamShortcutConverter
//
//  The per-game "Get Info" surface: a resizable utility window (reused, one at a
//  time) hosting a grouped Form. All per-game editing lives here so the main
//  list stays clutter-free. Edits apply immediately (no OK/Cancel) — the main
//  list updates behind the window.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Reusable utility window

/// Owns the single Game Properties window. A plain AppKit `NSWindow` (rather
/// than a SwiftUI `Window` scene) so it only appears when opened — no empty
/// window restored at launch — and is reused across games.
@MainActor
final class PropertiesWindowController {
    static let shared = PropertiesWindowController()

    private var window: NSWindow?
    private var delegate: WindowDelegate?

    func show(viewModel: MainViewModel) {
        if window == nil {
            let hosting = NSHostingController(rootView: GamePropertiesView(viewModel: viewModel))
            let win = NSWindow(contentViewController: hosting)
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.setContentSize(NSSize(width: 460, height: 640))
            win.isReleasedWhenClosed = false
            win.center()
            let delegate = WindowDelegate { [weak viewModel] in
                viewModel?.propertiesGameID = nil
            }
            win.delegate = delegate
            self.delegate = delegate
            self.window = win
        }
        if let game = viewModel.propertiesGameID.flatMap({ viewModel.game(id: $0) }) {
            window?.title = game.title
        }
        window?.makeKeyAndOrderFront(nil)
    }

    private final class WindowDelegate: NSObject, NSWindowDelegate {
        let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }
        func windowWillClose(_ notification: Notification) { onClose() }
    }
}

// MARK: - Properties view

struct GamePropertiesView: View {
    @ObservedObject var viewModel: MainViewModel

    private var game: GameEntry? {
        viewModel.propertiesGameID.flatMap { viewModel.game(id: $0) }
    }

    var body: some View {
        if let game {
            content(for: game)
        } else {
            VStack {
                Image(systemName: "gamecontroller")
                    .font(.largeTitle).foregroundColor(.secondary)
                Text("No game selected").foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func content(for game: GameEntry) -> some View {
        VStack(spacing: 0) {
            PropertiesHeader(viewModel: viewModel, game: game)
                .padding()
            Divider()
            Form {
                ArtworkSection(viewModel: viewModel, game: game)
                PlatformEmulatorSection(viewModel: viewModel, game: game)
                LaunchSection(viewModel: viewModel, game: game)
                Section {
                    Button("Reset All Overrides") {
                        viewModel.resetOverrides(for: game)
                    }
                    .disabled(!viewModel.anyOverrides(game))
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 420, minHeight: 520)
    }
}

// MARK: - Override dot

/// A small filled dot shown next to a field that has a per-game override.
private struct OverrideDot: View {
    let isOn: Bool
    var body: some View {
        Circle()
            .fill(isOn ? Color.accentColor : Color.clear)
            .frame(width: 6, height: 6)
            .help(isOn ? "Overridden for this game" : "")
            .accessibilityHidden(!isOn)
            .accessibilityLabel("Overridden for this game")
    }
}

/// A small ↩︎ reset button, shown only when the field is overridden.
private struct ResetButton: View {
    let isOn: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.uturn.backward")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help("Reset to default")
        .accessibilityLabel("Reset to default")
        .disabled(!isOn)
        .opacity(isOn ? 1 : 0)
    }
}

// MARK: - Header

private struct PropertiesHeader: View {
    @ObservedObject var viewModel: MainViewModel
    let game: GameEntry

    @State private var titleText: String = ""

    var body: some View {
        HStack(spacing: 14) {
            ThumbnailView(url: artworkURL, size: 96)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    TextField("Title", text: $titleText)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                        .onSubmit { viewModel.setTitle(titleText, for: game) }
                    OverrideDot(isOn: viewModel.hasOverride(.title, for: game))
                    ResetButton(isOn: viewModel.hasOverride(.title, for: game)) {
                        viewModel.resetOverride(.title, for: game)
                    }
                }
                Text("\(game.platform.displayName) · \(game.romPath.lastPathComponent)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .task(id: game.id) { titleText = game.title }
        .onChange(of: game.title) { titleText = $0 }
    }

    private var artworkURL: URL? {
        if case .cached(let url) = game.artworkStatus { return url }
        return nil
    }
}

// MARK: - Artwork section

private struct ArtworkSection: View {
    @ObservedObject var viewModel: MainViewModel
    let game: GameEntry

    @State private var showingMatchSheet = false

    var body: some View {
        Section("Artwork") {
            HStack(spacing: 12) {
                ThumbnailView(url: artworkURL, size: 64)
                    .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
                        handleImageDrop(providers)
                    }
                    .help("Drop an image here to use as artwork")
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Button("Fetch from SteamGridDB") {
                            Task { await viewModel.fetchArtwork(for: game) }
                        }
                        .disabled(isDownloading)
                        if isDownloading { ProgressView().controlSize(.small) }
                    }
                    HStack {
                        Button("Choose File…") { chooseFile() }
                        Button("Remove") { viewModel.removeArtwork(for: game) }
                            .disabled(!viewModel.hasArtwork(game))
                    }
                    Button("Match Manually…") { showingMatchSheet = true }
                        .disabled(!viewModel.canFetchArtwork)
                        .help(viewModel.canFetchArtwork
                              ? "Search SteamGridDB and pick the correct game"
                              : "Set a SteamGridDB API key in Settings first")
                    if let matchedName = viewModel.matchedGameName(for: game) {
                        HStack(spacing: 4) {
                            Text("Matched: \(matchedName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button {
                                viewModel.clearManualMatch(for: game)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .foregroundColor(.secondary)
                            .help("Clear match")
                            .accessibilityLabel("Clear SteamGridDB match")
                        }
                    }
                    if case .failed(let message) = game.artworkStatus {
                        Text(message).font(.caption).foregroundColor(.orange)
                    }
                }
                Spacer()
            }
        }
        .sheet(isPresented: $showingMatchSheet) {
            SGDBMatchSheet(viewModel: viewModel, game: game)
        }
    }

    private var isDownloading: Bool {
        if case .downloading = game.artworkStatus { return true }
        return false
    }

    private var artworkURL: URL? {
        if case .cached(let url) = game.artworkStatus { return url }
        return nil
    }

    private func chooseFile() {
        if let url = FilePicker.chooseFile(title: "Choose Artwork", extensions: ["png", "jpg", "jpeg"]) {
            viewModel.setCustomArtwork(url: url, for: game)
        }
    }

    /// Accept an image file dropped on the artwork well.
    private func handleImageDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = item as? URL
            }
            guard let url else { return }
            Task { @MainActor in viewModel.setCustomArtwork(url: url, for: game) }
        }
        return true
    }
}

// MARK: - Platform & Emulator section

private struct PlatformEmulatorSection: View {
    @ObservedObject var viewModel: MainViewModel
    let game: GameEntry

    var body: some View {
        Section("Platform & Emulator") {
            HStack {
                Picker("Platform", selection: Binding(
                    get: { game.platform },
                    set: { viewModel.setPlatform($0, for: game) }
                )) {
                    ForEach(viewModel.allPlatforms) { platform in
                        Text(platform.displayName).tag(platform)
                    }
                }
                OverrideDot(isOn: viewModel.hasOverride(.platform, for: game))
                ResetButton(isOn: viewModel.hasOverride(.platform, for: game)) {
                    viewModel.resetOverride(.platform, for: game)
                }
            }

            let options = viewModel.availableOptions(for: game)
            if options.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("No emulator installed for \(game.platform.displayName)", systemImage: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Button("Open Settings…") { openSettingsWindow() }
                }
            } else {
                HStack {
                    Picker("Emulator", selection: Binding(
                        get: { game.emulator },
                        set: { if let choice = $0 { viewModel.setEmulatorChoice(choice, for: game) } }
                    )) {
                        ForEach(options, id: \.choice) { option in
                            Text(label(for: option)).tag(Optional(option.choice))
                        }
                    }
                    OverrideDot(isOn: viewModel.hasOverride(.emulator, for: game))
                    ResetButton(isOn: viewModel.hasOverride(.emulator, for: game)) {
                        viewModel.resetOverride(.emulator, for: game)
                    }
                }
            }
        }
    }

    private func label(for option: EmulatorOption) -> String {
        let isDefault = viewModel.defaultChoiceSetting(for: game.platform) == option.choice
        return isDefault ? "\(option.displayName) (platform default)" : option.displayName
    }

    /// Open the Settings scene on macOS 13 (the `openSettings` environment value
    /// is 14+). Ventura renamed the selector to `showSettingsWindow:`.
    private func openSettingsWindow() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

// MARK: - Launch section

private struct LaunchSection: View {
    @ObservedObject var viewModel: MainViewModel
    let game: GameEntry

    @State private var argsText: String = ""

    var body: some View {
        Section("Launch") {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Arguments")
                    Spacer()
                    OverrideDot(isOn: viewModel.hasOverride(.args, for: game))
                    ResetButton(isOn: viewModel.hasOverride(.args, for: game)) {
                        viewModel.resetOverride(.args, for: game)
                    }
                }
                TextField("Arguments", text: $argsText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { viewModel.setArgsTemplate(argsText, for: game) }
                Text("Tokens: \(tokenHelp)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .task(id: game.id) { argsText = game.argsTemplate }
            .onChange(of: game.argsTemplate) { argsText = $0 }

            launchImageControl

            VStack(alignment: .leading, spacing: 4) {
                Text("ROM Path").font(.caption).foregroundColor(.secondary)
                HStack {
                    Text(game.romPath.path)
                        .font(.caption)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([game.romPath])
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    /// Authoritative token list expanded by `AppBundleGenerator.buildLaunchCommand`.
    private var tokenHelp: String {
        "{emulator} (the emulator binary), {rom} (the ROM/playlist path), {core} (RetroArch core, cores only)"
    }

    @ViewBuilder
    private var launchImageControl: some View {
        if !game.alternateImages.isEmpty {
            let images = [game.romPath] + game.alternateImages
            HStack {
                Picker("Launch File", selection: Binding(
                    get: { game.launchPath },
                    set: { viewModel.setLaunchImage($0, for: game) }
                )) {
                    ForEach(images, id: \.self) { url in
                        Text(url.lastPathComponent).tag(url)
                    }
                }
                OverrideDot(isOn: viewModel.hasOverride(.launchImage, for: game))
                ResetButton(isOn: viewModel.hasOverride(.launchImage, for: game)) {
                    viewModel.resetOverride(.launchImage, for: game)
                }
            }
        } else if game.launchPath.pathExtension.lowercased() == "m3u" {
            VStack(alignment: .leading, spacing: 2) {
                Text("Discs").font(.caption).foregroundColor(.secondary)
                ForEach(game.additionalFiles, id: \.self) { disc in
                    Text(disc.lastPathComponent).font(.caption)
                }
                Text("Launched via a generated .m3u playlist.")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Manual match sheet

/// A modal for correcting a wrong SteamGridDB match: search by title, pick the
/// right game, and (optionally) adopt its name as the game's title. Not a
/// main-list row, so observing the ViewModel is fine here.
private struct SGDBMatchSheet: View {
    @ObservedObject var viewModel: MainViewModel
    let game: GameEntry

    @Environment(\.dismiss) private var dismiss

    @State private var searchTerm: String = ""
    @State private var results: [SGDBGame] = []
    @State private var selectedID: Int?
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var useNameAsTitle = true

    private var selectedMatch: SGDBGame? {
        results.first { $0.id == selectedID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Match “\(game.title)”")
                .font(.headline)

            HStack {
                TextField("Search SteamGridDB", text: $searchTerm)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { search() }
                Button("Search") { search() }
                    .disabled(searchTerm.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
            }

            resultsList

            Toggle("Also use matched name as title", isOn: $useNameAsTitle)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Use This Match") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedMatch == nil)
            }
        }
        .padding()
        .frame(width: 420, height: 420)
        .task {
            searchTerm = game.title
            search()
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        if isSearching {
            VStack {
                Spacer()
                ProgressView("Searching…")
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if results.isEmpty {
            VStack {
                Spacer()
                Text(hasSearched ? "No results" : "Search for a game to match")
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            List(results, id: \.id, selection: $selectedID) { result in
                Text(result.name)
            }
            .border(Color.secondary.opacity(0.2))
        }
    }

    private func search() {
        let term = searchTerm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        isSearching = true
        Task {
            let found = await viewModel.searchArtworkMatches(term: term)
            results = found
            selectedID = found.first?.id
            hasSearched = true
            isSearching = false
        }
    }

    private func apply() {
        guard let match = selectedMatch else { return }
        Task {
            await viewModel.applyManualMatch(match, setTitle: useNameAsTitle, for: game)
            dismiss()
        }
    }
}
