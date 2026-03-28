//
//  SettingsView.swift
//  SteamShortcutConverter
//
//  Settings window view
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var showingShortcutsFilePicker = false
    @State private var showingOutputDirectoryPicker = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            
            Divider()
            
            // Settings content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Shortcuts.vdf selection
                    shortcutsFileSection
                    
                    Divider()
                    
                    // Output directory selection
                    outputDirectorySection
                    
                    Divider()
                    
                    // Conversion settings
                    conversionSettingsSection
                    
                    Divider()
                    
                    // Info section
                    infoSection
                    
                    Divider()
                    
                    // Reset configuration
                    resetSection
                }
                .padding()
            }
        }
        .frame(width: 600, height: 500)
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
                .fileImporter(
                    isPresented: $showingShortcutsFilePicker,
                    allowedContentTypes: [.item, .data],
                    allowsMultipleSelection: false
                ) { result in
                    handleShortcutsFileSelection(result)
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
                                        viewModel.loadShortcuts(forceAutoSelect: true)
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
                .fileImporter(
                    isPresented: $showingOutputDirectoryPicker,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    handleOutputDirectorySelection(result)
                }
            }
        }
    }
    
    // MARK: - Conversion Settings Section
    
    private var conversionSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conversion Settings")
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
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Info Section
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Information")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Last Conversion:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if let lastDate = viewModel.lastConversionDate {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(lastDate, style: .date)
                                .font(.subheadline)
                            Text(lastDate, style: .time)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Never")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Reset Section
    
    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reset")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Reset all settings to their default values. This will clear your shortcuts file path, output directory, and all custom names.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
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
    
    // MARK: - File Selection Handlers
    
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
    SettingsView(viewModel: MainViewModel())
}
