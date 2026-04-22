import Foundation
import JavaScriptCore
import SwiftData
import WebKit
import XCTest
@testable import Sumi

@available(macOS 15.5, *)
@MainActor
extension ExtensionManagerTests {
    func testResolveInstallSourceFindsSafariResourcesInsideAppBundle() throws {
        let fixture = try makeSafariExtensionFixture()

        let resolved = try ExtensionManager.resolveInstallSource(at: fixture.appURL)

        XCTAssertEqual(resolved.sourceKind, .app)
        XCTAssertEqual(resolved.resourcesURL.standardizedFileURL, fixture.resourcesURL.standardizedFileURL)
        XCTAssertEqual(resolved.sourceBundlePath.standardizedFileURL, fixture.appURL.standardizedFileURL)
    }

    func testResolveInstallSourceSupportsAppExtensionAndDirectory() throws {
        let fixture = try makeSafariExtensionFixture()

        let appexResolved = try ExtensionManager.resolveInstallSource(at: fixture.appexURL)
        XCTAssertEqual(appexResolved.sourceKind, .appex)
        XCTAssertEqual(appexResolved.resourcesURL.standardizedFileURL, fixture.resourcesURL.standardizedFileURL)

        let directoryURL = fixture.rootURL.appendingPathComponent("Unpacked", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data(
            """
            {"manifest_version":2,"name":"Unpacked","version":"1.0"}
            """.utf8
        ).write(to: directoryURL.appendingPathComponent("manifest.json"))

        let directoryResolved = try ExtensionManager.resolveInstallSource(at: directoryURL)
        XCTAssertEqual(directoryResolved.sourceKind, .directory)
        XCTAssertEqual(directoryResolved.resourcesURL.standardizedFileURL, directoryURL.standardizedFileURL)
    }

    func testPatchManifestAddsBridgeEntryWithoutInjectingScriptingPermission() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        let manifest: [String: Any] = [
            "manifest_version": 2,
            "name": "Bridge Test",
            "version": "1.0",
            "externally_connectable": [
                "matches": ["https://accounts.example.com/*"]
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: manifestURL)

        manager.patchManifestForWebKit(at: manifestURL)

        let patched = try ExtensionUtils.validateManifest(at: manifestURL)
        let permissions = patched["permissions"] as? [String] ?? []
        let contentScripts = patched["content_scripts"] as? [[String: Any]] ?? []
        let bridgeEntry = contentScripts.first {
            (($0["js"] as? [String]) ?? []).contains("sumi_bridge.js")
        }

        XCTAssertFalse(permissions.contains("scripting"))
        XCTAssertEqual(bridgeEntry?["run_at"] as? String, "document_start")
        XCTAssertEqual(bridgeEntry?["all_frames"] as? Bool, true)
        XCTAssertEqual(bridgeEntry?["matches"] as? [String], ["https://accounts.example.com/*"])
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: rootURL.appendingPathComponent("sumi_bridge.js").path
            )
        )
    }

    func testPatchManifestAddsBackgroundHelperForMV2Scripts() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        let manifest: [String: Any] = [
            "manifest_version": 2,
            "name": "External Background Bridge",
            "version": "1.0",
            "externally_connectable": [
                "matches": ["https://accounts.example.com/*"]
            ],
            "background": [
                "persistent": false,
                "scripts": ["background.js"]
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: manifestURL)
        try "console.log('background');\n".write(
            to: rootURL.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )

        manager.patchManifestForWebKit(at: manifestURL)

        let patched = try ExtensionUtils.validateManifest(at: manifestURL)
        let background = try XCTUnwrap(patched["background"] as? [String: Any])
        let scripts = try XCTUnwrap(background["scripts"] as? [String])

        XCTAssertEqual(
            scripts,
            ["sumi_external_runtime.js", "background.js"]
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: rootURL.appendingPathComponent("sumi_external_runtime.js").path
            )
        )
    }

    func testPatchManifestWrapsMV3ServiceWorkerForExternalHelper() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "External Service Worker Bridge",
            "version": "1.0",
            "externally_connectable": [
                "matches": ["https://accounts.example.com/*"]
            ],
            "background": [
                "service_worker": "background.js"
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: manifestURL)
        try "console.log('sw');\n".write(
            to: rootURL.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )

        manager.patchManifestForWebKit(at: manifestURL)

        let patched = try ExtensionUtils.validateManifest(at: manifestURL)
        let background = try XCTUnwrap(patched["background"] as? [String: Any])
        XCTAssertEqual(
            background["service_worker"] as? String,
            "sumi_external_worker.js"
        )

        let wrapperURL = rootURL.appendingPathComponent("sumi_external_worker.js")
        let wrapperSource = try String(contentsOf: wrapperURL, encoding: .utf8)
        XCTAssertTrue(wrapperSource.contains("SUMI_EC_ORIGINAL_SERVICE_WORKER: background.js"))
        XCTAssertTrue(wrapperSource.contains("importScripts(\"sumi_external_runtime.js\", \"background.js\");"))
    }

    func testPatchManifestDeduplicatesExternallyConnectableBridgeEntries() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        let manifest: [String: Any] = [
            "manifest_version": 2,
            "name": "Duplicate External Bridge",
            "version": "1.0",
            "externally_connectable": [
                "matches": ["https://example.com/*"]
            ],
            "content_scripts": [
                [
                    "all_frames": true,
                    "js": ["sumi_bridge.js"],
                    "matches": ["https://old.example/*"],
                    "run_at": "document_end",
                ],
                [
                    "all_frames": false,
                    "js": ["sumi_bridge.js"],
                    "matches": ["https://duplicate.example/*"],
                    "run_at": "document_idle",
                ],
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: manifestURL)

        manager.patchManifestForWebKit(at: manifestURL)

        let patched = try ExtensionUtils.validateManifest(at: manifestURL)
        let contentScripts = patched["content_scripts"] as? [[String: Any]] ?? []
        let bridgeEntries = contentScripts.filter {
            (($0["js"] as? [String]) ?? []).contains("sumi_bridge.js")
        }

        XCTAssertEqual(bridgeEntries.count, 1)
        XCTAssertEqual(bridgeEntries[0]["matches"] as? [String], ["https://example.com/*"])
        XCTAssertEqual(bridgeEntries[0]["run_at"] as? String, "document_start")
        XCTAssertEqual(bridgeEntries[0]["all_frames"] as? Bool, true)
    }

    func testPatchManifestForExternallyConnectableIsIdempotentAcrossRepeatedRuns() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        let manifest: [String: Any] = [
            "manifest_version": 2,
            "name": "Idempotent External Bridge",
            "version": "1.0",
            "externally_connectable": [
                "matches": ["https://example.com/*"]
            ],
            "background": [
                "scripts": ["background.js"]
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: manifestURL)
        try "console.log('background');\n".write(
            to: rootURL.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )

        manager.patchManifestForWebKit(at: manifestURL)
        let firstPatchedManifest = try Data(contentsOf: manifestURL)
        let firstBridgeScript = try Data(
            contentsOf: rootURL.appendingPathComponent("sumi_bridge.js")
        )
        let firstBackgroundHelper = try Data(
            contentsOf: rootURL.appendingPathComponent("sumi_external_runtime.js")
        )

        manager.patchManifestForWebKit(at: manifestURL)
        let secondPatchedManifest = try Data(contentsOf: manifestURL)
        let secondBridgeScript = try Data(
            contentsOf: rootURL.appendingPathComponent("sumi_bridge.js")
        )
        let secondBackgroundHelper = try Data(
            contentsOf: rootURL.appendingPathComponent("sumi_external_runtime.js")
        )

        XCTAssertEqual(firstPatchedManifest, secondPatchedManifest)
        XCTAssertEqual(firstBridgeScript, secondBridgeScript)
        XCTAssertEqual(firstBackgroundHelper, secondBackgroundHelper)

        let patched = try ExtensionUtils.validateManifest(at: manifestURL)
        let contentScripts = patched["content_scripts"] as? [[String: Any]] ?? []
        let bridgeEntries = contentScripts.filter {
            (($0["js"] as? [String]) ?? []).contains("sumi_bridge.js")
        }
        let background = try XCTUnwrap(patched["background"] as? [String: Any])
        let scripts = try XCTUnwrap(background["scripts"] as? [String])

        XCTAssertEqual(bridgeEntries.count, 1)
        XCTAssertEqual(scripts.filter { $0 == "sumi_external_runtime.js" }.count, 1)
    }

    func testPatchManifestAddsWebKitRuntimeCompatibilityPreludeForSafariMV2Background() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        let manifest: [String: Any] = [
            "manifest_version": 2,
            "name": "Safari Runtime Compatibility",
            "version": "1.0",
            "browser_specific_settings": [
                "safari": [
                    "strict_min_version": "14.0"
                ]
            ],
            "background": [
                "scripts": ["background.js"]
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: manifestURL)
        try "console.log('background');\n".write(
            to: rootURL.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )

        manager.patchManifestForWebKit(at: manifestURL)

        let patched = try ExtensionUtils.validateManifest(at: manifestURL)
        let background = try XCTUnwrap(patched["background"] as? [String: Any])
        let scripts = try XCTUnwrap(background["scripts"] as? [String])
        let preludeURL = rootURL.appendingPathComponent(
            ExtensionManager.webKitRuntimeCompatibilityPreludeFilename
        )

        XCTAssertEqual(
            scripts.first,
            ExtensionManager.webKitRuntimeCompatibilityPreludeFilename
        )
        XCTAssertEqual(scripts.filter {
            $0 == ExtensionManager.webKitRuntimeCompatibilityPreludeFilename
        }.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: preludeURL.path))

        let source = try String(contentsOf: preludeURL, encoding: .utf8)
        XCTAssertTrue(source.contains("browser_specific_settings"))
        XCTAssertTrue(source.contains("strict_min_version"))
    }

    func testPatchManifestKeepsOnlyCompatibilityPreludeForSafariMV2Background() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        let manifest: [String: Any] = [
            "manifest_version": 2,
            "name": "Safari Runtime Policy",
            "version": "1.0",
            "browser_specific_settings": [
                "safari": [
                    "strict_min_version": "14.0"
                ]
            ],
            "background": [
                "scripts": ["background.js"]
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: manifestURL)
        try "console.log('background');\n".write(
            to: rootURL.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )

        manager.patchManifestForWebKit(at: manifestURL)

        let patched = try ExtensionUtils.validateManifest(at: manifestURL)
        let background = try XCTUnwrap(patched["background"] as? [String: Any])
        let scripts = try XCTUnwrap(background["scripts"] as? [String])
        XCTAssertEqual(
            Array(scripts.prefix(2)),
            [
                ExtensionManager.webKitRuntimeCompatibilityPreludeFilename,
                "background.js",
            ]
        )
    }

    func testPatchManifestKeepsCompatibilityArtifactsByteStableAcrossRepeatedRuns() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        let manifest: [String: Any] = [
            "manifest_version": 2,
            "name": "Safari Runtime Compatibility Stability",
            "version": "1.0",
            "browser_specific_settings": [
                "safari": [
                    "strict_min_version": "14.0"
                ]
            ],
            "background": [
                "scripts": ["background.js"]
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: manifestURL)
        try "console.log('background');\n".write(
            to: rootURL.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )

        manager.patchManifestForWebKit(at: manifestURL)
        let firstPatchedManifest = try Data(contentsOf: manifestURL)
        let firstPrelude = try Data(
            contentsOf: rootURL.appendingPathComponent(
                ExtensionManager.webKitRuntimeCompatibilityPreludeFilename
            )
        )

        manager.patchManifestForWebKit(at: manifestURL)
        let secondPatchedManifest = try Data(contentsOf: manifestURL)
        let secondPrelude = try Data(
            contentsOf: rootURL.appendingPathComponent(
                ExtensionManager.webKitRuntimeCompatibilityPreludeFilename
            )
        )

        XCTAssertEqual(firstPatchedManifest, secondPatchedManifest)
        XCTAssertEqual(firstPrelude, secondPrelude)
    }

    func testPatchManifestWebKitRuntimeCompatibilityPreludeIsIdempotentAndSafariOnly() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let safariRootURL = try temporaryDirectory()
        let geckoRootURL = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: safariRootURL)
            try? FileManager.default.removeItem(at: geckoRootURL)
        }

        let safariManifestURL = safariRootURL.appendingPathComponent("manifest.json")
        try JSONSerialization.data(
            withJSONObject: [
                "manifest_version": 2,
                "name": "Safari Idempotent Runtime Compatibility",
                "version": "1.0",
                "browser_specific_settings": [
                    "safari": [
                        "strict_min_version": "14.0"
                    ]
                ],
                "background": [
                    "scripts": ["background.js"]
                ],
            ],
            options: [.sortedKeys]
        ).write(to: safariManifestURL)
        try "console.log('background');\n".write(
            to: safariRootURL.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )

        manager.patchManifestForWebKit(at: safariManifestURL)
        let firstPatchedManifest = try Data(contentsOf: safariManifestURL)
        manager.patchManifestForWebKit(at: safariManifestURL)
        let secondPatchedManifest = try Data(contentsOf: safariManifestURL)
        let safariPatched = try ExtensionUtils.validateManifest(at: safariManifestURL)
        let safariBackground = try XCTUnwrap(safariPatched["background"] as? [String: Any])
        let safariScripts = try XCTUnwrap(safariBackground["scripts"] as? [String])

        XCTAssertEqual(firstPatchedManifest, secondPatchedManifest)
        XCTAssertEqual(safariScripts.filter {
            $0 == ExtensionManager.webKitRuntimeCompatibilityPreludeFilename
        }.count, 1)

        let geckoManifestURL = geckoRootURL.appendingPathComponent("manifest.json")
        try JSONSerialization.data(
            withJSONObject: [
                "manifest_version": 2,
                "name": "Gecko Runtime Compatibility",
                "version": "1.0",
                "browser_specific_settings": [
                    "gecko": [
                        "id": "fixture@example.com"
                    ]
                ],
                "background": [
                    "scripts": ["background.js"]
                ],
            ],
            options: [.sortedKeys]
        ).write(to: geckoManifestURL)
        try "console.log('background');\n".write(
            to: geckoRootURL.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )

        manager.patchManifestForWebKit(at: geckoManifestURL)

        let geckoPatched = try ExtensionUtils.validateManifest(at: geckoManifestURL)
        let geckoBackground = try XCTUnwrap(geckoPatched["background"] as? [String: Any])
        let geckoScripts = try XCTUnwrap(geckoBackground["scripts"] as? [String])

        XCTAssertFalse(geckoScripts.contains(ExtensionManager.webKitRuntimeCompatibilityPreludeFilename))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: geckoRootURL
                    .appendingPathComponent(ExtensionManager.webKitRuntimeCompatibilityPreludeFilename)
                    .path
            )
        )
    }

    func testPatchManifestSelectiveContentScriptGuardIsDisabledByDefault() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        try JSONSerialization.data(
            withJSONObject: [
                "manifest_version": 2,
                "name": "SponsorBlock",
                "short_name": "SponsorBlock",
                "version": "1.0",
                "content_scripts": [[
                    "matches": ["https://*.youtube.com/*"],
                    "js": ["./js/content.js"],
                    "run_at": "document_start",
                ]],
            ],
            options: [.sortedKeys]
        ).write(to: manifestURL)
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent("js", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "console.log('content');\n".write(
            to: rootURL.appendingPathComponent("js/content.js"),
            atomically: true,
            encoding: .utf8
        )

        manager.patchManifestForWebKit(at: manifestURL)

        let patched = try ExtensionUtils.validateManifest(at: manifestURL)
        let contentScripts = try XCTUnwrap(patched["content_scripts"] as? [[String: Any]])
        let rootContents = try FileManager.default.contentsOfDirectory(atPath: rootURL.path)
        XCTAssertEqual(contentScripts[0]["js"] as? [String], ["./js/content.js"])
        XCTAssertFalse(
            rootContents.contains(where: { $0.hasPrefix("sumi_content_guard_") })
        )
    }

    func testPatchManifestSelectiveContentScriptGuardPatchesTargetedExtensionOnly() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let defaults = UserDefaults.standard
        let previousTargets = defaults.object(
            forKey: ExtensionManager.selectiveContentScriptGuardTargetsKey
        )
        defaults.set(["sponsorblock"], forKey: ExtensionManager.selectiveContentScriptGuardTargetsKey)
        defer {
            if let previousTargets {
                defaults.set(
                    previousTargets,
                    forKey: ExtensionManager.selectiveContentScriptGuardTargetsKey
                )
            } else {
                defaults.removeObject(forKey: ExtensionManager.selectiveContentScriptGuardTargetsKey)
            }
        }

        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        try JSONSerialization.data(
            withJSONObject: [
                "manifest_version": 2,
                "name": "SponsorBlock",
                "short_name": "SponsorBlock",
                "version": "1.0",
                "content_scripts": [[
                    "matches": ["https://*.youtube.com/*"],
                    "js": ["./js/content.js"],
                    "run_at": "document_start",
                ]],
            ],
            options: [.sortedKeys]
        ).write(to: manifestURL)
        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent("js", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "console.log('content');\n".write(
            to: rootURL.appendingPathComponent("js/content.js"),
            atomically: true,
            encoding: .utf8
        )

        manager.patchManifestForWebKit(at: manifestURL)

        let patched = try ExtensionUtils.validateManifest(at: manifestURL)
        let contentScripts = try XCTUnwrap(patched["content_scripts"] as? [[String: Any]])
        let jsFiles = try XCTUnwrap(contentScripts[0]["js"] as? [String])
        XCTAssertEqual(jsFiles.count, 1)
        XCTAssertTrue(jsFiles[0].hasPrefix("sumi_content_guard_"))

        let guardURL = rootURL.appendingPathComponent(jsFiles[0])
        XCTAssertTrue(FileManager.default.fileExists(atPath: guardURL.path))

        let guardSource = try String(contentsOf: guardURL, encoding: .utf8)
        XCTAssertFalse(guardSource.contains("data-sumi-cs-trace-"))
        XCTAssertTrue(guardSource.contains("XMLHttpRequest"))
    }

    func testWebKitRuntimeCompatibilityPreludePatchesRuntimeGetManifestWithoutOverwritingExistingValue() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        try JSONSerialization.data(
            withJSONObject: [
                "manifest_version": 2,
                "name": "Runtime Compatibility JS",
                "version": "1.0",
                "browser_specific_settings": [
                    "safari": [
                        "strict_min_version": "14.0"
                    ]
                ],
                "background": [
                    "scripts": ["background.js"]
                ],
            ],
            options: [.sortedKeys]
        ).write(to: manifestURL)
        try "console.log('background');\n".write(
            to: rootURL.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )

        manager.patchManifestForWebKit(at: manifestURL)

        let source = try String(
            contentsOf: rootURL.appendingPathComponent(
                ExtensionManager.webKitRuntimeCompatibilityPreludeFilename
            ),
            encoding: .utf8
        )

        let missingValueContext = try makeJavaScriptContextEvaluatingPrelude(
            source,
            manifestExpression: "({ name: 'Fixture', version: '1.0' })"
        )
        let missingValueJSON = try XCTUnwrap(
            missingValueContext.evaluateScript("JSON.stringify(chrome.runtime.getManifest())")?
                .toString()
        )
        let missingValueData = try XCTUnwrap(missingValueJSON.data(using: .utf8))
        let missingValueManifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: missingValueData) as? [String: Any]
        )
        let restoredSettings = try XCTUnwrap(
            missingValueManifest["browser_specific_settings"] as? [String: Any]
        )
        let restoredSafariSettings = try XCTUnwrap(restoredSettings["safari"] as? [String: Any])

        XCTAssertEqual(missingValueManifest["name"] as? String, "Fixture")
        XCTAssertEqual(restoredSafariSettings["strict_min_version"] as? String, "14.0")

        let existingValueContext = try makeJavaScriptContextEvaluatingPrelude(
            source,
            manifestExpression: "({ name: 'Fixture', version: '1.0', browser_specific_settings: { gecko: { id: 'fixture@example.com' } } })"
        )
        let existingValueJSON = try XCTUnwrap(
            existingValueContext.evaluateScript("JSON.stringify(chrome.runtime.getManifest())")?
                .toString()
        )
        let existingValueData = try XCTUnwrap(existingValueJSON.data(using: .utf8))
        let existingValueManifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: existingValueData) as? [String: Any]
        )
        let existingSettings = try XCTUnwrap(
            existingValueManifest["browser_specific_settings"] as? [String: Any]
        )

        XCTAssertNotNil(existingSettings["gecko"])
        XCTAssertNil(existingSettings["safari"])
    }

    func testWebKitRuntimeCompatibilityPreludeAlsoPatchesBrowserRuntimeGetManifest() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        try JSONSerialization.data(
            withJSONObject: [
                "manifest_version": 2,
                "name": "Browser Runtime Compatibility Fixture",
                "version": "1.0",
                "browser_specific_settings": [
                    "safari": [
                        "strict_min_version": "14.0"
                    ]
                ],
                "background": [
                    "scripts": ["background.js"]
                ],
            ],
            options: [.sortedKeys]
        ).write(to: manifestURL)
        try "console.log('background');\n".write(
            to: rootURL.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )

        manager.patchManifestForWebKit(at: manifestURL)

        let source = try String(
            contentsOf: rootURL.appendingPathComponent(
                ExtensionManager.webKitRuntimeCompatibilityPreludeFilename
            ),
            encoding: .utf8
        )

        let context = try XCTUnwrap(JSContext())
        var thrownException: JSValue?
        context.exceptionHandler = { _, exception in
            thrownException = exception
        }
        context.evaluateScript(
            """
            var browser = {
              runtime: {
                getManifest: function () {
                  return { name: 'Fixture', version: '1.0' };
                }
              }
            };
            var chrome = {
              runtime: browser.runtime
            };
            var console = {
              log: function () {},
              warn: function () {},
              error: function () {}
            };
            """
        )
        context.evaluateScript(source)

        if let thrownException {
            XCTFail("Prelude JavaScript threw: \(thrownException)")
        }

        let browserManifestJSON = try XCTUnwrap(
            context.evaluateScript("JSON.stringify(browser.runtime.getManifest())")?.toString()
        )
        let browserManifestData = try XCTUnwrap(browserManifestJSON.data(using: .utf8))
        let browserManifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: browserManifestData) as? [String: Any]
        )
        let browserSettings = try XCTUnwrap(
            browserManifest["browser_specific_settings"] as? [String: Any]
        )
        let safariSettings = try XCTUnwrap(browserSettings["safari"] as? [String: Any])

        XCTAssertEqual(browserManifest["name"] as? String, "Fixture")
        XCTAssertEqual(safariSettings["strict_min_version"] as? String, "14.0")
    }

    func testWebKitRuntimeCompatibilityPreludePatchesChromeAssignedAfterPrelude() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        try JSONSerialization.data(
            withJSONObject: [
                "manifest_version": 2,
                "name": "Late Chrome Runtime Compatibility Fixture",
                "version": "1.0",
                "browser_specific_settings": [
                    "safari": [
                        "strict_min_version": "14.0"
                    ]
                ],
                "background": [
                    "scripts": ["background.js"]
                ],
            ],
            options: [.sortedKeys]
        ).write(to: manifestURL)
        try "console.log('background');\n".write(
            to: rootURL.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )

        manager.patchManifestForWebKit(at: manifestURL)

        let source = try String(
            contentsOf: rootURL.appendingPathComponent(
                ExtensionManager.webKitRuntimeCompatibilityPreludeFilename
            ),
            encoding: .utf8
        )
        let context = try XCTUnwrap(JSContext())
        var thrownException: JSValue?
        context.exceptionHandler = { _, exception in
            thrownException = exception
        }

        context.evaluateScript(
            """
            var console = {
              log: function () {},
              warn: function () {},
              error: function () {}
            };
            """
        )
        context.evaluateScript(source)
        context.evaluateScript(
            """
            globalThis.chrome = {
              runtime: {
                getManifest: function () {
                  return { name: 'Late Chrome Fixture', version: '1.0' };
                }
              }
            };
            """
        )
        context.evaluateScript(source)

        if let thrownException {
            XCTFail("Prelude JavaScript threw: \(thrownException)")
        }

        let chromeManifest = try manifestDictionary(
            from: context,
            expression: "chrome.runtime.getManifest()"
        )
        let settings = try XCTUnwrap(chromeManifest["browser_specific_settings"] as? [String: Any])
        let safariSettings = try XCTUnwrap(settings["safari"] as? [String: Any])

        XCTAssertEqual(chromeManifest["name"] as? String, "Late Chrome Fixture")
        XCTAssertEqual(safariSettings["strict_min_version"] as? String, "14.0")
        XCTAssertEqual(
            context.evaluateScript("Boolean(chrome.runtime.getManifest.__sumiWebKitRuntimeCompatibilityWrapped)")?
                .toBool(),
            true
        )
    }

    func testWebKitRuntimeCompatibilityPreludePatchesRuntimeAssignedAfterChrome() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        try JSONSerialization.data(
            withJSONObject: [
                "manifest_version": 2,
                "name": "Late Runtime Compatibility Fixture",
                "version": "1.0",
                "browser_specific_settings": [
                    "safari": [
                        "strict_min_version": "14.0"
                    ]
                ],
                "background": [
                    "scripts": ["background.js"]
                ],
            ],
            options: [.sortedKeys]
        ).write(to: manifestURL)
        try "console.log('background');\n".write(
            to: rootURL.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )

        manager.patchManifestForWebKit(at: manifestURL)

        let source = try String(
            contentsOf: rootURL.appendingPathComponent(
                ExtensionManager.webKitRuntimeCompatibilityPreludeFilename
            ),
            encoding: .utf8
        )
        let context = try XCTUnwrap(JSContext())
        var thrownException: JSValue?
        context.exceptionHandler = { _, exception in
            thrownException = exception
        }

        context.evaluateScript(
            """
            var chrome = {};
            var console = {
              log: function () {},
              warn: function () {},
              error: function () {}
            };
            """
        )
        context.evaluateScript(source)
        context.evaluateScript(
            """
            chrome.runtime = {
              getManifest: function () {
                return { name: 'Late Runtime Fixture', version: '1.0' };
              }
            };
            """
        )

        if let thrownException {
            XCTFail("Prelude JavaScript threw: \(thrownException)")
        }

        let chromeManifest = try manifestDictionary(
            from: context,
            expression: "chrome.runtime.getManifest()"
        )
        let settings = try XCTUnwrap(chromeManifest["browser_specific_settings"] as? [String: Any])
        let safariSettings = try XCTUnwrap(settings["safari"] as? [String: Any])

        XCTAssertEqual(chromeManifest["name"] as? String, "Late Runtime Fixture")
        XCTAssertEqual(safariSettings["strict_min_version"] as? String, "14.0")
    }

    func testWebKitRuntimeCompatibilityPreludePatchesSeparateChromeAndBrowserRuntimes() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        try JSONSerialization.data(
            withJSONObject: [
                "manifest_version": 2,
                "name": "Separate Runtime Compatibility Fixture",
                "version": "1.0",
                "browser_specific_settings": [
                    "safari": [
                        "strict_min_version": "14.0"
                    ]
                ],
                "background": [
                    "scripts": ["background.js"]
                ],
            ],
            options: [.sortedKeys]
        ).write(to: manifestURL)
        try "console.log('background');\n".write(
            to: rootURL.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )

        manager.patchManifestForWebKit(at: manifestURL)

        let source = try String(
            contentsOf: rootURL.appendingPathComponent(
                ExtensionManager.webKitRuntimeCompatibilityPreludeFilename
            ),
            encoding: .utf8
        )
        let context = try XCTUnwrap(JSContext())
        var thrownException: JSValue?
        context.exceptionHandler = { _, exception in
            thrownException = exception
        }

        context.evaluateScript(
            """
            var chrome = {
              runtime: {
                getManifest: function () {
                  return { name: 'Chrome Fixture', version: '1.0' };
                }
              }
            };
            var browser = {
              runtime: {
                getManifest: function () {
                  return { name: 'Browser Fixture', version: '1.0' };
                }
              }
            };
            var console = {
              log: function () {},
              warn: function () {},
              error: function () {}
            };
            """
        )
        context.evaluateScript(source)

        if let thrownException {
            XCTFail("Prelude JavaScript threw: \(thrownException)")
        }

        let chromeManifest = try manifestDictionary(
            from: context,
            expression: "chrome.runtime.getManifest()"
        )
        let browserManifest = try manifestDictionary(
            from: context,
            expression: "browser.runtime.getManifest()"
        )

        XCTAssertEqual(chromeManifest["name"] as? String, "Chrome Fixture")
        XCTAssertEqual(browserManifest["name"] as? String, "Browser Fixture")
        XCTAssertNotNil((chromeManifest["browser_specific_settings"] as? [String: Any])?["safari"])
        XCTAssertNotNil((browserManifest["browser_specific_settings"] as? [String: Any])?["safari"])
    }

    func testWebKitRuntimeCompatibilityPreludeSuppressesProgrammaticContentScriptAPIs() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        try JSONSerialization.data(
            withJSONObject: [
                "manifest_version": 2,
                "name": "Programmatic Content Script Policy Fixture",
                "version": "1.0",
                "browser_specific_settings": [
                    "safari": [
                        "strict_min_version": "14.0"
                    ]
                ],
                "background": [
                    "scripts": ["background.js"]
                ],
            ],
            options: [.sortedKeys]
        ).write(to: manifestURL)
        try "console.log('background');\n".write(
            to: rootURL.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )

        manager.patchManifestForWebKit(at: manifestURL)

        let source = try String(
            contentsOf: rootURL.appendingPathComponent(
                ExtensionManager.webKitRuntimeCompatibilityPreludeFilename
            ),
            encoding: .utf8
        )
        let context = try XCTUnwrap(JSContext())
        var thrownException: JSValue?
        context.exceptionHandler = { _, exception in
            thrownException = exception
        }

        context.evaluateScript(
            """
            var browser = {
              runtime: {
                getManifest: function () {
                  return { name: 'Fixture', version: '1.0' };
                }
              },
              contentScripts: {
                register: function () { return 'contentScripts.register'; }
              },
              scripting: {
                registerContentScripts: function () { return 'scripting.registerContentScripts'; },
                executeScript: function () { return 'scripting.executeScript'; },
                insertCSS: function () { return 'scripting.insertCSS'; }
              },
              tabs: {
                executeScript: function () { return 'tabs.executeScript'; },
                insertCSS: function () { return 'tabs.insertCSS'; }
              }
            };
            var chrome = browser;
            var console = {
              log: function () {},
              warn: function () {},
              error: function () {}
            };
            """
        )
        context.evaluateScript(source)

        if let thrownException {
            XCTFail("Prelude JavaScript threw: \(thrownException)")
        }

        XCTAssertEqual(
            context.evaluateScript("typeof browser.contentScripts.register")?.toString(),
            "undefined"
        )
        XCTAssertEqual(
            context.evaluateScript("typeof browser.scripting.registerContentScripts")?.toString(),
            "undefined"
        )
        XCTAssertEqual(
            context.evaluateScript("typeof browser.scripting.executeScript")?.toString(),
            "undefined"
        )
        XCTAssertEqual(
            context.evaluateScript("typeof browser.scripting.insertCSS")?.toString(),
            "undefined"
        )
        XCTAssertEqual(
            context.evaluateScript("typeof browser.tabs.executeScript")?.toString(),
            "undefined"
        )
        XCTAssertEqual(
            context.evaluateScript("typeof browser.tabs.insertCSS")?.toString(),
            "undefined"
        )
    }

    func testWebKitRuntimeCompatibilityPreludeSuppressesLateAssignedProgrammaticContentScriptAPIs() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        try JSONSerialization.data(
            withJSONObject: [
                "manifest_version": 2,
                "name": "Late Programmatic Content Script Policy Fixture",
                "version": "1.0",
                "browser_specific_settings": [
                    "safari": [
                        "strict_min_version": "14.0"
                    ]
                ],
                "background": [
                    "scripts": ["background.js"]
                ],
            ],
            options: [.sortedKeys]
        ).write(to: manifestURL)
        try "console.log('background');\n".write(
            to: rootURL.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )

        manager.patchManifestForWebKit(at: manifestURL)

        let source = try String(
            contentsOf: rootURL.appendingPathComponent(
                ExtensionManager.webKitRuntimeCompatibilityPreludeFilename
            ),
            encoding: .utf8
        )
        let context = try XCTUnwrap(JSContext())
        var thrownException: JSValue?
        context.exceptionHandler = { _, exception in
            thrownException = exception
        }

        context.evaluateScript(
            """
            var browser = {
              runtime: {
                getManifest: function () {
                  return { name: 'Fixture', version: '1.0' };
                }
              }
            };
            var chrome = {};
            var console = {
              log: function () {},
              warn: function () {},
              error: function () {}
            };
            """
        )
        context.evaluateScript(source)
        context.evaluateScript(
            """
            chrome.contentScripts = {
              register: function () { return 'contentScripts.register'; }
            };
            chrome.scripting = {
              registerContentScripts: function () { return 'scripting.registerContentScripts'; },
              executeScript: function () { return 'scripting.executeScript'; },
              insertCSS: function () { return 'scripting.insertCSS'; }
            };
            chrome.tabs = {
              executeScript: function () { return 'tabs.executeScript'; },
              insertCSS: function () { return 'tabs.insertCSS'; }
            };
            """
        )

        if let thrownException {
            XCTFail("Prelude JavaScript threw: \(thrownException)")
        }

        XCTAssertEqual(
            context.evaluateScript("typeof chrome.contentScripts.register")?.toString(),
            "undefined"
        )
        XCTAssertEqual(
            context.evaluateScript("typeof chrome.scripting.registerContentScripts")?.toString(),
            "undefined"
        )
        XCTAssertEqual(
            context.evaluateScript("typeof chrome.scripting.executeScript")?.toString(),
            "undefined"
        )
        XCTAssertEqual(
            context.evaluateScript("typeof chrome.scripting.insertCSS")?.toString(),
            "undefined"
        )
        XCTAssertEqual(
            context.evaluateScript("typeof chrome.tabs.executeScript")?.toString(),
            "undefined"
        )
        XCTAssertEqual(
            context.evaluateScript("typeof chrome.tabs.insertCSS")?.toString(),
            "undefined"
        )
    }

    func testPrepareExtensionContextLeavesUnsupportedAPIsEmptyWhenSafariDiagnosticsDisabled() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let defaults = UserDefaults.standard
        let originalFlag = defaults.object(
            forKey: ExtensionManager.webKitRuntimeBlockProgrammaticContentScriptAPIsKey
        )
        defaults.removeObject(
            forKey: ExtensionManager.webKitRuntimeBlockProgrammaticContentScriptAPIsKey
        )
        defer {
            if let originalFlag {
                defaults.set(
                    originalFlag,
                    forKey: ExtensionManager.webKitRuntimeBlockProgrammaticContentScriptAPIsKey
                )
            } else {
                defaults.removeObject(
                    forKey: ExtensionManager.webKitRuntimeBlockProgrammaticContentScriptAPIsKey
                )
            }
        }

        let manifest: [String: Any] = [
            "manifest_version": 2,
            "name": "Safari Runtime Policy",
            "version": "1.0",
            "browser_specific_settings": [
                "safari": [
                    "strict_min_version": "14.0"
                ]
            ],
        ]
        let extensionRoot = try makeUnpackedExtensionDirectory(manifest: manifest)
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionRoot)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        manager.debugSetLoadedManifest(manifest, for: "safari.runtime.policy")
        manager.debugPrepareExtensionContextForRuntime(
            extensionContext,
            extensionId: "safari.runtime.policy"
        )

        XCTAssertEqual(
            extensionContext.unsupportedAPIs,
            Set([
                "browser.contentScripts.register",
                "browser.scripting.executeScript",
                "browser.scripting.insertCSS",
                "browser.scripting.registerContentScripts",
                "browser.tabs.executeScript",
                "browser.tabs.insertCSS",
            ])
        )
    }

    func testPrepareExtensionContextUsesUnsupportedAPIsForSafariDiagnostics() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let manifest: [String: Any] = [
            "manifest_version": 2,
            "name": "Safari Runtime Policy",
            "version": "1.0",
            "browser_specific_settings": [
                "safari": [
                    "strict_min_version": "14.0"
                ]
            ],
        ]
        let extensionRoot = try makeUnpackedExtensionDirectory(manifest: manifest)
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionRoot)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        manager.debugSetLoadedManifest(manifest, for: "safari.runtime.policy")
        manager.debugPrepareExtensionContextForRuntime(
            extensionContext,
            extensionId: "safari.runtime.policy"
        )

        XCTAssertEqual(
            extensionContext.unsupportedAPIs,
            Set([
                "browser.contentScripts.register",
                "browser.scripting.executeScript",
                "browser.scripting.insertCSS",
                "browser.scripting.registerContentScripts",
                "browser.tabs.executeScript",
                "browser.tabs.insertCSS",
            ])
        )
    }

    func testPrepareExtensionContextKeepsUnsupportedAPIsEmptyForNonSafariRuntime() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let manifest: [String: Any] = [
            "manifest_version": 2,
            "name": "Non Safari Runtime Policy",
            "version": "1.0",
        ]
        let extensionRoot = try makeUnpackedExtensionDirectory(manifest: manifest)
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionRoot)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        manager.debugSetLoadedManifest(manifest, for: "non.safari.runtime.policy")
        manager.debugPrepareExtensionContextForRuntime(
            extensionContext,
            extensionId: "non.safari.runtime.policy"
        )

        XCTAssertTrue(extensionContext.unsupportedAPIs.isEmpty)
    }

    func testSafariOnlyRuntimeDoesNotAutoGrantScriptingPermission() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let manifest: [String: Any] = [
            "manifest_version": 2,
            "name": "Safari Permission Fixture",
            "version": "1.0",
            "permissions": ["storage", "scripting"],
            "browser_specific_settings": [
                "safari": [
                    "strict_min_version": "14.0"
                ]
            ],
        ]
        let extensionRoot = try makeUnpackedExtensionDirectory(manifest: manifest)
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionRoot)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        manager.grantRequestedPermissions(
            to: extensionContext,
            webExtension: webExtension,
            manifest: manifest
        )

        let scriptingPermission = try requestedPermission(
            named: "scripting",
            in: webExtension
        )
        let storagePermission = try requestedPermission(
            named: "storage",
            in: webExtension
        )

        XCTAssertEqual(
            extensionContext.permissionStatus(for: scriptingPermission),
            .deniedExplicitly
        )
        XCTAssertEqual(
            extensionContext.permissionStatus(for: storagePermission),
            .grantedExplicitly
        )
    }

    func testNonSafariRuntimeStillAutoGrantsScriptingPermission() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let manifest: [String: Any] = [
            "manifest_version": 2,
            "name": "Non-Safari Permission Fixture",
            "version": "1.0",
            "permissions": ["storage", "scripting"],
        ]
        let extensionRoot = try makeUnpackedExtensionDirectory(manifest: manifest)
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionRoot)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        manager.grantRequestedPermissions(
            to: extensionContext,
            webExtension: webExtension,
            manifest: manifest
        )

        let scriptingPermission = try requestedPermission(
            named: "scripting",
            in: webExtension
        )

        XCTAssertEqual(
            extensionContext.permissionStatus(for: scriptingPermission),
            .grantedExplicitly
        )
    }

    func testPatchManifestRevertsLegacyMainWorldPatchOnlyForDomainSpecificScripts() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "World Patch Test",
            "version": "1.0",
            "content_scripts": [
                [
                    "matches": ["https://example.com/*"],
                    "js": ["content.js"],
                    "world": "MAIN",
                ],
                [
                    "matches": ["https://*.youtube.com/*"],
                    "js": ["document.js"],
                    "world": "MAIN",
                ],
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: manifestURL)

        manager.patchManifestForWebKit(at: manifestURL)

        let patched = try ExtensionUtils.validateManifest(at: manifestURL)
        let contentScripts = try XCTUnwrap(patched["content_scripts"] as? [[String: Any]])

        XCTAssertNil(contentScripts[0]["world"] as? String)
        XCTAssertEqual(contentScripts[1]["world"] as? String, "MAIN")
    }

    private func makeJavaScriptContextEvaluatingPrelude(
        _ source: String,
        manifestExpression: String
    ) throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        var thrownException: JSValue?
        context.exceptionHandler = { _, exception in
            thrownException = exception
        }

        context.evaluateScript(
            """
            var chrome = {
              runtime: {
                getManifest: function () {
                  return \(manifestExpression);
                }
              }
            };
            var console = {
              log: function () {},
              warn: function () {},
              error: function () {}
            };
            """
        )
        context.evaluateScript(source)

        if let thrownException {
            XCTFail("Prelude JavaScript threw: \(thrownException)")
        }

        return context
    }

    private func manifestDictionary(
        from context: JSContext,
        expression: String
    ) throws -> [String: Any] {
        let manifestJSON = try XCTUnwrap(
            context.evaluateScript("JSON.stringify(\(expression))")?.toString()
        )
        let manifestData = try XCTUnwrap(manifestJSON.data(using: .utf8))
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        )
    }

    private func requestedPermission(
        named name: String,
        in webExtension: WKWebExtension
    ) throws -> WKWebExtension.Permission {
        try XCTUnwrap(
            webExtension.requestedPermissions
                .union(webExtension.optionalPermissions)
                .first { $0.rawValue == name }
        )
    }

    func testValidatedExtensionPageURLRejectsPathTraversal() throws {
        let extensionRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        let escapedURL = extensionRoot
            .appendingPathComponent("../outside.html")

        XCTAssertThrowsError(
            try ExtensionUtils.validatedExtensionPageURL(
                escapedURL,
                within: extensionRoot
            )
        )
    }

    func testStoredOptionsPagePathFallsBackToCommonLocations() throws {
        let extensionRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Fallback Options",
            "version": "1.0",
        ]

        try FileManager.default.createDirectory(
            at: extensionRoot.appendingPathComponent("ui/options", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("<html></html>".utf8).write(
            to: extensionRoot.appendingPathComponent("ui/options/index.html")
        )
        try Data("<html></html>".utf8).write(
            to: extensionRoot.appendingPathComponent("options.html")
        )

        XCTAssertEqual(
            ExtensionUtils.storedOptionsPagePath(
                from: manifest,
                in: extensionRoot
            ),
            "ui/options/index.html"
        )
    }

    func testStoredOptionsPagePathIgnoresCandidatesOutsideExtensionRoot() throws {
        let extensionRoot = try temporaryDirectory()
        let parentRoot = extensionRoot.deletingLastPathComponent()
        defer {
            try? FileManager.default.removeItem(at: extensionRoot)
            try? FileManager.default.removeItem(
                at: parentRoot.appendingPathComponent("outside.html")
            )
        }

        try Data("<html></html>".utf8).write(
            to: parentRoot.appendingPathComponent("outside.html")
        )

        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Escaped Options",
            "version": "1.0",
            "options_page": "../outside.html",
        ]

        XCTAssertNil(
            ExtensionUtils.storedOptionsPagePath(
                from: manifest,
                in: extensionRoot
            )
        )
    }

    func testNestedOptionsPagePathResolvesLikeSponsorBlock() throws {
        let extensionRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        try FileManager.default.createDirectory(
            at: extensionRoot.appendingPathComponent("options", isDirectory: true),
            withIntermediateDirectories: true
        )
        let nestedFile = extensionRoot
            .appendingPathComponent("options", isDirectory: true)
            .appendingPathComponent("options.html")
        try Data("<html>nested</html>".utf8).write(to: nestedFile)

        XCTAssertEqual(
            ExtensionUtils.existingValidatedOptionsPagePath(
                "options/options.html",
                in: extensionRoot
            ),
            "options/options.html"
        )

        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Nested Options Fixture",
            "version": "1.0",
            "options_ui": [
                "page": "options/options.html",
                "open_in_tab": true,
            ],
        ]

        let resolved = try ExtensionUtils.resolvedOptionsPageURL(
            sdkURL: nil,
            persistedPath: nil,
            manifest: manifest,
            extensionRoot: extensionRoot
        )
        XCTAssertEqual(
            resolved.standardizedFileURL,
            nestedFile.standardizedFileURL
        )
        XCTAssertFalse(resolved.path.contains("%2F"))
    }

    func testManifestRelativePathJoinRejectsParentTraversal() throws {
        let extensionRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        XCTAssertNil(
            ExtensionUtils.url(
                extensionRoot,
                appendingManifestRelativePath: "options/../secrets.html"
            )
        )
    }

    func testResolvedOptionsPageURLFallsBackToManifestAndCommonPaths() throws {
        let extensionRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        let manifestWithDeclaredPage: [String: Any] = [
            "manifest_version": 3,
            "name": "Declared Options",
            "version": "1.0",
            "options_ui": [
                "page": "settings/options.html"
            ],
        ]
        try FileManager.default.createDirectory(
            at: extensionRoot.appendingPathComponent("settings", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("<html></html>".utf8).write(
            to: extensionRoot.appendingPathComponent("settings/options.html")
        )

        let declaredURL = try ExtensionUtils.resolvedOptionsPageURL(
            sdkURL: nil,
            persistedPath: nil,
            manifest: manifestWithDeclaredPage,
            extensionRoot: extensionRoot
        )
        XCTAssertEqual(
            declaredURL.standardizedFileURL,
            extensionRoot.appendingPathComponent("settings/options.html").standardizedFileURL
        )

        let manifestWithoutDeclaredPage: [String: Any] = [
            "manifest_version": 3,
            "name": "Common Path Options",
            "version": "1.0",
        ]
        try Data("<html></html>".utf8).write(
            to: extensionRoot.appendingPathComponent("options.html")
        )

        let fallbackURL = try ExtensionUtils.resolvedOptionsPageURL(
            sdkURL: nil,
            persistedPath: nil,
            manifest: manifestWithoutDeclaredPage,
            extensionRoot: extensionRoot
        )
        XCTAssertEqual(
            fallbackURL.standardizedFileURL,
            extensionRoot.appendingPathComponent("options.html").standardizedFileURL
        )
    }

    func testResolvedOptionsPageURLPrefersSDKAndPersistedPaths() throws {
        let extensionRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        try FileManager.default.createDirectory(
            at: extensionRoot.appendingPathComponent("persisted", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: extensionRoot.appendingPathComponent("manifest", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("<html></html>".utf8).write(
            to: extensionRoot.appendingPathComponent("persisted/options.html")
        )
        try Data("<html></html>".utf8).write(
            to: extensionRoot.appendingPathComponent("manifest/options.html")
        )

        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Priority Options",
            "version": "1.0",
            "options_page": "manifest/options.html",
        ]

        let persistedURL = try ExtensionUtils.resolvedOptionsPageURL(
            sdkURL: nil,
            persistedPath: "persisted/options.html",
            manifest: manifest,
            extensionRoot: extensionRoot
        )
        XCTAssertEqual(
            persistedURL.standardizedFileURL,
            extensionRoot.appendingPathComponent("persisted/options.html").standardizedFileURL
        )

        let sdkURL = extensionRoot.appendingPathComponent("sdk/options.html")
        try FileManager.default.createDirectory(
            at: sdkURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("<html></html>".utf8).write(to: sdkURL)

        let resolvedSDKURL = try ExtensionUtils.resolvedOptionsPageURL(
            sdkURL: sdkURL,
            persistedPath: "persisted/options.html",
            manifest: manifest,
            extensionRoot: extensionRoot
        )
        XCTAssertEqual(
            resolvedSDKURL.standardizedFileURL,
            sdkURL.standardizedFileURL
        )
    }

    func testInstallationPersistsFallbackOptionsPageMetadata() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let extensionRoot = try makeUnpackedExtensionDirectory(
            manifest: [
                "manifest_version": 3,
                "name": "Options Fallback Fixture",
                "version": "1.0",
            ]
        )
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        try Data("<html></html>".utf8).write(
            to: extensionRoot.appendingPathComponent("options.html")
        )

        var capturedRecord: InstalledExtension?
        manager.testHooks.beforePersistInstalledRecord = { record in
            capturedRecord = record
        }

        let result = await installExtension(manager, from: extensionRoot)
        manager.testHooks.beforePersistInstalledRecord = nil

        switch result {
        case .success(let installed):
            XCTAssertEqual(installed.optionsPagePath, "options.html")
            XCTAssertTrue(installed.hasOptionsPage)
            XCTAssertTrue(installed.hasExtensionPages)
        case .failure(let error):
            XCTFail("Installation should succeed with options fallback: \(error.localizedDescription)")
        }

        XCTAssertEqual(capturedRecord?.optionsPagePath, "options.html")
        XCTAssertEqual(capturedRecord?.hasOptionsPage, true)
        XCTAssertEqual(capturedRecord?.hasExtensionPages, true)
    }

    func testFreshInstallWithoutStorageCandidateSkipsWebKitDataCleanup() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let extensionId = "fresh.no-storage.\(UUID().uuidString)"

        let extensionRoot = try makeUnpackedExtensionDirectory(
            manifest: [
                "manifest_version": 3,
                "name": "Fresh Cleanup Fixture",
                "version": "1.0",
                "browser_specific_settings": [
                    "safari": [
                        "id": extensionId,
                    ],
                ],
            ]
        )
        defer { try? FileManager.default.removeItem(at: extensionRoot) }
        defer {
            try? FileManager.default.removeItem(
                at: ExtensionUtils.extensionsDirectory()
                    .appendingPathComponent(extensionId, isDirectory: true)
            )
        }

        var events: [String] = []
        var hooks = manager.testHooks
        hooks.webExtensionDataCleanup = { cleanedExtensionId in
            events.append("cleanup:\(cleanedExtensionId)")
            return true
        }
        hooks.beforePersistInstalledRecord = { record in
            events.append("persist:\(record.id)")
        }
        manager.testHooks = hooks

        let result = await installExtension(manager, from: extensionRoot)

        switch result {
        case .success(let installed):
            XCTAssertEqual(installed.id, extensionId)
        case .failure(let error):
            XCTFail("Fresh install should succeed without storage cleanup: \(error.localizedDescription)")
        }

        XCTAssertEqual(
            events,
            [
                "persist:\(extensionId)",
            ]
        )
    }

    func testFreshInstallRemovesStoredWebExtensionDataBeforePersistingRecord() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let extensionId = "fresh.cleanup.\(UUID().uuidString)"

        let extensionRoot = try makeUnpackedExtensionDirectory(
            manifest: [
                "manifest_version": 3,
                "name": "Fresh Cleanup Fixture",
                "version": "1.0",
                "browser_specific_settings": [
                    "safari": [
                        "id": extensionId,
                    ],
                ],
            ]
        )
        defer { try? FileManager.default.removeItem(at: extensionRoot) }
        defer {
            try? FileManager.default.removeItem(
                at: ExtensionUtils.extensionsDirectory()
                    .appendingPathComponent(extensionId, isDirectory: true)
            )
        }

        let storageDirectory = try makeWebExtensionStorageDirectory(
            for: manager,
            extensionId: extensionId
        )
        let localStorageURL = storageDirectory.appendingPathComponent("LocalStorage.db")
        try Data().write(to: localStorageURL)

        var events: [String] = []
        var storageDirectoryExistedBeforePersist = false
        var snapshotBeforeControllerLoad: ExtensionManager.WebExtensionStorageSnapshot?
        var hooks = manager.testHooks
        hooks.webExtensionDataCleanup = { cleanedExtensionId in
            events.append("cleanup:\(cleanedExtensionId)")
            try? FileManager.default.removeItem(at: localStorageURL)
            return true
        }
        hooks.beforeControllerLoad = { observedExtensionId, snapshot in
            guard observedExtensionId == extensionId else { return }
            snapshotBeforeControllerLoad = snapshot
        }
        hooks.beforePersistInstalledRecord = { record in
            events.append("persist:\(record.id)")
            storageDirectoryExistedBeforePersist = FileManager.default.fileExists(
                atPath: storageDirectory.path
            )
        }
        manager.testHooks = hooks

        let result = await installExtension(manager, from: extensionRoot)

        switch result {
        case .success(let installed):
            XCTAssertEqual(installed.id, extensionId)
        case .failure(let error):
            XCTFail("Fresh install should succeed after storage cleanup: \(error.localizedDescription)")
        }

        XCTAssertEqual(
            events,
            [
                "cleanup:\(extensionId)",
                "persist:\(extensionId)",
            ]
        )
        XCTAssertTrue(storageDirectoryExistedBeforePersist)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageDirectory.path))
        XCTAssertEqual(
            snapshotBeforeControllerLoad,
            ExtensionManager.WebExtensionStorageSnapshot(
                directoryExists: true,
                entryNames: [],
                hasRegisteredContentScriptsStore: false,
                hasLocalStorageStore: false,
                hasSyncStorageStore: false
            )
        )
    }

    func testStateOnlyWebExtensionStoragePrunesWithoutWebKitDataCleanup() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let extensionId = "state-only.cleanup.\(UUID().uuidString)"

        let storageDirectory = try makeWebExtensionStorageDirectory(
            for: manager,
            extensionId: extensionId
        )
        try Data().write(to: storageDirectory.appendingPathComponent("State.plist"))

        var cleanedWebExtensionDataIDs: [String] = []
        var hooks = manager.testHooks
        hooks.webExtensionDataCleanup = { cleanedExtensionId in
            cleanedWebExtensionDataIDs.append(cleanedExtensionId)
            return true
        }
        manager.testHooks = hooks

        await manager.removeStoredWebExtensionData(for: extensionId)

        XCTAssertTrue(cleanedWebExtensionDataIDs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storageDirectory.path))
    }

    func testCleanupErrorClassificationTreatsMissingOptionalStoresAsBenign() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let extensionId = "classification.fixture.\(UUID().uuidString)"

        let benignError = NSError(
            domain: "WKWebExtension",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Failed to create sqlite store for extension: \(extensionId)",
                NSLocalizedFailureReasonErrorKey:
                    "open(.../\(extensionId)/SyncStorage.db) - No such file or directory",
            ]
        )
        let actionableError = NSError(
            domain: "WKWebExtension",
            code: 2,
            userInfo: [
                NSLocalizedDescriptionKey: "Permission denied while removing extension data",
            ]
        )
        let postCleanupSnapshot = ExtensionManager.WebExtensionStorageSnapshot(
            directoryExists: true,
            entryNames: ["State.plist"],
            hasRegisteredContentScriptsStore: false,
            hasLocalStorageStore: false,
            hasSyncStorageStore: false
        )

        let classified = manager.classifyWebExtensionDataCleanupErrors(
            [benignError, actionableError],
            for: extensionId,
            preCleanupSnapshot: postCleanupSnapshot,
            postCleanupSnapshot: postCleanupSnapshot
        )

        XCTAssertEqual(classified.benignOptionalStoreDiagnostics.count, 1)
        XCTAssertEqual(classified.actionableDiagnostics.count, 1)
    }

    func testCleanupErrorClassificationTreatsGenericSQLiteCreationFailureAsBenignWhenOnlyOptionalStoresAreMissing()
        throws
    {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let extensionId = "classification.generic.\(UUID().uuidString)"
        let genericSQLiteError = NSError(
            domain: "WKWebExtension",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Failed to create sqlite store for extension: \(extensionId)",
            ]
        )
        let preCleanupSnapshot = ExtensionManager.WebExtensionStorageSnapshot(
            directoryExists: true,
            entryNames: ["LocalStorage.db", "State.plist"],
            hasRegisteredContentScriptsStore: false,
            hasLocalStorageStore: true,
            hasSyncStorageStore: false
        )
        let postCleanupSnapshot = ExtensionManager.WebExtensionStorageSnapshot(
            directoryExists: true,
            entryNames: ["State.plist"],
            hasRegisteredContentScriptsStore: false,
            hasLocalStorageStore: false,
            hasSyncStorageStore: false
        )

        let classified = manager.classifyWebExtensionDataCleanupErrors(
            [genericSQLiteError],
            for: extensionId,
            preCleanupSnapshot: preCleanupSnapshot,
            postCleanupSnapshot: postCleanupSnapshot
        )

        XCTAssertEqual(classified.benignOptionalStoreDiagnostics.count, 1)
        XCTAssertTrue(classified.actionableDiagnostics.isEmpty)
    }

    func testCleanupErrorClassificationKeepsNonOptionalFailureActionable() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let extensionId = "classification.actionable.\(UUID().uuidString)"
        let genericSQLiteError = NSError(
            domain: "WKWebExtension",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Failed to create sqlite store for extension: \(extensionId)",
            ]
        )
        let actionableError = NSError(
            domain: NSPOSIXErrorDomain,
            code: 13,
            userInfo: [
                NSLocalizedDescriptionKey: "Permission denied while removing extension data",
            ]
        )
        let snapshot = ExtensionManager.WebExtensionStorageSnapshot(
            directoryExists: true,
            entryNames: ["State.plist"],
            hasRegisteredContentScriptsStore: false,
            hasLocalStorageStore: false,
            hasSyncStorageStore: false
        )

        let classified = manager.classifyWebExtensionDataCleanupErrors(
            [genericSQLiteError, actionableError],
            for: extensionId,
            preCleanupSnapshot: snapshot,
            postCleanupSnapshot: snapshot
        )

        XCTAssertEqual(classified.benignOptionalStoreDiagnostics.count, 0)
        XCTAssertEqual(classified.actionableDiagnostics.count, 2)
    }

    func testCleanupErrorClassificationTreatsWebKitStorageCodeThreeAsBenignWhenOnlyOptionalStoresAreMissing()
        throws
    {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let extensionId = "classification.code3.\(UUID().uuidString)"
        let calculateError = NSError(
            domain: "WKWebExtensionDataRecordErrorDomain",
            code: 3,
            userInfo: [
                "NSDebugDescription": "Unable to calculate extension storage",
            ]
        )
        let deleteError = NSError(
            domain: "WKWebExtensionDataRecordErrorDomain",
            code: 3,
            userInfo: [
                "NSDebugDescription": "Unable to delete extension storage",
            ]
        )
        let snapshot = ExtensionManager.WebExtensionStorageSnapshot(
            directoryExists: true,
            entryNames: ["State.plist"],
            hasRegisteredContentScriptsStore: false,
            hasLocalStorageStore: false,
            hasSyncStorageStore: false
        )

        let classified = manager.classifyWebExtensionDataCleanupErrors(
            [calculateError, deleteError],
            for: extensionId,
            preCleanupSnapshot: snapshot,
            postCleanupSnapshot: snapshot
        )

        XCTAssertEqual(classified.benignOptionalStoreDiagnostics.count, 2)
        XCTAssertTrue(classified.actionableDiagnostics.isEmpty)
    }

    func testCleanupErrorClassificationTreatsWebKitStorageCodeThreeAsBenignWhenOnlyPreCleanupSnapshotShowsOptionalStoreGap()
        throws
    {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let extensionId = "classification.code3-preonly.\(UUID().uuidString)"
        let calculateError = NSError(
            domain: "WKWebExtensionDataRecordErrorDomain",
            code: 3,
            userInfo: [
                "NSDebugDescription": "Unable to calculate extension storage",
            ]
        )
        let deleteError = NSError(
            domain: "WKWebExtensionDataRecordErrorDomain",
            code: 3,
            userInfo: [
                "NSDebugDescription": "Unable to delete extension storage",
            ]
        )
        let preCleanupSnapshot = ExtensionManager.WebExtensionStorageSnapshot(
            directoryExists: true,
            entryNames: ["LocalStorage.db", "State.plist"],
            hasRegisteredContentScriptsStore: false,
            hasLocalStorageStore: true,
            hasSyncStorageStore: false
        )
        let postCleanupSnapshot = ExtensionManager.WebExtensionStorageSnapshot(
            directoryExists: false,
            entryNames: [],
            hasRegisteredContentScriptsStore: false,
            hasLocalStorageStore: false,
            hasSyncStorageStore: false
        )

        let classified = manager.classifyWebExtensionDataCleanupErrors(
            [calculateError, deleteError],
            for: extensionId,
            preCleanupSnapshot: preCleanupSnapshot,
            postCleanupSnapshot: postCleanupSnapshot
        )

        XCTAssertEqual(classified.benignOptionalStoreDiagnostics.count, 2)
        XCTAssertTrue(classified.actionableDiagnostics.isEmpty)
    }

    func testCleanupErrorClassificationKeepsWebKitStorageCodeThreeActionableWhenMixedWithNonOptionalFailure()
        throws
    {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let extensionId = "classification.code3-mixed.\(UUID().uuidString)"
        let codeThreeError = NSError(
            domain: "WKWebExtensionDataRecordErrorDomain",
            code: 3,
            userInfo: [
                "NSDebugDescription": "Unable to calculate extension storage",
            ]
        )
        let actionableError = NSError(
            domain: NSPOSIXErrorDomain,
            code: 13,
            userInfo: [
                NSLocalizedDescriptionKey: "Permission denied while removing extension data",
            ]
        )
        let snapshot = ExtensionManager.WebExtensionStorageSnapshot(
            directoryExists: true,
            entryNames: ["State.plist"],
            hasRegisteredContentScriptsStore: false,
            hasLocalStorageStore: false,
            hasSyncStorageStore: false
        )

        let classified = manager.classifyWebExtensionDataCleanupErrors(
            [codeThreeError, actionableError],
            for: extensionId,
            preCleanupSnapshot: snapshot,
            postCleanupSnapshot: snapshot
        )

        XCTAssertEqual(classified.benignOptionalStoreDiagnostics.count, 0)
        XCTAssertEqual(classified.actionableDiagnostics.count, 2)
    }

    func testWebExtensionStorageSnapshotReportsOptionalStorePresence() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let extensionId = "snapshot.fixture.\(UUID().uuidString)"
        let storageDirectory = try makeWebExtensionStorageDirectory(
            for: manager,
            extensionId: extensionId
        )

        try Data().write(to: storageDirectory.appendingPathComponent("State.plist"))
        try Data().write(
            to: storageDirectory.appendingPathComponent("LocalStorage.db")
        )

        let snapshot = manager.webExtensionStorageSnapshot(for: extensionId)

        XCTAssertTrue(snapshot.directoryExists)
        XCTAssertEqual(snapshot.entryNames, ["LocalStorage.db", "State.plist"])
        XCTAssertFalse(snapshot.hasRegisteredContentScriptsStore)
        XCTAssertTrue(snapshot.hasLocalStorageStore)
        XCTAssertFalse(snapshot.hasSyncStorageStore)
        XCTAssertFalse(snapshot.hasOnlyPrunableEntries)
    }

    func testReinstallExistingExtensionDoesNotRemoveStoredWebExtensionData() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let container = harness.container
        let manager = makeExtensionManager(in: harness)
        let extensionId = "existing.cleanup.\(UUID().uuidString)"

        let extensionRoot = try makeUnpackedExtensionDirectory(
            manifest: [
                "manifest_version": 3,
                "name": "Existing Cleanup Fixture",
                "version": "1.0",
                "browser_specific_settings": [
                    "safari": [
                        "id": extensionId,
                    ],
                ],
            ]
        )
        defer { try? FileManager.default.removeItem(at: extensionRoot) }
        defer {
            try? FileManager.default.removeItem(
                at: ExtensionUtils.extensionsDirectory()
                    .appendingPathComponent(extensionId, isDirectory: true)
            )
        }

        let manifest = try ExtensionUtils.validateManifest(
            at: extensionRoot.appendingPathComponent("manifest.json")
        )
        let record = makeInstalledExtensionRecord(
            id: extensionId,
            packagePath: extensionRoot.path,
            sourceBundlePath: extensionRoot.path,
            manifest: manifest,
            isEnabled: true
        )
        container.mainContext.insert(ExtensionEntity(record: record))
        try container.mainContext.save()
        manager.debugReplaceInstalledExtensions([record])

        let storageDirectory = try makeWebExtensionStorageDirectory(
            for: manager,
            extensionId: extensionId
        )
        let localStorageURL = storageDirectory.appendingPathComponent("LocalStorage.db")
        try Data().write(to: localStorageURL)

        var cleanedWebExtensionDataIDs: [String] = []
        var hooks = manager.testHooks
        hooks.webExtensionDataCleanup = { cleanedExtensionId in
            cleanedWebExtensionDataIDs.append(cleanedExtensionId)
            return true
        }
        manager.testHooks = hooks

        let result = await installExtension(manager, from: extensionRoot)

        switch result {
        case .success(let installed):
            XCTAssertEqual(installed.id, extensionId)
        case .failure(let error):
            XCTFail("Reinstall should succeed without clearing existing storage: \(error.localizedDescription)")
        }

        XCTAssertTrue(cleanedWebExtensionDataIDs.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: localStorageURL.path))
    }

    func testInstallCompletionSeesPublishedExtensionAfterRuntimeLoad() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let extensionId = "completion.install.\(UUID().uuidString)"

        let extensionRoot = try makeUnpackedExtensionDirectory(
            manifest: [
                "manifest_version": 3,
                "name": "Completion Fixture",
                "version": "1.0",
                "browser_specific_settings": [
                    "safari": [
                        "id": extensionId,
                    ],
                ],
            ]
        )
        defer { try? FileManager.default.removeItem(at: extensionRoot) }
        defer {
            try? FileManager.default.removeItem(
                at: ExtensionUtils.extensionsDirectory()
                    .appendingPathComponent(extensionId, isDirectory: true)
            )
        }

        let completionObservation = await withCheckedContinuation {
            (continuation: CheckedContinuation<
                (
                    Result<InstalledExtension, ExtensionError>,
                    Bool,
                    Bool
                ),
                Never
            >) in
            manager.installExtension(from: extensionRoot) { result in
                let contextWasLoaded = manager.extensionContexts[extensionId] != nil
                let extensionWasPublished = manager.installedExtensions.contains {
                    $0.id == extensionId
                }
                continuation.resume(
                    returning: (result, contextWasLoaded, extensionWasPublished)
                )
            }
        }

        let (result, contextWasLoaded, extensionWasPublished) = completionObservation

        switch result {
        case .success(let installed):
            XCTAssertEqual(installed.id, extensionId)
        case .failure(let error):
            XCTFail("Install completion should succeed: \(error.localizedDescription)")
        }

        XCTAssertTrue(contextWasLoaded)
        XCTAssertTrue(extensionWasPublished)
    }

    func testInstallationRollbackRemovesLoadedContextAndFilesWhenPersistenceFails() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let container = harness.container
        let manager = makeExtensionManager(in: harness)

        let extensionRoot = try makeUnpackedExtensionDirectory(
            manifest: [
                "manifest_version": 3,
                "name": "Rollback Fixture",
                "version": "1.0",
            ]
        )
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        var installedPackagePath: String?
        manager.testHooks.beforePersistInstalledRecord = { record in
            installedPackagePath = record.packagePath
            throw NSError(
                domain: "ExtensionManagerTests",
                code: 91,
                userInfo: [NSLocalizedDescriptionKey: "Injected persist failure"]
            )
        }

        let result = await installExtension(manager, from: extensionRoot)
        manager.testHooks.beforePersistInstalledRecord = nil

        switch result {
        case .success:
            XCTFail("Installation should have rolled back after injected failure")
        case .failure(let error):
            XCTAssertTrue(error.localizedDescription.contains("Injected persist failure"))
        }

        XCTAssertEqual(manager.loadedContextIDs, [])
        XCTAssertTrue(manager.debugRuntimeStateSnapshot.loadedManifestIDs.isEmpty)

        if let installedPackagePath {
            XCTAssertFalse(FileManager.default.fileExists(atPath: installedPackagePath))
        } else {
            XCTFail("Expected test hook to capture the installed package path")
        }

        XCTAssertTrue(
            try container.mainContext.fetch(FetchDescriptor<ExtensionEntity>()).isEmpty
        )
    }

    func testMV3InstallationFailsFastWhenServiceWorkerIsMissing() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let extensionRoot = try makeUnpackedExtensionDirectory(
            manifest: [
                "manifest_version": 3,
                "name": "Missing Worker",
                "version": "1.0",
                "background": [
                    "service_worker": "missing-worker.js",
                ],
            ]
        )
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        let result = await installExtension(manager, from: extensionRoot)
        switch result {
        case .success:
            XCTFail("MV3 install should fail when the declared service worker is missing")
        case .failure(let error):
            XCTAssertTrue(
                error.localizedDescription.contains("MV3 service worker not found: missing-worker.js")
            )
        }

        XCTAssertTrue(manager.loadedContextIDs.isEmpty)
        XCTAssertTrue(manager.installedExtensions.isEmpty)
    }

    func testStartupReloadLoadsEnabledExtensionFromPersistence() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let container = harness.container
        let extensionRoot = try makeUnpackedExtensionDirectory(
            manifest: [
                "manifest_version": 3,
                "name": "Persisted Fixture",
                "version": "1.0",
            ]
        )
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        let record = makeInstalledExtensionRecord(
            id: "persisted.extension",
            packagePath: extensionRoot.path,
            sourceBundlePath: extensionRoot.path,
            manifest: try ExtensionUtils.validateManifest(
                at: extensionRoot.appendingPathComponent("manifest.json")
            ),
            isEnabled: true
        )
        container.mainContext.insert(ExtensionEntity(record: record))
        try container.mainContext.save()

        let manager = makeExtensionManager(in: harness)
        let initSnapshot = manager.debugRuntimeStateSnapshot

        XCTAssertTrue(manager.extensionsLoaded)
        XCTAssertEqual(manager.installedExtensions.map(\.id), [record.id])
        XCTAssertEqual(initSnapshot.runtimeState, .idle)
        XCTAssertFalse(initSnapshot.isControllerInitialized)
        XCTAssertEqual(initSnapshot.profileExtensionStoreCount, 0)

        _ = try await requireRuntimeReadyController(
            for: manager,
            reason: .refresh,
            allowWithoutEnabledExtensions: false
        )

        XCTAssertEqual(manager.loadedContextIDs, [record.id])
        XCTAssertNotNil(manager.getExtensionContext(for: record.id))
    }

    func testStartupReloadDropsInvalidPersistedExtensionRecord() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let container = harness.container
        let scratchRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: scratchRoot) }

        let missingRoot = scratchRoot.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )

        let record = makeInstalledExtensionRecord(
            id: "persisted.invalid.extension",
            packagePath: missingRoot.path,
            sourceBundlePath: missingRoot.path,
            manifest: [
                "manifest_version": 3,
                "name": "Missing Persisted Fixture",
                "version": "1.0",
            ],
            isEnabled: true
        )
        container.mainContext.insert(ExtensionEntity(record: record))
        try container.mainContext.save()

        let manager = makeExtensionManager(in: harness)

        XCTAssertTrue(manager.loadedContextIDs.isEmpty)
        XCTAssertTrue(manager.installedExtensions.isEmpty)
        XCTAssertTrue(manager.extensionsLoaded)
        XCTAssertFalse(manager.debugRuntimeStateSnapshot.isControllerInitialized)
        XCTAssertTrue(
            try container.mainContext.fetch(FetchDescriptor<ExtensionEntity>()).isEmpty
        )
    }

    func testManifestPatchCacheSkipsUnchangedPackageButRepatchesChangedInputs()
        throws
    {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let rootURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        let manifest: [String: Any] = [
            "manifest_version": 2,
            "name": "Cached Patch Fixture",
            "version": "1.0",
            "externally_connectable": [
                "matches": ["https://example.com/*"]
            ],
            "background": [
                "scripts": ["background.js"]
            ],
        ]
        try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        ).write(to: manifestURL)
        try "console.log('background');\n".write(
            to: rootURL.appendingPathComponent("background.js"),
            atomically: true,
            encoding: .utf8
        )

        manager.patchManifestForWebKit(at: manifestURL)
        let firstPatchedManifest = try Data(contentsOf: manifestURL)
        let bridgeURL = rootURL.appendingPathComponent(
            ExtensionManager.externallyConnectableBridgeFilename
        )
        let expectedBridgeSource = try String(contentsOf: bridgeURL, encoding: .utf8)

        manager.patchManifestForWebKit(at: manifestURL)
        XCTAssertEqual(firstPatchedManifest, try Data(contentsOf: manifestURL))

        try "broken helper".write(
            to: bridgeURL,
            atomically: true,
            encoding: .utf8
        )
        manager.patchManifestForWebKit(at: manifestURL)
        XCTAssertEqual(
            try String(contentsOf: bridgeURL, encoding: .utf8),
            expectedBridgeSource
        )

        var patched = try ExtensionUtils.validateManifest(at: manifestURL)
        patched.removeValue(forKey: "content_scripts")
        patched["version"] = "1.1"
        try ExtensionUtils.writeJSONObjectIfChanged(patched, to: manifestURL)

        manager.patchManifestForWebKit(at: manifestURL)

        let repatched = try ExtensionUtils.validateManifest(at: manifestURL)
        let contentScripts = repatched["content_scripts"] as? [[String: Any]] ?? []
        XCTAssertTrue(
            contentScripts.contains {
                (($0["js"] as? [String]) ?? [])
                    .contains(ExtensionManager.externallyConnectableBridgeFilename)
            }
        )
    }
}
