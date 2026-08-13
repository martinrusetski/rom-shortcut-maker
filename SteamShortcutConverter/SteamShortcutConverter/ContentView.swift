//
//  ContentView.swift
//  SteamShortcutConverter
//
//  Rom Shortcut Maker — one window, three zones: source bar (top), grouped game
//  list (middle), generate bar (bottom). The window reads top to bottom as
//  "take these ROMs, make these apps, put them here."
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var isDropTargeted = false
    @State private var generationPlan = MainViewModel.GenerationPlan()

    var body: some View {
        VStack(spacing: 0) {
            SourceBar(viewModel: viewModel)
            Divider()
            GameListZone(viewModel: viewModel, generationPlan: generationPlan)
            Divider()
            GenerateBar(viewModel: viewModel, generationPlan: generationPlan)
        }
        .frame(minWidth: 760, minHeight: 480)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(3)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleFolderDrop(providers)
        }
        .task { await viewModel.load() }
        .task(id: viewModel.generationSignature) {
            generationPlan = await viewModel.generationPlan()
        }
        .onChange(of: viewModel.propertiesGameID) { id in
            if id != nil { PropertiesWindowController.shared.show(viewModel: viewModel) }
        }
        .alert("Something went wrong",
               isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showingSummary && (viewModel.conversionSummary?.hasIssues ?? false) },
            set: { if !$0 { viewModel.showingSummary = false } })) {
            if let summary = viewModel.conversionSummary {
                ResultsSheet(summary: summary) { viewModel.showingSummary = false }
            }
        }
    }

    /// Accept a folder dropped anywhere on the window and scan it immediately.
    private func handleFolderDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = item as? URL
            }
            guard let url else { return }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue else { return }
            Task { @MainActor in await viewModel.setScanDirectoryAndScan(url) }
        }
        return true
    }
}

// MARK: - Source bar (top)

private struct SourceBar: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("ROM Folder:")
                    .foregroundColor(.secondary)
                PathField(path: viewModel.scanDirectory, placeholder: "No folder chosen")
                Button("Choose…") { chooseFolder() }
                Button("Rescan") { Task { await viewModel.scan() } }
                    .disabled(viewModel.scanDirectory.isEmpty || viewModel.isProcessing)
                Divider().frame(height: 16)
                Button("Import from Steam…") { importFromSteam() }
                    .disabled(viewModel.isProcessing)
            }
            if viewModel.isProcessing {
                ProgressView(value: viewModel.progressValue)
                    .progressViewStyle(.linear)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func chooseFolder() {
        guard let url = FilePicker.chooseDirectory(title: "Select ROM Folder") else { return }
        Task { await viewModel.setScanDirectoryAndScan(url) }
    }

    private func importFromSteam() {
        guard let url = FilePicker.chooseFile(title: "Select shortcuts.vdf", extensions: ["vdf"]) else { return }
        Task { await viewModel.importFromVDF(url: url) }
    }
}

// MARK: - Game list (middle)

private struct GameListZone: View {
    @ObservedObject var viewModel: MainViewModel
    let generationPlan: MainViewModel.GenerationPlan

    @State private var search = ""
    @State private var filter: GameFilter = .all

    private enum GameFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case included = "Included"
        case changed = "Changed"
        case attention = "Needs Attention"

