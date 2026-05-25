import Foundation
import SwiftData
import WebKit
import XCTest

@testable import Sumi

final class ChromeMV3ControllerStorageTeardownAttachmentTests: XCTestCase {
    func testDataStoreIdentityPolicyRecordsPersistentProfileIdentity() {
        let diagnostics = ChromeMV3ControllerDataStoreIdentityPolicy.evaluate(
            profileIdentifier: "profile-1",
            dataStoreIdentity: .profileIdentifier("profile-1"),
            controllerConfigurationIdentifier: "controller-1",
            controllerCreated: false
        )

        XCTAssertEqual(diagnostics.profileIdentifier, "profile-1")
        XCTAssertEqual(diagnostics.dataStoreIdentityValue, "profile-1")
        XCTAssertEqual(diagnostics.storageKind, .persistentProfile)
        XCTAssertTrue(diagnostics.identityResolved)
        XCTAssertTrue(diagnostics.allowedForFuturePersistentProfileUse)
        XCTAssertFalse(diagnostics.allowedForFutureEphemeralPrivateProfileUse)
        XCTAssertFalse(diagnostics.cleanupRequiredOnDisableOrTeardown)
        XCTAssertFalse(diagnostics.generatedArtifactsTiedToDataStoreIdentity)
        XCTAssertEqual(
            diagnostics.controllerConfigurationIdentityString,
            "controller-1"
        )
        XCTAssertFalse(diagnostics.usesNonPersistentControllerConfiguration)
        XCTAssertFalse(diagnostics.clearsWebsiteDataOnCleanup)
        XCTAssertFalse(diagnostics.deletesGeneratedArtifactsOnCleanup)
    }

    func testDataStoreIdentityPolicyRecordsEphemeralProfileIdentity() {
        let diagnostics = ChromeMV3ControllerDataStoreIdentityPolicy.evaluate(
            profileIdentifier: "private-profile",
            dataStoreIdentity: .ephemeralProfileIdentifier("private-profile"),
            controllerCreated: true
        )

        XCTAssertEqual(diagnostics.storageKind, .ephemeralPrivateProfile)
        XCTAssertTrue(diagnostics.identityResolved)
        XCTAssertFalse(diagnostics.allowedForFuturePersistentProfileUse)
        XCTAssertTrue(diagnostics.allowedForFutureEphemeralPrivateProfileUse)
        XCTAssertTrue(diagnostics.cleanupRequiredOnDisableOrTeardown)
        XCTAssertTrue(diagnostics.usesNonPersistentControllerConfiguration)
        XCTAssertFalse(diagnostics.clearsWebsiteDataOnCleanup)
        XCTAssertFalse(diagnostics.deletesGeneratedArtifactsOnCleanup)
    }

    @MainActor
    func testDisabledModuleDoesNotResolveControllerDataStoreIdentity() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = ChromeMV3ControllerPolicyModuleProbe()
        let module = try makeExtensionsModule(
            registry: registry,
            probe: probe
        )

        let dataStoreDiagnostics =
            module.chromeMV3ControllerDataStoreIdentityDiagnosticsIfEnabled(
                explicitControllerCreationAllowed: true
            )
        let preflight = module.chromeMV3ControllerAttachmentPreflightIfEnabled(
            surface: .normalTab
        )
        let teardown = module.tearDownChromeMV3EmptyControllerOwnerIfEnabled(
            trigger: .moduleDisable
        )

        XCTAssertNil(dataStoreDiagnostics)
        XCTAssertNil(preflight)
        XCTAssertNil(teardown)
        XCTAssertEqual(probe.profileProviderCount, 0)
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertEqual(probe.ownerFactoryCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    @MainActor
    func testEnabledEmptyControllerReportsResolvedDataStoreIdentity() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.extensions)
        let probe = ChromeMV3ControllerPolicyModuleProbe()
        let module = try makeExtensionsModule(
            registry: registry,
            probe: probe
        )

