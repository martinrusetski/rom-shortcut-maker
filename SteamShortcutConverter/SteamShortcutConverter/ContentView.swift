//
//  ContentView.swift
//  SteamShortcutConverter
//
//  Main UI view
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MainViewModel()
    @State private var showingShortcutsFilePicker = false
    @State private var showingOutputDirectoryPicker = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Main content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Shortcuts.vdf selection
                    shortcutsFileSection
                    
                    Divider()
                    
                    // Output directory selection
                    outputDirectorySection
                    
                    Divider()
                    
                    // Shortcut list (placeholder)
                    shortcutListSection
                    
                    Divider()
                    
                    // Settings panel
                    settingsSection
                    
                    Divider()
                    
                    // Progress view (placeholder)
                    progressSection
                }
                .padding()
            }
            
            // Error message
            if let errorMessage = viewModel.errorMessage {
                errorView(message: errorMessage)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .fileImporter(
            isPresented: $showingShortcutsFilePicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            handleShortcutsFileSelection(result)
        }
        .fileImporter(
            isPresented: $showingOutputDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleOutputDirectorySelection(result)
        }
        .alert("Conversion Complete", isPresented: $viewModel.showingSummary) {
            Button("Done") {
                viewModel.showingSummary = false
            }
        } message: {
            if let summary = viewModel.conversionSummary {
                summaryMessage(for: summary)
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 4) {
            Text("Steam Shortcut Converter")
                .font(.title)
                .fontWeight(.semibold)
            Text("Convert Steam shortcuts to native macOS app bundles")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    // MARK: - Shortcuts File Section
    
    private var shortcutsFileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shortcuts File")
                .font(.headline)
            
            Text("Select your Steam shortcuts.vdf file")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                TextField("Path to shortcuts.vdf", text: $viewModel.shortcutsVDFPath)
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)
                
                Button("Browse...") {
                    showingShortcutsFilePicker = true
                }
                
                Button("Auto-Detect") {
                    viewModel.autoDetectShortcutsFile()
                }
            }
            
            // Show auto-detected paths if available
            if !viewModel.autoDetectedPaths.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Auto-detected files:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(viewModel.autoDetectedPaths, id: \.self) { path in
                        HStack {
                            Text(path)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Spacer()
                            
                            if viewModel.shortcutsVDFPath == path {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Button("Use") {
                                    viewModel.shortcutsVDFPath = path
                                    viewModel.saveConfiguration()
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                    }
                }
            }
        }
    }
    
    // MARK: - Output Directory Section
    
    private var outputDirectorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Output Directory")
                .font(.headline)
            
            Text("Choose where to save the generated app bundles")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                TextField("Output directory path", text: $viewModel.outputDirectory)
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)
                
                Button("Choose...") {
                    showingOutputDirectoryPicker = true
                }
            }
        }
    }
    
    // MARK: - Shortcut List Section
    
    private var shortcutListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ROM Shortcuts")
                    .font(.headline)
                
                Spacer()
                
                if !viewModel.shortcuts.isEmpty {
                    Button("Select All") {
                        viewModel.selectAll()
                    }
                    .buttonStyle(.borderless)
                    
                    Button("Deselect All") {
                        viewModel.deselectAll()
                    }
                    .buttonStyle(.borderless)
                }
            }
            
            if viewModel.shortcuts.isEmpty {
                Text("No ROM shortcuts found. Select a shortcuts.vdf file to begin.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(viewModel.shortcuts.count) ROM shortcuts detected • \(viewModel.selectedShortcutIDs.count) selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Shortcut list with headers
                    VStack(spacing: 0) {
                        // Header row
                        HStack(spacing: 12) {
                            Text("")
                                .frame(width: 20)
                            Text("")
                                .frame(width: 40)
                            Text("Name")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Emulator")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .frame(width: 100, alignment: .leading)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1))
                        
                        Divider()
                        
                        // Scrollable list
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(viewModel.shortcuts, id: \.appID) { shortcut in
                                    ShortcutRow(
                                        shortcut: shortcut,
                                        emulatorType: viewModel.getEmulatorType(for: shortcut),
                                        isSelected: Binding(
                                            get: { viewModel.isSelected(shortcut) },
                                            set: { _ in viewModel.toggleSelection(for: shortcut) }
                                        )
                                    )
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 300)
                    }
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }
            }
        }
    }
    
    // MARK: - Settings Section
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 16) {
                // Remove orphaned bundles checkbox
                Toggle("Remove orphaned bundles", isOn: $viewModel.removeOrphanedBundles)
                    .onChange(of: viewModel.removeOrphanedBundles) { _ in
                        viewModel.saveConfiguration()
                    }
                
                Text("When enabled, app bundles for shortcuts that no longer exist will be deleted during conversion.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
                
                Divider()
                
                // Last conversion date
                HStack {
                    Text("Last Conversion:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if let lastDate = viewModel.lastConversionDate {
                        Text(lastDate, style: .date)
                            .font(.subheadline)
                        Text(lastDate, style: .time)
                            .font(.subheadline)
                    } else {
                        Text("Never")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                // Reset configuration button
                Button(role: .destructive) {
                    viewModel.resetConfiguration()
                } label: {
                    Label("Reset Configuration", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Progress Section
    
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progress")
                .font(.headline)
            
            if viewModel.isProcessing {
                VStack(alignment: .leading, spacing: 12) {
                    // Current game being processed
                    if !viewModel.progressMessage.isEmpty {
                        Text(viewModel.progressMessage)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    
                    // Progress bar with percentage
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: viewModel.progressValue)
                        
                        HStack {
                            Text("\(Int(viewModel.progressValue * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            // Counts: processed / total (remaining)
                            Text("\(viewModel.processedCount) / \(viewModel.totalCount) (\(viewModel.remainingCount) remaining)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ready to convert \(viewModel.selectedShortcutIDs.count) shortcut\(viewModel.selectedShortcutIDs.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Convert") {
                        viewModel.startConversion()
                    }
                    .disabled(!viewModel.canProceed || viewModel.selectedShortcutIDs.isEmpty)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    
    // MARK: - Error View
    
    private func errorView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(message)
                    .font(.caption)
                Spacer()
                Button("Dismiss") {
                    viewModel.errorMessage = nil
                    viewModel.currentError = nil
                }
            }
            
            // Show actionable message if we have a structured error
            if let error = viewModel.currentError {
                Text(error.actionableMessage)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.leading, 24)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
    }
    
    // MARK: - File Selection Handlers
    
    private func summaryMessage(for summary: ConversionSummary) -> Text {
        var message = ""
        
        // Bundles created, updated, skipped, and removed
        message += "Bundles Created: \(summary.bundlesCreated)\n"
        message += "Bundles Updated: \(summary.bundlesUpdated)\n"
        message += "Bundles Skipped: \(summary.bundlesSkipped)\n"
        
        if summary.bundlesRemoved > 0 {
            message += "Bundles Removed: \(summary.bundlesRemoved)\n"
        }
        
        // Errors
        if !summary.errors.isEmpty {
            message += "\nErrors (\(summary.errors.count)):\n"
            for error in summary.errors.prefix(5) {
                message += "• \(error.shortcutName): \(error.message)\n"
            }
            if summary.errors.count > 5 {
                message += "• ... and \(summary.errors.count - 5) more\n"
            }
        }
        
        // Warnings
        if !summary.warnings.isEmpty {
            message += "\nWarnings (\(summary.warnings.count)):\n"
            for warning in summary.warnings.prefix(5) {
                message += "• [\(warning.type.rawValue)] \(warning.shortcutName): \(warning.message)\n"
            }
            if summary.warnings.count > 5 {
                message += "• ... and \(summary.warnings.count - 5) more\n"
            }
        }
        
        // Success message if no issues
        if !summary.hasIssues {
            message += "\nAll bundles converted successfully!"
        }
        
        return Text(message)
    }
    
    private func handleShortcutsFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                viewModel.selectShortcutsFile(url: url)
            }
        case .failure(let error):
            viewModel.errorMessage = "Failed to select file: \(error.localizedDescription)"
        }
    }
    
    private func handleOutputDirectorySelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                viewModel.selectOutputDirectory(url: url)
            }
        case .failure(let error):
            viewModel.errorMessage = "Failed to select directory: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
}
