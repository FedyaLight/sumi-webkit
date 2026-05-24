import Foundation
import SwiftData
import XCTest

@testable import Sumi

final class ChromeMV3ProfileHostTests: XCTestCase {
    func testProfileHostSkeletonCanBeConstructedInTestModeWithoutRuntimeActions() {
        let host = makeEnabledHost()
        let summary = host.diagnosticsSummary()

        XCTAssertEqual(host.moduleState, .enabled)
        XCTAssertTrue(host.isActive)
        XCTAssertEqual(host.controllerState, .absentNotCreated)
        XCTAssertEqual(summary.candidateVariantCount, 1)
        XCTAssertTrue(summary.allowedForProfilePreflight)
        XCTAssertFalse(summary.canCreateControllerNow)
        XCTAssertFalse(summary.canLoadContextNow)
        XCTAssertFalse(summary.canAttachToNormalTabsNow)
        XCTAssertFalse(summary.registersUserScriptsNow)
        XCTAssertFalse(summary.launchesNativeMessagingNow)
        XCTAssertFalse(summary.startsBackgroundWorkNow)
    }

    @MainActor
    func testDisabledModuleDoesNotCreateProfileHostOrManager() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = ChromeMV3HostExtensionsRuntimeProbe()
        let module = try makeExtensionsModule(registry: registry, probe: probe)

        let host = module.chromeMV3ProfileHostIfEnabled(
            candidateRewrittenVariants: [makeCandidate()]
        )

