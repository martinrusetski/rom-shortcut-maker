//
//  AppResources.swift
//  RomShortcutMaker
//
//  Resolves SwiftPM resources without relying on the generated Bundle.module
//  search paths in a hand-assembled macOS app bundle.
//

import Foundation

enum AppResources {
    static let bundleName = "RomShortcutMaker_RomShortcutMaker.bundle"

    static func url(forResource name: String, withExtension extensionName: String) -> URL? {
        if let url = packagedURL(
            forResource: name,
            withExtension: extensionName,
            mainBundle: .main
        ) {
            return url
        }

        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: name, withExtension: extensionName)
        #else
        return nil
        #endif
    }

    static func packagedURL(
        forResource name: String,
        withExtension extensionName: String,
        mainBundle: Bundle
    ) -> URL? {
        if let url = mainBundle.url(forResource: name, withExtension: extensionName) {
            return url
        }

        let filename = "\(name).\(extensionName)"
        let roots = [mainBundle.resourceURL, mainBundle.bundleURL].compactMap { $0 }

        for root in roots {
            let resourceBundleURL = root.appendingPathComponent(bundleName, isDirectory: true)

            if let resourceBundle = Bundle(url: resourceBundleURL),
               let url = resourceBundle.url(forResource: name, withExtension: extensionName) {
                return url
            }

            let flatURL = resourceBundleURL.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: flatURL.path) {
                return flatURL
            }

            let macOSBundleURL = resourceBundleURL
                .appendingPathComponent("Contents/Resources", isDirectory: true)
                .appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: macOSBundleURL.path) {
                return macOSBundleURL
            }
        }

        return nil
    }
}
