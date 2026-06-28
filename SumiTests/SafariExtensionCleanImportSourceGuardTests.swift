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
        "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionPermissionsOriginsCompatibility.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionPermissionLifecycleDiagnostics.swift",
        "Sumi/Managers/ExtensionManager/ExtensionManager+Store.swift",
        "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionInstallCapabilityOwner.swift",
        "Sumi/Managers/ExtensionManager/ExtensionActionPopupPresentationOwner.swift",
        "Sumi/Managers/ExtensionManager/ExtensionActionSurfaceStatePresenter.swift",
        "Sumi/Managers/ExtensionManager/ExtensionOptionsWindowPresenter.swift",
        "Sumi/Managers/ExtensionManager/ExtensionPermissionPromptRoutingOwner.swift",
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

    func testSafariEnablePathDoesNotPatchManifestInjectCompatJSOrCopyAppex() throws {
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
            installationSource,
            [
                "SafariAppExtensionResources.copyResources",
            ],
            context: "Safari app-extension enable path"
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
        assertExcludes(
            safariResourcesSource,
            [
                "copyResources",
                "falling back to copied package",
            ],
            context: "Safari app-extension runtime factory"
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
        let permissionsCompatibilitySource = try source(named: extensionManagerPaths[15])

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
                "location.protocol !== \"safari-web-extension:\""
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

    func testSafariURLSchemeUsesNativeWebKitRegistration() throws {
        let managerSource = try source(named: extensionManagerPaths[3])
        let installationSource = try source(named: extensionManagerPaths[0])
        let contextLoadSource = try source(
            named: "Sumi/Managers/ExtensionManager/ExtensionRuntimeContextLoadOwner.swift"
        )
        let runtimeSources = try [
            managerSource,
            installationSource,
            contextLoadSource,
            source(named: extensionManagerPaths[4]),
            source(named: extensionManagerPaths[5]),
            source(named: extensionManagerPaths[7]),
            source(
                named: "Sumi/Managers/ExtensionManager/ExtensionManager+ProfileRuntime.swift"
            ),
            source(named: "Sumi/Managers/ExtensionManager/ExtensionUtils.swift"),
        ].joined()
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let deletedURLShim = repoRoot.appendingPathComponent(
            "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionURLSchemeCompatibility.swift"
        )

        XCTAssertTrue(
            managerSource.contains(
                "WKWebExtension.MatchPattern.registerCustomURLScheme"
            ),
            "The Safari-shaped scheme must be registered with WebKit before contexts are created"
        )
        XCTAssertTrue(
            managerSource.contains("safari-web-extension")
                && contextLoadSource.contains("ExtensionManager.safariWebExtensionURLScheme")
                && contextLoadSource.contains("extensionContext.baseURL = baseURL"),
            "Extension contexts should use the registered Safari-shaped base URL directly"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: deletedURLShim.path),
            "Native custom-scheme support should replace the URL rewriting shim"
        )
        assertExcludes(
            runtimeSources,
            [
                "SafariExtensionURLSchemeCompatibility",
                "webKitLoadableExtensionURL",
                "installURLSchemeCompatibilityPreludes",
                "runtime.getURL = wrapped",
                "toInternalString",
            ],
            context: "native Safari extension URL scheme"
        )
    }

    func testExternallyConnectableIsNotIntroducedAsSiteAccessSurface() throws {
        let storeSource = try source(named: extensionManagerPaths[17])
        let diagnosticsSource = try source(named: extensionManagerPaths[16])

        XCTAssertTrue(
            diagnosticsSource.contains("externallyConnectableReportedSeparately"),
            "Diagnostics must report externally_connectable separately from site/content-script access"
        )

        XCTAssertFalse(
            storeSource.contains("+ externallyConnectableMatches"),
            "raw manifest site-access extraction must not union externally_connectable.matches into host/content-script match patterns"
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

    func testNativeMessagingUsesProductionRelayWithoutCompatFallbackShims() throws {
        let delegateSource = try source(named: extensionManagerPaths[7])
        let relaySource = try source(named: extensionManagerPaths[8])
        let portSessionSource = try source(named: extensionManagerPaths[9])

        XCTAssertFalse(delegateSource.contains("safariNativeMessagingHost.handleSendMessage"))
        XCTAssertFalse(delegateSource.contains("safariNativeMessagingHost.handleConnect"))
        XCTAssertTrue(delegateSource.contains("sendMessage message: Any"))
        XCTAssertTrue(delegateSource.contains("connectUsing port: WKWebExtension.MessagePort"))
        XCTAssertTrue(delegateSource.contains("nativeMessagingRelay.handleSendMessage"))
        XCTAssertTrue(delegateSource.contains("nativeMessagingRelay.handleConnect"))
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
        let capabilityOwnerSource = try source(named: extensionManagerPaths[18])
        let siteAccessPolicyStoreSource = try source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionSiteAccessPolicyStore.swift"
        )

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
            installationSource.contains("applyConfiguredSiteAccessPolicy")
                && siteAccessPolicyStoreSource.contains("siteAccessStorageKey")
                && capabilityOwnerSource.contains("webExtension.optionalPermissionMatchPatterns"),
            "Production context load should restore profile-scoped site access policy, including optional host patterns only when Sumi settings allow them"
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

    func testGenericPermissionLifecycleCodeHasNoVendorSpecificBranches() throws {
        let genericSources = try [
            "Sumi/Managers/ExtensionManager/ExtensionManager+ControllerDelegate.swift",
            "Sumi/Managers/ExtensionManager/ExtensionManager+Installation.swift",
            "Sumi/Managers/ExtensionManager/ExtensionManager+Profiles.swift",
            "Sumi/Managers/ExtensionManager/ExtensionManager+ProfileRuntime.swift",
            "Sumi/Managers/ExtensionManager/ExtensionManager+Store.swift",
            "Sumi/Managers/ExtensionManager/ExtensionManager+UI.swift",
            "Sumi/Managers/ExtensionManager/ExtensionRuntimeContextLoadOwner.swift",
            "Sumi/Managers/ExtensionManager/ExtensionActionPopupPresentationOwner.swift",
            "Sumi/Managers/ExtensionManager/ExtensionActionSurfaceStatePresenter.swift",
            "Sumi/Managers/ExtensionManager/ExtensionOptionsWindowPresenter.swift",
            "Sumi/Managers/ExtensionManager/ExtensionPermissionPromptRoutingOwner.swift",
            "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionPermissionLifecycleDiagnostics.swift",
            "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionSiteAccessPolicy.swift",
            "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionSiteAccessPolicyStore.swift",
            "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionInstallCapabilityOwner.swift",
        ].map(source(named:)).joined(separator: "\n")

        for token in [
            "bitwarden",
            "1password",
            "proton",
            "raindrop",
            "account.proton",
            "pass.proton",
            "com.bitwarden",
        ] {
            XCTAssertFalse(
                genericSources.localizedCaseInsensitiveContains(token),
                "Generic permission/lifecycle code must not contain vendor-specific branches or domains: \(token)"
            )
        }
    }

    func testPermissionLifecycleDiagnosticsSourceDoesNotLogSecrets() throws {
        let diagnosticsSource = try source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionPermissionLifecycleDiagnostics.swift"
        )

        assertExcludes(
            diagnosticsSource,
            [
                "HTTPCookie",
                "document.cookie",
                "access_token",
                "refresh_token",
                "authPayload",
                "messageBody",
                "message.body",
                "domContent",
                "document.body.innerHTML",
                "absoluteString",
            ],
            context: "permission lifecycle diagnostics"
        )
        XCTAssertTrue(diagnosticsSource.contains("sanitizedURL"))
        XCTAssertTrue(diagnosticsSource.contains("redactedPath"))
    }

    func testActiveTabTemporaryGrantRiskIsDocumented() throws {
        let installationSource = try source(
            named: "Sumi/Managers/ExtensionManager/ExtensionManager+Installation.swift"
        )
        let capabilityOwnerSource = try source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionInstallCapabilityOwner.swift"
        )
        XCTAssertTrue(installationSource.contains("grantActiveTabURLAccess"))
        XCTAssertTrue(
            capabilityOwnerSource.contains("decisionSource: .activeTabTemporaryGrant"),
            "activeTab grants must be visible in diagnostics"
        )
        XCTExpectFailure(
            "Current activeTab implementation grants a URL globally. Goal 2 should make it tab/navigation-scoped with WebKit tab-aware APIs."
        ) {
            XCTAssertFalse(
                capabilityOwnerSource.contains("extensionContext.setPermissionStatus(.grantedExplicitly, for: url)"),
                "activeTab/current-page grants must not become global URL grants"
            )
        }
    }

    func testSiteAccessPolicyApplyDoesNotUseDestructiveWebViewRebuildAsRepair() throws {
        let storeSource = try source(
            named: "Sumi/Managers/ExtensionManager/ExtensionManager+Store.swift"
        )
        let profileSource = try source(
            named: "Sumi/Managers/ExtensionManager/ExtensionManager+Profiles.swift"
        )
        let runtimeSource = try source(
            named: "Sumi/Managers/ExtensionManager/ExtensionManager+ProfileRuntime.swift"
        )

        XCTAssertTrue(storeSource.contains("logReloadRebuild"))
        XCTExpectFailure(
            "Current policy apply path can reach updateWebViewsForProfile and rebuildLiveWebViews; Goal 2 should replace this with bounded reload/rebind semantics."
        ) {
            XCTAssertFalse(
                storeSource.contains("reconcileOpenTabsAfterExtensionContextLoad")
                    && profileSource.contains("updateWebViewsForProfile")
                    && runtimeSource.contains("coordinator.rebuildLiveWebViews(for: tab)"),
                "Applying site-access policy must not destructively rebuild live normal WebViews"
            )
        }
    }

    func testExtensionCreatedExternalLoginURLRoutesThroughNormalTabs() throws {
        let requestedTabLifecycleSource = try source(
            named: "Sumi/Managers/ExtensionManager/ExtensionRequestedTabLifecycleOwner.swift"
        )

        XCTAssertTrue(
            requestedTabLifecycleSource.contains(".normalBrowserTab"),
            "Extension-created external web URLs must be diagnosable as normal browser tabs"
        )
        XCTAssertFalse(
            requestedTabLifecycleSource.contains("presentExtensionExternalWebPopupSession"),
            "External https://account.example.test/login URLs requested by extensions should not use the auxiliary mini-window path"
        )
    }

    func testTabAwarePermissionAPIsArePreferredWhenTabIsKnown() throws {
        let capabilityOwnerSource = try source(
            named: "Sumi/Managers/ExtensionManager/SafariExtension/SafariExtensionInstallCapabilityOwner.swift"
        )
        let controllerSource = try source(
            named: "Sumi/Managers/ExtensionManager/ExtensionManager+ControllerDelegate.swift"
        )
        let routingOwnerSource = try source(
            named: "Sumi/Managers/ExtensionManager/ExtensionPermissionPromptRoutingOwner.swift"
        )
        let uiSource = try source(
            named: "Sumi/Managers/ExtensionManager/ExtensionManager+UI.swift"
        )

        XCTAssertTrue(controllerSource.contains("in tab: (any WKWebExtensionTab)?"))
        XCTAssertTrue(
            capabilityOwnerSource.contains("permissionStatus(for: permission, in: tab)")
                && capabilityOwnerSource.contains("permissionStatus(for: matchPattern, in: tab)")
                && capabilityOwnerSource.contains("permissionStatus(for: url, in: tab)"),
            "The shared permission status helper must evaluate permissions, match patterns, and URLs in the supplied tab context"
        )
        XCTAssertTrue(
            routingOwnerSource.contains(
                "manager.effectivePermissionStatus(for: $0, in: extensionContext, tab: tab)"
            )
                && routingOwnerSource.contains("manager.effectivePermissionStatus(")
                && routingOwnerSource.contains("for: url,")
                && routingOwnerSource.contains("tab: tab")
                && uiSource.contains("effectivePermissionStatus("),
            "WebKit permission prompts and action access checks must fall back to global grants when tab-aware status is unknown"
        )
        XCTAssertTrue(
            capabilityOwnerSource.contains("permissionStatus(for: pattern, in: tab)"),
            "Common host-permission helpers must preserve tab-aware granted match patterns"
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
        let optionsPresenterSource = try source(
            named: "Sumi/Managers/ExtensionManager/ExtensionOptionsWindowPresenter.swift"
        )
        let startupProtectionRuntimeSource = try source(
            named: "Sumi/Managers/BrowserManager/BrowserStartupProtectionRuntime.swift"
        )
        let requestedTabLifecycleSource = try source(
            named: "Sumi/Managers/ExtensionManager/ExtensionRequestedTabLifecycleOwner.swift"
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
            startupProtectionRuntimeSource.contains(
                "ExtensionUtils.isExtensionOwnedURL(tab.url) || tab.webExtensionContextOverride != nil"
            ),
            "Startup materialization deferral must not discard runtime-owned extension pages"
        )
        XCTAssertTrue(
            requestedTabLifecycleSource.contains("materializeExtensionOwnedTabIfNeeded"),
            "Background extension-created internal tabs must be materialized through the extension context"
        )
        XCTAssertFalse(
            profilesSource.contains("extensionContext.webViewConfiguration"),
            "Pre-load runtime context preparation must not consume or mutate WebKit's extension page configuration"
        )
        XCTAssertTrue(
            optionsPresenterSource.contains("sdkResolvedURL")
                && optionsPresenterSource.contains("extensionContext.webViewConfiguration"),
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
