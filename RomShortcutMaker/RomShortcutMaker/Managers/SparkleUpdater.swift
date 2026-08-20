//
//  SparkleUpdater.swift
//  RomShortcutMaker
//
//  In-app auto-updates via Sparkle. The updater reads its feed URL and public
//  EdDSA key from the app's Info.plist (SUFeedURL / SUPublicEDKey), which the
//  release build writes. In a plain `swift run` dev build those keys are absent,
//  so Sparkle simply logs that it cannot check for updates and the app runs on.
//

import SwiftUI
import Sparkle

/// Owns the Sparkle updater for the app's lifetime. `startingUpdater: true`
/// schedules the automatic background check on launch.
final class UpdaterViewModel: ObservableObject {
    let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var updater: SPUUpdater { controller.updater }
}

/// Mirrors Sparkle's `canCheckForUpdates` (KVO) into an `@Published` value so a
/// SwiftUI menu item can disable itself while an update session is in flight.
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    private var observation: NSKeyValueObservation?

    init(updater: SPUUpdater) {
        observation = updater.observe(\.canCheckForUpdates, options: [.initial]) { [weak self] updater, _ in
            self?.canCheckForUpdates = updater.canCheckForUpdates
        }
    }
}

/// The "Check for Updates…" menu command, wired to Sparkle.
struct CheckForUpdatesView: View {
    @StateObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        _viewModel = StateObject(wrappedValue: CheckForUpdatesViewModel(updater: updater))
    }

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!viewModel.canCheckForUpdates)
    }
}