        let owner = try XCTUnwrap(
            module.createChromeMV3EmptyControllerOwnerIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )
        let diagnostics = try XCTUnwrap(
            module.chromeMV3ControllerDataStoreIdentityDiagnosticsIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )

        XCTAssertNotNil(owner.controller)
        XCTAssertEqual(probe.ownerFactoryCount, 1)
        XCTAssertEqual(diagnostics.profileIdentifier, probe.profile.id.uuidString)
        XCTAssertEqual(diagnostics.dataStoreIdentityValue, probe.profile.id.uuidString)
        XCTAssertEqual(diagnostics.storageKind, .persistentProfile)
        XCTAssertTrue(diagnostics.identityResolved)
        XCTAssertTrue(diagnostics.allowedForFuturePersistentProfileUse)
        XCTAssertFalse(diagnostics.allowedForFutureEphemeralPrivateProfileUse)
        XCTAssertTrue(diagnostics.cleanupRequiredOnDisableOrTeardown)
        XCTAssertFalse(diagnostics.generatedArtifactsTiedToDataStoreIdentity)
        XCTAssertFalse(diagnostics.clearsWebsiteDataOnCleanup)
        XCTAssertFalse(diagnostics.deletesGeneratedArtifactsOnCleanup)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    @MainActor
    func testTeardownReleasesEmptyControllerAndReportsZeroRuntimeCounts()
        throws
    {
        let owner = try XCTUnwrap(
            ChromeMV3EmptyControllerFactory.makeOwner(
                gateDecision: makeDecision(
                    explicitControllerCreationAllowed: true
                ),
                defaultWebsiteDataStore: .nonPersistent(),
                controllerIdentifier: UUID()
            )
        )

        XCTAssertNotNil(owner.controller)

        let diagnostics = owner.tearDown(trigger: .profileClose)
        let teardownPolicy = try XCTUnwrap(diagnostics.teardownPolicy)

        XCTAssertNil(owner.controller)
        XCTAssertEqual(diagnostics.controllerState, .tornDown)
        XCTAssertFalse(diagnostics.controllerCreated)
        XCTAssertEqual(diagnostics.contextCount, 0)
        XCTAssertEqual(diagnostics.loadedExtensionCount, 0)
        XCTAssertEqual(diagnostics.attachedWebViewCount, 0)
        XCTAssertEqual(diagnostics.nativeMessagingPortCount, 0)
        XCTAssertEqual(diagnostics.pendingContextLoads, 0)
        XCTAssertEqual(diagnostics.pendingAttachments, 0)
        XCTAssertEqual(teardownPolicy.trigger, .profileClose)
        XCTAssertTrue(teardownPolicy.shouldReleaseEmptyController)
        XCTAssertFalse(teardownPolicy.shouldClearWebsiteData)
        XCTAssertFalse(teardownPolicy.shouldDeleteGeneratedArtifacts)
        XCTAssertFalse(teardownPolicy.shouldCancelNativeMessagingPorts)
        XCTAssertTrue(teardownPolicy.futureConfigurationsBecomeUnattachedImmediately)
        XCTAssertTrue(teardownPolicy.marksExistingDebugAttachedWebViewsStale)
        XCTAssertFalse(teardownPolicy.claimsExistingWebViewsDetached)
        XCTAssertTrue(
            teardownPolicy
                .requiresWebViewRecreationForExistingDebugAttachedInstances
        )
        XCTAssertEqual(teardownPolicy.pendingContextLoadsAfterTeardown, 0)
        XCTAssertEqual(teardownPolicy.pendingAttachmentsAfterTeardown, 0)
        XCTAssertTrue(
            diagnostics.liveNormalTabAttachmentSnapshot.recentDecisions.isEmpty
        )
    }

