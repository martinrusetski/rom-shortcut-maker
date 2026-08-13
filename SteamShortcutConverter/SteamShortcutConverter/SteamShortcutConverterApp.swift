//
//  SteamShortcutConverterApp.swift
//  SteamShortcutConverter
//
//  Main application entry point for Steam Shortcut to App Bundle Converter
//

import SwiftUI

@main
struct SteamShortcutConverterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Owned here (not in ContentView) so the main window, the Settings scene, and
    // the Game Properties window all share one instance.
    @StateObject private var viewModel = MainViewModel()

    // Sparkle auto-updater, owned for the app's lifetime.
    @StateObject private var updaterViewModel = UpdaterViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterViewModel.updater)
            }
            AppCommands(viewModel: viewModel)
        }

        Settings {
            SettingsView(viewModel: viewModel)
                .frame(width: 560, height: 560)
        }
    }
}

// MARK: - Menu commands

/// A deliberately short menu for library-wide actions.
struct AppCommands: Commands {
    @ObservedObject var viewModel: MainViewModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Rescan") { Task { await viewModel.scan() } }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(viewModel.watchedFolders.isEmpty || viewModel.isProcessing)

            Divider()

            Button("Generate Bundles") { Task { await viewModel.generate() } }
                .disabled(!viewModel.canGenerate || viewModel.isProcessing)

            Button("Game Properties") {
                if let id = viewModel.selection.first { viewModel.propertiesGameID = id }
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(viewModel.selection.isEmpty)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

