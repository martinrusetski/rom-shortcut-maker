import Foundation
import XCTest
@testable import RomShortcutMaker

final class AppResourcesTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppResourcesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testFindsResourceInFlatSwiftPMBundle() throws {
        let mainBundle = try makeAppBundle()
        let resourceURL = try writeResource(
            relativePath: "Contents/Resources/\(AppResources.bundleName)/emulators.json"
        )

        XCTAssertEqual(
            AppResources.packagedURL(
                forResource: "emulators",
                withExtension: "json",
                mainBundle: mainBundle
            )?.standardizedFileURL,
            resourceURL.standardizedFileURL
        )
    }

    func testFindsResourceInMacOSStyleSwiftPMBundle() throws {
        let mainBundle = try makeAppBundle()
        let resourceURL = try writeResource(
            relativePath: "Contents/Resources/\(AppResources.bundleName)/Contents/Resources/emulators.json"
        )

        XCTAssertEqual(
            AppResources.packagedURL(
                forResource: "emulators",
                withExtension: "json",
                mainBundle: mainBundle
            )?.standardizedFileURL,
            resourceURL.standardizedFileURL
        )
    }

    func testFindsResourceBundleAtCommandLineSwiftPMLocation() throws {
        let mainBundle = try makeAppBundle()
        let resourceURL = try writeResource(
            relativePath: "\(AppResources.bundleName)/emulators.json"
        )

        XCTAssertEqual(
            AppResources.packagedURL(
                forResource: "emulators",
                withExtension: "json",
                mainBundle: mainBundle
            )?.standardizedFileURL,
            resourceURL.standardizedFileURL
        )
    }

    private func makeAppBundle() throws -> Bundle {
        let contentsURL = temporaryDirectory.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        let info: [String: Any] = [
            "CFBundleIdentifier": "com.romshortcutmaker.tests.resources",
            "CFBundleName": "AppResourcesTests",
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1"
        ]
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try infoData.write(to: contentsURL.appendingPathComponent("Info.plist"))

        return try XCTUnwrap(Bundle(url: temporaryDirectory))
    }

    private func writeResource(relativePath: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: url)
        return url
    }
}
