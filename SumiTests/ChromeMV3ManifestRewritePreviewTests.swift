import CryptoKit
import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3ManifestRewritePreviewTests: XCTestCase {
    private let fixedInstallDate = Date(timeIntervalSince1970: 1_700_000_000)
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testMinimalServiceWorkerProducesWrapperPreviewWithoutManifestRewrite() throws {
        let fixture = try writeBundle(
            named: "minimal-service-worker-preview",
            manifest: minimalServiceWorkerManifest(),
            files: [
                "background.js": "chrome.runtime.onInstalled.addListener(() => {});\n",
            ]
        )

        let generatedManifest = try readJSONObject(at: fixture.result.generatedManifestURL)
        let background = try XCTUnwrap(generatedManifest["background"] as? [String: Any])
        XCTAssertEqual(background["service_worker"] as? String, "background.js")
        XCTAssertFalse(try canonicalJSONString(generatedManifest).contains("_sumi_runtime"))
        XCTAssertFalse(fixture.result.record.runtimeLoadable)
        XCTAssertFalse(fixture.preview.runtimeLoadableAfterPreview)

        let operation = try operation(.replaceServiceWorkerWithWrapper, in: fixture.preview)
        let serviceWorker = try XCTUnwrap(operation.serviceWorker)
        XCTAssertFalse(operation.appliedNow)
        XCTAssertEqual(serviceWorker.wrapperKind, .classic)
        XCTAssertEqual(serviceWorker.originalServiceWorkerPath, "background.js")
        XCTAssertEqual(
            serviceWorker.futureWrapperPath,
            "_sumi_runtime/service-worker-wrapper.classic.js"
        )
    }

    func testModuleServiceWorkerGetsModuleWrapperPreview() throws {
        let fixture = try writeBundle(
            named: "module-service-worker-preview",
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

        let serviceWorker = try XCTUnwrap(
            operation(.replaceServiceWorkerWithWrapper, in: fixture.preview)
                .serviceWorker
        )
        XCTAssertEqual(serviceWorker.wrapperKind, .module)
        XCTAssertEqual(serviceWorker.originalBackgroundType, "module")
        XCTAssertEqual(serviceWorker.originalServiceWorkerPath, "worker.js")
        XCTAssertEqual(
            serviceWorker.futureWrapperPath,
            "_sumi_runtime/service-worker-wrapper.module.js"
        )

        let generatedManifest = try readJSONObject(at: fixture.result.generatedManifestURL)
        let background = try XCTUnwrap(generatedManifest["background"] as? [String: Any])
        XCTAssertEqual(background["service_worker"] as? String, "worker.js")
        XCTAssertEqual(background["type"] as? String, "module")
    }

    func testClassicServiceWorkerGetsClassicWrapperPreview() throws {
        let fixture = try writeBundle(
            named: "classic-service-worker-preview",
            manifest: minimalServiceWorkerManifest(),
            files: [
                "background.js": "chrome.runtime.onMessage.addListener(() => {});\n",
            ]
        )

        let serviceWorker = try XCTUnwrap(
            operation(.replaceServiceWorkerWithWrapper, in: fixture.preview)
                .serviceWorker
        )
        XCTAssertEqual(serviceWorker.wrapperKind, .classic)
        XCTAssertNil(serviceWorker.originalBackgroundType)
        XCTAssertEqual(
            serviceWorker.futureWrapperModuleName,
            .serviceWorkerWrapperClassic
        )
    }

    func testContentScriptsGetPlannedShimPrefixWithoutManifestRewrite() throws {
        let fixture = try writeBundle(
            named: "content-script-preview",
            manifest: [
                "manifest_version": 3,
                "name": "Content Preview",
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
        let contentScripts = try XCTUnwrap(
            generatedManifest["content_scripts"] as? [[String: Any]]
        )
        XCTAssertEqual(contentScripts.first?["js"] as? [String], ["a.js", "b.js"])
        XCTAssertFalse(try canonicalJSONString(generatedManifest).contains("_sumi_runtime"))

        let contentOperation = try operation(.prependContentScriptShims, in: fixture.preview)
        let contentScript = try XCTUnwrap(contentOperation.contentScript)
        XCTAssertEqual(
            contentScript.plannedShimPrefix,
            [
                "_sumi_runtime/chrome-shim.common.js",
                "_sumi_runtime/chrome-shim.content-script.js",
            ]
        )
        XCTAssertEqual(contentScript.originalScripts, ["a.js", "b.js"])
        XCTAssertEqual(
            contentScript.plannedScriptsAfterPrepend,
            [
                "_sumi_runtime/chrome-shim.common.js",
                "_sumi_runtime/chrome-shim.content-script.js",
                "a.js",
                "b.js",
            ]
        )
        XCTAssertEqual(
            fixture.preview.plannedOperations.map(\.order),
            Array(1...fixture.preview.plannedOperations.count)
        )
    }

    func testPasswordManagerContentScriptFrameMetadataAppearsInPreview() throws {
        let fixture = try writeBundle(
            named: "password-manager-content-preview",
            manifest: passwordManagerManifest(),
            files: passwordManagerFiles()
        )

        let contentScript = try XCTUnwrap(
            operation(.prependContentScriptShims, in: fixture.preview)
                .contentScript
        )
        XCTAssertEqual(contentScript.matches, ["https://*/*"])
        XCTAssertEqual(contentScript.runAt, "document_start")
        XCTAssertEqual(contentScript.allFrames, true)
        XCTAssertEqual(contentScript.matchAboutBlank, true)
        XCTAssertEqual(contentScript.matchOriginAsFallback, true)
        XCTAssertEqual(contentScript.world, "ISOLATED")
        XCTAssertEqual(contentScript.originalScripts, ["content.js"])

        let generatedManifest = try readJSONObject(at: fixture.result.generatedManifestURL)
        let contentScripts = try XCTUnwrap(
            generatedManifest["content_scripts"] as? [[String: Any]]
        )
        XCTAssertEqual(contentScripts.first?["js"] as? [String], ["content.js"])
        XCTAssertEqual(contentScripts.first?["all_frames"] as? Bool, true)
        XCTAssertEqual(contentScripts.first?["match_about_blank"] as? Bool, true)
    }

    func testActionPopupGetsExtensionPageInjectionPreviewWithoutHTMLRewrite() throws {
        let popupHTML = "<!doctype html><title>Popup</title><script src=\"popup.js\"></script>\n"
        let fixture = try writeBundle(
            named: "action-popup-preview",
            manifest: [
                "manifest_version": 3,
                "name": "Popup Preview",
                "version": "1.0",
                "action": [
                    "default_popup": "popup.html",
                ],
            ],
            files: [
                "popup.html": popupHTML,
            ]
        )

        let target = try extensionPage(
            context: .actionPopup,
            field: "action.default_popup",
            in: fixture.preview
        )
        XCTAssertEqual(target.pagePath, "popup.html")
        XCTAssertEqual(target.futureShimPaths, ["_sumi_runtime/chrome-shim.extension-page.js"])
        XCTAssertFalse(target.htmlRewriteAppliedNow)
        XCTAssertFalse(target.manifestRewriteAppliedNow)
        XCTAssertEqual(
            try String(
                contentsOf: fixture.result.generatedBundleRootURL
                    .appendingPathComponent("popup.html"),
                encoding: .utf8
            ),
            popupHTML
        )
    }

    func testOptionsPageAndOptionsUIGetExtensionPageInjectionPreviewWithoutHTMLRewrite() throws {
        let optionsPageHTML = "<!doctype html><title>Options Page</title>\n"
        let optionsUIHTML = "<!doctype html><title>Options UI</title>\n"
        let fixture = try writeBundle(
            named: "options-preview",
            manifest: [
                "manifest_version": 3,
                "name": "Options Preview",
                "version": "1.0",
                "options_page": "options.html",
                "options_ui": [
                    "page": "options-ui.html",
                    "open_in_tab": false,
                ],
            ],
            files: [
                "options.html": optionsPageHTML,
                "options-ui.html": optionsUIHTML,
            ]
        )

        let optionsPage = try extensionPage(
            context: .optionsPage,
            field: "options_page",
            in: fixture.preview
        )
        let optionsUI = try extensionPage(
            context: .optionsPage,
            field: "options_ui.page",
            in: fixture.preview
        )
        XCTAssertEqual(optionsPage.pagePath, "options.html")
        XCTAssertEqual(optionsPage.optionsDeclarationKey, "options_page")
        XCTAssertEqual(optionsUI.pagePath, "options-ui.html")
        XCTAssertEqual(optionsUI.optionsDeclarationKey, "options_ui")
        XCTAssertEqual(
            try String(
                contentsOf: fixture.result.generatedBundleRootURL
                    .appendingPathComponent("options.html"),
                encoding: .utf8
            ),
            optionsPageHTML
        )
        XCTAssertEqual(
            try String(
                contentsOf: fixture.result.generatedBundleRootURL
                    .appendingPathComponent("options-ui.html"),
                encoding: .utf8
            ),
            optionsUIHTML
        )
    }

    func testSidePanelDefaultPathGetsDeferredExtensionPagePlanningOnly() throws {
        let sidePanelHTML = "<!doctype html><title>Side Panel</title>\n"
        let fixture = try writeBundle(
            named: "side-panel-preview",
            manifest: [
                "manifest_version": 3,
                "name": "Side Panel Preview",
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

        let sidePanel = try extensionPage(
            context: .sidePanel,
            field: "side_panel.default_path",
            in: fixture.preview
        )
        XCTAssertEqual(sidePanel.pagePath, "sidepanel.html")
        XCTAssertTrue(sidePanel.nativeHostPlanningOnly)
        XCTAssertEqual(sidePanel.deferredAPIs, [.sidePanel])
        XCTAssertFalse(sidePanel.runtimeTemplateCurrentlyRequired)
        XCTAssertTrue(
            fixture.preview.deferredAPIsBlockingRuntimeLoadability
                .contains(.sidePanel)
        )
        XCTAssertFalse(fixture.preview.runtimeLoadableAfterPreview)
        XCTAssertEqual(
            try String(
                contentsOf: fixture.result.generatedBundleRootURL
                    .appendingPathComponent("sidepanel.html"),
                encoding: .utf8
            ),
            sidePanelHTML
        )
    }

    func testUnsupportedAPIsAreRecordedAndKeepPreviewNonLoadable() throws {
        let fixture = try writeBundle(
            named: "unsupported-api-preview",
            manifest: [
                "manifest_version": 3,
                "name": "Unsupported API Preview",
                "version": "1.0",
                "permissions": ["debugger"],
            ],
            files: [:]
        )

        XCTAssertTrue(
            fixture.preview.unsupportedAPIsBlockingRuntimeLoadability
                .contains(.debugger)
        )
        XCTAssertFalse(fixture.preview.runtimeLoadableAfterPreview)
        let unsupported = try operation(.recordUnsupportedAPIs, in: fixture.preview)
        XCTAssertEqual(unsupported.blockedByAPIs, [.debugger])
        XCTAssertFalse(unsupported.appliedNow)
    }

    func testPreviewOutputIsDeterministicAndIdempotent() throws {
        let fixtureDirectory = try makeFixture(
            named: "deterministic-preview",
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
        let firstPreview = try String(
            contentsOf: first.manifestRewritePreviewURL,
            encoding: .utf8
        )

        let second = try writer.writeGeneratedBundle(
            originalBundleRecord: stage.originalBundleRecord,
            manifestSnapshot: stage.manifestSnapshot,
            planningRecord: stage.generatedBundlePlan
        )
        let secondPreview = try String(
            contentsOf: second.manifestRewritePreviewURL,
            encoding: .utf8
        )

        XCTAssertEqual(firstPreview, secondPreview)
        XCTAssertEqual(first.record.manifestRewritePreviewSHA256, second.record.manifestRewritePreviewSHA256)
    }

    func testGeneratedBundleMetadataReferencesPreviewWithoutRuntimeLoadability() throws {
        let fixture = try writeBundle(
            named: "metadata-preview-reference",
            manifest: passwordManagerManifest(),
            files: passwordManagerFiles()
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(
            ChromeMV3GeneratedBundleRecord.self,
            from: Data(contentsOf: fixture.result.generatedMetadataURL)
        )
        let previewData = try Data(contentsOf: fixture.result.manifestRewritePreviewURL)
        XCTAssertEqual(metadata.manifestRewritePreviewPath, fixture.result.manifestRewritePreviewURL.path)
        XCTAssertEqual(metadata.manifestRewritePreviewSHA256, sha256Hex(previewData))
        XCTAssertFalse(metadata.runtimeLoadable)
        XCTAssertFalse(metadata.generatedRuntimeFilesWritten)
        XCTAssertFalse(metadata.executableRuntimeFilesWritten)
        XCTAssertFalse(fixture.preview.appliedNow)
        XCTAssertTrue(fixture.preview.plannedOperations.allSatisfy { $0.appliedNow == false })
    }

    func testManifestRewritePreviewSourceDoesNotConstructRuntimeObjects() throws {
        let source = try String(
            contentsOf: projectRoot()
                .appendingPathComponent(
                    "Sumi/Models/Extension/ChromeMV3/ChromeMV3ManifestRewritePreview.swift"
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
        var preview: ChromeMV3ManifestRewritePreview
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
        let preview = try JSONDecoder().decode(
            ChromeMV3ManifestRewritePreview.self,
            from: Data(contentsOf: result.manifestRewritePreviewURL)
        )
        return WrittenBundleFixture(result: result, preview: preview)
    }

    private func operation(
        _ type: ChromeMV3ManifestRewritePreviewOperationType,
        in preview: ChromeMV3ManifestRewritePreview
    ) throws -> ChromeMV3ManifestRewritePreviewOperation {
        try XCTUnwrap(preview.plannedOperations.first { $0.type == type })
    }

    private func extensionPage(
        context: ChromeMV3ExtensionPageShimContext,
        field: String,
        in preview: ChromeMV3ManifestRewritePreview
    ) throws -> ChromeMV3ExtensionPageShimInjectionPreview {
        try XCTUnwrap(
            preview.plannedOperations
                .compactMap(\.extensionPage)
                .first {
                    $0.context == context && $0.sourceManifestField == field
                }
        )
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

    private func readJSONObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func canonicalJSONString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        return try XCTUnwrap(String(data: data, encoding: .utf8))
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