        var id: Self { self }
    }

    private var filteredGames: [GameEntry] {
        viewModel.games.filter { game in
            let matchesSearch = search.isEmpty
                || game.title.localizedCaseInsensitiveContains(search)
                || game.platform.displayName.localizedCaseInsensitiveContains(search)
                || (game.emulator?.shortDisplayName.localizedCaseInsensitiveContains(search) ?? false)
            guard matchesSearch else { return false }
            switch filter {
            case .all: return true
            case .included: return game.isSelected
            case .changed:
                let action = generationPlan.action(for: game)
                return action == .create || action == .update
            case .attention: return generationPlan.action(for: game) == .needsAttention
            }
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        if viewModel.games.isEmpty && viewModel.operation == .scanning {
            VStack(spacing: 12) {
                ProgressView()
                Text("Scanning ROM folder…")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.games.isEmpty {
            EmptyStateView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    TextField("Search games", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                    Picker("Show", selection: $filter) {
                        ForEach(GameFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .frame(width: 170)
                    Spacer()
                    Text("\(filteredGames.count) of \(viewModel.games.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)

                Divider()

                Table(filteredGames, selection: $viewModel.selection) {
                    TableColumn("") { game in
                        Toggle("", isOn: Binding(
                            get: { game.isSelected },
                            set: { viewModel.setSelected($0, for: game) }
                        ))
                        .labelsHidden()
                        .help("Include in generation")
                        .accessibilityLabel("Include \(game.title) in generation")
                    }
                    .width(28)

                    TableColumn("Game") { game in
                        GameTitleCell(game: game, action: generationPlan.action(for: game))
                    }
                    .width(min: 210, ideal: 280, max: 420)

                    TableColumn("Platform") { game in
                        Picker("Platform", selection: Binding(
                            get: { game.platform },
                            set: { viewModel.setPlatform($0, for: game) }
                        )) {
                            ForEach(viewModel.allPlatformsIncludingUnknown) { platform in
                                Text(platform.displayName).tag(platform)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .help("Change platform for \(game.title)")
                    }
                    .width(min: 100, ideal: 120, max: 160)

                    TableColumn("Emulator") { game in
                        InlineEmulatorPicker(viewModel: viewModel, game: game)
                    }
                    .width(min: 125, ideal: 155, max: 210)

                    TableColumn("") { game in
                        Button {
                            viewModel.propertiesGameID = game.id
                        } label: {
                            Label("Edit…", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Open Game Properties for \(game.title)")
                    }
                    .width(78)
                }
                .contextMenu(forSelectionType: GameEntry.ID.self) { ids in
                    selectionMenu(for: ids)
                } primaryAction: { ids in
                    if let id = ids.first { viewModel.propertiesGameID = id }
                }
                .onDeleteCommand { excludeSelection() }
            }
        }
    }

    /// Games a context-menu action applies to: the whole selection when the
    /// clicked row is part of it, otherwise just that row.
    private func targets(for ids: Set<GameEntry.ID>) -> [GameEntry] {
        viewModel.games.filter { ids.contains($0.id) }
    }

    @ViewBuilder
    private func selectionMenu(for ids: Set<GameEntry.ID>) -> some View {
        let targets = targets(for: ids)
        let game = targets.first
        let allIncluded = targets.allSatisfy { $0.isSelected }

        Button("Properties") { if let game { viewModel.propertiesGameID = game.id } }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(targets.count != 1)
        Button("Fetch Artwork") {
            Task { for t in targets { await viewModel.fetchArtwork(for: t) } }
        }
        Button(allIncluded ? "Exclude from Generate" : "Include in Generate") {
            for t in targets { viewModel.setSelected(!allIncluded, for: t) }
        }
        Divider()
        Menu("Assign Platform") {
            ForEach(viewModel.allPlatforms) { platform in
                Button(platform.displayName) {
                    viewModel.setPlatform(platform, for: targets)
                }
            }
        }
        Menu("Set Folder Platform Rule") {
            ForEach(viewModel.allPlatforms) { platform in
                Button(platform.displayName) {
                    if let game { viewModel.setFolderPlatformRule(platform, for: game) }
                }
            }
        }
        .disabled(game == nil)
        Divider()
        Button("Reveal in Finder") {
            if let game { NSWorkspace.shared.activateFileViewerSelecting([game.romPath]) }
        }
        .disabled(game == nil)
        Button("Reset Overrides") {
            for t in targets { viewModel.resetOverrides(for: t) }
        }
    }

    private func excludeSelection() {
        for game in viewModel.games where viewModel.selection.contains(game.id) {
            viewModel.setSelected(false, for: game)
        }
    }
}

private struct InlineEmulatorPicker: View {
    @ObservedObject var viewModel: MainViewModel
    let game: GameEntry

    private var options: [EmulatorOption] {
        viewModel.availableOptions(for: game)
    }

    var body: some View {
        if options.isEmpty {
            Button {
                if game.platform.id == "unknown" {
                    viewModel.propertiesGameID = game.id
                } else {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            } label: {
                Label(
                    game.platform.id == "unknown" ? "Choose platform" : "Set up…",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .lineLimit(1)
            }
            .buttonStyle(.borderless)
            .foregroundColor(.orange)
            .help(game.platform.id == "unknown"
                  ? "Choose a platform before selecting an emulator"
                  : "No compatible emulator is configured. Open Settings to set one up.")
        } else {
            Picker("Emulator", selection: Binding<EmulatorChoice?>(
                get: { game.emulator },
                set: { if let choice = $0 { viewModel.setEmulatorChoice(choice, for: game) } }
            )) {
                if game.emulator == nil {
                    Text("Choose…").tag(Optional<EmulatorChoice>.none)
                }
                ForEach(options, id: \.choice) { option in
                    Text(label(for: option)).tag(Optional(option.choice))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .help("Change emulator for \(game.title)")
        }
    }

    private func label(for option: EmulatorOption) -> String {
        viewModel.defaultChoiceSetting(for: game.platform) == option.choice
            ? "\(option.displayName) - default"
            : option.displayName
    }
}

// MARK: - Generate bar (bottom)

private struct GenerateBar: View {
    @ObservedObject var viewModel: MainViewModel
    let generationPlan: MainViewModel.GenerationPlan

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Output:")
                    .foregroundColor(.secondary)
                PathField(path: viewModel.outputDirectory, placeholder: "No output folder chosen")
                Button("Choose…") {
                    if let url = FilePicker.chooseDirectory(title: "Select Output Folder") {
                        viewModel.setOutputDirectory(url)
                    }
                }
            }
            HStack(spacing: 8) {
                generationSummary
                    .font(.caption)
                Spacer()
                if generationPlan.isUpToDate {
                    Button("Rebuild Selected") { Task { await viewModel.generate(forceRebuild: true) } }
                        .disabled(!viewModel.canGenerate || viewModel.isProcessing)
                } else {
                    Button(generateButtonTitle) { Task { await viewModel.generate() } }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!viewModel.canGenerate || viewModel.isProcessing || generationPlan.pendingCount == 0)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var generateButtonTitle: String {
        if generationPlan.pendingCount == 0 {
            return generationPlan.needsAttention > 0 ? "Resolve Issues" : "Generate"
        }
        return generationPlan.pendingCount == 1
            ? "Generate 1 Change"
            : "Generate \(generationPlan.pendingCount) Changes"
    }

    @ViewBuilder
    private var generationSummary: some View {
        if viewModel.isProcessing {
            operationStatus
        } else if generationPlan.isUpToDate {
            Label(upToDateSummary, systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
        } else {
            Text(planSummaryText)
                .foregroundColor(.secondary)
        }
    }

    private var upToDateSummary: String {
        let base = "All \(generationPlan.selectedCount) selected apps are up to date"
        guard generationPlan.excluded > 0 else { return base }
        return base + " · \(generationPlan.excluded) excluded"
    }

    private var planSummaryText: String {
        var parts: [String] = []
        if generationPlan.created > 0 { parts.append("\(generationPlan.created) new") }
        if generationPlan.updated > 0 {
            parts.append("\(generationPlan.updated) " + (generationPlan.updated == 1 ? "update" : "updates"))
        }
        if generationPlan.upToDate > 0 { parts.append("\(generationPlan.upToDate) up to date") }
        if generationPlan.needsAttention > 0 { parts.append("\(generationPlan.needsAttention) need attention") }
        if generationPlan.excluded > 0 { parts.append("\(generationPlan.excluded) excluded") }
        if generationPlan.removed > 0 {
            parts.append("\(generationPlan.removed) " + (generationPlan.removed == 1 ? "removal" : "removals"))
        }
        return parts.isEmpty ? "No games selected" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var operationStatus: some View {
        switch viewModel.operation {
        case .scanning:
            Label("Scanning ROM folder…", systemImage: "magnifyingglass")
        case .importing:
            Label("Importing from Steam…", systemImage: "square.and.arrow.down")
        case .generating:
            Label("Generating \(viewModel.progressMessage)…", systemImage: "gearshape.2")
        case .idle:
            Text(planSummaryText)
        }
    }
}

// MARK: - Empty state

private struct EmptyStateView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.3x3.square")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Choose a ROM folder to get started")
                .font(.title3)
            Text("Pick a folder of ROMs and Rom Shortcut Maker will scan it into launchable macOS apps.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Choose ROM Folder…") {
                if let url = FilePicker.chooseDirectory(title: "Select ROM Folder") {
                    Task { await viewModel.setScanDirectoryAndScan(url) }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Import from Steam…") {
                if let url = FilePicker.chooseFile(title: "Select shortcuts.vdf", extensions: ["vdf"]) {
                    Task { await viewModel.importFromVDF(url: url) }
                }
            }
            .buttonStyle(.link)
        }
        .padding()
    }
}

// MARK: - Results sheet (issues only)

private struct ResultsSheet: View {
    let summary: ConversionSummary
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Generation finished with issues")
                .font(.headline)
            Text("Created \(summary.bundlesCreated), updated \(summary.bundlesUpdated), skipped \(summary.bundlesSkipped)"
                 + (summary.bundlesRemoved > 0 ? ", removed \(summary.bundlesRemoved)" : ""))
                .foregroundColor(.secondary)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(summary.warnings) { warning in
                        Label("\(warning.shortcutName): \(warning.message)", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                    }
                    ForEach(summary.errors) { error in
                        Label("\(error.shortcutName): \(error.message)", systemImage: "xmark.octagon")
                            .foregroundColor(.red)
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 240)
            HStack {
                Spacer()
                Button("Done", action: dismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 460)
    }
}

// MARK: - Shared bits

/// Read-only, middle-truncated path display styled like a disabled field.
struct PathField: View {
    let path: String
    let placeholder: String

    var body: some View {
        Text(path.isEmpty ? placeholder : path)
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundColor(path.isEmpty ? .secondary : .primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.25)))
            .help(path)
    }
}

// MARK: - Shared pickers

enum FilePicker {
    static func chooseDirectory(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseFile(title: String, extensions: [String]) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        return panel.runModal() == .OK ? panel.url : nil
    }
}