    func testTeardownPoliciesDoNotDeleteGeneratedArtifacts() {
        for trigger in ChromeMV3EmptyControllerTeardownTrigger.allCases {
            let policy = ChromeMV3EmptyControllerTeardownPolicyEvaluator
                .evaluate(trigger: trigger, controllerCreated: true)

            XCTAssertEqual(policy.trigger, trigger)
            XCTAssertTrue(policy.shouldReleaseEmptyController)
            XCTAssertFalse(policy.shouldClearWebsiteData)
            XCTAssertFalse(policy.shouldDeleteGeneratedArtifacts)
            XCTAssertFalse(policy.shouldCancelNativeMessagingPorts)
            XCTAssertTrue(policy.futureConfigurationsBecomeUnattachedImmediately)
            XCTAssertTrue(policy.marksExistingDebugAttachedWebViewsStale)
            XCTAssertFalse(policy.claimsExistingWebViewsDetached)
            XCTAssertTrue(
                policy.requiresWebViewRecreationForExistingDebugAttachedInstances
            )
            XCTAssertEqual(policy.userVisibleReloadOrRecreatePolicy, "deferred")
            XCTAssertEqual(policy.pendingContextLoadsAfterTeardown, 0)
            XCTAssertEqual(policy.pendingAttachmentsAfterTeardown, 0)
        }
    }

    func testAttachmentPreflightForNormalTabIsFutureEligibleButBlockedNow() {
        let result = makeAttachmentPreflight(surface: .normalTab)

        XCTAssertEqual(result.surface, .normalTab)
        XCTAssertEqual(result.eligibilityStatus, .futureEligible)
        XCTAssertTrue(result.futureEligibleForNormalBrowsing)
        XCTAssertFalse(result.canAttachControllerNow)
        XCTAssertFalse(result.wouldRequireEnabledModule)
        XCTAssertTrue(result.wouldRequireCreatedController)
        XCTAssertTrue(result.wouldRequireLoadableRuntime)
        XCTAssertFalse(result.wouldRequireNormalBrowsingSurface)
        XCTAssertTrue(result.wouldRequireSameControllerAsFutureContext)
        XCTAssertTrue(
            result.blockingReasons.contains(
                "Controller attachment is blocked now; this prompt only performs preflight."
            )
        )
        XCTAssertTrue(
            result.riskNotes.contains(
                "Future tab WebViews must receive the same WKWebExtensionController as the future loaded context."
            )
        )
    }

    func testPinnedEssentialsLiveNormalBrowsingFollowsNormalTabPolicy() {
        let result = makeAttachmentPreflight(
            surface: .pinnedEssentialsLiveNormalBrowsing
        )

        XCTAssertEqual(result.eligibilityStatus, .futureEligible)
        XCTAssertTrue(result.futureEligibleForNormalBrowsing)
        XCTAssertFalse(result.canAttachControllerNow)
        XCTAssertTrue(result.wouldRequireLoadableRuntime)
        XCTAssertTrue(result.wouldRequireSameControllerAsFutureContext)
    }

    func testLauncherMetadataPreviewMiniAndHelperSurfacesAreBlocked() {
        let cases: [(ChromeMV3WebViewSurface, ChromeMV3WebViewEligibilityStatus)] = [
            (.pinnedEssentialsLauncherMetadata, .neverEligible),
            (.peekGlancePreview, .notEligible),
            (.miniWindow, .notEligible),
            (.faviconDownload, .neverEligible),
            (.downloadHelper, .neverEligible),
            (.helperWebView, .neverEligible),
        ]

        for (surface, expectedStatus) in cases {
            let result = makeAttachmentPreflight(surface: surface)

            XCTAssertEqual(result.eligibilityStatus, expectedStatus, surface.rawValue)
            XCTAssertFalse(result.futureEligibleForNormalBrowsing, surface.rawValue)
            XCTAssertFalse(result.canAttachControllerNow, surface.rawValue)
            XCTAssertTrue(
                result.wouldRequireNormalBrowsingSurface,
                surface.rawValue
            )
            XCTAssertFalse(
                result.wouldRequireSameControllerAsFutureContext,
                surface.rawValue
            )
        }
    }

