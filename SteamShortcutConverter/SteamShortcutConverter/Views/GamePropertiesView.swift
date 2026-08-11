//
//  GamePropertiesView.swift
//  SteamShortcutConverter
//
//  A focused Get Info-style editor. Common changes stay visible; diagnostics
//  and command-template editing live under Advanced.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Reusable utility window

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
            win.setContentSize(NSSize(width: 560, height: 650))
            win.minSize = NSSize(width: 520, height: 520)
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
            updateTitle(game.title)
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func updateTitle(_ title: String) {
        window?.title = title.isEmpty ? "Game Properties" : title
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
            VStack(spacing: 0) {
                PropertiesHeader(viewModel: viewModel, game: game)
                    .padding(16)
                Divider()
                Form {
                    GameSettingsSection(viewModel: viewModel, game: game)
                    LaunchSection(viewModel: viewModel, game: game)
                    AdvancedSection(viewModel: viewModel, game: game)
                }
                .formStyle(.grouped)
                Divider()
                HStack {
                    Text("Changes are saved automatically")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Reset Changes") { viewModel.resetOverrides(for: game) }
                        .disabled(!viewModel.anyOverrides(game))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .frame(minWidth: 520, minHeight: 520)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "gamecontroller")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("No game selected").foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct RevertButton: View {
    let isVisible: Bool
    let action: () -> Void

    var body: some View {
        if isVisible {
            Button("Revert", action: action)
                .controlSize(.small)
                .buttonStyle(.borderless)
                .foregroundColor(.accentColor)
                .help("Restore the detected default")
        }
    }
}

// MARK: - Header and artwork

private struct PropertiesHeader: View {
    @ObservedObject var viewModel: MainViewModel
    let game: GameEntry

    @State private var titleText = ""
    @State private var showingArtworkPicker = false
    @State private var titleSaveTask: Task<Void, Never>?
    @FocusState private var titleIsFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ThumbnailView(url: artworkURL, size: 104)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "photo.badge.plus")
                        .padding(5)
                        .background(.regularMaterial, in: Circle())
                        .padding(5)
                }
                .contentShape(Rectangle())
                .onTapGesture { showingArtworkPicker = true }
                .onDrop(of: [.image, .fileURL], isTargeted: nil, perform: handleImageDrop)
                .help("Click or drop an image to change artwork")

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Game title", text: $titleText)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                        .focused($titleIsFocused)
                        .onSubmit { commitTitle() }
                    RevertButton(isVisible: viewModel.hasOverride(.title, for: game)) {
                        viewModel.resetOverride(.title, for: game)
                    }
                }

                Text("\(game.platform.displayName) · \(game.romPath.lastPathComponent)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let matchedName = viewModel.matchedGameName(for: game) {
                    Text("SteamGridDB: \(matchedName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Button("Change Artwork…") { showingArtworkPicker = true }
                    Menu {
                        Button("Use Best SteamGridDB Result") {
                            Task { await viewModel.fetchArtwork(for: game) }
                        }
                        .disabled(!viewModel.canFetchArtwork)
                        Button("Choose Local File…") { chooseLocalArtwork() }
                        Divider()
                        if viewModel.matchedGameName(for: game) != nil {
                            Button("Clear SteamGridDB Match") {
                                viewModel.clearManualMatch(for: game)
                            }
                        }
                        Button("Remove Artwork", role: .destructive) {
                            viewModel.removeArtwork(for: game)
                        }
                        .disabled(!viewModel.hasArtwork(game))
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    if case .downloading = game.artworkStatus {
                        ProgressView().controlSize(.small)
                    }
                }

                if case .failed(let message) = game.artworkStatus {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .lineLimit(2)
                }
            }
        }
        .task(id: game.id) {
            titleText = game.title
            PropertiesWindowController.shared.updateTitle(game.title)
        }
        .onChange(of: titleText) { newValue in
            guard newValue != game.title else { return }
            viewModel.setTitleDraft(newValue, for: game)
            PropertiesWindowController.shared.updateTitle(newValue)
            titleSaveTask?.cancel()
            titleSaveTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                viewModel.saveTitleDraft()
            }
        }
        .onChange(of: game.title) { newValue in
            if newValue != titleText { titleText = newValue }
            PropertiesWindowController.shared.updateTitle(newValue)
        }
        .onChange(of: titleIsFocused) { focused in
            if !focused { commitTitle() }
        }
        .onDisappear {
            titleSaveTask?.cancel()
            commitTitle()
        }
        .sheet(isPresented: $showingArtworkPicker) {
            ArtworkPickerSheet(viewModel: viewModel, game: game)
        }
    }

    private var artworkURL: URL? {
        if case .cached(let url) = game.artworkStatus { return url }
        return nil
    }

    private func commitTitle() {
        titleSaveTask?.cancel()
        viewModel.setTitle(titleText, for: game)
    }

    private func chooseLocalArtwork() {
        guard let url = FilePicker.chooseFile(
            title: "Choose Artwork",
            extensions: ["png", "jpg", "jpeg", "webp"]
        ) else { return }
        viewModel.setCustomArtwork(url: url, for: game)
    }

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

