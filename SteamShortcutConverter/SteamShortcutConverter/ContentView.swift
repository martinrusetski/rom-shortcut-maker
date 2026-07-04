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

    var body: some View {
        VStack(spacing: 0) {
            SourceBar(viewModel: viewModel)
            Divider()
            GameListZone(viewModel: viewModel)
            Divider()
            GenerateBar(viewModel: viewModel)
        }
        .frame(minWidth: 640, minHeight: 480)
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

    var body: some View {
        if viewModel.games.isEmpty {
            EmptyStateView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $viewModel.selection) {
                ForEach(viewModel.groupedGames, id: \.platform.id) { group in
                    let isUnknown = group.platform.id == "unknown"
                    Section {
                        if isUnknown || !viewModel.isCollapsed(group.platform.id) {
                            ForEach(group.games) { game in
                                GameListRow(game: game) { viewModel.setSelected($0, for: game) }
                                    .tag(game.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) { viewModel.propertiesGameID = game.id }
                                    .contextMenu { rowMenu(for: game) }
                            }
                        }
                    } header: {
                        PlatformSectionHeader(
                            platform: group.platform,
                            count: group.games.count,
                            isCollapsed: viewModel.isCollapsed(group.platform.id),
                            isUnknown: isUnknown,
                            toggle: { viewModel.toggleCollapsed(group.platform.id) }
                        )
                    }
                }
            }
            .onDeleteCommand { excludeSelection() }
        }
    }

    /// Games a context-menu action applies to: the whole selection when the
    /// clicked row is part of it, otherwise just that row.
    private func targets(for game: GameEntry) -> [GameEntry] {
        if viewModel.selection.contains(game.id) {
            return viewModel.games.filter { viewModel.selection.contains($0.id) }
        }
        return [game]
    }

    @ViewBuilder
    private func rowMenu(for game: GameEntry) -> some View {
        let targets = targets(for: game)
        let allIncluded = targets.allSatisfy { $0.isSelected }

        Button("Properties") { viewModel.propertiesGameID = game.id }
            .keyboardShortcut("i", modifiers: .command)
        Button("Fetch Artwork") {
            Task { for t in targets { await viewModel.fetchArtwork(for: t) } }
        }
        Button(allIncluded ? "Exclude from Generate" : "Include in Generate") {
            for t in targets { viewModel.setSelected(!allIncluded, for: t) }
        }
        Divider()
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([game.romPath])
        }
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

// MARK: - Generate bar (bottom)

private struct GenerateBar: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var preview: MainViewModel.GenerationPreview?

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("Output:")
                    .foregroundColor(.secondary)
                PathField(path: viewModel.outputDirectory, placeholder: "No output folder chosen")
                Button("Choose…") {
                    if let url = FilePicker.chooseDirectory(title: "Select Output Folder") {
                        viewModel.outputDirectory = url.path
                    }
                }
                if let previewText { Text(previewText).font(.caption).foregroundColor(.secondary) }
                Button("Generate") { Task { await viewModel.generate() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canGenerate || viewModel.isProcessing)
                    .help(viewModel.canGenerate ? "" : "Choose an output folder and select at least one game with an emulator.")
            }
            statusLine
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .task(id: viewModel.generationSignature) {
            guard !viewModel.games.isEmpty else { preview = nil; return }
            preview = await viewModel.previewChanges()
        }
    }

    /// "will create 3, update 2, skip 137" — the trust signal that automation is
    /// doing the right thing, without a confirmation sheet.
    private var previewText: String? {
        guard !viewModel.isProcessing, let preview, !viewModel.games.isEmpty else { return nil }
        var parts: [String] = []
        if preview.created > 0 { parts.append("create \(preview.created)") }
        if preview.updated > 0 { parts.append("update \(preview.updated)") }
        if preview.unchanged > 0 { parts.append("skip \(preview.unchanged)") }
        if preview.removed > 0 { parts.append("remove \(preview.removed)") }
        guard !parts.isEmpty else { return nil }
        return "will " + parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var statusLine: some View {
        HStack {
            if viewModel.isProcessing && !viewModel.progressMessage.isEmpty {
                Text("Generating \(viewModel.progressMessage)…")
            } else {
                Text(statusText)
            }
            Spacer()
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    private var statusText: String {
        guard !viewModel.games.isEmpty else { return " " }
        var parts = ["\(viewModel.games.count) games"]
        let attention = viewModel.needsAttentionCount
        if attention > 0 { parts.append("\(attention) need attention") }
        if let summary = viewModel.conversionSummary, viewModel.showingSummary || !summary.hasIssues {
            parts.append("created \(summary.bundlesCreated), updated \(summary.bundlesUpdated)")
        }
        if let date = viewModel.lastConversionDate {
            parts.append("last generated \(date.formatted(date: .omitted, time: .shortened))")
        }
        return parts.joined(separator: " · ")
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
        panel.allowedFileTypes = extensions
        return panel.runModal() == .OK ? panel.url : nil
    }
}
