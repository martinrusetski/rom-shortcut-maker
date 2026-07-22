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
                .frame(width: 460, height: 420)
        }
    }
}

// MARK: - Menu commands

/// A deliberately short menu, mirroring the in-window controls.
struct AppCommands: Commands {
    @ObservedObject var viewModel: MainViewModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Choose ROM Folder…") {
                if let url = FilePicker.chooseDirectory(title: "Select ROM Folder") {
                    Task { await viewModel.setScanDirectoryAndScan(url) }
                }
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Rescan") { Task { await viewModel.scan() } }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(viewModel.scanDirectory.isEmpty || viewModel.isProcessing)

            Button("Import from Steam…") {
                if let url = FilePicker.chooseFile(title: "Select shortcuts.vdf", extensions: ["vdf"]) {
                    Task { await viewModel.importFromVDF(url: url) }
                }
            }
            .disabled(viewModel.isProcessing)

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
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only apply legacy window height locking for versions older than macOS 13
        if #available(macOS 13.0, *) {
            // Managed by .windowResizability(.contentSize)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let window = NSApplication.shared.windows.first {
                    let currentHeight = window.frame.height
                    window.minSize = NSSize(width: 500, height: currentHeight)
                    window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: currentHeight)
                }
            }
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}



