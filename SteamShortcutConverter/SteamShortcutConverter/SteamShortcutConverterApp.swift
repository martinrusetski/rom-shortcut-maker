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
    
    var body: some Scene {
        let group = WindowGroup {
            ContentView()
        }
        
        if #available(macOS 13.0, *) {
            return group.windowResizability(.contentSize)
        } else {
            return group
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