    func testExtensionPopupAndOptionsAreFutureOnlyThroughExtensionUIHost() {
        for surface in [
            ChromeMV3WebViewSurface.extensionOwnedPopup,
            .extensionOwnedOptionsPage,
        ] {
            let result = makeAttachmentPreflight(surface: surface)

            XCTAssertEqual(
                result.eligibilityStatus,
                .futureEligibleThroughExtensionUIHostOnly,
                surface.rawValue
            )
            XCTAssertFalse(result.futureEligibleForNormalBrowsing)
            XCTAssertFalse(result.canAttachControllerNow)
            XCTAssertTrue(result.wouldRequireNormalBrowsingSurface)
            XCTAssertTrue(
                result.riskNotes.contains(
                    "Define a dedicated extension-owned UI host."
                )
            )
        }
    }

    @MainActor
    func testBrowserConfigNormalTabConfigurationsRemainUnattached() {
        let profile = Profile(name: "Chrome MV3 Attachment Guard")
        let browserConfiguration = BrowserConfiguration()
        let configuration = browserConfiguration.normalTabWebViewConfiguration(
            for: profile,
            url: URL(string: "https://example.com")
        )
        let diagnostic = ChromeMV3WebViewConfigurationAttachmentGuard.inspect(
            configuration: configuration,
            siteID: "test.normalTab",
            surface: .normalTab
        )

        XCTAssertTrue(diagnostic.isNormalTabConfiguration)
        XCTAssertFalse(diagnostic.hasControllerAttachment)
        XCTAssertFalse(diagnostic.attachmentAllowedNow)
        XCTAssertEqual(
            diagnostic.verdict,
            "No Chrome MV3 controller attachment detected."
        )
        XCTAssertNil(configuration.webExtensionController)
    }

