import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3OriginalBundleStoreTests: XCTestCase {
    private let fixedInstallDate = Date(timeIntervalSince1970: 1_700_000_000)
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testStagesMinimalUnpackedMV3OriginalBundle() throws {
        let fixture = try makeFixture(
            named: "minimal-mv3",
            manifest: minimalManifest(),
            files: [
                "background.js": "chrome.runtime.onInstalled.addListener(() => {});\n",
            ]
        )
        let result = try makeStore().stageUnpackedDirectory(at: fixture)

        XCTAssertTrue(result.originalBundleRecord.id.hasPrefix("unpacked-"))
        XCTAssertEqual(result.originalBundleRecord.manifestName, "Minimal MV3")
        XCTAssertEqual(result.originalBundleRecord.manifestVersion, "1.0.0")
        XCTAssertEqual(result.originalBundleRecord.manifestFormatVersion, 3)
        XCTAssertEqual(result.originalBundleRecord.installDate, fixedInstallDate)
        XCTAssertTrue(result.originalBundleRecord.readOnlyByConvention)
        XCTAssertEqual(result.originalBundleRecord.sourceMetadata.sourceKind, .unpackedDirectory)
        XCTAssertEqual(result.originalBundleRecord.sourceMetadata.fileCount, 2)
        XCTAssertEqual(
            result.originalBundleRecord.packageMetadata.sourceSHA256,
            result.originalBundleRecord.sourceMetadata.contentSHA256
        )
        XCTAssertEqual(
            result.originalBundleRecord.extensionIdentity.derivationInput,
            "unpackedDirectory:\(result.originalBundleRecord.sourceMetadata.contentSHA256)"
        )
        XCTAssertTrue(result.originalBundleRecord.installReport.isValid)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: result.originalBundleRecord.storedPaths.originalBundleRootPath
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: URL(fileURLWithPath: result.originalBundleRecord.storedPaths.originalBundleRootPath)
                    .appendingPathComponent("manifest.json")
                    .path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: URL(fileURLWithPath: result.originalBundleRecord.storedPaths.originalBundleRootPath)
                    .appendingPathComponent("background.js")
                    .path
            )
        )
    }

    func testRejectsAppAndAppexInputPathsBeforeStaging() throws {
        for packageName in ["Legacy.app", "Legacy.appex"] {
            let packageURL = try makeTemporaryDirectory()
                .appendingPathComponent(packageName, isDirectory: true)
            try FileManager.default.createDirectory(
                at: packageURL,
                withIntermediateDirectories: true
            )
            let storeRoot = try makeTemporaryDirectory()

            XCTAssertThrowsError(
                try makeStore(rootURL: storeRoot).stageUnpackedDirectory(at: packageURL)
            ) { error in
                XCTAssertTrue(
                    String(describing: error).contains("Safari .app/.appex")
                )
            }
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: storeRoot.appendingPathComponent("originals").path
                )
            )
        }
    }

    func testRejectsMV2ThroughExistingValidatorBeforeStaging() throws {
        let fixture = try makeFixture(
            named: "mv2",
            manifest: [
                "manifest_version": 2,
                "name": "Legacy MV2",
                "version": "1.0",
                "background": [
                    "scripts": ["background.js"],
                    "persistent": false,
                ],
            ],
            files: [
                "background.js": "",
            ]
        )
        let storeRoot = try makeTemporaryDirectory()

        XCTAssertThrowsError(
            try makeStore(rootURL: storeRoot).stageUnpackedDirectory(at: fixture)
        ) { error in
            XCTAssertTrue(String(describing: error).contains("manifest_version 3"))
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: storeRoot.appendingPathComponent("originals").path
            )
        )
    }

    func testStoresManifestSnapshotDeterministically() throws {
        let fixture = try makeFixture(
            named: "stable-snapshot",
            manifest: passwordManagerManifest(),
            files: passwordManagerFiles()
        )
        let store = try makeStore()

        let first = try store.stageUnpackedDirectory(at: fixture)
        let second = try store.stageUnpackedDirectory(at: fixture)

        XCTAssertEqual(first.manifestSnapshot, second.manifestSnapshot)
        XCTAssertEqual(
            try ChromeMV3DeterministicJSON.encodedString(first.manifestSnapshot),
            try ChromeMV3DeterministicJSON.encodedString(second.manifestSnapshot)
        )
        XCTAssertEqual(
            first.manifestSnapshot.canonicalManifestJSON,
            second.manifestSnapshot.canonicalManifestJSON
        )
        XCTAssertTrue(
            first.manifestSnapshot.canonicalManifestJSON
                .contains("\"manifest_version\":3")
        )

        let persistedSnapshot = try String(
            contentsOf: URL(
                fileURLWithPath: first.originalBundleRecord.storedPaths
                    .manifestSnapshotPath
            ),
            encoding: .utf8
        )
        XCTAssertEqual(
            persistedSnapshot,
            try ChromeMV3DeterministicJSON.encodedString(first.manifestSnapshot)
        )
    }

    func testStoresCapabilityInstallReportBuckets() throws {
        let fixture = try makeFixture(
            named: "unsupported-apis",
            manifest: [
                "manifest_version": 3,
                "name": "Unsupported APIs",
                "version": "1.0",
                "permissions": [
                    "debugger",
                    "enterprise.platformKeys",
                ],
                "devtools_page": "devtools.html",
            ],
            files: [
                "devtools.html": "<!doctype html><title>DevTools</title>\n",
            ]
        )

        let result = try makeStore().stageUnpackedDirectory(at: fixture)
        let report = result.originalBundleRecord.installReport

        XCTAssertTrue(report.unsupportedAPIs.contains(.debugger))
        XCTAssertTrue(report.unsupportedAPIs.contains(.devtools))
        XCTAssertTrue(report.unsupportedAPIs.contains(.enterprise))
        XCTAssertEqual(
            result.manifestSnapshot.capabilitySummary.unsupportedAPIs,
            report.unsupportedAPIs
        )
        XCTAssertTrue(
            report.warnings.contains { issue in
                issue.code == "unsupportedAPI" && issue.field == "debugger"
            }
        )

        let persistedReport = try String(
            contentsOf: URL(
                fileURLWithPath: result.originalBundleRecord.storedPaths
                    .installReportPath
            ),
            encoding: .utf8
        )
        XCTAssertEqual(
            persistedReport,
            try ChromeMV3DeterministicJSON.encodedString(report)
        )
    }

    func testContentScriptFixtureStagesAllFramesAndMatchAboutBlank() throws {
        let fixture = try makeFixture(
            named: "content-script-frames",
            manifest: [
                "manifest_version": 3,
                "name": "Content Script Frames",
                "version": "1.0",
                "content_scripts": [
                    [
                        "matches": ["https://example.com/*"],
                        "js": ["content.js"],
                        "all_frames": true,
                        "match_about_blank": true,
                    ],
                ],
            ],
            files: [
                "content.js": "document.documentElement.dataset.sumiFixture = 'frames';\n",
            ]
        )

        let result = try makeStore().stageUnpackedDirectory(at: fixture)
        let contentScript = try XCTUnwrap(
            result.manifestSnapshot.normalizedManifest.contentScripts.first
        )

        XCTAssertTrue(contentScript.allFrames)
        XCTAssertTrue(contentScript.matchAboutBlank)
        XCTAssertEqual(
            result.manifestSnapshot.installReport.manifestSummary?
                .contentScriptCount,
            1
        )
        XCTAssertTrue(
            result.manifestSnapshot.capabilitySummary.detectedAPIs.contains(
                .scripting
            )
        )
        XCTAssertFalse(result.generatedBundlePlan.plannedServiceWorkerWrapperNeeded)
    }

    func testCreatesGeneratedBundlePlanningRecordWithoutWritingRuntimeFiles() throws {
        let fixture = try makeFixture(
            named: "minimal-planning",
            manifest: minimalManifest(),
            files: [
                "background.js": "",
            ]
        )

        let result = try makeStore().stageUnpackedDirectory(at: fixture)
        let plan = result.generatedBundlePlan

        XCTAssertEqual(
            plan.originalBundleRecordID,
            result.originalBundleRecord.id
        )
        XCTAssertEqual(
            plan.originalBundleContentSHA256,
            result.originalBundleRecord.sourceMetadata.contentSHA256
        )
        XCTAssertEqual(
            plan.generatorVersion,
            ChromeMV3OriginalBundleStore.currentGeneratorVersion
        )
        XCTAssertTrue(plan.plannedManifestRewriteNeeded)
        XCTAssertTrue(plan.plannedServiceWorkerWrapperNeeded)
        XCTAssertTrue(plan.plannedJSShimModules.contains("chrome.runtime"))
        XCTAssertTrue(
            plan.runtimeResourcePlan.requires(.serviceWorkerWrapperClassic)
        )
        XCTAssertTrue(plan.runtimeResourcePlan.requires(.chromeShimCommon))
        XCTAssertTrue(
            plan.runtimeResourcePlan.requires(.chromeShimServiceWorker)
        )
        XCTAssertTrue(plan.runtimeResourcePlan.templatesAreInert)
        XCTAssertFalse(plan.runtimeResourcePlan.runtimeLoadable)
        XCTAssertFalse(plan.runtimeResourcePlan.executableRuntimeFilesWritten)
        XCTAssertFalse(plan.inertRuntimeTemplatesWritten)
        XCTAssertFalse(plan.executableRuntimeFilesWritten)
        XCTAssertFalse(plan.generatedRuntimeFilesWritten)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: plan.generatedBundleRootPlaceholderPath
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: result.originalBundleRecord.storedPaths
                    .generatedBundlePlanPath
            )
        )
    }

    func testPasswordManagerLikeFixtureProducesExpectedFeatureDetection() throws {
        let fixture = try makeFixture(
            named: "password-manager-like",
            manifest: passwordManagerManifest(),
            files: passwordManagerFiles()
        )

        let result = try makeStore().stageUnpackedDirectory(at: fixture)
        let features = result.manifestSnapshot.passwordManagerFeatures

        XCTAssertTrue(features.contentScripts)
        XCTAssertTrue(features.allFrames)
        XCTAssertTrue(features.matchAboutBlank)
        XCTAssertTrue(features.runtimeMessaging)
        XCTAssertTrue(features.nativeMessaging)
        XCTAssertTrue(features.actionPopup)
        XCTAssertTrue(features.storage)
        XCTAssertTrue(features.hostPermissions)
        XCTAssertTrue(
            result.generatedBundlePlan.plannedJSShimModules.contains("chrome.runtime")
        )
        XCTAssertTrue(
            result.generatedBundlePlan.plannedJSShimModules.contains("chrome.storage")
        )
        XCTAssertTrue(
            result.generatedBundlePlan.plannedNativeHostAPIs.contains(.nativeMessaging)
        )
        XCTAssertTrue(result.generatedBundlePlan.deferredAPIs.contains(.nativeMessaging))
        XCTAssertTrue(
            result.generatedBundlePlan.runtimeResourcePlan.requires(.hostBridgeStub)
        )
        XCTAssertTrue(
            result.generatedBundlePlan.runtimeResourcePlan.requires(
                .chromeShimContentScript
            )
        )
        XCTAssertTrue(
            result.generatedBundlePlan.runtimeResourcePlan.requires(
                .chromeShimExtensionPage
            )
        )
    }

    func testUnsafeManifestPathsAreRejectedBeforeStaging() throws {
        let fixture = try makeFixture(
            named: "unsafe-path",
            manifest: [
                "manifest_version": 3,
                "name": "Unsafe Path",
                "version": "1.0",
                "content_scripts": [
                    [
                        "matches": ["https://example.com/*"],
                        "js": ["../content.js"],
                    ],
                ],
            ],
            files: [
                "content.js": "",
            ]
        )
        let storeRoot = try makeTemporaryDirectory()

        XCTAssertThrowsError(
            try makeStore(rootURL: storeRoot).stageUnpackedDirectory(at: fixture)
        ) { error in
            XCTAssertTrue(String(describing: error).contains("Unsafe resource path"))
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: storeRoot.appendingPathComponent("originals").path
            )
        )
    }

    func testUnsafeBundleFilesystemPathsAreRejectedBeforeStaging() throws {
        let fixture = try makeFixture(
            named: "unsafe-filesystem-path",
            manifest: minimalManifest(),
            files: [
                "background.js": "",
            ]
        )
        let escapedLinkURL = fixture.appendingPathComponent("linked-secret.js")
        try FileManager.default.createSymbolicLink(
            at: escapedLinkURL,
            withDestinationURL: URL(fileURLWithPath: "/tmp/secret.js")
        )
        let storeRoot = try makeTemporaryDirectory()

        XCTAssertThrowsError(
            try makeStore(rootURL: storeRoot).stageUnpackedDirectory(at: fixture)
        ) { error in
            XCTAssertTrue(
                String(describing: error).contains("Unsafe extension bundle path")
            )
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: storeRoot.appendingPathComponent("originals").path
            )
        )
    }

    func testOriginalBundleStoreLayerDoesNotReferenceRuntimeObjects() throws {
        _ = try makeStore().stageUnpackedDirectory(
            at: makeFixture(
                named: "no-runtime",
                manifest: minimalManifest(),
                files: [
                    "background.js": "",
                ]
            )
        )

        let source = try String(
            contentsOf: projectRoot()
                .appendingPathComponent(
                    "Sumi/Models/Extension/ChromeMV3/ChromeMV3OriginalBundleStore.swift"
                ),
            encoding: .utf8
        )
        for forbidden in [
            "import " + "WebKit",
            "WKWebExtension" + "Controller(",
            "WKWebExtension" + "Context(",
            "WKWebExtension(",
            "webExtension" + "Controller =",
            "add" + "UserScript",
            "connect" + "Native",
            "Extension" + "Manager(",
            "NativeMessaging" + "Handler(",
        ] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
    }

    private func minimalManifest() -> [String: Any] {
        [
            "manifest_version": 3,
            "name": "Minimal MV3",
            "version": "1.0.0",
            "background": [
                "service_worker": "background.js",
            ],
        ]
    }

    private func passwordManagerManifest() -> [String: Any] {
        [
            "manifest_version": 3,
            "name": "Password Manager Fixture",
            "version": "2.3.4",
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
        ]
    }

    private func passwordManagerFiles() -> [String: String] {
        [
            "background.js": "chrome.runtime.onMessage.addListener(() => {});\n",
            "content.js": "document.documentElement.dataset.sumiFixture = 'password';\n",
            "popup.html": "<!doctype html><title>Password Manager</title>\n",
        ]
    }

    private func makeStore(rootURL: URL? = nil) throws -> ChromeMV3OriginalBundleStore {
        let rootURL = try rootURL ?? makeTemporaryDirectory()
        return ChromeMV3OriginalBundleStore(
            rootURL: rootURL,
            now: { self.fixedInstallDate }
        )
    }

    private func makeFixture(
        named name: String,
        manifest: [String: Any],
        files: [String: String]
    ) throws -> URL {
        let directory = try makeTemporaryDirectory()
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try manifestData.write(
            to: directory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )

        for (relativePath, contents) in files {
            let fileURL = directory.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        return directory
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

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
