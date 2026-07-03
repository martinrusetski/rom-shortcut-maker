//
//  ScanView.swift
//  SteamShortcutConverter
//

import SwiftUI

struct ScanView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack {
                Picker("Source", selection: $viewModel.sourceMode) {
                    Text("Scan ROM Directory").tag(MainViewModel.SourceMode.scan)
                    Text("Import from Steam VDF").tag(MainViewModel.SourceMode.vdf)
                }
                .pickerStyle(.segmented)
                .frame(width: 360)
                Spacer()
            }

            if viewModel.sourceMode == .scan {
                scanControls
            } else {
                vdfControls
            }

            if viewModel.isProcessing {
                ProgressView(value: viewModel.progressValue)
            }
            if !viewModel.progressMessage.isEmpty {
                Text(viewModel.progressMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Divider()
            gameList
        }
        .padding()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Rom Shortcut Maker").font(.title2).fontWeight(.semibold)
            Text("Generate native macOS app bundles for your ROMs")
                .font(.subheadline).foregroundColor(.secondary)
        }
    }

    private var scanControls: some View {
        HStack {
            TextField("ROM directory", text: $viewModel.scanDirectory)
                .textFieldStyle(.roundedBorder)
            Button("Choose…") {
                if let url = FilePicker.chooseDirectory(title: "Select ROM Directory") {
                    viewModel.scanDirectory = url.path
                }
            }
            Button("Scan") {
                Task { await viewModel.scan() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.scanDirectory.isEmpty || viewModel.isProcessing)
        }
    }

    private var vdfControls: some View {
        HStack {
            Text("Import shortcuts.vdf from your Steam userdata.")
                .foregroundColor(.secondary)
            Spacer()
            Button("Import…") {
                if let url = FilePicker.chooseFile(title: "Select shortcuts.vdf", extensions: ["vdf"]) {
                    Task { await viewModel.importFromVDF(url: url) }
                }
            }
            .disabled(viewModel.isProcessing)
        }
    }

    private var gameList: some View {
        Group {
            if viewModel.games.isEmpty {
                VStack {
                    Spacer()
                    Text("No games yet — scan a ROM directory to begin.")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(viewModel.games) { game in
                    GameRow(viewModel: viewModel, game: game)
                }
            }
        }
    }
}
