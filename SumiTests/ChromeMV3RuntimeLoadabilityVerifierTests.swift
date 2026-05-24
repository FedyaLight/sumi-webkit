import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3RuntimeLoadabilityVerifierTests: XCTestCase {
    private let fixedInstallDate = Date(timeIntervalSince1970: 1_700_000_000)
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testMinimalRewrittenVariantPassesStructuralChecksButRemainsNonLoadable() throws {
        let fixture = try writeBundle(
            named: "loadability-minimal",
            manifest: serviceWorkerManifest(),
            files: [
                "background.js": "chrome.runtime.onInstalled.addListener(() => {});\n",
            ]
        )

        let variant = try writeVariant(for: fixture)
        let report = try readReport(from: variant.variantRootURL)

        XCTAssertEqual(
            variant.variantRootURL
                .appendingPathComponent(
                    ChromeMV3RuntimeLoadabilityVerifier.reportFileName
                )
                .path,
            variant.variantRootURL
                .appendingPathComponent("runtime-loadability-report.json")
                .path
        )
        XCTAssertFalse(report.runtimeLoadable)
        XCTAssertTrue(report.readOnlyStaticInspection)
        XCTAssertTrue(report.structurallyValid)
        XCTAssertTrue(report.passedChecks.contains(.manifestShape))
        XCTAssertTrue(report.passedChecks.contains(.serviceWorkerWrapperReference))
        XCTAssertTrue(report.passedChecks.contains(.serviceWorkerWrapperTemplatePresence))
        XCTAssertTrue(report.deferredChecks.contains(.runtimeMessagingNotImplemented))
        XCTAssertTrue(report.deferredChecks.contains(.WebKitRuntimeNotWired))
        XCTAssertEqual(report.generatedVariantRootRelativeName, "generated-rewritten")
    }

    func testMissingWrapperFileFailsVerification() throws {
        let fixture = try writeBundle(
            named: "loadability-missing-wrapper",
            manifest: serviceWorkerManifest(),
            files: [
                "background.js": "chrome.runtime.onInstalled.addListener(() => {});\n",
            ]
        )
        let variant = try writeVariant(for: fixture)
        try FileManager.default.removeItem(
            at: variant.variantRootURL
                .appendingPathComponent("_sumi_runtime/service-worker-wrapper.classic.js")
        )

        let report = try ChromeMV3RuntimeLoadabilityVerifier()
            .verifyRewrittenVariant(at: variant.variantRootURL)

        XCTAssertFalse(report.structurallyValid)
        XCTAssertTrue(report.failedChecks.contains(.serviceWorkerWrapperTemplatePresence))
        XCTAssertTrue(
            report.missing.contains("_sumi_runtime/service-worker-wrapper.classic.js")
        )
    }

    func testModuleClassicWrapperMismatchFailsDeterministically() throws {
        let fixture = try writeBundle(
            named: "loadability-wrapper-mismatch",
            manifest: [
                "manifest_version": 3,
                "name": "Module Worker",
                "version": "1.0",
                "background": [
                    "service_worker": "background.js",
                    "type": "module",
                ],
            ],
            files: [
                "background.js": "export {};\n",
            ]
        )
        let variant = try writeVariant(for: fixture)
        var manifest = try readJSONObject(
            at: variant.variantRootURL.appendingPathComponent("manifest.json")
        )
        var background = try XCTUnwrap(manifest["background"] as? [String: Any])
        background["service_worker"] = "_sumi_runtime/service-worker-wrapper.classic.js"
        manifest["background"] = background
        try writeJSONObject(
            manifest,
            to: variant.variantRootURL.appendingPathComponent("manifest.json")
        )

        let first = try ChromeMV3RuntimeLoadabilityVerifier()
            .verifyRewrittenVariant(at: variant.variantRootURL)
        let second = try ChromeMV3RuntimeLoadabilityVerifier()
            .verifyRewrittenVariant(at: variant.variantRootURL)

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.failedChecks.contains(.serviceWorkerWrapperReference))
        XCTAssertTrue(
            check(.serviceWorkerWrapperReference, in: first)?
                .details
                .contains("expected: _sumi_runtime/service-worker-wrapper.module.js")
                == true
        )
    }

    func testContentScriptShimPrefixOrderAndMetadataPreservationAreVerified() throws {
        let fixture = try writeBundle(
            named: "loadability-content-metadata",
            manifest: [
                "manifest_version": 3,
                "name": "Content Metadata",
                "version": "1.0",
                "content_scripts": [
                    [
                        "matches": ["https://example.com/*"],
                        "exclude_matches": ["https://example.com/private/*"],
                        "include_globs": ["*example*"],
                        "exclude_globs": ["*private*"],
                        "js": ["a.js", "b.js"],
                        "run_at": "document_start",
                        "all_frames": true,
                        "match_about_blank": true,
                        "match_origin_as_fallback": true,
                        "world": "ISOLATED",
                    ],
                ],
            ],
            files: [
                "a.js": "window.a = true;\n",
                "b.js": "window.b = true;\n",
            ]
        )
        let variant = try writeVariant(for: fixture)

        let report = try readReport(from: variant.variantRootURL)

        XCTAssertTrue(report.passedChecks.contains(.contentScriptShimOrdering))
        XCTAssertTrue(report.passedChecks.contains(.contentScriptFieldPreservation))
        let orderingDetails = try XCTUnwrap(
            check(.contentScriptShimOrdering, in: report)
        ).details.joined(separator: "\n")
        XCTAssertTrue(orderingDetails.contains("content_scripts[0].js has shim prefix"))
        let preservationDetails = try XCTUnwrap(
            check(.contentScriptFieldPreservation, in: report)
        ).details.joined(separator: "\n")
        XCTAssertTrue(preservationDetails.contains("content_scripts[0].matches is preserved."))
        XCTAssertTrue(preservationDetails.contains("content_scripts[0].world is preserved."))
    }

    func testExtensionPageShimDetectionWorksForPopupAndOptionsPages() throws {
        let fixture = try writeBundle(
            named: "loadability-extension-pages",
            manifest: [
                "manifest_version": 3,
                "name": "Extension Pages",
                "version": "1.0",
                "action": [
                    "default_popup": "popup.html",
                ],
                "options_page": "options.html",
                "options_ui": [
                    "page": "settings/options-ui.html",
                    "open_in_tab": false,
                ],
            ],
            files: [
                "popup.html": "<!doctype html><html><head><title>Popup</title></head><body></body></html>\n",
                "options.html": "<!doctype html><title>Options</title>\n",
                "settings/options-ui.html": "<!doctype html><html><head><title>Options UI</title></head><body></body></html>\n",
            ]
        )
        let variant = try writeVariant(for: fixture)

        let report = try readReport(from: variant.variantRootURL)

        XCTAssertTrue(report.passedChecks.contains(.extensionPageShimPresence))
        XCTAssertEqual(
            staticCheck("action.default_popup", in: report)?.injectionStatus,
            .beforeClosingHead
        )
        XCTAssertEqual(
            staticCheck("options_page", in: report)?.injectionStatus,
            .documentStartFallbackNoHead
        )
        XCTAssertEqual(
            staticCheck("options_ui.page", in: report)?.expectedShimRelativeSrcs,
            ["../_sumi_runtime/chrome-shim.extension-page.js"]
        )
    }

    func testCSPMetaTagProducesWarningWhenShimTagIsPresent() throws {
        let fixture = try writeBundle(
            named: "loadability-csp-warning",
            manifest: [
                "manifest_version": 3,
                "name": "CSP Warning",
                "version": "1.0",
                "action": [
                    "default_popup": "popup.html",
                ],
            ],
            files: [
                "popup.html": """
                <!doctype html><html><head>
                <meta http-equiv="Content-Security-Policy" content="script-src 'self'">
                <title>Popup</title></head><body></body></html>

                """,
            ]
        )
        let variant = try writeVariant(for: fixture)

        let report = try readReport(from: variant.variantRootURL)

        XCTAssertTrue(report.passedChecks.contains(.extensionPageCSPWarnings))
        XCTAssertTrue(
            report.warnings.contains {
                $0.contains("CSP meta tag present in popup.html")
            }
        )
        XCTAssertEqual(
            staticCheck("action.default_popup", in: report)?.containsCSPMetaTag,
            true
        )
    }

    func testSidePanelRemainsDeferredPlanningOnly() throws {
        let fixture = try writeBundle(
            named: "loadability-side-panel",
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
                "sidepanel.html": "<!doctype html><html><head><title>Side</title></head><body></body></html>\n",
            ]
        )
        let variant = try writeVariant(for: fixture)

        let report = try readReport(from: variant.variantRootURL)

        XCTAssertTrue(report.deferredChecks.contains(.sidePanelDeferredPlanningOnly))
        XCTAssertEqual(
            staticCheck("side_panel.default_path", in: report)?.injectionStatus,
            .planningOnlyDeferred
        )
        XCTAssertTrue(report.deferredAPIs.contains(.sidePanel))
    }

    func testNativeMessagingIsBlockedDeferredAndNotImplemented() throws {
        let fixture = try writeBundle(
            named: "loadability-native-messaging",
            manifest: passwordManagerManifest(),
            files: passwordManagerFiles()
        )
        let variant = try writeVariant(for: fixture)

        let report = try readReport(from: variant.variantRootURL)

        XCTAssertTrue(report.deferredChecks.contains(.nativeMessagingBlocked))
        XCTAssertTrue(report.passedChecks.contains(.noNativeMessagingRuntime))
        XCTAssertTrue(report.deferredAPIs.contains(.nativeMessaging))
        XCTAssertTrue(
            report.blockers.contains("Native messaging host bridge is not implemented.")
        )
    }

    func testUnsupportedAPIsRemainBlockersAccordingToClassification() throws {
        let fixture = try writeBundle(
            named: "loadability-unsupported",
            manifest: [
                "manifest_version": 3,
                "name": "Unsupported",
                "version": "1.0",
                "permissions": ["debugger"],
            ],
            files: [:]
        )
        let variant = try writeVariant(for: fixture)

        let report = try readReport(from: variant.variantRootURL)

        XCTAssertTrue(report.unsupportedAPIs.contains(.debugger))
        XCTAssertTrue(report.failedChecks.contains(.unsupportedAPIs))
        XCTAssertTrue(
            report.blockers.contains("Unsupported APIs remain unresolved or were silently removed.")
        )
    }

    func testPasswordManagerLikeFixtureProducesReadinessReportAndBlockers() throws {
        let fixture = try writeBundle(
            named: "loadability-password-manager",
            manifest: passwordManagerManifest(),
            files: passwordManagerFiles()
        )
        let variant = try writeVariant(for: fixture)

        let report = try readReport(from: variant.variantRootURL)
        let readiness = report.passwordManagerReadiness

        XCTAssertTrue(readiness.contentScriptsPresent)
        XCTAssertTrue(readiness.allFramesDetected)
        XCTAssertTrue(readiness.matchAboutBlankDetected)
        XCTAssertTrue(readiness.hostPermissionsPresent)
        XCTAssertTrue(readiness.actionPopupPresent)
        XCTAssertTrue(readiness.storagePermissionPresent)
        XCTAssertTrue(readiness.nativeMessagingDetected)
        XCTAssertTrue(readiness.nativeMessagingBlocked)
        XCTAssertFalse(readiness.runtimeMessagingImplemented)
        XCTAssertFalse(readiness.controlledInputPageWorldBehaviorVerified)
        XCTAssertFalse(readiness.serviceWorkerLifecycleVerified)
        XCTAssertTrue(
            readiness.blockers.contains("Native messaging is detected but blocked/deferred.")
        )
    }

    func testRuntimeLoadabilityReportIsDeterministicAndIdempotent() throws {
        let fixture = try writeBundle(
            named: "loadability-idempotent",
            manifest: passwordManagerManifest(),
            files: passwordManagerFiles()
        )
        let variant = try writeVariant(for: fixture)
        let verifier = ChromeMV3RuntimeLoadabilityVerifier()

        let first = try verifier.writeReport(
            forRewrittenVariantAt: variant.variantRootURL
        )
        let firstData = try Data(
            contentsOf: variant.variantRootURL
                .appendingPathComponent(
                    ChromeMV3RuntimeLoadabilityVerifier.reportFileName
                )
        )
        let second = try verifier.writeReport(
            forRewrittenVariantAt: variant.variantRootURL
        )
        let secondData = try Data(
            contentsOf: variant.variantRootURL
                .appendingPathComponent(
                    ChromeMV3RuntimeLoadabilityVerifier.reportFileName
                )
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(firstData, secondData)
    }

    func testVerifierDoesNotModifyRewrittenVariantFiles() throws {
        let fixture = try writeBundle(
            named: "loadability-read-only",
            manifest: passwordManagerManifest(),
            files: passwordManagerFiles()
        )
        let variant = try writeVariant(for: fixture)
        let before = try fileContents(rootURL: variant.variantRootURL)

        _ = try ChromeMV3RuntimeLoadabilityVerifier()
            .verifyRewrittenVariant(at: variant.variantRootURL)

        let after = try fileContents(rootURL: variant.variantRootURL)
        XCTAssertEqual(before, after)
    }

    func testVerifierSourceDoesNotReferenceRuntimeObjectsOrInjectionAPIs() throws {
        let source = try readString(
            at: projectRoot()
                .appendingPathComponent(
                    "Sumi/Models/Extension/ChromeMV3/ChromeMV3RuntimeLoadabilityVerifier.swift"
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
        try writeJSONObject(
            manifest,
            to: directory.appendingPathComponent("manifest.json")
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

    private func readReport(
        from variantRootURL: URL
    ) throws -> ChromeMV3RuntimeLoadabilityReport {
        try JSONDecoder().decode(
            ChromeMV3RuntimeLoadabilityReport.self,
            from: Data(
                contentsOf: variantRootURL
                    .appendingPathComponent(
                        ChromeMV3RuntimeLoadabilityVerifier.reportFileName
                    )
            )
        )
    }

    private func check(
        _ category: ChromeMV3RuntimeLoadabilityCheckCategory,
        in report: ChromeMV3RuntimeLoadabilityReport
    ) -> ChromeMV3RuntimeLoadabilityCheck? {
        report.verificationChecks.first { $0.category == category }
    }

    private func staticCheck(
        _ sourceManifestField: String,
        in report: ChromeMV3RuntimeLoadabilityReport
    ) -> ChromeMV3ExtensionPageStaticVerification? {
        report.extensionPageStaticChecks.first {
            $0.sourceManifestField == sourceManifestField
        }
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

    private func writeJSONObject(
        _ object: [String: Any],
        to url: URL
    ) throws {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: [.atomic])
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