// MARK: - Common settings

private struct GameSettingsSection: View {
    @ObservedObject var viewModel: MainViewModel
    let game: GameEntry

    var body: some View {
        Section("Game") {
            HStack {
                Picker("Platform", selection: Binding(
                    get: { game.platform },
                    set: { viewModel.setPlatform($0, for: game) }
                )) {
                    ForEach(viewModel.allPlatformsIncludingUnknown) { platform in
                        Text(platform.displayName).tag(platform)
                    }
                }
                RevertButton(isVisible: viewModel.hasOverride(.platform, for: game)) {
                    viewModel.resetOverride(.platform, for: game)
                }
            }

            let options = viewModel.availableOptions(for: game)
            if options.isEmpty {
                HStack {
                    Label(
                        game.platform.id == "unknown"
                            ? "Assign a platform before choosing an emulator"
                            : "No compatible emulator installed",
                        systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Spacer()
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
                    RevertButton(isVisible: viewModel.hasOverride(.emulator, for: game)) {
                        viewModel.resetOverride(.emulator, for: game)
                    }
                }
            }
        }
    }

    private func label(for option: EmulatorOption) -> String {
        let isDefault = viewModel.defaultChoiceSetting(for: game.platform) == option.choice
        return isDefault ? "\(option.displayName) - platform default" : option.displayName
    }

    private func openSettingsWindow() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

// MARK: - Launch

private struct LaunchSection: View {
    @ObservedObject var viewModel: MainViewModel
    let game: GameEntry

    var body: some View {
        Section("Launch") {
            if !game.alternateImages.isEmpty {
                HStack {
                    Picker("Game file", selection: Binding(
                        get: { game.launchPath },
                        set: { viewModel.setLaunchImage($0, for: game) }
                    )) {
                        ForEach([game.romPath] + game.alternateImages, id: \.self) { url in
                            Text(url.lastPathComponent).tag(url)
                        }
                    }
                    RevertButton(isVisible: viewModel.hasOverride(.launchImage, for: game)) {
                        viewModel.resetOverride(.launchImage, for: game)
                    }
                }
            } else {
                LabeledContent("Game file") {
                    Text(game.launchPath.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }

            if game.launchPath.pathExtension.lowercased() == "m3u", let count = game.discCount {
                LabeledContent("Playlist") {
                    Text("\(count) discs")
                        .foregroundColor(.secondary)
                }
            }

            LabeledContent("Location") {
                HStack {
                    Text(game.romPath.deletingLastPathComponent().path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(.secondary)
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([game.romPath])
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}

// MARK: - Advanced

private struct AdvancedSection: View {
    @ObservedObject var viewModel: MainViewModel
    let game: GameEntry

    @State private var isExpanded = false
    @State private var argsText = ""

    var body: some View {
        Section {
            DisclosureGroup("Advanced", isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Command template")
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(.secondary)
                            .help("Use {emulator} for the executable, {rom} for the game file, and {core} for a RetroArch core.")
                        Spacer()
                        RevertButton(isVisible: viewModel.hasOverride(.args, for: game)) {
                            viewModel.resetOverride(.args, for: game)
                        }
                    }
                    TextField("Command template", text: $argsText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit { viewModel.setArgsTemplate(argsText, for: game) }

                    if let detection = viewModel.detectionInfo(for: game) {
                        Divider()
                        DetectionDetails(info: detection)
                    }
                }
                .padding(.top, 6)
            }
        }
        .task(id: game.id) { argsText = game.argsTemplate }
        .onChange(of: game.argsTemplate) { argsText = $0 }
    }
}

private struct DetectionDetails: View {
    let info: PlatformDetectionInfo
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup("Detection details", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                Text(info.summary)
                    .foregroundColor(info.resolvedBy == nil ? .orange : .secondary)
                ForEach(Array(info.evidence.enumerated()), id: \.offset) { _, evidence in
                    Text(evidence)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(info.sourceDirectory.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - SteamGridDB artwork picker

private struct ArtworkPickerSheet: View {
    @ObservedObject var viewModel: MainViewModel
    let game: GameEntry

    @Environment(\.dismiss) private var dismiss
    @State private var searchTerm = ""
    @State private var matches: [SGDBGame] = []
    @State private var selectedMatchID: Int?
    @State private var candidates: [SGDBArtworkCandidate] = []
    @State private var selectedCandidateID: String?
    @State private var isSearching = false
    @State private var isLoadingArtwork = false
    @State private var useNameAsTitle = false
    @State private var candidateTask: Task<Void, Never>?

    private var selectedMatch: SGDBGame? {
        matches.first { $0.id == selectedMatchID }
    }

    private var selectedCandidate: SGDBArtworkCandidate? {
        candidates.first { $0.id == selectedCandidateID }
    }

    private var iconCandidates: [SGDBArtworkCandidate] {
        candidates.filter { $0.sourceType == .icon }
    }

    private var gridCandidates: [SGDBArtworkCandidate] {
        candidates.filter { $0.sourceType == .grid }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Artwork")
                .font(.title2.weight(.semibold))

            HStack {
                TextField("Search SteamGridDB", text: $searchTerm)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { search() }
                Button("Search") { search() }
                    .disabled(searchTerm.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
            }

            HStack(alignment: .top, spacing: 12) {
                GroupBox("Game match") {
                    if isSearching {
                        ProgressView("Searching…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if matches.isEmpty {
                        Text("No matches")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(matches, id: \.id, selection: $selectedMatchID) { match in
                            Text(match.name).lineLimit(2)
                        }
                    }
                }
                .frame(width: 190)

                GroupBox("Available artwork") {
                    if isLoadingArtwork {
                        ProgressView("Loading artwork…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if candidates.isEmpty {
                        Text(selectedMatch == nil ? "Choose a game match" : "No artwork found")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                candidateSection(title: "Icons", items: iconCandidates)
                                if !gridCandidates.isEmpty {
                                    candidateSection(title: "Grid fallback", items: gridCandidates)
                                }
                            }
                            .padding(4)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 350)

            Toggle("Use matched SteamGridDB name as the game title", isOn: $useNameAsTitle)

            HStack {
                Text("Icons are preferred. Grid artwork is shown only as a fallback.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Use Artwork") { applySelection() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedMatch == nil || selectedCandidate == nil)
            }
        }
        .padding(16)
        .frame(width: 680, height: 520)
        .task {
            searchTerm = game.title
            search()
        }
        .onChange(of: selectedMatchID) { _ in loadSelectedMatchArtwork() }
        .onDisappear { candidateTask?.cancel() }
    }

    @ViewBuilder
    private func candidateSection(title: String, items: [SGDBArtworkCandidate]) -> some View {
        if !items.isEmpty {
            Text(title)
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92, maximum: 120), spacing: 10)], spacing: 10) {
                ForEach(items) { candidate in
                    Button {
                        selectedCandidateID = candidate.id
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            AsyncImage(url: candidate.image.thumb ?? candidate.image.url) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFit()
                                case .failure:
                                    Image(systemName: "photo")
                                        .font(.largeTitle)
                                        .foregroundColor(.secondary)
                                default:
                                    ProgressView()
                                }
                            }
                            .frame(height: 92)
                            .frame(maxWidth: .infinity)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 7))

                            if selectedCandidateID == candidate.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                                    .background(Color(nsColor: .windowBackgroundColor), in: Circle())
                                    .padding(5)
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(
                                    selectedCandidateID == candidate.id ? Color.accentColor : Color.clear,
                                    lineWidth: 3)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func search() {
        let term = searchTerm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        isSearching = true
        matches = []
        candidates = []
        selectedCandidateID = nil
        Task {
            let found = await viewModel.searchArtworkMatches(term: term)
            matches = found
            selectedMatchID = found.first?.id
            isSearching = false
        }
    }

    private func loadSelectedMatchArtwork() {
        candidateTask?.cancel()
        guard let match = selectedMatch else {
            candidates = []
            selectedCandidateID = nil
            return
        }
        isLoadingArtwork = true
        candidates = []
        selectedCandidateID = nil
        candidateTask = Task {
            let found = await viewModel.artworkCandidates(for: match)
            guard !Task.isCancelled, selectedMatchID == match.id else { return }
            candidates = found
            selectedCandidateID = found.first?.id
            isLoadingArtwork = false
        }
    }

    private func applySelection() {
        guard let match = selectedMatch, let candidate = selectedCandidate else { return }
        Task {
            await viewModel.applyArtworkCandidate(
                candidate,
                match: match,
                setTitle: useNameAsTitle,
                for: game)
            dismiss()
        }
    }
}
