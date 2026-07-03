//
//  GenerateView.swift
//  SteamShortcutConverter
//

import SwiftUI

struct GenerateView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Generate").font(.title2).fontWeight(.semibold)

            HStack {
                TextField("Output directory", text: $viewModel.outputDirectory)
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") {
                    if let url = FilePicker.chooseDirectory(title: "Select Output Directory") {
                        viewModel.outputDirectory = url.path
                    }
                }
            }

            Toggle("Remove orphaned bundles", isOn: $viewModel.removeOrphanedBundles)

            HStack {
                Button("Generate Bundles") {
                    Task { await viewModel.generate() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canGenerate || viewModel.isProcessing)

                if let date = viewModel.lastConversionDate {
                    Text("Last generated \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }

            if viewModel.isProcessing {
                ProgressView(value: viewModel.progressValue)
                Text(viewModel.progressMessage).font(.caption).foregroundColor(.secondary)
            }

            Divider()

            if let summary = viewModel.conversionSummary {
                summaryPanel(summary)
            } else {
                Text("\(viewModel.games.filter { $0.isSelected }.count) games selected.")
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    private func summaryPanel(_ summary: ConversionSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Summary").font(.headline)
            Text("Created \(summary.bundlesCreated), Updated \(summary.bundlesUpdated), Skipped \(summary.bundlesSkipped), Removed \(summary.bundlesRemoved), \(summary.errors.count) errors")
            ForEach(summary.warnings) { warning in
                Label("\(warning.shortcutName): \(warning.message)", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundColor(.orange)
            }
            ForEach(summary.errors) { error in
                Label("\(error.shortcutName): \(error.message)", systemImage: "xmark.octagon")
                    .font(.caption).foregroundColor(.red)
            }
        }
    }
}
