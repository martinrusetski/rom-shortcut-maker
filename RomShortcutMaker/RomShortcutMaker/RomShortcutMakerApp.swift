//
//  RomShortcutMakerApp.swift
//  RomShortcutMaker
//
//  Main application entry point for Steam Shortcut to App Bundle Converter
//

import SwiftUI
import Darwin

@main
struct RomShortcutMakerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Owned here (not in ContentView) so the main window, the Settings scene, and
    // the Game Properties window all share one instance.
    @StateObject private var viewModel: MainViewModel

    // Sparkle auto-updater, owned for the app's lifetime.
    @StateObject private var updaterViewModel: UpdaterViewModel

    init() {
        if CommandLine.arguments.contains("--validate-resources") {
            do {
                _ = try SystemDatabase()
                guard AppResources.url(
                    forResource: "DefaultShortcutIcon",
                    withExtension: "icns"
                ) != nil else {
                    throw AppResourceValidationError.defaultShortcutIconMissing
                }
                print("Packaged resources validated.")
                Darwin.exit(EXIT_SUCCESS)
            } catch {
                let message = "Packaged resource validation failed: \(error.localizedDescription)\n"
                FileHandle.standardError.write(Data(message.utf8))
                Darwin.exit(EXIT_FAILURE)
            }
        }

        _viewModel = StateObject(wrappedValue: MainViewModel())
        _updaterViewModel = StateObject(wrappedValue: UpdaterViewModel())
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Rom Shortcut Maker") {
                    appDelegate.showAboutWindow()
                }
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterViewModel.updater)
            }
            CommandGroup(replacing: .help) {
                Link("Rom Shortcut Maker Help",
                     destination: URL(string: "https://github.com/martinrusetski/rom-shortcut-maker#readme")!)
            }
            AppCommands(viewModel: viewModel)
        }

        Settings {
            SettingsView(viewModel: viewModel)
                .frame(width: 560, height: 560)
        }
    }
}

private enum AppResourceValidationError: LocalizedError {
    case defaultShortcutIconMissing

    var errorDescription: String? {
        "DefaultShortcutIcon.icns resource not found in packaged app."
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

            Button("Create Shortcuts") { Task { await viewModel.generate() } }
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
    private lazy var aboutWindowController = AboutWindowController()

    func showAboutWindow() {
        aboutWindowController.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
