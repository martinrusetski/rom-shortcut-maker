//
//  ContentView.swift
//  SteamShortcutConverter
//
//  Rom Shortcut Maker — a content-first game library with native search
//  and generation dock.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var isDropTargeted = false
    @State private var generationPlan = MainViewModel.GenerationPlan()
    @State private var search = ""

    var body: some View {
        ZStack {
            LibraryBackground()

            VStack(spacing: 0) {
                GameListZone(
                    viewModel: viewModel,
                    generationPlan: generationPlan,
                    search: $search
                )
                GenerateDock(viewModel: viewModel, generationPlan: generationPlan)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }
        .frame(minWidth: 820, minHeight: 520)
        .searchable(text: $search, placement: .toolbar, prompt: "Search Games")
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                reloadButton
            }
        }
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
        .onChange(of: viewModel.propertiesGameID) {
            if viewModel.propertiesGameID != nil {
                PropertiesWindowController.shared.show(viewModel: viewModel)
            }
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
        .sheet(isPresented: $viewModel.showingWatchedFolderPrompt) {
            FirstFolderPrompt(viewModel: viewModel)
        }
    }

    private var reloadButton: some View {
        Button {
            Task { await viewModel.scan() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .help("Reload watched folders")
        .accessibilityLabel("Reload watched folders")
        .disabled(viewModel.watchedFolders.isEmpty || viewModel.isProcessing)
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
            Task { @MainActor in await viewModel.addWatchedFolder(url) }
        }
        return true
    }
}

private struct LibraryBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.07),
                    Color.clear,
                    Color.cyan.opacity(0.035)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Game list (middle)

private struct GameListZone: View {
    @ObservedObject var viewModel: MainViewModel
    let generationPlan: MainViewModel.GenerationPlan
    @Binding var search: String
    @SceneStorage("game-library-table-columns")
    private var columnCustomization: TableColumnCustomization<GameEntry>

