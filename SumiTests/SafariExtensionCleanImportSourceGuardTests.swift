import XCTest

@testable import Sumi

@available(macOS 15.5, *)
final class SafariExtensionCleanImportSourceGuardTests: XCTestCase {
    private let extensionManagerPaths = [
        "Sumi/Managers/ExtensionManager/ExtensionManager+Installation.swift",
        "Sumi/Managers/ExtensionManager/ExtensionManager+ManifestPatching.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SafariAppExtensionResources.swift",
        "Sumi/Managers/ExtensionManager/ExtensionManager.swift",
        "Sumi/Managers/ExtensionManager/ExtensionManager+UI.swift",
        "Sumi/Managers/ExtensionManager/ExtensionManager+ControllerDelegate.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingRelay.swift",
    ]

    private let deletedCompatArtifacts = [
        "webkit_runtime_compat.js",
        "webkit_runtime_compat_worker.js",
        "externally_connectable_page_bridge.js",
        "externally_connectable_isolated_bridge.js",
        "externally_connectable_worker.js",
        "externally_connectable_background_helper.js",
        "selective_content_script_guard.js",
        "sumi_webkit_runtime_compat.js",
        "sumi_bridge.js",
        "sumi_external_runtime.js",
        "ExtensionRuntimeBundledScript",
        "ExtensionManager+ExternallyConnectableScripts",
        "SumiExternallyConnectableUserScript",
        "patchManifestForWebKit",
        "manifestPatchCache",
    ]

    func testSafariImportPathDoesNotPatchManifestOrInjectCompatJS() throws {
        let installationSource = try source(named: extensionManagerPaths[0])
        let manifestSource = try source(named: extensionManagerPaths[1])
        let safariResourcesSource = try source(named: extensionManagerPaths[2])

        assertExcludes(
            installationSource,
            [
                "patchManifestForWebKit",
                "setupExternallyConnectableBridge",
                "ExtensionRuntimeResources",
                "sumi_webkit_runtime_compat",
            ],
            context: "Safari installation path"
        )

        assertExcludes(
            manifestSource,
            [
                "patchManifestForWebKit",
                "sumi_webkit_runtime_compat",
                "sumi_bridge.js",
                "webkit_runtime_compat",
                "selective_content_script_guard",
            ],
            context: "manifest install-source resolution"
        )

        XCTAssertTrue(
            safariResourcesSource.contains("WKWebExtension(appExtensionBundle:"),
            "Safari runtime should prefer signed appex load"
        )
        XCTAssertTrue(
            safariResourcesSource.contains("originalAppexBundle"),
            "Safari runtime should record original appex load source"
        )
    }

    func testExtensionManagerDoesNotAttachCompatUserScriptsToNormalTabs() throws {
        let managerSource = try source(named: extensionManagerPaths[3])
        XCTAssertTrue(
            managerSource.contains("func normalTabUserScripts() -> [SumiUserScript]"),
            "Extension manager should expose normal-tab script hook"
        )
        XCTAssertFalse(
            managerSource.contains("SumiExternallyConnectableUserScript"),
            "Externally-connectable page bridge must not be injected into normal tabs"
        )
    }

    func testPopupAndActionPathsDoNotReferenceCompatBundles() throws {
        let uiSource = try source(named: extensionManagerPaths[4])
        assertExcludes(
            uiSource,
            [
                "ExtensionRuntimeResources",
                "sumi_webkit_runtime_compat",
                "pageWorldExternallyConnectableBridgeScript",
            ],
            context: "extension popup/action UI"
        )
    }

    func testNativeMessagingUsesSwiftRelayNotCompatJS() throws {
        let delegateSource = try source(named: extensionManagerPaths[5])
        let relaySource = try source(named: extensionManagerPaths[6])

        XCTAssertTrue(
            delegateSource.contains("safariNativeMessagingHost.handleSendMessage")
                || delegateSource.contains("SumiNativeMessagingRelay")
        )
        XCTAssertTrue(relaySource.contains("WKWebExtension.MessagePort"))
        assertExcludes(
            relaySource + delegateSource,
            deletedCompatArtifacts,
            context: "Safari native messaging relay"
        )
    }

    func testDeletedCompatArtifactsAreAbsentFromRepository() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let runtimeResources = repoRoot
            .appendingPathComponent("Sumi/Managers/ExtensionManager/ExtensionRuntimeResources")
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(
            atPath: runtimeResources.path,
            isDirectory: &isDirectory
        ),
           isDirectory.boolValue
        {
            let remainingJS = try FileManager.default.contentsOfDirectory(
                at: runtimeResources,
                includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension.lowercased() == "js" }
            XCTAssertTrue(
                remainingJS.isEmpty,
                "ExtensionRuntimeResources must not ship compat JS: \(remainingJS)"
            )
        }

        for relativePath in extensionManagerPaths {
            let source = try source(named: relativePath)
            assertExcludes(source, deletedCompatArtifacts, context: relativePath)
        }
    }

    func testProfileIsolationAndPrivateTabGuardsRemainWired() throws {
        let profileIsolationSource = try source(
            named: "SumiTests/SafariExtensionProfileIsolationTests.swift"
        )
        let installationSource = try source(named: extensionManagerPaths[0])

        XCTAssertTrue(profileIsolationSource.contains("SafariExtensionProfileIsolationTests"))
        XCTAssertTrue(
            installationSource.contains("ensureExtensionController(for:"),
            "Per-profile extension controller wiring must remain"
        )
        XCTAssertTrue(
            installationSource.contains("finalizeEnabledExtensionRuntime"),
            "Enable/load finalize path must remain for content scripts"
        )
    }

    func testRaindropAndRescanPathsDoNotRestoreMV3Shims() throws {
        let importStoreSource = try source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionImportStore.swift"
        )
        let scannerSource = try source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionScanner.swift"
        )

        assertExcludes(
            importStoreSource + scannerSource,
            [
                "ChromeMV3",
                "patchManifestForWebKit",
                "webkit_runtime_compat",
                "sumi_webkit_runtime_compat",
            ],
            context: "Raindrop import/rescan"
        )
    }

    private func source(named relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func assertExcludes(
        _ source: String,
        _ forbidden: [String],
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for token in forbidden {
            XCTAssertFalse(
                source.contains(token),
                "\(context) should not contain \(token)",
                file: file,
                line: line
            )
        }
    }
}
