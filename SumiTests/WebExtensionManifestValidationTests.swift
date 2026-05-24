import XCTest

@testable import Sumi

final class WebExtensionManifestValidationTests: XCTestCase {
    func testManifestVersionTwoIsRejected() throws {
        let manifestURL = try writeManifest([
            "manifest_version": 1 + 1,
            "name": "Legacy Extension",
            "version": "1.0",
        ])

        XCTAssertThrowsError(try ExtensionUtils.validateManifest(at: manifestURL)) { error in
            XCTAssertTrue(String(describing: error).contains("manifest_version 3"))
        }
    }

    func testBackgroundHTMLIsRejected() throws {
        let manifestURL = try writeManifest([
            "manifest_version": 3,
            "name": "Legacy Background",
            "version": "1.0",
            "background": [
                "page": "background.html",
            ],
        ])

        XCTAssertThrowsError(try ExtensionUtils.validateManifest(at: manifestURL)) { error in
            XCTAssertTrue(String(describing: error).contains("Background pages"))
        }
    }

    func testBackgroundScriptsAreRejected() throws {
        let manifestURL = try writeManifest([
            "manifest_version": 3,
            "name": "Legacy Scripts",
            "version": "1.0",
            "background": [
                "scripts": ["background.js"],
                "persistent": false,
            ],
        ])

        XCTAssertThrowsError(try ExtensionUtils.validateManifest(at: manifestURL)) { error in
            XCTAssertTrue(String(describing: error).contains("Background scripts"))
        }
    }

    private func writeManifest(_ manifest: [String: Any]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent("manifest.json")
        let data = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: [.atomic])
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return url
    }
}
