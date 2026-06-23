//
//  ContentView.swift
//  SteamShortcutConverter
//
//  Main UI view
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MainViewModel()
    @State private var showingSettings = false
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // Header
                headerView
                
                Divider()
                
                // Main content
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Shortcut list
                        shortcutListSection
                        
                        // Convert button and progress section
                        convertAndProgressSection
                    }
                    .padding()
                }
                
                // Error message
                if let errorMessage = viewModel.errorMessage {
                    errorView(message: errorMessage)
                }
            }
            
            // Settings button in bottom right corner
            Button(action: {
                showingSettings = true
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
            .padding(16)
        }
        .frame(minWidth: 500, maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel)
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
                    
                    // Shortcut list
                    VStack(spacing: 0) {
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
                                        ),
                                        displayName: viewModel.getDisplayName(for: shortcut),
                                        hasCustomName: viewModel.hasCustomName(for: shortcut),
                                        onRename: { newName in
                                            viewModel.setCustomName(newName, for: shortcut)
                                        },
                                        onResetName: {
                                            viewModel.resetCustomName(for: shortcut)
                                        }
                                    )
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(minHeight: 100, maxHeight: 500)
                    }
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }
            }
        }
    }
    
    // MARK: - Convert and Progress Section
    
    private var convertAndProgressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.isProcessing {
                // Show progress when processing
                VStack(alignment: .leading, spacing: 12) {
                    if !viewModel.progressMessage.isEmpty {
                        Text(viewModel.progressMessage)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: viewModel.progressValue)
                        
                        HStack {
                            Text("\(Int(viewModel.progressValue * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text("\(viewModel.processedCount) / \(viewModel.totalCount) (\(viewModel.remainingCount) remaining)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                // Show convert button when not processing
                VStack(alignment: .leading, spacing: 12) {
                    if !viewModel.canProceed || viewModel.selectedShortcutIDs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            if viewModel.shortcutsVDFPath.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundColor(.orange)
                                    Text("Select a shortcuts.vdf file in Settings")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if viewModel.outputDirectory.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundColor(.orange)
                                    Text("Choose an output directory in Settings")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if viewModel.selectedShortcutIDs.isEmpty && !viewModel.shortcuts.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundColor(.orange)
                                    Text("Select at least one shortcut to convert")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    } else {
                        Text("Ready to convert \(viewModel.selectedShortcutIDs.count) shortcut\(viewModel.selectedShortcutIDs.count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
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
}

#Preview {
    ContentView()
}
