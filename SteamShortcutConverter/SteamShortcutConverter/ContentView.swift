//
//  ContentView.swift
//  SteamShortcutConverter
//
//  Rom Shortcut Maker — tabbed scan / artwork / generate / settings UI.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var viewModel = MainViewModel()

    var body: some View {
        TabView {
            ScanView(viewModel: viewModel)
                .tabItem { Label("Scan", systemImage: "magnifyingglass") }

            ArtworkView(viewModel: viewModel)
                .tabItem { Label("Artwork", systemImage: "photo") }

            GenerateView(viewModel: viewModel)
                .tabItem { Label("Generate", systemImage: "hammer") }

            SettingsView(viewModel: viewModel)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .frame(minWidth: 820, minHeight: 560)
        .task { await viewModel.load() }
        .alert("Something went wrong",
               isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
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