        XCTAssertNil(host)
        XCTAssertEqual(probe.managerCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testDisabledPreflightRefusesControllerCreation() {
        let host = ChromeMV3ProfileHost(
            profileIdentifier: "disabled-profile",
            extensionsEnabled: false,
            profileDataStoreIdentity: .profileIdentifier("disabled-profile"),
            candidateRewrittenVariants: [makeCandidate()]
        )
        let eligibility = ChromeMV3WebViewEligibilityPolicy.evaluate(
            surface: .normalTab,
            extensionModuleEnabled: host.isActive,
            profileHostActive: host.isActive
        )

        let result = ChromeMV3RuntimePreflight.evaluate(
            profileHost: host,
            candidate: host.candidate(withID: "candidate-1"),
            report: makeRuntimeLoadabilityReport(),
            webViewEligibility: eligibility
        )

        XCTAssertFalse(result.canCreateControllerNow)
        XCTAssertFalse(result.canLoadContextNow)
        XCTAssertFalse(result.canAttachToNormalTabsNow)
        XCTAssertFalse(result.normalTabFutureEligible)
        XCTAssertTrue(
            result.blockingReasons.contains("Chrome MV3 profile host is disabled for this profile.")
        )
    }

    func testEnabledHostStillRefusesControllerCreationBecausePromptTenBlockersRemain() {
        let host = makeEnabledHost()
        let eligibility = ChromeMV3WebViewEligibilityPolicy.evaluate(
            surface: .normalTab,
            extensionModuleEnabled: true,
            profileHostActive: true
        )

        let result = ChromeMV3RuntimePreflight.evaluate(
            profileHost: host,
            candidate: host.candidate(withID: "candidate-1"),
            report: makeRuntimeLoadabilityReport(),
            webViewEligibility: eligibility
        )

        XCTAssertTrue(result.consumedRuntimeLoadabilityReport)
        XCTAssertEqual(result.runtimeLoadable, false)
        XCTAssertTrue(result.normalTabFutureEligible)
        XCTAssertFalse(result.canCreateControllerNow)
        XCTAssertFalse(result.canLoadContextNow)
        XCTAssertFalse(result.canAttachToNormalTabsNow)
        XCTAssertTrue(
            result.blockingReasons.contains("WebKit runtime loading is not yet wired.")
        )
        XCTAssertTrue(
            result.blockingReasons.contains("Controller creation is intentionally blocked by the non-loading host skeleton.")
        )
    }

    func testNormalTabSurfaceIsFutureEligibleButNotAttachableNow() {
        let eligibility = ChromeMV3WebViewEligibilityPolicy.evaluate(
            surface: .normalTab,
            extensionModuleEnabled: true,
            profileHostActive: true
        )

        XCTAssertEqual(eligibility.status, .futureEligible)
        XCTAssertTrue(eligibility.isFutureEligibleForNormalBrowsing)
        XCTAssertFalse(eligibility.canAttachControllerNow)
        XCTAssertTrue(
            eligibility.requiredFuturePreconditions.contains(
                "Runtime preflight must clear all generated-rewritten variant blockers."
            )
        )
    }

    func testPinnedEssentialsSurfacesAreSeparated() {
        let launcher = ChromeMV3WebViewEligibilityPolicy.evaluate(
            surface: .pinnedEssentialsLauncherMetadata,
            extensionModuleEnabled: true,
            profileHostActive: true
        )
        let liveRuntime = ChromeMV3WebViewEligibilityPolicy.evaluate(
            surface: .pinnedEssentialsLiveNormalBrowsing,
            extensionModuleEnabled: true,
            profileHostActive: true
        )

        XCTAssertEqual(launcher.status, .neverEligible)
        XCTAssertFalse(launcher.canAttachControllerNow)
        XCTAssertEqual(liveRuntime.status, .futureEligible)
        XCTAssertTrue(liveRuntime.isFutureEligibleForNormalBrowsing)
        XCTAssertFalse(liveRuntime.canAttachControllerNow)
    }

    func testPreviewMiniAndHelperSurfacesAreNotEligible() {
        let surfaces: [(ChromeMV3WebViewSurface, ChromeMV3WebViewEligibilityStatus)] = [
            (.peekGlancePreview, .notEligible),
            (.miniWindow, .notEligible),
            (.faviconDownload, .neverEligible),
            (.downloadHelper, .neverEligible),
            (.helperWebView, .neverEligible),
        ]

        for (surface, expectedStatus) in surfaces {
            let eligibility = ChromeMV3WebViewEligibilityPolicy.evaluate(
                surface: surface,
                extensionModuleEnabled: true,
                profileHostActive: true
            )

            XCTAssertEqual(eligibility.status, expectedStatus, surface.rawValue)
            XCTAssertFalse(eligibility.isFutureEligibleForNormalBrowsing, surface.rawValue)
            XCTAssertFalse(eligibility.canAttachControllerNow, surface.rawValue)
        }
    }

    func testExtensionOwnedPagesRequireFutureUIHost() {
        for surface in [
            ChromeMV3WebViewSurface.extensionOwnedPopup,
            .extensionOwnedOptionsPage,
        ] {
            let eligibility = ChromeMV3WebViewEligibilityPolicy.evaluate(
                surface: surface,
                extensionModuleEnabled: true,
                profileHostActive: true
            )

            XCTAssertEqual(
                eligibility.status,
                .futureEligibleThroughExtensionUIHostOnly,
                surface.rawValue
            )
            XCTAssertFalse(eligibility.isFutureEligibleForNormalBrowsing)
            XCTAssertFalse(eligibility.canAttachControllerNow)
            XCTAssertTrue(
                eligibility.requiredFuturePreconditions.contains(
                    "Define a dedicated extension-owned UI host."
                )
            )
        }
    }

    func testWebKitPopupHelperRequiresPromotionBeforeReevaluation() {
        let eligibility = ChromeMV3WebViewEligibilityPolicy.evaluate(
            surface: .webKitCreatedPopupOrNewWindow,
            extensionModuleEnabled: true,
            profileHostActive: true
        )

        XCTAssertEqual(eligibility.status, .eligibleAfterPromotionAndReevaluation)
        XCTAssertFalse(eligibility.isFutureEligibleForNormalBrowsing)
        XCTAssertFalse(eligibility.canAttachControllerNow)
        XCTAssertTrue(
            eligibility.requiredFuturePreconditions.contains(
                "Promote the surface to a real normal browsing tab or window."
            )
        )
    }

    func testPreflightConsumesRuntimeLoadabilityReportAndPreservesRuntimeLoadableFalse() {
        let host = makeEnabledHost()
        let result = host.evaluatePreflight(
            candidateID: "candidate-1",
            report: makeRuntimeLoadabilityReport()
        )
        let passedChecks = Set(result.checks.filter(\.passed).map(\.check))

        XCTAssertTrue(result.consumedRuntimeLoadabilityReport)
        XCTAssertEqual(result.runtimeLoadable, false)
        XCTAssertTrue(passedChecks.contains(.reportExists))
        XCTAssertTrue(passedChecks.contains(.runtimeLoadableRemainsFalse))
        XCTAssertTrue(passedChecks.contains(.manifestVersionIsMV3))
        XCTAssertTrue(passedChecks.contains(.rewrittenVariantExists))
        XCTAssertTrue(passedChecks.contains(.runtimeTemplatesExist))
        XCTAssertTrue(passedChecks.contains(.blockersRecorded))
        XCTAssertTrue(passedChecks.contains(.unsupportedAndDeferredAPIsRepresented))
        XCTAssertTrue(passedChecks.contains(.futureWebKitPreconditionsRemainUnsatisfied))
        XCTAssertFalse(result.canCreateControllerNow)
        XCTAssertFalse(result.canLoadContextNow)
        XCTAssertFalse(result.canAttachToNormalTabsNow)
    }

    func testDiagnosticsReportNoScriptHostMessagingOrScheduledWork() {
        let result = makeEnabledHost().evaluatePreflight(
            candidateID: "candidate-1",
            report: makeRuntimeLoadabilityReport()
        )
        let summary = makeEnabledHost().diagnosticsSummary(
            preflightResults: [result]
        )

        XCTAssertFalse(summary.registersUserScriptsNow)
        XCTAssertFalse(summary.launchesNativeMessagingNow)
        XCTAssertFalse(summary.startsBackgroundWorkNow)
        XCTAssertTrue(
            summary.blockingReasons.contains(
                "Normal-tab attachment is intentionally blocked by the non-loading host skeleton."
            )
        )
    }

    func testSourceGuardsForNewHostLayer() throws {
        let source = try [
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3ProfileHost.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3RuntimePreflight.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3WebViewEligibilityPolicy.swift",
        ]
            .map { try Self.source(named: $0) }
            .joined(separator: "\n")

        for forbidden in [
            "import " + "WebKit",
            "WKWebExtension" + "(",
            "WKWebExtension" + "Controller(",
            "WKWebExtension" + "Context(",
            "load" + "ExtensionContext",
            "add" + "UserScript",
            "connect" + "Native",
            "DispatchSource" + "Ti" + "mer",
            "Ti" + "mer",
        ] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
    }

    private func makeEnabledHost() -> ChromeMV3ProfileHost {
        ChromeMV3ProfileHost(
            profileIdentifier: "profile-1",
            extensionsEnabled: true,
            profileDataStoreIdentity: .profileIdentifier("profile-1"),
            candidateRewrittenVariants: [makeCandidate()]
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

    private func makeRuntimeLoadabilityReport() -> ChromeMV3RuntimeLoadabilityReport {
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
            passwordManagerReadiness: ChromeMV3PasswordManagerRuntimeReadinessReport(
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
        probe: ChromeMV3HostExtensionsRuntimeProbe
    ) throws -> SumiExtensionsModule {
        let container = try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let initialProfile = Profile(name: "Chrome MV3 Host Test")
        return SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: BrowserConfiguration(),
            initialProfileProvider: { initialProfile },
            managerFactory: { context, initialProfile, browserConfiguration in
                probe.managerCount += 1
                return ExtensionManager(
                    context: context,
                    initialProfile: initialProfile,
                    browserConfiguration: browserConfiguration
                )
            }
        )
    }

    private static func source(named relativePath: String) throws -> String {
        let sourceURL = repoRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private final class ChromeMV3HostExtensionsRuntimeProbe {
    var managerCount = 0
}
