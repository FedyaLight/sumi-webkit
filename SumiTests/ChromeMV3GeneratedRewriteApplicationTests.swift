import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3GeneratedRewriteApplicationTests: XCTestCase {
    private let fixedInstallDate = Date(timeIntervalSince1970: 1_700_000_000)
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testGateRefusesWhenDryRunReportIsMissing() throws {
        let fixture = try writeBundle(
            named: "rewrite-gate-missing-report",
            manifest: serviceWorkerManifest(),
            files: [
                "background.js": "chrome.runtime.onInstalled.addListener(() => {});\n",
            ]
        )

        let decision = ChromeMV3GeneratedRewriteApplicationGate.evaluate(
            generatedBundleRecord: fixture.result.record,
            generatedBundleRootURL: fixture.result.generatedBundleRootURL,
            runtimeResourcePlan: fixture.runtimeResourcePlan,
            manifestRewritePreview: fixture.preview,
            dryRunReport: nil,
            dryRunDirectoryURL: dryRunRootURL(for: fixture.result)
        )

        XCTAssertFalse(decision.canApplyRewriteVariant)
        XCTAssertTrue(
            decision.blockingReasons.contains("Dry-run verification report is missing.")
        )
        XCTAssertFalse(decision.stillRuntimeLoadable)
    }

    func testGateRefusesWhenCandidateArtifactsAreMissing() throws {
        let fixture = try writeBundle(
            named: "rewrite-gate-missing-artifact",
            manifest: serviceWorkerManifest(),
            files: [
                "background.js": "chrome.runtime.onInstalled.addListener(() => {});\n",
            ]
        )
        try FileManager.default.removeItem(
            at: dryRunRootURL(for: fixture.result)
                .appendingPathComponent("manifest.rewrite-candidate.json")
        )

        let decision = ChromeMV3GeneratedRewriteApplicationGate.evaluate(
            generatedBundleRecord: fixture.result.record,
            generatedBundleRootURL: fixture.result.generatedBundleRootURL,
            runtimeResourcePlan: fixture.runtimeResourcePlan,
            manifestRewritePreview: fixture.preview,
            dryRunReport: fixture.dryRunReport,
            dryRunDirectoryURL: dryRunRootURL(for: fixture.result)
        )

        XCTAssertFalse(decision.canApplyRewriteVariant)
        XCTAssertTrue(
            decision.blockingReasons.contains {
                $0.contains("Missing or invalid dry-run artifact")
                    && $0.contains("manifest.rewrite-candidate.json")
            }
        )
    }

    func testAllowsSafeMinimalDryRunToCreateSeparateRewrittenVariant() throws {
        let fixture = try writeBundle(
            named: "rewrite-minimal",
            manifest: serviceWorkerManifest(),
            files: [
                "background.js": "chrome.runtime.onInstalled.addListener(() => {});\n",
            ]
        )

        let result = try writeVariant(for: fixture)

        XCTAssertTrue(
            result.variantRootURL.path.hasSuffix(
                "/generated/\(fixture.stage.originalBundleRecord.id)/generated-rewritten"
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: result.applicationReportURL.path
            )
        )
        XCTAssertFalse(result.report.runtimeLoadable)
        XCTAssertFalse(result.report.appliedToOriginalGeneratedBundle)
        XCTAssertTrue(result.report.appliedToRewrittenVariant)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.result.generatedBundleRootURL
                    .appendingPathComponent(
                        ChromeMV3GeneratedRewriteVariantWriter.applicationReportFileName
                    )
                    .path
            )
        )
    }

    func testRewrittenVariantManifestReplacesServiceWorkerAndOriginalStaysUnchanged() throws {
        let fixture = try writeBundle(
            named: "rewrite-service-worker",
            manifest: serviceWorkerManifest(),
            files: [
                "background.js": "chrome.runtime.onInstalled.addListener(() => {});\n",
            ]
        )

        let result = try writeVariant(for: fixture)
        let rewrittenManifest = try readJSONObject(at: result.manifestURL)
        let rewrittenBackground = try XCTUnwrap(
            rewrittenManifest["background"] as? [String: Any]
        )
        XCTAssertEqual(
            rewrittenBackground["service_worker"] as? String,
            "_sumi_runtime/service-worker-wrapper.classic.js"
        )

        let originalManifest = try readJSONObject(at: fixture.result.generatedManifestURL)
        let originalBackground = try XCTUnwrap(
            originalManifest["background"] as? [String: Any]
        )
        XCTAssertEqual(originalBackground["service_worker"] as? String, "background.js")
        XCTAssertEqual(
            result.report.runtimeLoadabilityReport.serviceWorkerWrapperPathNowPresentInRewrittenManifest,
            "_sumi_runtime/service-worker-wrapper.classic.js"
        )
    }

    func testRewrittenVariantContentScriptsContainShimPrefixAndOriginalStaysUnchanged() throws {
        let fixture = try writeBundle(
            named: "rewrite-content-script",
            manifest: [
                "manifest_version": 3,
                "name": "Content Script Rewrite",
                "version": "1.0",
                "content_scripts": [
                    [
                        "matches": ["https://example.com/*"],
                        "js": ["content.js"],
                    ],
                ],
            ],
            files: [
                "content.js": "document.documentElement.dataset.sumi = 'content';\n",
            ]
        )

        let result = try writeVariant(for: fixture)
        let rewrittenManifest = try readJSONObject(at: result.manifestURL)
        let rewrittenScripts = try XCTUnwrap(
            rewrittenManifest["content_scripts"] as? [[String: Any]]
        )
        XCTAssertEqual(
            rewrittenScripts.first?["js"] as? [String],
            [
                "_sumi_runtime/chrome-shim.common.js",
                "_sumi_runtime/chrome-shim.content-script.js",
                "content.js",
            ]
        )

        let originalManifest = try readJSONObject(at: fixture.result.generatedManifestURL)
        let originalScripts = try XCTUnwrap(
            originalManifest["content_scripts"] as? [[String: Any]]
        )
        XCTAssertEqual(originalScripts.first?["js"] as? [String], ["content.js"])
        XCTAssertEqual(
            result.report.runtimeLoadabilityReport
                .contentScriptShimPathsNowPresentInRewrittenManifest
                .first?
                .shimPrefixPaths,
            [
                "_sumi_runtime/chrome-shim.common.js",
                "_sumi_runtime/chrome-shim.content-script.js",
            ]
        )
    }

    func testPopupWithHeadIsRewrittenOnlyInVariant() throws {
        let popupHTML = "<!doctype html><html><head><title>Popup</title></head><body></body></html>\n"
        let fixture = try writeBundle(
            named: "rewrite-popup-head",
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

        let result = try writeVariant(for: fixture)
        let rewrittenHTML = try readString(
            at: result.variantRootURL.appendingPathComponent("popup.html")
        )
        XCTAssertTrue(
            rewrittenHTML.contains(
                "<script src=\"_sumi_runtime/chrome-shim.extension-page.js\"></script>\n</head>"
            )
        )
        XCTAssertEqual(
            try readString(
                at: fixture.result.generatedBundleRootURL
                    .appendingPathComponent("popup.html")
            ),
            popupHTML
        )
        XCTAssertTrue(
            result.report.runtimeLoadabilityReport
                .extensionPageShimTagsNowPresentInRewrittenHTML
                .contains {
                    $0.sourceManifestField == "action.default_popup"
                        && $0.shimTagsPresent
                }
        )
    }

    func testPopupWithoutHeadUsesCandidateOnlyInVariant() throws {
        let popupHTML = "<!doctype html><title>Popup</title><body></body>\n"
        let fixture = try writeBundle(
            named: "rewrite-popup-no-head",
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

        let result = try writeVariant(for: fixture)
        let rewrittenHTML = try readString(
            at: result.variantRootURL.appendingPathComponent("popup.html")
        )
        XCTAssertTrue(
            rewrittenHTML.hasPrefix(
                "<script src=\"_sumi_runtime/chrome-shim.extension-page.js\"></script>\n<!doctype html>"
            )
        )
        XCTAssertEqual(
            try readString(
                at: fixture.result.generatedBundleRootURL
                    .appendingPathComponent("popup.html")
            ),
            popupHTML
        )
    }

    func testOptionsPageAndOptionsUIAreRewrittenOnlyInVariant() throws {
        let fixture = try writeBundle(
            named: "rewrite-options",
            manifest: [
                "manifest_version": 3,
                "name": "Options Rewrite",
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

        let result = try writeVariant(for: fixture)
        XCTAssertTrue(
            try readString(
                at: result.variantRootURL.appendingPathComponent("options.html")
            )
            .contains("<script src=\"_sumi_runtime/chrome-shim.extension-page.js\"></script>")
        )
        XCTAssertTrue(
            try readString(
                at: result.variantRootURL.appendingPathComponent("ui/options-ui.html")
            )
            .contains("<script src=\"../_sumi_runtime/chrome-shim.extension-page.js\"></script>")
        )
        XCTAssertFalse(
            try readString(
                at: fixture.result.generatedBundleRootURL.appendingPathComponent("options.html")
            )
            .contains("_sumi_runtime/chrome-shim.extension-page.js")
        )
        XCTAssertFalse(
            try readString(
                at: fixture.result.generatedBundleRootURL
                    .appendingPathComponent("ui/options-ui.html")
            )
            .contains("_sumi_runtime/chrome-shim.extension-page.js")
        )
    }

    func testSidePanelDefaultPathRemainsDeferredPlanningOnly() throws {
        let sidePanelHTML = "<!doctype html><html><head><title>Side</title></head><body></body></html>\n"
        let fixture = try writeBundle(
            named: "rewrite-side-panel",
            manifest: [
                "manifest_version": 3,
                "name": "Side Panel Rewrite",
                "version": "1.0",
                "permissions": ["sidePanel"],
                "side_panel": [
                    "default_path": "sidepanel.html",
                ],
            ],
            files: [
                "sidepanel.html": sidePanelHTML,
            ]
        )

        let result = try writeVariant(for: fixture)
        XCTAssertEqual(
            try readString(
                at: result.variantRootURL.appendingPathComponent("sidepanel.html")
            ),
            sidePanelHTML
        )
        XCTAssertTrue(
            result.report.runtimeLoadabilityReport.copiedOrInjectedExtensionPages
                .contains {
                    $0.sourceManifestField == "side_panel.default_path"
                        && $0.nativeHostPlanningOnly
                        && $0.shimTagsPresent == false
                }
        )
        XCTAssertFalse(result.report.runtimeLoadable)
    }

    func testRuntimeTemplateFilesExistAndReportKeepsVariantNonLoadable() throws {
        let fixture = try writeBundle(
            named: "rewrite-runtime-templates",
            manifest: passwordManagerManifest(),
            files: passwordManagerFiles()
        )

        let result = try writeVariant(for: fixture)
        let runtimeTemplatePaths = fixture.result.record
            .writtenInertRuntimeTemplateResources
            .map(\.outputRelativePath)
            .sorted()
        XCTAssertFalse(runtimeTemplatePaths.isEmpty)
        for path in runtimeTemplatePaths {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: result.variantRootURL.appendingPathComponent(path).path
                ),
                path
            )
        }
        XCTAssertEqual(result.report.copiedRuntimeTemplatePaths, runtimeTemplatePaths)
        XCTAssertFalse(result.report.runtimeLoadable)
        XCTAssertFalse(result.report.executableRuntimeFilesWritten)
        XCTAssertFalse(result.report.runtimeLoadabilityReport.runtimeLoadable)
        XCTAssertFalse(
            result.report.runtimeLoadabilityReport.executableRuntimeFilesWritten
        )
    }

    func testRuntimeLoadabilityReportListsMessagingRuntimeAndWebKitBlockers() throws {
        let fixture = try writeBundle(
            named: "rewrite-blockers",
            manifest: passwordManagerManifest(),
            files: passwordManagerFiles()
        )

        let result = try writeVariant(for: fixture)
        let blockers = result.report.runtimeLoadabilityReport.blockers.joined(separator: "\n")
        XCTAssertTrue(blockers.contains("Runtime messaging is not implemented."))
        XCTAssertTrue(blockers.contains("Native messaging host bridge is not implemented."))
        XCTAssertTrue(blockers.contains("WebKit runtime loading is not yet wired."))
        XCTAssertTrue(blockers.contains("Service-worker wrapper lifecycle is not fixture-verified."))
    }

    func testUnsupportedAndDeferredAPIsKeepRewrittenVariantNonLoadable() throws {
        let fixture = try writeBundle(
            named: "rewrite-unsupported-deferred",
            manifest: [
                "manifest_version": 3,
                "name": "Unsupported Deferred",
                "version": "1.0",
                "permissions": ["debugger", "offscreen"],
                "content_scripts": [
                    [
                        "matches": ["https://example.com/*"],
                        "js": ["content.js"],
                    ],
                ],
            ],
            files: [
                "content.js": "document.documentElement.dataset.sumi = 'unsupported';\n",
            ]
        )

        let result = try writeVariant(for: fixture)
        XCTAssertTrue(result.report.unsupportedAPIs.contains(.debugger))
        XCTAssertTrue(result.report.deferredAPIs.contains(.offscreen))
        XCTAssertFalse(result.report.runtimeLoadable)
        XCTAssertTrue(
            result.report.runtimeLoadabilityReport.blockers.contains(
                "Deferred or unsupported APIs remain unresolved."
            )
        )
    }

    func testPasswordManagerLikeFixtureProducesNonLoadableRewrittenVariant() throws {
        let fixture = try writeBundle(
            named: "rewrite-password-manager",
            manifest: passwordManagerManifest(),
            files: passwordManagerFiles()
        )

        let result = try writeVariant(for: fixture)
        let rewrittenManifest = try readJSONObject(at: result.manifestURL)
        XCTAssertEqual(
            rewrittenManifest["permissions"] as? [String],
            ["nativeMessaging", "storage"]
        )
        XCTAssertTrue(result.report.deferredAPIs.contains(.nativeMessaging))
        XCTAssertFalse(result.report.runtimeLoadable)
        XCTAssertTrue(
            result.report.runtimeLoadabilityReport.blockers.contains(
                "Native messaging host bridge is not implemented."
            )
        )
        XCTAssertTrue(
            result.report.runtimeLoadabilityReport.blockers.contains(
                "Runtime messaging is not implemented."
            )
        )
    }

    func testRepeatedApplicationIsDeterministicAndIdempotent() throws {
        let fixture = try writeBundle(
            named: "rewrite-idempotent",
            manifest: passwordManagerManifest(),
            files: passwordManagerFiles()
        )

        let first = try writeVariant(for: fixture)
        let firstFiles = try fileContents(rootURL: first.variantRootURL)
        let second = try writeVariant(for: fixture)
        let secondFiles = try fileContents(rootURL: second.variantRootURL)

        XCTAssertEqual(firstFiles, secondFiles)
        XCTAssertEqual(first.report, second.report)
    }

    func testNewRewriteApplicationSourceDoesNotReferenceRuntimeObjects() throws {
        let source = try readString(
            at: projectRoot()
                .appendingPathComponent(
                    "Sumi/Models/Extension/ChromeMV3/ChromeMV3GeneratedRewriteApplication.swift"
                )
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
        var stage: ChromeMV3OriginalBundleStageResult
        var result: ChromeMV3GeneratedBundleWriteResult
        var runtimeResourcePlan: ChromeMV3RuntimeResourcePlan
        var preview: ChromeMV3ManifestRewritePreview
        var dryRunReport: ChromeMV3ManifestRewriteDryRunVerificationReport
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
        let runtimeResourcePlan = try JSONDecoder().decode(
            ChromeMV3RuntimeResourcePlan.self,
            from: Data(
                contentsOf: result.generatedBundleRootURL
                    .appendingPathComponent("runtime-resource-plan.json")
            )
        )
        let preview = try JSONDecoder().decode(
            ChromeMV3ManifestRewritePreview.self,
            from: Data(contentsOf: result.manifestRewritePreviewURL)
        )
        let dryRunReport = try JSONDecoder().decode(
            ChromeMV3ManifestRewriteDryRunVerificationReport.self,
            from: Data(contentsOf: result.manifestRewriteDryRunReportURL)
        )
        return WrittenBundleFixture(
            stage: stage,
            result: result,
            runtimeResourcePlan: runtimeResourcePlan,
            preview: preview,
            dryRunReport: dryRunReport
        )
    }

    private func writeVariant(
        for fixture: WrittenBundleFixture
    ) throws -> ChromeMV3GeneratedRewriteVariantWriteResult {
        try ChromeMV3GeneratedRewriteVariantWriter().writeRewrittenVariant(
            generatedBundleRecord: fixture.result.record,
            generatedBundleRootURL: fixture.result.generatedBundleRootURL,
            runtimeResourcePlan: fixture.runtimeResourcePlan,
            manifestRewritePreview: fixture.preview,
            dryRunReport: fixture.dryRunReport
        )
    }

    private func serviceWorkerManifest() -> [String: Any] {
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

    private func dryRunRootURL(
        for result: ChromeMV3GeneratedBundleWriteResult
    ) -> URL {
        result.generatedBundleRootURL
            .appendingPathComponent("_sumi_rewrite_dry_run", isDirectory: true)
    }

    private func fileContents(rootURL: URL) throws -> [String: String] {
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

    private func readString(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

}