    private var filteredGames: [GameEntry] {
        viewModel.games.filter { game in
            search.isEmpty
                || game.title.localizedCaseInsensitiveContains(search)
                || game.platform.displayName.localizedCaseInsensitiveContains(search)
                || (game.emulator?.shortDisplayName.localizedCaseInsensitiveContains(search) ?? false)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        if viewModel.games.isEmpty && viewModel.operation == .scanning {
            VStack(spacing: 12) {
                ProgressView()
                Text("Scanning watched folders…")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.games.isEmpty {
            EmptyStateView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(
                filteredGames,
                selection: $viewModel.selection,
                columnCustomization: $columnCustomization
            ) {
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
                    .width(min: 180, ideal: 300, max: .infinity)
                    .customizationID("game")
                    .disabledCustomizationBehavior([.reorder, .visibility])

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
                        .frame(maxWidth: .infinity)
                        .help("Change platform for \(game.title)")
                    }
                    .width(min: 130, ideal: 160, max: 260)
                    .customizationID("platform")
                    .disabledCustomizationBehavior([.reorder, .visibility])

                    TableColumn("Emulator") { game in
                        InlineEmulatorPicker(viewModel: viewModel, game: game)
                    }
                    .width(min: 170, ideal: 190, max: 320)
                    .customizationID("emulator")
                    .disabledCustomizationBehavior([.reorder, .visibility])

                    TableColumn("") { game in
                        Button {
                            viewModel.propertiesGameID = game.id
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Open Game Properties for \(game.title)")
                        .accessibilityLabel("Open Game Properties for \(game.title)")
                    }
                    .width(36)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 42)
            .background(TableColumnResizingBridge())
            .overlay {
                if !search.isEmpty && filteredGames.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .contextMenu(forSelectionType: GameEntry.ID.self) { ids in
                selectionMenu(for: ids)
            } primaryAction: { ids in
                if let id = ids.first { viewModel.propertiesGameID = id }
            }
            .onDeleteCommand { excludeSelection() }
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
                if opensProperties {
                    viewModel.propertiesGameID = game.id
                } else {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            } label: {
                Label(
                    emptyActionLabel,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .lineLimit(1)
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundColor(.orange)
            .help(emptyActionHelp)
        } else {
            FixedWidthMenu(
                title: selectedLabel,
                width: 146,
                accessibilityLabel: "Emulator for \(game.title): \(selectedLabel)"
            ) {
                ForEach(options, id: \.choice) { option in
                    Button {
                        viewModel.setEmulatorChoice(option.choice, for: game)
                    } label: {
                        if game.emulator == option.choice {
                            Label(label(for: option), systemImage: "checkmark")
                        } else {
                            Text(label(for: option))
                        }
                    }
                }
            }
            .help("Change emulator for \(game.title)")
        }
    }

    private var opensProperties: Bool {
        switch game.status {
        case .unknownPlatform, .needsLaunchTarget, .invalidSource:
            true
        case .ready, .noEmulator:
            false
        }
    }

    private var emptyActionLabel: String {
        switch game.status {
        case .unknownPlatform: "Choose platform"
        case .needsLaunchTarget: "Choose startup"
        case .invalidSource: "Inspect package"
        case .ready, .noEmulator: "Set up…"
        }
    }

    private var emptyActionHelp: String {
        switch game.status {
        case .unknownPlatform:
            "Choose a platform before selecting an emulator"
        case .needsLaunchTarget:
            "Choose which DOS program or configuration starts this game"
        case .invalidSource:
            "Inspect the DOS package problem"
        case .ready, .noEmulator:
            "No compatible emulator is configured. Open Settings to set one up."
        }
    }

    private var selectedLabel: String {
        guard let choice = game.emulator,
              let option = options.first(where: { $0.choice == choice }) else {
            return "Choose…"
        }
        return label(for: option)
    }

    private func label(for option: EmulatorOption) -> String {
        viewModel.defaultChoiceSetting(for: game.platform) == option.choice
            ? "\(option.displayName) - default"
            : option.displayName
    }
}

// MARK: - Generation dock (bottom)

private struct GenerateDock: View {
    @ObservedObject var viewModel: MainViewModel
    let generationPlan: MainViewModel.GenerationPlan

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                statusSymbol

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.headline)
                    generationSummary
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button(action: chooseOutputFolder) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("OUTPUT")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Label(outputFolderName, systemImage: "folder")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: 180, alignment: .leading)
                }
                .buttonStyle(.glass)
                .help(viewModel.outputDirectory.isEmpty
                      ? "Choose Output Folder"
                      : "Output folder: \(viewModel.outputDirectory)")

                if generationPlan.isUpToDate {
                    Button {
                        Task { await viewModel.generate(forceRebuild: true) }
                    } label: {
                        Label("Rebuild Selected", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .disabled(!viewModel.canGenerate || viewModel.isProcessing)
                } else {
                    Button {
                        Task { await viewModel.generate() }
                    } label: {
                        Label(generateButtonTitle, systemImage: "wand.and.sparkles")
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.accentColor)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canGenerate || viewModel.isProcessing || generationPlan.pendingCount == 0)
                }
            }

            if viewModel.isProcessing {
                ProgressView(value: viewModel.progressValue)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var generateButtonTitle: String {
        if generationPlan.pendingCount == 0 {
            return generationPlan.needsAttention > 0 ? "Resolve Issues" : "Generate"
        }
        return generationPlan.pendingCount == 1
            ? "Generate 1 Change"
            : "Generate \(generationPlan.pendingCount) Changes"
    }

    private var statusTitle: String {
        if viewModel.isProcessing {
            switch viewModel.operation {
            case .scanning: return "Scanning your library"
            case .importing: return "Importing from Steam"
            case .generating: return "Creating your apps"
            case .idle: break
            }
        }
        if generationPlan.isUpToDate { return "Your library is up to date" }
        if generationPlan.pendingCount > 0 {
            return generationPlan.pendingCount == 1 ? "1 change is ready" : "\(generationPlan.pendingCount) changes are ready"
        }
        if generationPlan.needsAttention > 0 { return "Some games need attention" }
        return "Choose games to generate"
    }

    @ViewBuilder
    private var statusSymbol: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.14))
            Image(systemName: statusSymbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(statusColor)
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }

    private var statusSymbolName: String {
        if viewModel.isProcessing { return "gearshape.2.fill" }
        if generationPlan.isUpToDate { return "checkmark" }
        if generationPlan.needsAttention > 0 && generationPlan.pendingCount == 0 {
            return "exclamationmark"
        }
        return "sparkles"
    }

    private var statusColor: Color {
        if generationPlan.needsAttention > 0 && generationPlan.pendingCount == 0 {
            return .orange
        }
        return generationPlan.isUpToDate ? .green : .accentColor
    }

    @ViewBuilder
    private var generationSummary: some View {
        if viewModel.isProcessing {
            operationStatus
        } else {
            Text(generationPlan.isUpToDate ? upToDateSummary : planSummaryText)
                .lineLimit(1)
                .truncationMode(.tail)
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

    private var outputFolderName: String {
        guard !viewModel.outputDirectory.isEmpty else { return "Choose Folder" }
        return URL(fileURLWithPath: viewModel.outputDirectory).lastPathComponent
    }

    private func chooseOutputFolder() {
        if let url = FilePicker.chooseDirectory(title: "Select Output Folder") {
            viewModel.setOutputDirectory(url)
        }
    }

    @ViewBuilder
    private var operationStatus: some View {
        switch viewModel.operation {
        case .scanning:
            Label("Scanning watched folders…", systemImage: "magnifyingglass")
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
            Text(viewModel.watchedFolders.isEmpty ? "Add a ROM folder to get started" : "No ROMs found")
                .font(.title3)
            Text(viewModel.watchedFolders.isEmpty
                 ? "Watched folders are managed in Settings and combined into one app library."
                 : "The watched folders do not contain any recognized games.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            SettingsLink {
                Label("Open Settings", systemImage: "gearshape")
            }
            .buttonStyle(.glassProminent)
            .tint(.accentColor)
            .controlSize(.large)
        }
        .padding()
    }
}

private struct FirstFolderPrompt: View {
    @ObservedObject var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 72, height: 72)
                .glassEffect(.regular, in: Circle())

            VStack(spacing: 7) {
                Text("Add Your ROM Folder")
                    .font(.title2.bold())
                Text("Rom Shortcut Maker watches one or more folders and keeps them together in a single app library.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 350)
            }

            Button {
                guard let url = FilePicker.chooseDirectory(title: "Add Watched Folder") else { return }
                dismiss()
                Task { await viewModel.addWatchedFolder(url) }
            } label: {
                Label("Choose ROM Folder", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            Button("Not Now") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(30)
        .frame(width: 440)
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
