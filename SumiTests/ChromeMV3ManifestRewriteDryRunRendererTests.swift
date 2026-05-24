import CryptoKit
import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3ManifestRewriteDryRunRendererTests: XCTestCase {
    private let fixedInstallDate = Date(timeIntervalSince1970: 1_700_000_000)
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testDryRunCandidateManifestRewritesServiceWorkerButGeneratedManifestStaysUnchanged() throws {
        let fixture = try writeBundle(
            named: "dry-run-minimal-service-worker",
            manifest: minimalServiceWorkerManifest(),
            files: [
                "background.js": "chrome.runtime.onInstalled.addListener(() => {});\n",
            ]
        )

        let generatedManifest = try readJSONObject(at: fixture.result.generatedManifestURL)
        let generatedBackground = try XCTUnwrap(generatedManifest["background"] as? [String: Any])
        XCTAssertEqual(generatedBackground["service_worker"] as? String, "background.js")

        let candidateManifest = try readJSONObject(at: manifestCandidateURL(for: fixture.result))
        let candidateBackground = try XCTUnwrap(candidateManifest["background"] as? [String: Any])
        XCTAssertEqual(
            candidateBackground["service_worker"] as? String,
            "_sumi_runtime/service-worker-wrapper.classic.js"
        )
        XCTAssertFalse(fixture.result.record.runtimeLoadable)
        XCTAssertFalse(fixture.report.runtimeLoadableAfterDryRun)
        XCTAssertFalse(fixture.report.appliedToGeneratedManifest)
        XCTAssertFalse(fixture.report.appliedToGeneratedHTML)
    }

    func testModuleServiceWorkerCandidateUsesModuleWrapperPath() throws {
        let fixture = try writeBundle(
            named: "dry-run-module-service-worker",
            manifest: [
                "manifest_version": 3,
                "name": "Module Worker",
                "version": "1.0",
                "background": [
                    "service_worker": "worker.js",
                    "type": "module",
                ],
            ],
            files: [
                "worker.js": "export {};\n",
            ]
        )

        let candidateManifest = try readJSONObject(at: manifestCandidateURL(for: fixture.result))
        let candidateBackground = try XCTUnwrap(candidateManifest["background"] as? [String: Any])
        XCTAssertEqual(
            candidateBackground["service_worker"] as? String,
            "_sumi_runtime/service-worker-wrapper.module.js"
        )
        XCTAssertEqual(candidateBackground["type"] as? String, "module")

        let generatedManifest = try readJSONObject(at: fixture.result.generatedManifestURL)
        let generatedBackground = try XCTUnwrap(generatedManifest["background"] as? [String: Any])
        XCTAssertEqual(generatedBackground["service_worker"] as? String, "worker.js")
        XCTAssertEqual(generatedBackground["type"] as? String, "module")
    }

    func testClassicServiceWorkerCandidateUsesClassicWrapperPath() throws {
        let fixture = try writeBundle(
            named: "dry-run-classic-service-worker",
            manifest: minimalServiceWorkerManifest(),
            files: [
                "background.js": "chrome.runtime.onMessage.addListener(() => {});\n",
            ]
        )

        let candidateManifest = try readJSONObject(at: manifestCandidateURL(for: fixture.result))
        let candidateBackground = try XCTUnwrap(candidateManifest["background"] as? [String: Any])
        XCTAssertEqual(
            candidateBackground["service_worker"] as? String,
            "_sumi_runtime/service-worker-wrapper.classic.js"
        )
    }

    func testContentScriptShimPrefixAppearsInCandidateOnlyAndOriginalOrderIsPreserved() throws {
        let fixture = try writeBundle(
            named: "dry-run-content-order",
            manifest: [
                "manifest_version": 3,
                "name": "Content Order",
                "version": "1.0",
                "content_scripts": [
                    [
                        "matches": ["https://example.com/*"],
                        "js": ["a.js", "b.js"],
                    ],
                ],
            ],
            files: [
                "a.js": "console.log('a');\n",
                "b.js": "console.log('b');\n",
            ]
        )

        let generatedManifest = try readJSONObject(at: fixture.result.generatedManifestURL)
        let generatedScripts = try XCTUnwrap(generatedManifest["content_scripts"] as? [[String: Any]])
        XCTAssertEqual(generatedScripts.first?["js"] as? [String], ["a.js", "b.js"])

        let candidateManifest = try readJSONObject(at: manifestCandidateURL(for: fixture.result))
        let candidateScripts = try XCTUnwrap(candidateManifest["content_scripts"] as? [[String: Any]])
        XCTAssertEqual(
            candidateScripts.first?["js"] as? [String],
            [
                "_sumi_runtime/chrome-shim.common.js",
                "_sumi_runtime/chrome-shim.content-script.js",
                "a.js",
                "b.js",
            ]
        )
    }

    func testContentScriptMetadataFieldsArePreservedInCandidate() throws {
        let fixture = try writeBundle(
            named: "dry-run-content-metadata",
            manifest: [
                "manifest_version": 3,
                "name": "Content Metadata",
                "version": "1.0",
                "content_scripts": [
                    [
                        "matches": ["https://example.com/*"],
                        "exclude_matches": ["https://example.com/private/*"],
                        "include_globs": ["*example.com/app/*"],
                        "exclude_globs": ["*logout*"],
                        "css": ["content.css"],
                        "js": ["content.js"],
                        "run_at": "document_start",
                        "all_frames": true,
                        "match_about_blank": true,
                        "match_origin_as_fallback": true,
                        "world": "ISOLATED",
                    ],
                ],
            ],
            files: [
                "content.css": "html { color: black; }\n",
                "content.js": "console.log('content');\n",
            ]
        )

        let candidateManifest = try readJSONObject(at: manifestCandidateURL(for: fixture.result))
        let candidateScripts = try XCTUnwrap(candidateManifest["content_scripts"] as? [[String: Any]])
        let script = try XCTUnwrap(candidateScripts.first)
        XCTAssertEqual(script["matches"] as? [String], ["https://example.com/*"])
        XCTAssertEqual(script["exclude_matches"] as? [String], ["https://example.com/private/*"])
        XCTAssertEqual(script["include_globs"] as? [String], ["*example.com/app/*"])
        XCTAssertEqual(script["exclude_globs"] as? [String], ["*logout*"])
        XCTAssertEqual(script["css"] as? [String], ["content.css"])
        XCTAssertEqual(script["run_at"] as? String, "document_start")
        XCTAssertEqual(script["all_frames"] as? Bool, true)
        XCTAssertEqual(script["match_about_blank"] as? Bool, true)
        XCTAssertEqual(script["match_origin_as_fallback"] as? Bool, true)
        XCTAssertEqual(script["world"] as? String, "ISOLATED")
    }

    func testActionPopupWithHeadCandidateInjectsShimBeforeClosingHead() throws {
        let popupHTML = "<!doctype html><html><head><title>Popup</title></head><body><script src=\"popup.js\"></script></body></html>\n"
        let fixture = try writeBundle(
            named: "dry-run-popup-head",
            manifest: [
                "manifest_version": 3,
                "name": "Popup Head",
                "version": "1.0",
                "action": [
                    "default_popup": "popup.html",
                ],
            ],
            files: [
                "popup.html": popupHTML,
            ]
        )

        let artifact = try extensionPageArtifact(
            field: "action.default_popup",
            in: fixture.report
        )
        XCTAssertEqual(artifact.injectionPlacement, .beforeClosingHead)
        let candidateHTML = try candidateHTML(for: artifact, in: fixture.result)
        let shimRange = try XCTUnwrap(candidateHTML.range(of: "<script src=\"_sumi_runtime/chrome-shim.extension-page.js\"></script>"))
        let headRange = try XCTUnwrap(candidateHTML.range(of: "</head>"))
        XCTAssertLessThan(shimRange.lowerBound, headRange.lowerBound)
        XCTAssertEqual(
            try String(
                contentsOf: fixture.result.generatedBundleRootURL
                    .appendingPathComponent("popup.html"),
                encoding: .utf8
            ),
            popupHTML
        )
    }

    func testPopupWithoutHeadUsesDeterministicDocumentStartFallback() throws {
        let popupHTML = "<!doctype html><title>Popup</title><script src=\"popup.js\"></script>\n"
        let fixture = try writeBundle(
            named: "dry-run-popup-no-head",
            manifest: [
                "manifest_version": 3,
                "name": "Popup No Head",
                "version": "1.0",
                "action": [
                    "default_popup": "popup.html",
                ],
            ],
            files: [
                "popup.html": popupHTML,
            ]
        )

        let artifact = try extensionPageArtifact(
            field: "action.default_popup",
            in: fixture.report
        )
        XCTAssertEqual(artifact.injectionPlacement, .documentStartFallbackNoHead)
        let candidateHTML = try candidateHTML(for: artifact, in: fixture.result)
        XCTAssertTrue(
            candidateHTML.hasPrefix(
                "<script src=\"_sumi_runtime/chrome-shim.extension-page.js\"></script>\n<!doctype html>"
            )
        )
    }

    func testOptionsPageAndOptionsUICandidatesAreRendered() throws {
        let fixture = try writeBundle(
            named: "dry-run-options",
            manifest: [
                "manifest_version": 3,
                "name": "Options",
                "version": "1.0",
                "options_page": "options.html",
                "options_ui": [
                    "page": "ui/options-ui.html",
                    "open_in_tab": false,
                ],
            ],
            files: [
                "options.html": "<!doctype html><html><head><title>Options</title></head><body></body></html>\n",
                "ui/options-ui.html": "<!doctype html><html><head><title>Options UI</title></head><body></body></html>\n",
            ]
        )

        let optionsPage = try extensionPageArtifact(field: "options_page", in: fixture.report)
        let optionsUI = try extensionPageArtifact(field: "options_ui.page", in: fixture.report)
        XCTAssertTrue(optionsPage.renderedHTMLCandidate)
        XCTAssertTrue(optionsUI.renderedHTMLCandidate)
        XCTAssertTrue(try candidateHTML(for: optionsPage, in: fixture.result).contains("_sumi_runtime/chrome-shim.extension-page.js"))
        XCTAssertTrue(try candidateHTML(for: optionsUI, in: fixture.result).contains("../_sumi_runtime/chrome-shim.extension-page.js"))
    }

    func testSidePanelCandidateRemainsDeferredPlanningOnly() throws {
        let fixture = try writeBundle(
            named: "dry-run-side-panel",
            manifest: [
                "manifest_version": 3,
                "name": "Side Panel",
                "version": "1.0",
                "permissions": ["sidePanel"],
                "side_panel": [
                    "default_path": "sidepanel.html",
                ],
            ],
            files: [
                "sidepanel.html": "<!doctype html><html><head><title>Side</title></head></html>\n",
            ]
        )

        let artifact = try extensionPageArtifact(
            field: "side_panel.default_path",
            in: fixture.report
        )
        XCTAssertFalse(artifact.renderedHTMLCandidate)
        XCTAssertTrue(artifact.nativeHostPlanningOnly)
        XCTAssertEqual(artifact.injectionPlacement, .planningOnlyDeferred)
        XCTAssertNil(artifact.candidateRelativePath)
        XCTAssertTrue(
            fixture.report.operationsSkipped.contains {
                $0.sourceManifestFields.contains("side_panel.default_path")
            }
        )
        XCTAssertFalse(fixture.report.runtimeLoadableAfterDryRun)
    }

    func testUnsupportedAndDeferredAPIsKeepDryRunNotLoadable() throws {
        let fixture = try writeBundle(
            named: "dry-run-unsupported-deferred",
            manifest: [
                "manifest_version": 3,
                "name": "Unsupported Deferred",
                "version": "1.0",
                "permissions": ["debugger", "offscreen"],
            ],
            files: [:]
        )

        XCTAssertTrue(fixture.report.unsupportedAPIs.contains(.debugger))
        XCTAssertTrue(fixture.report.deferredAPIs.contains(.offscreen))
        XCTAssertFalse(fixture.report.runtimeLoadableAfterDryRun)
        XCTAssertFalse(fixture.report.appliedToGeneratedManifest)
        XCTAssertFalse(fixture.report.appliedToGeneratedHTML)
    }

    func testPasswordManagerFixtureReportsNativeMessagingInertDeferred() throws {
        let fixture = try writeBundle(
            named: "dry-run-password-manager",
            manifest: passwordManagerManifest(),
            files: passwordManagerFiles()
        )

        let candidateManifest = try readJSONObject(at: manifestCandidateURL(for: fixture.result))
        XCTAssertEqual(candidateManifest["permissions"] as? [String], ["nativeMessaging", "storage"])
        XCTAssertEqual(candidateManifest["host_permissions"] as? [String], ["https://*/*"])
        XCTAssertTrue(fixture.report.deferredAPIs.contains(.nativeMessaging))
        XCTAssertTrue(
            fixture.report.operationsRendered.contains {
                $0.type == .recordHostBridgeDeferred
            }
        )
        XCTAssertFalse(fixture.report.runtimeLoadableAfterDryRun)
    }

    func testDryRunArtifactsAreDeterministicAndIdempotent() throws {
        let fixtureDirectory = try makeFixture(
            named: "dry-run-deterministic",
            manifest: passwordManagerManifest(),
            files: passwordManagerFiles()
        )
        let storeRoot = try makeTemporaryDirectory()
        let stage = try ChromeMV3OriginalBundleStore(
            rootURL: storeRoot,
            now: { self.fixedInstallDate }
        ).stageUnpackedDirectory(at: fixtureDirectory)
        let writer = ChromeMV3GeneratedBundleWriter(rootURL: storeRoot)

        let first = try writer.writeGeneratedBundle(
            originalBundleRecord: stage.originalBundleRecord,
            manifestSnapshot: stage.manifestSnapshot,
            planningRecord: stage.generatedBundlePlan
        )
        let firstFiles = try dryRunFileContents(rootURL: dryRunRootURL(for: first))

        let second = try writer.writeGeneratedBundle(
            originalBundleRecord: stage.originalBundleRecord,
            manifestSnapshot: stage.manifestSnapshot,
            planningRecord: stage.generatedBundlePlan
        )
        let secondFiles = try dryRunFileContents(rootURL: dryRunRootURL(for: second))

        XCTAssertEqual(firstFiles, secondFiles)
    }

    func testGeneratedBundleMetadataReferencesDryRunReportWithoutRuntimeLoadability() throws {
        let fixture = try writeBundle(
            named: "dry-run-metadata-reference",
            manifest: passwordManagerManifest(),
            files: passwordManagerFiles()
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(
            ChromeMV3GeneratedBundleRecord.self,
            from: Data(contentsOf: fixture.result.generatedMetadataURL)
        )
        let reportData = try Data(contentsOf: fixture.result.manifestRewriteDryRunReportURL)
        XCTAssertEqual(metadata.manifestRewriteDryRunReportPath, fixture.result.manifestRewriteDryRunReportURL.path)
        XCTAssertEqual(metadata.manifestRewriteDryRunReportSHA256, sha256Hex(reportData))
        XCTAssertEqual(metadata.manifestRewriteDryRunDirectoryPath, dryRunRootURL(for: fixture.result).path)
        XCTAssertFalse(metadata.runtimeLoadable)
    }

    func testRealGeneratedManifestAndHTMLFilesAreUnchangedAfterDryRun() throws {
        let popupHTML = "<!doctype html><title>Password Manager</title>\n"
        let fixture = try writeBundle(
            named: "dry-run-real-files-unchanged",
            manifest: passwordManagerManifest(),
            files: [
                "background.js": "chrome.runtime.onMessage.addListener(() => {});\n",
                "content.js": "document.documentElement.dataset.sumiFixture = 'password';\n",
                "popup.html": popupHTML,
            ]
        )

        let generatedManifest = try readJSONObject(at: fixture.result.generatedManifestURL)
        let generatedBackground = try XCTUnwrap(generatedManifest["background"] as? [String: Any])
        let generatedScripts = try XCTUnwrap(generatedManifest["content_scripts"] as? [[String: Any]])
        XCTAssertEqual(generatedBackground["service_worker"] as? String, "background.js")
        XCTAssertEqual(generatedScripts.first?["js"] as? [String], ["content.js"])
        XCTAssertEqual(
            try String(
                contentsOf: fixture.result.generatedBundleRootURL
                    .appendingPathComponent("popup.html"),
                encoding: .utf8
            ),
            popupHTML
        )
    }

    func testDryRunRendererSourceDoesNotConstructRuntimeObjects() throws {
        let source = try String(
            contentsOf: projectRoot()
                .appendingPathComponent(
                    "Sumi/Models/Extension/ChromeMV3/ChromeMV3ManifestRewriteDryRunRenderer.swift"
                ),
            encoding: .utf8
        )
        for forbidden in [
            "import " + "WebKit",
            "WKWebExtension" + "Controller",
            "WKWebExtension" + "Context",
            "WK" + "WebExtension(",
            "webExtension" + "Controller",
            "add" + "UserScript",
            "connect" + "Native",
            "NativeMessaging" + "Handler(",
        ] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
    }

    private struct WrittenBundleFixture {
        var result: ChromeMV3GeneratedBundleWriteResult
        var report: ChromeMV3ManifestRewriteDryRunVerificationReport
    }

    private func writeBundle(
        named name: String,
        manifest: [String: Any],
        files: [String: String]
    ) throws -> WrittenBundleFixture {
        let fixture = try makeFixture(
            named: name,
            manifest: manifest,
            files: files
        )
        let storeRoot = try makeTemporaryDirectory()
        let stage = try ChromeMV3OriginalBundleStore(
            rootURL: storeRoot,
            now: { self.fixedInstallDate }
        ).stageUnpackedDirectory(at: fixture)
        let result = try ChromeMV3GeneratedBundleWriter(rootURL: storeRoot)
            .writeGeneratedBundle(
                originalBundleRecord: stage.originalBundleRecord,
                manifestSnapshot: stage.manifestSnapshot,
                planningRecord: stage.generatedBundlePlan
            )
        let report = try JSONDecoder().decode(
            ChromeMV3ManifestRewriteDryRunVerificationReport.self,
            from: Data(contentsOf: result.manifestRewriteDryRunReportURL)
        )
        return WrittenBundleFixture(result: result, report: report)
    }

    private func minimalServiceWorkerManifest() -> [String: Any] {
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
                    "match_origin_as_fallback": true,
                    "run_at": "document_start",
                    "world": "ISOLATED",
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

    private func manifestCandidateURL(
        for result: ChromeMV3GeneratedBundleWriteResult
    ) -> URL {
        dryRunRootURL(for: result)
            .appendingPathComponent("manifest.rewrite-candidate.json")
    }

    private func dryRunRootURL(
        for result: ChromeMV3GeneratedBundleWriteResult
    ) -> URL {
        result.generatedBundleRootURL
            .appendingPathComponent("_sumi_rewrite_dry_run", isDirectory: true)
    }

    private func extensionPageArtifact(
        field: String,
        in report: ChromeMV3ManifestRewriteDryRunVerificationReport
    ) throws -> ChromeMV3ExtensionPageRewriteCandidateArtifact {
        try XCTUnwrap(
            report.extensionPageArtifacts.first {
                $0.sourceManifestField == field
            }
        )
    }

    private func candidateHTML(
        for artifact: ChromeMV3ExtensionPageRewriteCandidateArtifact,
        in result: ChromeMV3GeneratedBundleWriteResult
    ) throws -> String {
        let relativePath = try XCTUnwrap(artifact.candidateRelativePath)
        return try String(
            contentsOf: dryRunRootURL(for: result)
                .appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func dryRunFileContents(rootURL: URL) throws -> [String: String] {
        let resolvedRootURL = rootURL.resolvingSymlinksInPath()
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: resolvedRootURL,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
        )
        let rootPath = resolvedRootURL.path.hasSuffix("/")
            ? resolvedRootURL.path
            : resolvedRootURL.path + "/"
        var contents: [String: String] = [:]

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let relativePath = String(
                url.resolvingSymlinksInPath().path.dropFirst(rootPath.count)
            )
            contents[relativePath] = try String(contentsOf: url, encoding: .utf8)
        }

        return contents
    }

    private func readJSONObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
