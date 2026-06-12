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
        "Sumi/Managers/ExtensionManager/ExtensionManager+Profiles.swift",
        "Sumi/Managers/ExtensionManager/ExtensionManager+ActionPopupAnchor.swift",
        "Sumi/Managers/ExtensionManager/ExtensionManager+ControllerDelegate.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingRelay.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingPortSession.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingRelayLoopGuard.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingDiagnosticCoalescer.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingAdapterTransport.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SumiNativeMessagingProtocolAdapter.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SumiCompanionAppResolver.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionURLSchemeCompatibility.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionPermissionsOriginsCompatibility.swift",
        "Sumi/Managers/ExtensionManager/ExtensionManager+Store.swift",
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
        "SafariExtensionRuntimeConnectCompatibility",
        "ExternallyConnectablePortRegistry",
        "ExtensionManager+ExternallyConnectableNativeMessaging",
        "sumiExternallyConnectableRuntime",
        "SUMI_EC_PAGE_BRIDGE",
        "__sumiRuntimeConnectCompatibility",
        "runtime.connect = wrappedConnect",
        "nativeOnConnect.addListener",
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

    func testPermissionsOriginsCompatibilityLayerIsNarrowAndExtensionScoped() throws {
        let permissionsCompatibilitySource = try source(named: extensionManagerPaths[16])

        XCTAssertTrue(
            permissionsCompatibilitySource.contains(
                "SafariExtensionPermissionsOriginsCompatibility"
            )
        )
        XCTAssertTrue(
            permissionsCompatibilitySource.contains(
                "location.protocol !== \"webkit-extension:\""
            )
        )
        XCTAssertTrue(
            permissionsCompatibilitySource.contains(
                "for (const name of [\"contains\", \"request\", \"remove\"])"
            )
        )
        assertExcludes(
            permissionsCompatibilitySource,
            [
                "patchManifestForWebKit",
                "ExtensionRuntimeResources",
                "sumi_webkit_runtime_compat",
                "selective_content_script_guard",
            ],
            context: "permissions origins compatibility"
        )
    }

    func testURLSchemeCompatibilityLayerIsNarrowAndSafariScoped() throws {
        let urlSchemeCompatibilitySource = try source(named: extensionManagerPaths[15])

        XCTAssertTrue(
            urlSchemeCompatibilitySource.contains(
                "SafariExtensionURLSchemeCompatibility"
            )
        )
        XCTAssertTrue(
            urlSchemeCompatibilitySource.contains("safari-web-extension://")
        )
        XCTAssertTrue(
            urlSchemeCompatibilitySource.contains("runtime.getURL = wrapped")
        )
        XCTAssertTrue(
            urlSchemeCompatibilitySource.contains("toInternalString")
        )
        XCTAssertTrue(
            urlSchemeCompatibilitySource.contains("Reflect.get(target, property, target)"),
            "Wrapped iframe WindowProxy access must preserve native DOM accessor receivers"
        )
        assertExcludes(
            urlSchemeCompatibilitySource,
            [
                "patchManifestForWebKit",
                "ExtensionRuntimeResources",
                "sumi_webkit_runtime_compat",
                "selective_content_script_guard",
            ],
            context: "URL scheme compatibility"
        )
    }

    func testRuntimeConnectCompatibilityLayerWasDeleted() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let deletedRuntimeConnectShim = repoRoot.appendingPathComponent(
            "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionRuntimeConnectCompatibility.swift"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: deletedRuntimeConnectShim.path),
            "runtime.connect/onConnect must use native WebKit behavior unless a proven WebKit gap reappears"
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

    func testActionPopupDelegateDoesNotRetargetWebKitOwnedPopupConfiguration() throws {
        let delegateSource = try source(named: extensionManagerPaths[7])
        XCTAssertTrue(
            delegateSource.contains("action.popupPopover")
                && delegateSource.contains("action.popupWebView"),
            "Action popup presentation should use WebKit's native popup popover/web view"
        )
        assertExcludes(
            delegateSource,
            [
                "popupWebView.configuration.webExtensionController =",
                "popupWebView.configuration.websiteDataStore =",
                "popupWebView.configuration.defaultWebpagePreferences",
            ],
            context: "WebKit-owned action popup web view"
        )
    }

    func testNativeMessagingUsesSwiftRelayNotCompatJS() throws {
        let delegateSource = try source(named: extensionManagerPaths[7])
        let relaySource = try source(named: extensionManagerPaths[8])
        let portSessionSource = try source(named: extensionManagerPaths[9])

        XCTAssertTrue(
            delegateSource.contains("safariNativeMessagingHost.handleSendMessage")
                || delegateSource.contains("SumiNativeMessagingRelay")
        )
        XCTAssertTrue(
            relaySource.contains("SumiNativeMessagingRelay")
                || portSessionSource.contains("WKWebExtension.MessagePort")
        )
        assertExcludes(
            relaySource + portSessionSource + delegateSource,
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

    func testLazyRuntimeDoesNotEagerlyLoadAllExtensions() throws {
        let profilesSource = try source(named: extensionManagerPaths[5])
        let uiSource = try source(named: extensionManagerPaths[4])
        let managerSource = try source(named: extensionManagerPaths[3])
        let installationSource = try source(named: extensionManagerPaths[0])
        let controllerDelegateSource = try source(named: extensionManagerPaths[7])
        let storeSource = try source(named: extensionManagerPaths[17])

        XCTAssertTrue(profilesSource.contains("if forceReload {"))
        XCTAssertFalse(
            profilesSource.contains("await self.ensureEnabledExtensionsLoaded(for: profileId)"),
            "Profile switches must not eagerly load every enabled extension"
        )
        XCTAssertFalse(
            uiSource.contains("await ensureEnabledExtensionsLoaded(for: tabProfileId)"),
            "Action popup must not eagerly load every enabled extension"
        )
        XCTAssertFalse(
            profilesSource.contains("scheduleExtensionBackgroundWakeForNavigationIfNeeded"),
            "Ordinary navigation must not wake extension backgrounds just to inject content scripts"
        )
        XCTAssertFalse(
            managerSource.contains("case reload"),
            "Background wake reasons should be explicit lifecycle/API events, not ordinary reloads"
        )
        XCTAssertTrue(
            installationSource.contains("postLoadBackgroundWakeReason"),
            "Existing-extension context loads must make background wake opt-in"
        )
        XCTAssertTrue(
            installationSource.contains("requiredMatchPatterns.union(webExtension.optionalPermissionMatchPatterns)")
                && installationSource.contains(": requiredMatchPatterns"),
            "Production context load should auto-grant required host/content-script match patterns while keeping optional host patterns prompt-controlled"
        )
        XCTAssertTrue(
            controllerDelegateSource.contains("promptForExtensionPermissionDecision")
                && controllerDelegateSource.contains("promptForPermissionToAccess")
                && controllerDelegateSource.contains("promptForPermissionMatchPatterns")
                && controllerDelegateSource.contains("extensionPermissionPromptQueue")
                && controllerDelegateSource.contains("extensionPermissionPromptWaitersByKey"),
            "Safari/WebExtension host access requests must go through a serialized, deduplicated user permission prompt"
        )
        XCTAssertTrue(
            storeSource.contains("extensionPermissionDecisionsStorageKey")
                && storeSource.contains("applyStoredExtensionPermissionDecisions")
                && storeSource.contains("hostMatchPatternString"),
            "Explicit WebExtension permission decisions must be persisted profile-scope and restored without storing full page URLs"
        )
    }

    func testPopupAnchorAndSuppressionProbesHaveNoExtensionSpecificBranches() throws {
        let anchorSource = try source(named: extensionManagerPaths[6])
        let loopGuardSource = try source(named: extensionManagerPaths[10])
        let coalescerSource = try source(named: extensionManagerPaths[11])

        for token in ["bitwarden", "1password", "proton", "raindrop", "com.bitwarden.desktop"] {
            XCTAssertFalse(anchorSource.localizedCaseInsensitiveContains(token))
            XCTAssertFalse(coalescerSource.localizedCaseInsensitiveContains(token))
        }
        XCTAssertTrue(loopGuardSource.contains("supportedRelayProtocolHostBundleIdentifiers"))
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

    func testExtensionOwnedPagesAreRuntimeOwnedNotSessionRestored() throws {
        let utilsSource = try source(
            named: "Sumi/Managers/ExtensionManager/ExtensionUtils.swift"
        )
        let persistenceSource = try source(
            named: "Sumi/Managers/TabManager/TabManager+Persistence.swift"
        )
        let restoreSource = try source(
            named: "Sumi/Managers/TabManager/TabRestoreLoader.swift"
        )
        let tabUIDelegateSource = try source(
            named: "Sumi/Models/Tab/Tab+UIDelegate.swift"
        )
        let tabRuntimeSource = try source(
            named: "Sumi/Models/Tab/Tab+WebViewRuntime.swift"
        )
        let routingSource = try source(
            named: "Sumi/Services/BrowserWebViewRoutingService.swift"
        )
        let uiSource = try source(
            named: "Sumi/Managers/ExtensionManager/ExtensionManager+UI.swift"
        )
        let browserManagerSource = try source(
            named: "Sumi/Managers/BrowserManager/BrowserManager.swift"
        )
        let delegateSource = try source(
            named: "Sumi/Managers/ExtensionManager/ExtensionManager+ControllerDelegate.swift"
        )
        let profilesSource = try source(
            named: "Sumi/Managers/ExtensionManager/ExtensionManager+Profiles.swift"
        )

        XCTAssertTrue(utilsSource.contains("extensionOwnedURLSchemes"))
        XCTAssertTrue(utilsSource.contains("\"webkit-extension\""))
        XCTAssertTrue(utilsSource.contains("\"safari-web-extension\""))
        XCTAssertTrue(
            persistenceSource.contains("ExtensionUtils.isExtensionOwnedURL(tab.url) == false"),
            "Regular tab persistence must exclude extension-owned pages generically"
        )
        XCTAssertTrue(
            restoreSource.contains("removed extension-owned restored tab"),
            "Startup restore must repair stale extension-owned regular tabs"
        )
        XCTAssertFalse(
            tabUIDelegateSource.contains("let extensionSchemes"),
            "Popup navigation should use the shared extension-owned URL predicate"
        )
        XCTAssertTrue(
            tabRuntimeSource.contains("webExtensionContextOverride"),
            "Extension-created pages must keep their WKWebExtensionContext until WebView creation"
        )
        XCTAssertTrue(
            routingSource.contains("ExtensionUtils.isExtensionOwnedURL(tab.url) == false"),
            "Runtime-owned extension pages must not enter ordinary cross-window tab sync"
        )
        XCTAssertTrue(
            browserManagerSource.contains(
                "ExtensionUtils.isExtensionOwnedURL(tab.url) || tab.webExtensionContextOverride != nil"
            ),
            "Startup materialization deferral must not discard runtime-owned extension pages"
        )
        XCTAssertTrue(
            delegateSource.contains("materializeExtensionOwnedTabIfNeeded"),
            "Background extension-created internal tabs must be materialized through the extension context"
        )
        XCTAssertFalse(
            profilesSource.contains("extensionContext.webViewConfiguration"),
            "Pre-load runtime context preparation must not consume or mutate WebKit's extension page configuration"
        )
        XCTAssertTrue(
            uiSource.contains("sdkResolvedURL")
                && uiSource.contains("extensionContext.webViewConfiguration"),
            "Options pages should prefer WebKit/context URLs and context-bound WebView configuration"
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