    @MainActor
    func testBrowserConfigAuxiliaryConfigurationsRemainUnattached() {
        let browserConfiguration = BrowserConfiguration()
        let cases: [(BrowserConfigurationAuxiliarySurface, ChromeMV3WebViewSurface)] = [
            (.faviconDownload, .faviconDownload),
            (.glance, .peekGlancePreview),
            (.miniWindow, .miniWindow),
            (.extensionOptions, .extensionOwnedOptionsPage),
        ]

        for (surface, chromeSurface) in cases {
            let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
                surface: surface
            )
            let diagnostic = ChromeMV3WebViewConfigurationAttachmentGuard.inspect(
                configuration: configuration,
                siteID: "test.auxiliary.\(surface.rawValue)",
                surface: chromeSurface
            )

            XCTAssertFalse(diagnostic.isNormalTabConfiguration, surface.rawValue)
            XCTAssertFalse(diagnostic.hasControllerAttachment, surface.rawValue)
            XCTAssertFalse(diagnostic.attachmentAllowedNow, surface.rawValue)
            XCTAssertNil(configuration.webExtensionController, surface.rawValue)
        }
    }

    func testSurfaceInventoryKeepsRealCreationSitesUnattached() {
        let diagnostics = ChromeMV3WebViewSurfaceInventory.diagnostics(
            extensionModuleEnabled: true,
            profileHostActive: true
        )

        XCTAssertFalse(diagnostics.isEmpty)
        for diagnostic in diagnostics {
            XCTAssertFalse(
                diagnostic.controllerAttachmentAllowedNow,
                diagnostic.siteID
            )
            XCTAssertFalse(
                diagnostic.currentEligibility.canAttachControllerNow,
                diagnostic.siteID
            )
        }

        XCTAssertTrue(
            diagnostics.contains {
                $0.siteID == "glance.preview.tab"
                    && $0.currentEligibility.status == .notEligible
            }
        )
        XCTAssertTrue(
            diagnostics.contains {
                $0.siteID == "miniWindow.oauth.webView"
                    && $0.currentEligibility.status == .notEligible
            }
        )
        XCTAssertTrue(
            diagnostics.contains {
                $0.siteID == "extension.action.popup"
                    && $0.currentEligibility.status ==
                        .futureEligibleThroughExtensionUIHostOnly
            }
        )
    }

    func testContextLoadingAndRuntimeRemainBlocked() {
        let runtimePreflight = makeRuntimePreflight(surface: .normalTab)

        XCTAssertEqual(runtimePreflight.runtimeLoadable, false)
        XCTAssertFalse(runtimePreflight.canCreateControllerNow)
        XCTAssertFalse(runtimePreflight.canLoadContextNow)
        XCTAssertFalse(runtimePreflight.canAttachToNormalTabsNow)

        let controllerDiagnostics = ChromeMV3EmptyControllerDiagnostics
            .notCreated(
                gateDecision: makeDecision(
                    explicitControllerCreationAllowed: false
                )
            )

        XCTAssertFalse(controllerDiagnostics.canLoadContextNow)
        XCTAssertFalse(controllerDiagnostics.canAttachToNormalTabsNow)
        XCTAssertFalse(controllerDiagnostics.runtimeLoadable)
    }

    func testSourceGuardForStorageTeardownAndAttachmentPolicy() throws {
        let sourceFiles = try Self.chromeMV3SourceFiles()
        let controllerInitializerFiles = sourceFiles
            .filter { $0.contents.contains("WKWebExtension" + "Controller(") }
            .map(\.relativePath)
            .sorted()

        XCTAssertEqual(
            controllerInitializerFiles,
            [
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3EmptyControllerOwner.swift",
            ]
        )

        let extensionObjectInitializerFiles = sourceFiles
            .filter { $0.contents.contains("WKWebExtension" + "(") }
            .map(\.relativePath)
            .sorted()

        XCTAssertEqual(
            extensionObjectInitializerFiles,
            [
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3ExtensionObjectProbeRunner.swift",
            ]
        )

        let source = sourceFiles.map(\.contents).joined(separator: "\n")
        let assignmentFiles = sourceFiles
            .filter { Self.containsWebViewControllerAssignment($0.contents) }
            .map(\.relativePath)
            .sorted()

        XCTAssertEqual(
            assignmentFiles,
            [
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3NormalTabConfigurationAttachmentBridge.swift",
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3SyntheticConfigurationAttachmentHarness.swift",
            ]
        )

        for forbidden in [
            "WKWebExtension" + "Context(",
            "load" + "ExtensionContext",
            "add" + "UserScript",
            "connect" + "Native",
            "DispatchSource" + "Ti" + "mer",
            "scheduled" + "Ti" + "mer",
            "Ti" + "mer",
            "poll" + "ing",
        ] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
    }

    private static func containsWebViewControllerAssignment(
        _ contents: String
    ) -> Bool {
        [
            "configuration.webExtensionController" + " =",
            "config.webExtensionController" + " =",
            "result.configuration?.webExtensionController" + " =",
        ].contains { contents.contains($0) }
    }

    private func makeAttachmentPreflight(
        surface: ChromeMV3WebViewSurface
    ) -> ChromeMV3ControllerAttachmentPreflight {
        let runtimePreflight = makeRuntimePreflight(surface: surface)
        let controllerDiagnostics = ChromeMV3EmptyControllerDiagnostics
            .notCreated(
                gateDecision: makeDecision(
                    explicitControllerCreationAllowed: true
                )
            )
        let eligibility = ChromeMV3WebViewEligibilityPolicy.evaluate(
            surface: surface,
            extensionModuleEnabled: true,
            profileHostActive: true
        )

        return ChromeMV3ControllerAttachmentPreflightEvaluator.evaluate(
            surface: surface,
            eligibility: eligibility,
            controllerDiagnostics: controllerDiagnostics,
            runtimePreflight: runtimePreflight,
            moduleState: .enabled
        )
    }

    private func makeRuntimePreflight(
        surface: ChromeMV3WebViewSurface
    ) -> ChromeMV3RuntimePreflightResult {
        let host = makeEnabledHost()
        let eligibility = ChromeMV3WebViewEligibilityPolicy.evaluate(
            surface: surface,
            extensionModuleEnabled: true,
            profileHostActive: true
        )
        return ChromeMV3RuntimePreflight.evaluate(
            profileHost: host,
            candidate: host.candidate(withID: "candidate-1"),
            report: makeRuntimeLoadabilityReport(),
            webViewEligibility: eligibility
        )
    }

    private func makeEnabledHost() -> ChromeMV3ProfileHost {
        ChromeMV3ProfileHost(
            profileIdentifier: "profile-1",
            extensionsEnabled: true,
            profileDataStoreIdentity: .profileIdentifier("profile-1"),
            candidateRewrittenVariants: [makeCandidate()]
        )
    }

    private func makeDecision(
        extensionsModuleEnabled: Bool = true,
        hostEnabled: Bool = true,
        explicitControllerCreationAllowed: Bool,
        requestedContextLoading: Bool = false,
        requestedNormalTabAttachment: Bool = false,
        profileIdentifier: String = "profile-1",
        profileDataStoreIdentity: ChromeMV3ProfileDataStoreIdentity =
            .profileIdentifier("profile-1"),
        disabledRuntimeInvariantStatus: ChromeMV3DisabledRuntimeInvariantStatus =
            .satisfied
    ) -> ChromeMV3ControllerCreationGateDecision {
        let host = ChromeMV3ProfileHost(
            profileIdentifier: profileIdentifier,
            extensionsEnabled: hostEnabled,
            profileDataStoreIdentity: profileDataStoreIdentity
        )
        return host.controllerCreationGateDecision(
            extensionsModuleEnabled: extensionsModuleEnabled,
            explicitControllerCreationAllowed: explicitControllerCreationAllowed,
            requestedContextLoading: requestedContextLoading,
            requestedNormalTabAttachment: requestedNormalTabAttachment,
            disabledRuntimeInvariantStatus: disabledRuntimeInvariantStatus
        )
    }

    private func makeCandidate() -> ChromeMV3RewrittenVariantCandidate {
        ChromeMV3RewrittenVariantCandidate(
            id: "candidate-1",
            rewrittenVariantRootPath: "/tmp/sumi/generated-rewritten",
            runtimeLoadabilityReportPath: "/tmp/sumi/generated-rewritten/runtime-loadability-report.json",
            manifestVersion: 3,
            rewrittenVariantExists: true
        )
    }

    private func makeRuntimeLoadabilityReport()
        -> ChromeMV3RuntimeLoadabilityReport
    {
        let checks = [
            ChromeMV3RuntimeLoadabilityCheck(
                category: .manifestShape,
                status: .passed,
                message: "Rewritten manifest exists and declares manifest_version 3.",
                relatedPaths: ["manifest.json"],
                details: []
            ),
            ChromeMV3RuntimeLoadabilityCheck(
                category: .runtimeTemplateFileHashes,
                status: .passed,
                message: "Runtime template file hashes were recorded.",
                relatedPaths: ["_sumi_runtime/chrome-shim.common.js"],
                details: []
            ),
            ChromeMV3RuntimeLoadabilityCheck(
                category: .unsupportedAPIs,
                status: .passed,
                message: "Unsupported API classifications are represented.",
                relatedPaths: ["manifest.json"],
                details: []
            ),
            ChromeMV3RuntimeLoadabilityCheck(
                category: .deferredAPIs,
                status: .deferred,
                message: "Deferred APIs remain planning-only.",
                relatedPaths: ["manifest.json"],
                details: ["runtime"]
            ),
            ChromeMV3RuntimeLoadabilityCheck(
                category: .runtimeMessagingNotImplemented,
                status: .deferred,
                message: "Runtime messaging bridge is not implemented.",
                relatedPaths: ["manifest.json"],
                details: []
            ),
            ChromeMV3RuntimeLoadabilityCheck(
                category: .WebKitRuntimeNotWired,
                status: .deferred,
                message: "WebKit extension runtime loading is intentionally not wired.",
                relatedPaths: [],
                details: []
            ),
        ]

        return ChromeMV3RuntimeLoadabilityReport(
            schemaVersion: 1,
            id: "runtime-loadability-test",
            generatedVariantRootPath: "/tmp/sumi/generated-rewritten",
            generatedVariantRootRelativeName: "generated-rewritten",
            sourceApplicationReportHash: nil,
            rewrittenManifestHash: ChromeMV3RuntimeLoadabilityFileHash(
                relativePath: "manifest.json",
                sha256: String(repeating: "a", count: 64),
                byteCount: 128
            ),
            runtimeTemplateFileHashes: [
                ChromeMV3RuntimeLoadabilityFileHash(
                    relativePath: "_sumi_runtime/chrome-shim.common.js",
                    sha256: String(repeating: "b", count: 64),
                    byteCount: 64
                ),
            ],
            extensionPageRewrittenFileHashes: [],
            extensionPageStaticChecks: [],
            verificationChecks: checks,
            passedChecks: [.manifestShape, .runtimeTemplateFileHashes, .unsupportedAPIs],
            failedChecks: [],
            deferredChecks: [
                .deferredAPIs,
                .runtimeMessagingNotImplemented,
                .WebKitRuntimeNotWired,
            ],
            warnings: [],
            missing: [],
            blockers: [
                "Runtime messaging is not implemented.",
                "WebKit runtime loading is not yet wired.",
            ],
            unsupportedAPIs: [],
            deferredAPIs: [.runtime],
            requiredFutureRuntimeComponents: [
                "Future WebKit controller creation must be explicit and profile-scoped.",
                "Future context loading must wait for verified runtime messaging.",
            ],
            passwordManagerReadiness:
                ChromeMV3PasswordManagerRuntimeReadinessReport(
                    contentScriptsPresent: false,
                    allFramesDetected: false,
                    matchAboutBlankDetected: false,
                    hostPermissionsPresent: false,
                    actionPopupPresent: false,
                    storagePermissionPresent: false,
                    nativeMessagingDetected: false,
                    nativeMessagingBlocked: false,
                    runtimeMessagingImplemented: false,
                    controlledInputPageWorldBehaviorVerified: false,
                    serviceWorkerLifecycleVerified: false,
                    blockers: [],
                    deferredChecks: []
                ),
            structurallyValid: true,
            runtimeLoadable: false,
            runtimeLoadableFalseReason: "Non-loading test fixture.",
            readOnlyStaticInspection: true,
            documentationSources: []
        )
    }

    @MainActor
    private func makeExtensionsModule(
        registry: SumiModuleRegistry,
        probe: ChromeMV3ControllerPolicyModuleProbe
    ) throws -> SumiExtensionsModule {
        let container = try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: BrowserConfiguration(),
            initialProfileProvider: {
                probe.profileProviderCount += 1
                return probe.profile
            },
            managerFactory: { context, initialProfile, browserConfiguration in
                probe.managerCount += 1
                return ExtensionManager(
                    context: context,
                    initialProfile: initialProfile,
                    browserConfiguration: browserConfiguration
                )
            },
            chromeMV3EmptyControllerOwnerFactory: { decision, dataStore, identifier in
                probe.ownerFactoryCount += 1
                return ChromeMV3EmptyControllerFactory.makeOwner(
                    gateDecision: decision,
                    defaultWebsiteDataStore: dataStore,
                    controllerIdentifier: identifier
                )
            }
        )
    }

    private static func chromeMV3SourceFiles() throws
        -> [(relativePath: String, contents: String)]
    {
        let root = repoRoot.appendingPathComponent(
            "Sumi/Models/Extension/ChromeMV3"
        )
        return try FileManager.default
            .contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "swift" }
            .map { url in
                let relativePath =
                    "Sumi/Models/Extension/ChromeMV3/\(url.lastPathComponent)"
                return (
                    relativePath,
                    try String(contentsOf: url, encoding: .utf8)
                )
            }
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

@MainActor
private final class ChromeMV3ControllerPolicyModuleProbe {
    let profile = Profile(name: "Chrome MV3 Controller Policy Test")
    var profileProviderCount = 0
    var managerCount = 0
    var ownerFactoryCount = 0
}
