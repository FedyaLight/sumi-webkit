import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3InstallFoundationTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testAcceptsMinimalValidMV3ManifestWithServiceWorker() throws {
        let manifestURL = try writeManifest([
            "manifest_version": 3,
            "name": "Minimal MV3",
            "version": "1.0.0",
            "background": [
                "service_worker": "background.js",
            ],
        ])

        let manifest = try ChromeMV3ManifestValidator.validateManifestFile(
            at: manifestURL
        )
        let report = ChromeMV3InstallReporter.report(for: manifest)

        XCTAssertEqual(manifest.manifestVersion, 3)
        XCTAssertEqual(manifest.background?.serviceWorker, "background.js")
        XCTAssertTrue(report.isValid)
        XCTAssertEqual(report.detectedAPIs, [.runtime])
        XCTAssertTrue(report.supportedAPIs.contains(.runtime))
        XCTAssertTrue(report.shimmedAPIs.contains(.runtime))
    }

    func testRejectsManifestVersionTwo() throws {
        let manifestURL = try writeManifest([
            "manifest_version": 2,
            "name": "Legacy MV2",
            "version": "1.0",
        ])

        XCTAssertThrowsError(
            try ChromeMV3ManifestValidator.validateManifestFile(at: manifestURL)
        ) { error in
            XCTAssertTrue(String(describing: error).contains("manifest_version 3"))
        }
    }

    func testRejectsBackgroundPage() throws {
        let manifestURL = try writeManifest([
            "manifest_version": 3,
            "name": "Legacy Background Page",
            "version": "1.0",
            "background": [
                "page": "background.html",
            ],
        ])

        XCTAssertThrowsError(
            try ChromeMV3ManifestValidator.validateManifestFile(at: manifestURL)
        ) { error in
            XCTAssertTrue(String(describing: error).contains("Background pages"))
        }
    }

    func testRejectsBackgroundScripts() throws {
        let manifestURL = try writeManifest([
            "manifest_version": 3,
            "name": "Legacy Background Scripts",
            "version": "1.0",
            "background": [
                "scripts": ["background.js"],
            ],
        ])

        XCTAssertThrowsError(
            try ChromeMV3ManifestValidator.validateManifestFile(at: manifestURL)
        ) { error in
            XCTAssertTrue(String(describing: error).contains("Background scripts"))
        }
    }

    func testRejectsMissingManifestVersion() throws {
        let manifestURL = try writeManifest([
            "name": "Missing Version",
            "version": "1.0",
        ])

        XCTAssertThrowsError(
            try ChromeMV3ManifestValidator.validateManifestFile(at: manifestURL)
        ) { error in
            XCTAssertTrue(String(describing: error).contains("Missing manifest_version"))
        }
    }

    func testRejectsInvalidJSON() throws {
        let directory = try makeTemporaryDirectory()
        let manifestURL = directory.appendingPathComponent("manifest.json")
        try "{".write(to: manifestURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try ChromeMV3ManifestValidator.validateManifestFile(at: manifestURL)
        ) { error in
            XCTAssertTrue(String(describing: error).contains("Invalid manifest.json"))
        }
    }

    func testRejectsMissingManifest() throws {
        let directory = try makeTemporaryDirectory()

        XCTAssertThrowsError(
            try ChromeMV3ManifestValidator.validatePackage(
                at: directory,
                sourceKind: .unpackedDirectory
            )
        ) { error in
            XCTAssertTrue(String(describing: error).contains("Missing manifest.json"))
        }

        let report = ChromeMV3InstallInspector.inspectUnpackedDirectory(
            at: directory
        )
        XCTAssertFalse(report.isValid)
        XCTAssertEqual(report.fatalValidationErrors.first?.code, "missingManifest")
    }

    func testRejectsSafariPackageInputs() throws {
        let packageURL = try makeTemporaryDirectory()
            .appendingPathComponent("Legacy.appex", isDirectory: true)
        try FileManager.default.createDirectory(
            at: packageURL,
            withIntermediateDirectories: true
        )

        XCTAssertThrowsError(
            try ChromeMV3ManifestValidator.validatePackage(
                at: packageURL,
                sourceKind: .unpackedDirectory
            )
        ) { error in
            XCTAssertTrue(String(describing: error).contains(".app/.appex"))
        }
    }

    func testRejectsUnsafePathTraversalInDeclaredResources() throws {
        let cases: [[String: Any]] = [
            [
                "manifest_version": 3,
                "name": "Unsafe Service Worker",
                "version": "1.0",
                "background": ["service_worker": "../background.js"],
            ],
            [
                "manifest_version": 3,
                "name": "Unsafe Content Script",
                "version": "1.0",
                "content_scripts": [
                    [
                        "matches": ["https://example.com/*"],
                        "js": ["scripts/../../inject.js"],
                    ],
                ],
            ],
            [
                "manifest_version": 3,
                "name": "Unsafe Options Page",
                "version": "1.0",
                "options_ui": ["page": "../options.html"],
            ],
            [
                "manifest_version": 3,
                "name": "Unsafe Action Popup",
                "version": "1.0",
                "action": ["default_popup": "/popup.html"],
            ],
        ]

        for manifest in cases {
            let manifestURL = try writeManifest(manifest)
            XCTAssertThrowsError(
                try ChromeMV3ManifestValidator.validateManifestFile(
                    at: manifestURL
                )
            ) { error in
                XCTAssertTrue(String(describing: error).contains("Unsafe resource path"))
            }
        }
    }

    func testMarksDebuggerDevtoolsAndEnterpriseUnsupported() throws {
        let manifest = try validateManifest([
            "manifest_version": 3,
            "name": "Unsupported APIs",
            "version": "1.0",
            "permissions": [
                "debugger",
                "enterprise.platformKeys",
            ],
            "devtools_page": "devtools.html",
        ])

        let report = ChromeMV3InstallReporter.report(for: manifest)

        XCTAssertTrue(report.unsupportedAPIs.contains(.debugger))
        XCTAssertTrue(report.unsupportedAPIs.contains(.devtools))
        XCTAssertTrue(report.unsupportedAPIs.contains(.enterprise))
    }

    func testMarksSidePanelOffscreenAndIdentityConservatively() throws {
        let manifest = try validateManifest([
            "manifest_version": 3,
            "name": "Deferred APIs",
            "version": "1.0",
            "permissions": [
                "sidePanel",
                "offscreen",
                "identity",
            ],
            "side_panel": [
                "default_path": "side-panel.html",
            ],
        ])

        let report = ChromeMV3InstallReporter.report(for: manifest)

        XCTAssertTrue(report.deferredAPIs.contains(.sidePanel))
        XCTAssertTrue(report.deferredAPIs.contains(.offscreen))
        XCTAssertTrue(report.deferredAPIs.contains(.identity))
        XCTAssertTrue(report.nativeHostAPIs.contains(.sidePanel))
        XCTAssertTrue(report.nativeHostAPIs.contains(.identity))
        XCTAssertTrue(report.needsVerificationAPIs.contains(.offscreen))
    }

    func testDetectsPasswordManagerRelevantManifestFeatures() throws {
        let manifest = try validateManifest([
            "manifest_version": 3,
            "name": "Password Manager Fixture",
            "version": "1.0",
            "background": [
                "service_worker": "background.js",
            ],
            "permissions": [
                "nativeMessaging",
                "storage",
            ],
            "host_permissions": [
                "https://*/*",
            ],
            "content_scripts": [
                [
                    "matches": ["https://*/*"],
                    "js": ["content.js"],
                    "all_frames": true,
                    "match_about_blank": true,
                ],
            ],
            "action": [
                "default_popup": "popup.html",
            ],
        ])

        let features = ChromeMV3InstallReporter.report(
            for: manifest
        ).passwordManagerFeatures

        XCTAssertTrue(features.contentScripts)
        XCTAssertTrue(features.allFrames)
        XCTAssertTrue(features.matchAboutBlank)
        XCTAssertTrue(features.runtimeMessaging)
        XCTAssertTrue(features.nativeMessaging)
        XCTAssertTrue(features.actionPopup)
        XCTAssertTrue(features.storage)
        XCTAssertTrue(features.hostPermissions)
    }

    func testProducesStableInstallReport() throws {
        let manifest = try validateManifest([
            "manifest_version": 3,
            "name": "Stable Report",
            "version": "1.2.3",
            "background": [
                "service_worker": "background.js",
                "type": "module",
            ],
            "permissions": [
                "nativeMessaging",
                "storage",
            ],
            "host_permissions": [
                "https://example.com/*",
            ],
            "content_scripts": [
                [
                    "matches": ["https://example.com/*"],
                    "js": ["content.js"],
                ],
            ],
            "action": [
                "default_popup": "popup.html",
            ],
            "browser_specific_settings": [
                "gecko": ["id": "stable@example.com"],
            ],
        ])
        let metadata = ChromeMV3PackageMetadata(
            extensionIdentity: ChromeMV3ExtensionIdentity(
                id: nil,
                derivationInput: "stable-manifest-hash"
            ),
            originalBundlePath: "/fixtures/stable-report",
            originalBundleLastPathComponent: "stable-report",
            sourceKind: .unpackedDirectory,
            generatedBundlePath: nil,
            installDate: nil,
            installedVersion: "1.2.3",
            sourceSHA256: nil,
            manifestSHA256: "stable-manifest-hash"
        )

        let first = ChromeMV3InstallReporter.report(
            for: manifest,
            packageMetadata: metadata
        )
        let second = ChromeMV3InstallReporter.report(
            for: manifest,
            packageMetadata: metadata
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(try encoded(first), try encoded(second))
        XCTAssertEqual(first.manifestSummary?.backgroundServiceWorker, "background.js")
        XCTAssertTrue(first.nativeHostAPIs.contains(.nativeMessaging))
        XCTAssertTrue(first.deferredAPIs.contains(.nativeMessaging))
    }

    func testValidationAndClassificationLayerDoesNotConstructRuntimeObjects() throws {
        let manifest = try validateManifest([
            "manifest_version": 3,
            "name": "No Runtime Construction",
            "version": "1.0",
            "background": [
                "service_worker": "background.js",
            ],
        ])

        _ = ChromeMV3InstallReporter.report(for: manifest)

        let foundationSource = try chromeMV3FoundationSource()
        XCTAssertFalse(foundationSource.contains("import WebKit"))
        XCTAssertFalse(foundationSource.contains("WKWebExtension" + "Controller("))
        XCTAssertFalse(foundationSource.contains("WKWebExtension" + "Context("))
        XCTAssertFalse(foundationSource.contains("WKWebExtension" + "("))
        XCTAssertFalse(foundationSource.contains("ExtensionManager("))
        XCTAssertFalse(foundationSource.contains("WKUser" + "Script("))
        XCTAssertFalse(foundationSource.contains("NativeMessagingHandler("))
    }

    private func validateManifest(_ manifest: [String: Any]) throws -> ChromeMV3Manifest {
        let manifestURL = try writeManifest(manifest)
        return try ChromeMV3ManifestValidator.validateManifestFile(at: manifestURL)
    }

    private func writeManifest(_ manifest: [String: Any]) throws -> URL {
        let directory = try makeTemporaryDirectory()
        let url = directory.appendingPathComponent("manifest.json")
        let data = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: [.atomic])
        return url
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)
        return directory
    }

    private func encoded(_ report: ChromeMV3InstallReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(report)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func chromeMV3FoundationSource() throws -> String {
        let directory = projectRoot()
            .appendingPathComponent("Sumi/Models/Extension/ChromeMV3")
        return try [
            "ChromeMV3Manifest.swift",
            "ChromeMV3ManifestValidator.swift",
            "ChromeMV3CapabilityClassifier.swift",
            "ChromeMV3InstallReport.swift",
        ]
        .map {
            try String(
                contentsOf: directory.appendingPathComponent($0),
                encoding: .utf8
            )
        }
        .joined(separator: "\n")
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
