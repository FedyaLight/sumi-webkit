import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3GeneratedBundleWriterTests: XCTestCase {
    private let fixedInstallDate = Date(timeIntervalSince1970: 1_700_000_000)
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testWritesGeneratedManifestForMinimalMV3() throws {
        let stage = try stageBundle(
            named: "minimal-generated",
            manifest: minimalManifest(),
            files: [
                "background.js": "chrome.runtime.onInstalled.addListener(() => {});\n",
            ]
        )

        let result = try makeWriter(rootURL: stage.storeRoot)
            .writeGeneratedBundle(
                originalBundleRecord: stage.result.originalBundleRecord,
                manifestSnapshot: stage.result.manifestSnapshot,
                planningRecord: stage.result.generatedBundlePlan
            )

        let generatedManifest = try readJSONObject(
            at: result.generatedManifestURL
        )
        let background = try XCTUnwrap(
            generatedManifest["background"] as? [String: Any]
        )
        XCTAssertEqual(background["service_worker"] as? String, "background.js")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: result.generatedBundleRootURL
                    .appendingPathComponent("background.js")
                    .path
            )
        )
        XCTAssertEqual(result.record.generatedRuntimeFilesWritten, false)
        XCTAssertTrue(result.record.inertRuntimeTemplatesWritten)
        XCTAssertFalse(result.record.executableRuntimeFilesWritten)
        XCTAssertEqual(result.record.runtimeLoadable, false)
        XCTAssertEqual(result.record.copiedResourcePaths, ["background.js"])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: result.generatedBundleRootURL
                    .appendingPathComponent("_sumi_runtime")
                    .path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: result.generatedBundleRootURL
                    .appendingPathComponent("runtime-resource-plan.json")
                    .path
            )
        )
        XCTAssertTrue(
            result.record.generatedBundleRootPath.hasSuffix(
                "/generated/\(stage.result.originalBundleRecord.id)/generated"
            )
        )
    }

    func testOutputIsDeterministicAcrossRepeatedWrites() throws {
        let stage = try stageBundle(
            named: "deterministic-generated",
            manifest: passwordManagerManifest(),
            files: passwordManagerFiles()
        )
        let writer = makeWriter(rootURL: stage.storeRoot)

        _ = try writer.writeGeneratedBundle(
            originalBundleRecord: stage.result.originalBundleRecord,
            manifestSnapshot: stage.result.manifestSnapshot,
            planningRecord: stage.result.generatedBundlePlan
        )
        let firstFiles = try generatedFileContents(
            rootURL: generatedRoot(
                storeRoot: stage.storeRoot,
                recordID: stage.result.originalBundleRecord.id
            )
        )

        _ = try writer.writeGeneratedBundle(
            originalBundleRecord: stage.result.originalBundleRecord,
            manifestSnapshot: stage.result.manifestSnapshot,
            planningRecord: stage.result.generatedBundlePlan
        )
        let secondFiles = try generatedFileContents(
            rootURL: generatedRoot(
                storeRoot: stage.storeRoot,
                recordID: stage.result.originalBundleRecord.id
            )
        )

        XCTAssertEqual(firstFiles, secondFiles)
        XCTAssertEqual(
            firstFiles["generated-bundle-metadata.json"],
            secondFiles["generated-bundle-metadata.json"]
        )
    }

    func testMetadataRecordsRuntimeDraftStateAndPlanning() throws {
        let stage = try stageBundle(
            named: "metadata-draft",
            manifest: passwordManagerManifest(),
            files: passwordManagerFiles()
        )

        let result = try makeWriter(rootURL: stage.storeRoot)
            .writeGeneratedBundle(
                originalBundleRecord: stage.result.originalBundleRecord,
                manifestSnapshot: stage.result.manifestSnapshot,
                planningRecord: stage.result.generatedBundlePlan
            )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(
            ChromeMV3GeneratedBundleRecord.self,
            from: Data(contentsOf: result.generatedMetadataURL)
        )
        XCTAssertEqual(metadata, result.record)
        XCTAssertFalse(metadata.generatedRuntimeFilesWritten)
        XCTAssertTrue(metadata.inertRuntimeTemplatesWritten)
        XCTAssertFalse(metadata.executableRuntimeFilesWritten)
        XCTAssertFalse(metadata.runtimeLoadable)
        XCTAssertTrue(metadata.plannedServiceWorkerWrapperNeeded)
        XCTAssertTrue(metadata.plannedShimModules.contains("chrome.runtime"))
        XCTAssertTrue(
            metadata.plannedRuntimeTemplateModules.contains(
                .serviceWorkerWrapperClassic
            )
        )
        XCTAssertTrue(
            metadata.plannedRuntimeTemplateModules.contains(
                .chromeShimContentScript
            )
        )
        XCTAssertTrue(
            metadata.plannedRuntimeTemplateModules.contains(
                .chromeShimExtensionPage
            )
        )
        XCTAssertTrue(
            metadata.plannedRuntimeTemplateModules.contains(.hostBridgeStub)
        )
        XCTAssertTrue(metadata.plannedNativeHostAPIs.contains(.nativeMessaging))
        XCTAssertTrue(metadata.deferredAPIs.contains(.nativeMessaging))
        XCTAssertEqual(
            metadata.writtenInertRuntimeTemplateResources.map(\.moduleName),
            metadata.plannedRuntimeTemplateModules
        )
        XCTAssertTrue(
            metadata.writtenInertRuntimeTemplateResources.allSatisfy(\.inert)
        )
        XCTAssertTrue(
            metadata.writtenInertRuntimeTemplateResources.allSatisfy {
                $0.runtimeLoadable == false
            }
        )
        XCTAssertEqual(
            metadata.originalBundleContentSHA256,
            stage.result.originalBundleRecord.sourceMetadata.contentSHA256
        )
        XCTAssertEqual(
            metadata.manifestSHA256,
            stage.result.manifestSnapshot.manifestSHA256
        )
        XCTAssertEqual(
            metadata.installReportSummary.capabilitySummary.deferredAPIs,
            stage.result.manifestSnapshot.capabilitySummary.deferredAPIs
        )

        let runtimePlan = try JSONDecoder().decode(
            ChromeMV3RuntimeResourcePlan.self,
            from: Data(contentsOf: result.generatedBundleRootURL
                .appendingPathComponent("runtime-resource-plan.json"))
        )
        XCTAssertEqual(runtimePlan, stage.result.generatedBundlePlan.runtimeResourcePlan)
        XCTAssertFalse(runtimePlan.runtimeLoadable)
        XCTAssertFalse(runtimePlan.executableRuntimeFilesWritten)
    }

    func testPreservesServiceWorkerAndContentScriptsWithoutRuntimeInjection() throws {
        let stage = try stageBundle(
            named: "manifest-draft-rewrite",
            manifest: [
                "manifest_version": 3,
                "name": "Manifest Draft Rewrite",
                "version": "1.0",
                "background": [
                    "service_worker": "background.js",
                ],
                "content_scripts": [
                    [
                        "matches": ["https://example.com/*"],
                        "js": ["content.js"],
                    ],
                ],
            ],
            files: [
                "background.js": "chrome.runtime.onMessage.addListener(() => {});\n",
                "content.js": "chrome.runtime.sendMessage({ready: true});\n",
            ]
        )

        let result = try makeWriter(rootURL: stage.storeRoot)
            .writeGeneratedBundle(
                originalBundleRecord: stage.result.originalBundleRecord,
                manifestSnapshot: stage.result.manifestSnapshot,
                planningRecord: stage.result.generatedBundlePlan
            )

        let manifest = try readJSONObject(at: result.generatedManifestURL)
        let background = try XCTUnwrap(manifest["background"] as? [String: Any])
        let contentScripts = try XCTUnwrap(
            manifest["content_scripts"] as? [[String: Any]]
        )
        XCTAssertEqual(background["service_worker"] as? String, "background.js")
        XCTAssertEqual(contentScripts.first?["js"] as? [String], ["content.js"])
        XCTAssertFalse(
            try canonicalJSONString(manifest)
                .contains("_sumi_runtime")
        )
        XCTAssertFalse(
            result.record.copiedResourcePaths.contains { path in
                path.localizedCaseInsensitiveContains("shim")
                    || path.localizedCaseInsensitiveContains("wrapper")
            }
        )
        let generatedFiles = try generatedFileContents(
            rootURL: result.generatedBundleRootURL
        )
        XCTAssertTrue(
            generatedFiles.keys.contains("_sumi_runtime/chrome-shim.content-script.js"),
            generatedFiles.keys.sorted().joined(separator: ",")
        )
        XCTAssertTrue(
            generatedFiles.keys.contains("_sumi_runtime/service-worker-wrapper.classic.js"),
            generatedFiles.keys.sorted().joined(separator: ",")
        )
        XCTAssertFalse(result.record.generatedRuntimeFilesWritten)
        XCTAssertTrue(result.record.inertRuntimeTemplatesWritten)
        XCTAssertFalse(result.record.executableRuntimeFilesWritten)
        XCTAssertFalse(result.record.runtimeLoadable)
    }

    func testGeneratedRuntimeTemplatesAreInertAndNotReferencedByManifest() throws {
        let stage = try stageBundle(
            named: "runtime-template-output",
            manifest: passwordManagerManifest(),
            files: passwordManagerFiles()
        )

        let result = try makeWriter(rootURL: stage.storeRoot)
            .writeGeneratedBundle(
                originalBundleRecord: stage.result.originalBundleRecord,
                manifestSnapshot: stage.result.manifestSnapshot,
                planningRecord: stage.result.generatedBundlePlan
            )

        let generatedManifest = try readJSONObject(at: result.generatedManifestURL)
        XCTAssertFalse(
            try canonicalJSONString(generatedManifest).contains("_sumi_runtime")
        )
        let background = try XCTUnwrap(
            generatedManifest["background"] as? [String: Any]
        )
        XCTAssertEqual(background["service_worker"] as? String, "background.js")
        let contentScripts = try XCTUnwrap(
            generatedManifest["content_scripts"] as? [[String: Any]]
        )
        XCTAssertEqual(contentScripts.first?["js"] as? [String], ["content.js"])

        let generatedFiles = try generatedFileContents(
            rootURL: result.generatedBundleRootURL
        )
        let runtimeFiles = generatedFiles.filter { key, _ in
            key.hasPrefix("_sumi_runtime/")
        }
        XCTAssertEqual(
            Set(runtimeFiles.keys),
            Set(result.record.writtenInertRuntimeTemplateResources.map(\.outputRelativePath))
        )
        XCTAssertTrue(result.record.inertRuntimeTemplatesWritten)
        XCTAssertFalse(result.record.executableRuntimeFilesWritten)
        XCTAssertFalse(result.record.generatedRuntimeFilesWritten)
        XCTAssertFalse(result.record.runtimeLoadable)

        let forbiddenFragments = [
            "set" + "Timeout",
            "set" + "Interval",
            "connect" + "Native",
            "send" + "NativeMessage",
            "add" + "EventListener(",
            "chrome.runtime." + "onMessage",
            "browser.runtime." + "onMessage",
            "document.create" + "Element(",
            "append" + "Child(",
        ]
        for (path, contents) in runtimeFiles {
            XCTAssertTrue(contents.contains("notWired: true"), path)
            XCTAssertTrue(contents.contains("runtimeLoadable: false"), path)
            for forbidden in forbiddenFragments {
                XCTAssertFalse(contents.contains(forbidden), "\(path): \(forbidden)")
            }
        }
    }

    func testCopiesSafeManifestReferencedResourcesOnly() throws {
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Resource Copy",
            "version": "1.0",
            "background": [
                "service_worker": "scripts/background.js",
                "type": "module",
            ],
            "content_scripts": [
                [
                    "matches": ["https://example.com/*"],
                    "js": ["content/content.js"],
                    "css": ["content/content.css"],
                ],
            ],
            "action": [
                "default_popup": "ui/popup.html",
                "default_icon": [
                    "16": "icons/action-16.png",
                    "32": "/icons/action-32.png",
                ],
            ],
            "icons": [
                "48": "icons/icon-48.png",
                "128": "icons/icon-128.png",
            ],
            "options_page": "options.html",
            "options_ui": [
                "page": "options-ui.html",
                "open_in_tab": true,
            ],
            "web_accessible_resources": [
                [
                    "resources": [
                        "public/logo.png",
                        "public/assets/*",
                    ],
                    "matches": ["https://example.com/*"],
                ],
            ],
            "declarative_net_request": [
                "rule_resources": [
                    [
                        "id": "ruleset_1",
                        "enabled": true,
                        "path": "rules/rules_1.json",
                    ],
                ],
            ],
            "side_panel": [
                "default_path": "sidepanel.html",
            ],
            "permissions": [
                "declarativeNetRequest",
                "storage",
            ],
        ]
        let stage = try stageBundle(
            named: "safe-resources",
            manifest: manifest,
            files: [
                "scripts/background.js": "chrome.runtime.onInstalled.addListener(() => {});\n",
                "content/content.js": "document.body.dataset.test = '1';\n",
                "content/content.css": "body { color: rgb(1, 2, 3); }\n",
                "ui/popup.html": "<!doctype html><title>Popup</title>\n",
                "icons/action-16.png": "action icon\n",
                "icons/action-32.png": "action icon root relative\n",
                "icons/icon-48.png": "icon 48\n",
                "icons/icon-128.png": "icon 128\n",
                "options.html": "<!doctype html><title>Options</title>\n",
                "options-ui.html": "<!doctype html><title>Options UI</title>\n",
                "public/logo.png": "logo\n",
                "public/assets/nested/data.json": "{}\n",
                "rules/rules_1.json": "[]\n",
                "sidepanel.html": "<!doctype html><title>Side Panel</title>\n",
                "unreferenced.js": "throw new Error('not copied');\n",
            ]
        )

        let result = try makeWriter(rootURL: stage.storeRoot)
            .writeGeneratedBundle(
                originalBundleRecord: stage.result.originalBundleRecord,
                manifestSnapshot: stage.result.manifestSnapshot,
                planningRecord: stage.result.generatedBundlePlan
            )

        let expectedCopiedPaths = [
            "content/content.css",
            "content/content.js",
            "icons/action-16.png",
            "icons/action-32.png",
            "icons/icon-128.png",
            "icons/icon-48.png",
            "options-ui.html",
            "options.html",
            "public/assets/nested/data.json",
            "public/logo.png",
            "rules/rules_1.json",
            "scripts/background.js",
            "sidepanel.html",
            "ui/popup.html",
        ]
        XCTAssertEqual(result.record.copiedResourcePaths, expectedCopiedPaths)
        for path in expectedCopiedPaths {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: result.generatedBundleRootURL
                        .appendingPathComponent(path)
                        .path
                ),
                path
            )
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: result.generatedBundleRootURL
                    .appendingPathComponent("unreferenced.js")
                    .path
            )
        )
        XCTAssertTrue(result.record.resourceWarnings.isEmpty)
    }

    func testCopiesStaticImportScriptsDependenciesFromClassicServiceWorker()
        throws
    {
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Static ImportScripts",
            "version": "1.0",
            "background": [
                "service_worker": "scripts/background.js",
            ],
        ]
        let stage = try stageBundle(
            named: "classic-importscripts-resources",
            manifest: manifest,
            files: [
                "scripts/background.js": """
                importScripts('./deps/one.js', 'nested/two.js');
                const dynamicPath = 'dynamic.js';
                importScripts(dynamicPath);
                importScripts('../outside.js');
                """,
                "scripts/deps/one.js": "globalThis.one = true;\n",
                "scripts/nested/two.js": """
                importScripts('child/three.js');
                """,
                "scripts/nested/child/three.js": "globalThis.three = true;\n",
                "scripts/dynamic.js": "throw new Error('not statically copied');\n",
                "outside.js": "throw new Error('outside worker directory');\n",
            ]
        )

        let result = try makeWriter(rootURL: stage.storeRoot)
            .writeGeneratedBundle(
                originalBundleRecord: stage.result.originalBundleRecord,
                manifestSnapshot: stage.result.manifestSnapshot,
                planningRecord: stage.result.generatedBundlePlan
            )

        let expectedCopiedPaths = [
            "scripts/background.js",
            "scripts/deps/one.js",
            "scripts/nested/child/three.js",
            "scripts/nested/two.js",
        ]
        XCTAssertEqual(result.record.copiedResourcePaths, expectedCopiedPaths)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: result.generatedBundleRootURL
                    .appendingPathComponent("scripts/dynamic.js")
                    .path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: result.generatedBundleRootURL
                    .appendingPathComponent("outside.js")
                    .path
            )
        )
    }

    func testRejectsSymlinkReferencedResource() throws {
        let stage = try stageBundle(
            named: "symlink-resource",
            manifest: minimalManifest(),
            files: [
                "background.js": "chrome.runtime.onInstalled.addListener(() => {});\n",
            ]
        )
        let originalRootURL = URL(
            fileURLWithPath: stage.result.originalBundleRecord.storedPaths
                .originalBundleRootPath,
            isDirectory: true
        )
        let backgroundURL = originalRootURL.appendingPathComponent("background.js")
        try FileManager.default.removeItem(at: backgroundURL)
        try FileManager.default.createSymbolicLink(
            at: backgroundURL,
            withDestinationURL: URL(fileURLWithPath: "/tmp/sumi-background.js")
        )

        XCTAssertThrowsError(
            try makeWriter(rootURL: stage.storeRoot).writeGeneratedBundle(
                originalBundleRecord: stage.result.originalBundleRecord,
                manifestSnapshot: stage.result.manifestSnapshot,
                planningRecord: stage.result.generatedBundlePlan
            )
        ) { error in
            XCTAssertTrue(
                String(describing: error)
                    .localizedCaseInsensitiveContains("symbolic link")
            )
        }
    }

    func testRejectsPathTraversalFromManifestSnapshot() throws {
        let stage = try stageBundle(
            named: "traversal-resource",
            manifest: minimalManifest(),
            files: [
                "background.js": "",
            ]
        )
        var snapshot = stage.result.manifestSnapshot
        snapshot.canonicalManifestJSON = try canonicalJSONString([
            "manifest_version": 3,
            "name": "Traversal Resource",
            "version": "1.0",
            "background": [
                "service_worker": "../background.js",
            ],
        ])

        XCTAssertThrowsError(
            try makeWriter(rootURL: stage.storeRoot).writeGeneratedBundle(
                originalBundleRecord: stage.result.originalBundleRecord,
                manifestSnapshot: snapshot,
                planningRecord: stage.result.generatedBundlePlan
            )
        ) { error in
            XCTAssertTrue(String(describing: error).contains("Unsafe"))
        }
    }

    func testGeneratedBundleWriterSourceDoesNotConstructRuntimeObjects() throws {
        let source = try String(
            contentsOf: projectRoot()
                .appendingPathComponent(
                    "Sumi/Models/Extension/ChromeMV3/ChromeMV3GeneratedBundleWriter.swift"
                ),
            encoding: .utf8
        )
        for forbidden in [
            "import " + "WebKit",
            "WKWebExtension" + "Controller(",
            "WKWebExtension" + "Context(",
            "WK" + "WebExtension(",
            "webExtension" + "Controller =",
            "add" + "UserScript",
            "connect" + "Native",
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

    private struct StageBundle {
        var storeRoot: URL
        var result: ChromeMV3OriginalBundleStageResult
    }

    private func stageBundle(
        named name: String,
        manifest: [String: Any],
        files: [String: String]
    ) throws -> StageBundle {
        let fixture = try makeFixture(
            named: name,
            manifest: manifest,
            files: files
        )
        let storeRoot = try makeTemporaryDirectory()
        let result = try ChromeMV3OriginalBundleStore(
            rootURL: storeRoot,
            now: { self.fixedInstallDate }
        ).stageUnpackedDirectory(at: fixture)
        return StageBundle(storeRoot: storeRoot, result: result)
    }

    private func makeWriter(rootURL: URL) -> ChromeMV3GeneratedBundleWriter {
        ChromeMV3GeneratedBundleWriter(rootURL: rootURL)
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

    private func generatedRoot(storeRoot: URL, recordID: String) -> URL {
        storeRoot
            .appendingPathComponent("generated", isDirectory: true)
            .appendingPathComponent(recordID, isDirectory: true)
            .appendingPathComponent("generated", isDirectory: true)
    }

    private func generatedFileContents(rootURL: URL) throws -> [String: String] {
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

    private func canonicalJSONString(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
