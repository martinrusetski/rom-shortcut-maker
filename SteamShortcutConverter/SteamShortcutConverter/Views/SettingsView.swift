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
            Form {
                Section {
                    shortcutsFileSection
                }
                
                Section {
                    outputDirectorySection
                }
                
                Section {
                    conversionSettingsSection
                }
                
                Section {
                    infoSection
                }
                
                Section {
                    resetSection
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 600, height: 500)
    }
    
    // MARK: - Shortcuts File Section
    
    private var shortcutsFileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Shortcuts File") {
                HStack(spacing: 8) {
                    Button("Auto-Detect") {
                        viewModel.autoDetectShortcutsFile()
                    }
                    
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
                }
            }
            
            if !viewModel.shortcutsVDFPath.isEmpty {
                Text(viewModel.shortcutsVDFPath)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            
            // Show auto-detected paths if available
            if !viewModel.autoDetectedPaths.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Auto-detected:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(viewModel.autoDetectedPaths, id: \.self) { path in
                        HStack(spacing: 8) {
                            if viewModel.shortcutsVDFPath == path {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                            
                            Text(path)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            
                            Spacer()
                            
                            if viewModel.shortcutsVDFPath != path {
                                Button("Use") {
                                    viewModel.shortcutsVDFPath = path
                                    viewModel.saveConfiguration()
                                    viewModel.loadShortcuts(forceAutoSelect: true)
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                            }
                        }
                        .padding(6)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(4)
                    }
                }
            }
        }
    }
    
    // MARK: - Output Directory Section
    
    private var outputDirectorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Output Directory") {
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
            
            if !viewModel.outputDirectory.isEmpty {
                Text(viewModel.outputDirectory)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
    }
    
    // MARK: - Conversion Settings Section
    
    private var conversionSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Remove orphaned bundles", isOn: $viewModel.removeOrphanedBundles)
                .onChange(of: viewModel.removeOrphanedBundles) { _ in
                    viewModel.saveConfiguration()
                }
            
            Text("Delete app bundles for shortcuts that no longer exist")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Info Section
    
    private var infoSection: some View {
        LabeledContent("Last Conversion") {
            if let lastDate = viewModel.lastConversionDate {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(lastDate, style: .date)
                        .font(.subheadline)
                    Text(lastDate, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Never")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Reset Section
    
    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(role: .destructive) {
                viewModel.resetConfiguration()
            } label: {
                Label("Reset Configuration", systemImage: "arrow.counterclockwise")
            }
            
            Text("Clear all settings and custom names")
                .font(.caption)
                .foregroundColor(.secondary)
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
