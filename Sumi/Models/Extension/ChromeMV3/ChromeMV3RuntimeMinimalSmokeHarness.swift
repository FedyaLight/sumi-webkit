//
//  ChromeMV3RuntimeMinimalSmokeHarness.swift
//  Sumi
//
//  DEBUG/internal smoke harness for an inert MV3 fixture. This is not Chrome
//  MV3 product runtime support and does not expose chrome.runtime.
//

import CryptoKit
import Foundation

enum ChromeMV3RuntimeMinimalSmokeOutcome:
    String,
    Codable,
    Sendable
{
    case blocked
    case passed
    case failed
}

enum ChromeMV3RuntimeMinimalSmokeStep:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case fixturePolicyEvaluated
    case acceptedExtensionObjectObserved
    case detachedContextObserved
    case controllerLoadObserved
    case sameControllerVerified
    case syntheticConfigurationCreated
    case syntheticConfigurationAttached
    case syntheticWebViewCreated
    case syntheticWebViewSkipped
    case syntheticNavigationSkipped
    case sideEffectsObserved
    case teardownCompleted
}

enum ChromeMV3RuntimeMinimalSmokeWebViewState:
    String,
    Codable,
    Sendable
{
    case notRequested
    case blocked
    case created
    case skipped
}

enum ChromeMV3RuntimeMinimalSmokeTeardownState:
    String,
    Codable,
    Sendable
{
    case notRequested
    case completed
}

enum ChromeMV3RuntimeMinimalSmokeGateBlocker:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case extensionsModuleDisabled
    case explicitSmokeHarnessNotAllowed
    case acceptedExtensionObjectUnavailable
    case detachedContextMissing
    case controllerLoadGateMissing
    case controllerLoadGateBlocked
    case loadedContextMissing
    case sameControllerMissing
    case minimalInertFixturePolicyFailed
    case realNormalTabAttachmentObserved
    case auxiliarySurfaceAttachmentObserved
    case jsBridgeExposed
    case serviceWorkerWakeAvailable
    case runtimeDispatchAvailable
    case storageEventDispatchAvailable
    case nativeMessagingAvailable
    case productRuntimeExposureRequested
    case syntheticNavigationRequested
    case runtimeLoadabilityInvariantViolation

    var reason: String {
        switch self {
        case .extensionsModuleDisabled:
            return "The extensions module is disabled."
        case .explicitSmokeHarnessNotAllowed:
            return "Explicit DEBUG/internal minimal smoke harness mode is not enabled."
        case .acceptedExtensionObjectUnavailable:
            return "An accepted WKWebExtension object is not available."
        case .detachedContextMissing:
            return "The inert fixture context was not observed before or during controller load."
        case .controllerLoadGateMissing:
            return "Controller-load gate diagnostics are missing."
        case .controllerLoadGateBlocked:
            return "The controller-load gate did not allow the inert fixture load."
        case .loadedContextMissing:
            return "A loaded inert WKWebExtensionContext was not observed in the controller."
        case .sameControllerMissing:
            return "The loaded context and synthetic configuration cannot prove the same controller identity."
        case .minimalInertFixturePolicyFailed:
            return "The fixture is not minimal and inert enough for the smoke harness."
        case .realNormalTabAttachmentObserved:
            return "A real normal-tab WebView attachment was observed; the smoke harness must stay synthetic."
        case .auxiliarySurfaceAttachmentObserved:
            return "An auxiliary/helper WebView surface attachment was observed."
        case .jsBridgeExposed:
            return "The Sumi JS bridge is exposed or injectable, which is forbidden."
        case .serviceWorkerWakeAvailable:
            return "A service-worker wake path is available or was observed."
        case .runtimeDispatchAvailable:
            return "Runtime message dispatch is available or was observed."
        case .storageEventDispatchAvailable:
            return "Storage runtime event dispatch is available or was observed."
        case .nativeMessagingAvailable:
            return "Native messaging launch or port opening is available or was observed."
        case .productRuntimeExposureRequested:
            return "Product runtime exposure, extension code execution, JS injection, native messaging, or product UI was requested."
        case .syntheticNavigationRequested:
            return "Synthetic WebView navigation was requested; the minimal smoke harness does not navigate."
        case .runtimeLoadabilityInvariantViolation:
            return "runtimeLoadable and chrome.runtime availability must remain false."
        }
    }
}

struct ChromeMV3RuntimeMinimalSmokeIdentity:
    Codable,
    Equatable,
    Sendable
{
    var kind: String
    var stableID: String
    var present: Bool
}

struct ChromeMV3RuntimeMinimalSmokeScenario:
    Codable,
    Equatable,
    Sendable
{
    var scenarioID: String
    var fixtureID: String
    var extensionID: String
    var profileID: String
}

struct ChromeMV3RuntimeMinimalSmokeSideEffectCounters:
    Codable,
    Equatable,
    Sendable
{
    var contextLoadedIntoController: Int
    var syntheticConfigurationAttached: Int
    var syntheticWebViewCreated: Int
    var syntheticNavigationAttempted: Int
    var jsBridgeAvailableNow: Bool
    var sumiJSInjectionCount: Int
    var scriptMessageHandlerCount: Int
    var serviceWorkerWakeCount: Int
    var runtimeDispatchCount: Int
    var runtimePortCount: Int
    var nativeMessagingPortCount: Int
    var processLaunchCount: Int
    var storageEventDispatchCount: Int
    var productUIExposureCount: Int
    var runtimeLoadable: Bool
    var chromeRuntimeAvailableNow: Bool
    var productRuntimeExposed: Bool
}

struct ChromeMV3RuntimeMinimalSmokeConfigurationResult:
    Codable,
    Equatable,
    Sendable
{
    var syntheticConfigurationCreated: Bool
    var syntheticConfigurationAttached: Bool
    var syntheticConfigurationIdentity:
        ChromeMV3RuntimeMinimalSmokeIdentity
    var controllerIdentity:
        ChromeMV3RuntimeMinimalSmokeIdentity
    var controllerIdentityMatchesLoadedContextController: Bool
    var realNormalTabConfigurationTouched: Bool
    var helperPreviewMiniFaviconDownloadSurfacesExcluded: Bool
    var disabledDefaultPathsRemainUnattached: Bool
    var userScriptCount: Int
}

struct ChromeMV3RuntimeMinimalSmokeWebViewResult:
    Codable,
    Equatable,
    Sendable
{
    var state: ChromeMV3RuntimeMinimalSmokeWebViewState
    var syntheticWebViewIdentity:
        ChromeMV3RuntimeMinimalSmokeIdentity?
    var syntheticWebViewCreated: Bool
    var syntheticWebViewUsesSameController: Bool
    var userVisibleWindowCreated: Bool
    var productTabRegistered: Bool
    var navigationAttempted: Bool
    var safeInertURLLoaded: Bool
    var blockingReasons: [String]
    var warnings: [String]
}

struct ChromeMV3RuntimeMinimalSmokeControllerLoadSummary:
    Codable,
    Equatable,
    Sendable
{
    var controllerLoadGateReportSummary:
        ChromeMV3ControllerLoadGateReportSummary?
    var loadOwnerState: ChromeMV3ControllerLoadOwnerState?
    var controllerLoadAttempted: Bool
    var contextLoadedIntoController: Bool
    var controllerLoadCount: Int
    var runtimeLoadable: Bool
    var chromeRuntimeAvailableNow: Bool
    var jsBridgeAvailableNow: Bool
}

struct ChromeMV3RuntimeMinimalSmokeTeardownResult:
    Codable,
    Equatable,
    Sendable
{
    var state: ChromeMV3RuntimeMinimalSmokeTeardownState
    var syntheticWebViewReleaseRequested: Bool
    var syntheticWebViewReleased: Bool
    var syntheticConfigurationReleaseRequested: Bool
    var syntheticConfigurationReleased: Bool
    var syntheticConfigurationAttachedAfterTeardown: Bool
    var loadedContextOwnerTeardownRequested: Bool
    var loadedContextOwnerTornDown: Bool
    var contextUnloadAttempted: Bool
    var contextUnloadedFromController: Bool
    var detachedContextReleased: Bool
    var controllerOwnerTornDown: Bool
    var generatedArtifactsDeleted: Bool
    var websiteDataCleared: Bool
    var diagnosticsResetForFutureRuns: Bool
    var warnings: [String]
}

struct ChromeMV3RuntimeMinimalSmokeGateInput:
    Codable,
    Equatable,
    Sendable
{
    var scenario: ChromeMV3RuntimeMinimalSmokeScenario
    var generatedRewrittenRootPath: String
    var extensionsModuleEnabled: Bool
    var explicitInternalSmokeHarnessAllowed: Bool
    var explicitSyntheticWebViewCreationAllowed: Bool
    var syntheticNavigationRequested: Bool
    var acceptedWebExtensionObjectAvailable: Bool
    var detachedContextAvailable: Bool
    var loadedContextAvailable: Bool
    var sameControllerAvailable: Bool
    var minimalInertFixturePolicy:
        ChromeMV3MinimalInertFixturePolicyResult
    var controllerLoadGateDecision:
        ChromeMV3ControllerLoadGateDecision?
    var controllerLoadOwnerDiagnostics:
        ChromeMV3ControllerLoadOwnerDiagnostics?
    var liveNormalTabAttachmentSnapshot:
        ChromeMV3LiveNormalTabAttachmentRecorderSnapshot?
    var runtimeBridgeReadinessReport:
        ChromeMV3RuntimeBridgeReadinessReport?
    var requestedProductRuntimeExposure: Bool
    var requestedExtensionCodeExecution: Bool
    var requestedUserScriptRegistration: Bool
    var requestedNativeMessagingLaunch: Bool
    var requestedServiceWorkerWake: Bool
    var requestedRuntimeDispatch: Bool
    var requestedStorageEventDispatch: Bool
    var requestedProductUI: Bool
}

struct ChromeMV3RuntimeMinimalSmokeGateDiagnostics:
    Codable,
    Equatable,
    Sendable
{
    var canRunSmokeHarnessNow: Bool
    var canCreateSyntheticConfigurationNow: Bool
    var canCreateSyntheticWebViewNow: Bool
    var canNavigateSyntheticWebViewNow: Bool
    var runtimeLoadable: Bool
    var chromeRuntimeAvailableNow: Bool
    var jsBridgeAvailableNow: Bool
    var productRuntimeExposed: Bool
    var realNormalTabsTouchedByDefault: Bool
    var disabledDefaultPathsRemainUnattached: Bool
    var excludedSurfaces: [ChromeMV3WebViewSurface]
    var warnings: [String]
}

struct ChromeMV3RuntimeMinimalSmokeGateDecision:
    Codable,
    Equatable,
    Sendable
{
    var input: ChromeMV3RuntimeMinimalSmokeGateInput
    var canRunSmokeHarnessNow: Bool
    var canCreateSyntheticConfigurationNow: Bool
    var canCreateSyntheticWebViewNow: Bool
    var canNavigateSyntheticWebViewNow: Bool
    var runtimeLoadable: Bool
    var chromeRuntimeAvailableNow: Bool
    var jsBridgeAvailableNow: Bool
    var productRuntimeExposed: Bool
    var blockers: [ChromeMV3RuntimeMinimalSmokeGateBlocker]
    var blockingReasons: [String]
    var warnings: [String]
    var diagnostics: ChromeMV3RuntimeMinimalSmokeGateDiagnostics
}

struct ChromeMV3RuntimeMinimalSmokeReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var scenarioID: String
    var fixtureID: String
    var extensionID: String
    var profileID: String
    var outcome: ChromeMV3RuntimeMinimalSmokeOutcome
    var canRunSmokeHarnessNow: Bool
    var contextLoadedIntoController: Bool
    var syntheticConfigurationAttached: Bool
    var syntheticWebViewState:
        ChromeMV3RuntimeMinimalSmokeWebViewState
    var runtimeLoadable: Bool
    var chromeRuntimeAvailableNow: Bool
    var jsBridgeAvailableNow: Bool
    var productRuntimeExposed: Bool
}

struct ChromeMV3RuntimeMinimalSmokeReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var generatedRewrittenRootPath: String
    var scenario: ChromeMV3RuntimeMinimalSmokeScenario
    var controllerIdentity: ChromeMV3RuntimeMinimalSmokeIdentity
    var contextIdentity: ChromeMV3RuntimeMinimalSmokeIdentity
    var syntheticConfigurationIdentity:
        ChromeMV3RuntimeMinimalSmokeIdentity
    var syntheticWebViewIdentity:
        ChromeMV3RuntimeMinimalSmokeIdentity?
    var steps: [ChromeMV3RuntimeMinimalSmokeStep]
    var outcome: ChromeMV3RuntimeMinimalSmokeOutcome
    var fixturePolicyResult:
        ChromeMV3MinimalInertFixturePolicyResult
    var contentScriptSmokeSummary:
        ChromeMV3ContentScriptSmokeReportSummary? = nil
    var controllerLoadResult:
        ChromeMV3RuntimeMinimalSmokeControllerLoadSummary
    var gateDecision: ChromeMV3RuntimeMinimalSmokeGateDecision
    var sameControllerSyntheticConfigurationResult:
        ChromeMV3RuntimeMinimalSmokeConfigurationResult
    var syntheticWebViewResult:
        ChromeMV3RuntimeMinimalSmokeWebViewResult
    var sideEffectCounters:
        ChromeMV3RuntimeMinimalSmokeSideEffectCounters
    var webKitInternalUncertaintyNotes: [String]
    var teardownResult:
        ChromeMV3RuntimeMinimalSmokeTeardownResult
    var chromeRuntimeAvailableNow: Bool
    var jsBridgeAvailableNow: Bool
    var runtimeLoadable: Bool
    var productRuntimeExposed: Bool
    var whyRuntimeLoadableRemainsFalse: [String]
    var blockers: [ChromeMV3RuntimeMinimalSmokeGateBlocker]
    var blockingReasons: [String]
    var warnings: [String]
    var documentationSources:
        [ChromeMV3WebKitObjectAcceptanceDocumentationSource]

    var summary: ChromeMV3RuntimeMinimalSmokeReportSummary {
        ChromeMV3RuntimeMinimalSmokeReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            scenarioID: scenario.scenarioID,
            fixtureID: scenario.fixtureID,
            extensionID: scenario.extensionID,
            profileID: scenario.profileID,
            outcome: outcome,
            canRunSmokeHarnessNow:
                gateDecision.canRunSmokeHarnessNow,
            contextLoadedIntoController:
                controllerLoadResult.contextLoadedIntoController,
            syntheticConfigurationAttached:
                sameControllerSyntheticConfigurationResult
                .syntheticConfigurationAttached,
            syntheticWebViewState: syntheticWebViewResult.state,
            runtimeLoadable: runtimeLoadable,
            chromeRuntimeAvailableNow: chromeRuntimeAvailableNow,
            jsBridgeAvailableNow: jsBridgeAvailableNow,
            productRuntimeExposed: productRuntimeExposed
        )
    }
}

enum ChromeMV3RuntimeMinimalSmokeGate {
    static func evaluate(
        input: ChromeMV3RuntimeMinimalSmokeGateInput
    ) -> ChromeMV3RuntimeMinimalSmokeGateDecision {
        var blockers: [ChromeMV3RuntimeMinimalSmokeGateBlocker] = []
        var warnings = input.minimalInertFixturePolicy.warnings

        if input.extensionsModuleEnabled == false {
            blockers.append(.extensionsModuleDisabled)
        }
        if input.explicitInternalSmokeHarnessAllowed == false {
            blockers.append(.explicitSmokeHarnessNotAllowed)
        }
        if input.acceptedWebExtensionObjectAvailable == false {
            blockers.append(.acceptedExtensionObjectUnavailable)
        }
        if input.detachedContextAvailable == false {
            blockers.append(.detachedContextMissing)
        }
        guard let controllerLoadDecision =
            input.controllerLoadGateDecision
        else {
            blockers.append(.controllerLoadGateMissing)
            return decision(
                input: input,
                blockers: blockers,
                warnings: warnings
            )
        }
        if controllerLoadDecision.loadAttemptAllowed == false {
            blockers.append(.controllerLoadGateBlocked)
        }
        if input.loadedContextAvailable == false
            || input.controllerLoadOwnerDiagnostics?
            .contextLoadedIntoController != true
        {
            blockers.append(.loadedContextMissing)
        }
        if input.sameControllerAvailable == false {
            blockers.append(.sameControllerMissing)
        }
        if input.minimalInertFixturePolicy
            .loadSafeForMinimalInertFixture == false
        {
            blockers.append(.minimalInertFixturePolicyFailed)
        }

        let liveSnapshot = input.liveNormalTabAttachmentSnapshot
            ?? input.controllerLoadGateDecision?
            .input
            .liveNormalTabAttachmentSnapshot
        if (liveSnapshot?.attachedConfigurationCount ?? 0) > 0
            || (liveSnapshot?.createdAttachedWebViewCount ?? 0) > 0
        {
            blockers.append(.realNormalTabAttachmentObserved)
        }
        if liveSnapshot?.accidentallyAttachedAuxiliarySurface == true {
            blockers.append(.auxiliarySurfaceAttachmentObserved)
        }

        let readiness = input.runtimeBridgeReadinessReport
        let jsBridge = readiness?.jsBridgeContractReportSummary
        let observedServiceWorkerWakeCount =
            input.controllerLoadOwnerDiagnostics?.serviceWorkerWakeCount ?? 0
        let observedNativeMessagingPortCount =
            input.controllerLoadOwnerDiagnostics?.nativeMessagingPortCount ?? 0
        if isSmokeTrue(jsBridge?.jsBridgeAvailableNow)
            || isSmokeTrue(jsBridge?.exposedToJSNow)
            || isSmokeTrue(jsBridge?.canInjectScriptsNow)
        {
            blockers.append(.jsBridgeExposed)
        }
        if isSmokeTrue(
            readiness?.serviceWorkerLifecycleReportSummary?
                .canWakeServiceWorkerNow
        )
            || isSmokeTrue(
                readiness?.serviceWorkerLifecycleGate
                    .serviceWorkerWakeImplemented
            )
            || observedServiceWorkerWakeCount > 0
            || input.requestedServiceWorkerWake
        {
            blockers.append(.serviceWorkerWakeAvailable)
        }
        if isSmokeTrue(readiness?.messagingGate.dispatchImplemented)
            || input.requestedRuntimeDispatch
        {
            blockers.append(.runtimeDispatchAvailable)
        }
        if isSmokeTrue(readiness?.storageGate.storageRuntimeImplemented)
            || input.requestedStorageEventDispatch
        {
            blockers.append(.storageEventDispatchAvailable)
        }
        if isSmokeTrue(
            readiness?.nativeMessagingGate
                .nativeMessagingRuntimeImplemented
        )
            || isSmokeTrue(
                readiness?.nativeMessagingGate.processLaunchImplemented
            )
            || isSmokeTrue(
                readiness?.nativeMessagingReadinessReportSummary?
                    .processLaunchAllowedNow
            )
            || isSmokeTrue(
                readiness?.nativeMessagingReadinessReportSummary?
                    .canOpenPortNow
            )
            || observedNativeMessagingPortCount > 0
            || input.requestedNativeMessagingLaunch
        {
            blockers.append(.nativeMessagingAvailable)
        }
        if input.requestedProductRuntimeExposure
            || input.requestedExtensionCodeExecution
            || input.requestedUserScriptRegistration
            || input.requestedProductUI
        {
            blockers.append(.productRuntimeExposureRequested)
        }
        if input.syntheticNavigationRequested {
            blockers.append(.syntheticNavigationRequested)
        }

        if isSmokeTrue(input.controllerLoadOwnerDiagnostics?.runtimeLoadable)
            || isSmokeTrue(
                input.controllerLoadOwnerDiagnostics?
                    .chromeRuntimeAvailableNow
            )
            || isSmokeTrue(
                input.controllerLoadOwnerDiagnostics?
                    .jsBridgeAvailableNow
            )
            || isSmokeTrue(readiness?.runtimeLoadable)
            || isSmokeTrue(controllerLoadDecision.runtimeLoadable)
            || isSmokeTrue(controllerLoadDecision.chromeRuntimeAvailableNow)
            || isSmokeTrue(controllerLoadDecision.jsBridgeAvailableNow)
            || isSmokeTrue(controllerLoadDecision.canExecuteExtensionCodeNow)
        {
            blockers.append(.runtimeLoadabilityInvariantViolation)
        }

        warnings.append(
            "The smoke harness is DEBUG/internal and synthetic; passing it does not expose Chrome MV3 runtime."
        )
        if input.explicitSyntheticWebViewCreationAllowed == false {
            warnings.append(
                "Synthetic WKWebView creation is skipped unless explicitly allowed for this smoke run."
            )
        }
        warnings.append(
            "Synthetic WebView navigation remains blocked; no page load is attempted."
        )

        return decision(
            input: input,
            blockers: blockers,
            warnings: warnings
        )
    }

    private static func decision(
        input: ChromeMV3RuntimeMinimalSmokeGateInput,
        blockers: [ChromeMV3RuntimeMinimalSmokeGateBlocker],
        warnings: [String]
    ) -> ChromeMV3RuntimeMinimalSmokeGateDecision {
        let uniqueBlockers = Array(Set(blockers)).sorted {
            $0.rawValue < $1.rawValue
        }
        let canRun = uniqueBlockers.isEmpty
        let canCreateWebView =
            canRun && input.explicitSyntheticWebViewCreationAllowed
        let diagnostics = ChromeMV3RuntimeMinimalSmokeGateDiagnostics(
            canRunSmokeHarnessNow: canRun,
            canCreateSyntheticConfigurationNow: canRun,
            canCreateSyntheticWebViewNow: canCreateWebView,
            canNavigateSyntheticWebViewNow: false,
            runtimeLoadable: false,
            chromeRuntimeAvailableNow: false,
            jsBridgeAvailableNow: false,
            productRuntimeExposed: false,
            realNormalTabsTouchedByDefault: false,
            disabledDefaultPathsRemainUnattached: true,
            excludedSurfaces:
                ChromeMV3WebViewSurface.allCases
                .filter { $0 != .syntheticTestConfiguration }
                .sorted { $0.rawValue < $1.rawValue },
            warnings: uniqueSorted(warnings)
        )
        return ChromeMV3RuntimeMinimalSmokeGateDecision(
            input: input,
            canRunSmokeHarnessNow: canRun,
            canCreateSyntheticConfigurationNow: canRun,
            canCreateSyntheticWebViewNow: canCreateWebView,
            canNavigateSyntheticWebViewNow: false,
            runtimeLoadable: false,
            chromeRuntimeAvailableNow: false,
            jsBridgeAvailableNow: false,
            productRuntimeExposed: false,
            blockers: uniqueBlockers,
            blockingReasons:
                uniqueSorted(uniqueBlockers.map(\.reason)),
            warnings: diagnostics.warnings,
            diagnostics: diagnostics
        )
    }
}

enum ChromeMV3RuntimeMinimalSmokeReportWriter {
    static let reportFileName =
        "runtime-minimal-smoke-harness-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3RuntimeMinimalSmokeReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3RuntimeMinimalSmokeReport {
        guard directoryExists(rootURL.standardizedFileURL) else {
            return report
        }
        try ChromeMV3DeterministicJSON.write(
            report,
            to: rootURL.standardizedFileURL
                .appendingPathComponent(Self.reportFileName)
        )
        return report
    }

    private static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }
}

enum ChromeMV3RuntimeMinimalSmokeReportGenerator {
    static func makeBlockedReport(
        gateDecision: ChromeMV3RuntimeMinimalSmokeGateDecision
    ) -> ChromeMV3RuntimeMinimalSmokeReport {
        makeReport(
            gateDecision: gateDecision,
            controllerIdentity: identity(
                kind: "controller",
                stableID: "missing-controller",
                present: false
            ),
            contextIdentity: identity(
                kind: "context",
                stableID: "missing-context",
                present: false
            ),
            syntheticConfigurationIdentity: identity(
                kind: "syntheticConfiguration",
                stableID:
                    "synthetic-configuration:\(gateDecision.input.scenario.scenarioID)",
                present: false
            ),
            syntheticWebViewIdentity: nil,
            configurationResult: configurationResult(
                gateDecision: gateDecision,
                configurationCreated: false,
                configurationAttached: false,
                controllerMatchesContext: false,
                userScriptCount: 0
            ),
            webViewResult: webViewResult(
                state: .blocked,
                identity: nil,
                created: false,
                sameController: false,
                blockingReasons: gateDecision.blockingReasons,
                warnings: gateDecision.warnings
            ),
            teardownResult: teardownResult(
                webViewCreated: false,
                configurationCreated: false,
                syntheticConfigurationAttachedAfterTeardown: false,
                loadedOwnerDiagnostics: nil,
                detachedContextReleased: false,
                controllerOwnerTornDown: false,
                diagnosticsResetForFutureRuns: false
            )
        )
    }

    static func makeReport(
        gateDecision: ChromeMV3RuntimeMinimalSmokeGateDecision,
        controllerIdentity: ChromeMV3RuntimeMinimalSmokeIdentity,
        contextIdentity: ChromeMV3RuntimeMinimalSmokeIdentity,
        syntheticConfigurationIdentity:
            ChromeMV3RuntimeMinimalSmokeIdentity,
        syntheticWebViewIdentity:
            ChromeMV3RuntimeMinimalSmokeIdentity?,
        configurationResult:
            ChromeMV3RuntimeMinimalSmokeConfigurationResult,
        webViewResult:
            ChromeMV3RuntimeMinimalSmokeWebViewResult,
        teardownResult:
            ChromeMV3RuntimeMinimalSmokeTeardownResult
    ) -> ChromeMV3RuntimeMinimalSmokeReport {
        let input = gateDecision.input
        let loadDiagnostics = input.controllerLoadOwnerDiagnostics
        let contextLoaded = isSmokeTrue(
            loadDiagnostics?.contextLoadedIntoController
        )
        let configurationAttached =
            configurationResult.syntheticConfigurationAttached
        let webViewCreated = webViewResult.syntheticWebViewCreated
        let outcome: ChromeMV3RuntimeMinimalSmokeOutcome
        if gateDecision.canRunSmokeHarnessNow == false {
            outcome = .blocked
        } else if configurationAttached
            && configurationResult
            .controllerIdentityMatchesLoadedContextController
            && webViewResult.navigationAttempted == false
        {
            outcome = .passed
        } else {
            outcome = .failed
        }

        return ChromeMV3RuntimeMinimalSmokeReport(
            schemaVersion: 1,
            id: reportID(
                scenario: input.scenario,
                rootPath: input.generatedRewrittenRootPath,
                outcome: outcome,
                webViewState: webViewResult.state
            ),
            reportFileName:
                ChromeMV3RuntimeMinimalSmokeReportWriter.reportFileName,
            generatedRewrittenRootPath:
                input.generatedRewrittenRootPath,
            scenario: input.scenario,
            controllerIdentity: controllerIdentity,
            contextIdentity: contextIdentity,
            syntheticConfigurationIdentity:
                syntheticConfigurationIdentity,
            syntheticWebViewIdentity: syntheticWebViewIdentity,
            steps: steps(
                gateDecision: gateDecision,
                configurationAttached: configurationAttached,
                webViewResult: webViewResult,
                teardownResult: teardownResult
            ),
            outcome: outcome,
            fixturePolicyResult: input.minimalInertFixturePolicy,
            controllerLoadResult:
                ChromeMV3RuntimeMinimalSmokeControllerLoadSummary(
                    controllerLoadGateReportSummary:
                        input.controllerLoadOwnerDiagnostics?
                        .gateDecision
                        .summaryLikeReportSummary(),
                    loadOwnerState:
                        loadDiagnostics?.state,
                    controllerLoadAttempted:
                        loadDiagnostics?.controllerLoadAttempted
                            ?? false,
                    contextLoadedIntoController: contextLoaded,
                    controllerLoadCount:
                        loadDiagnostics?.controllerLoadCount ?? 0,
                    runtimeLoadable: false,
                    chromeRuntimeAvailableNow: false,
                    jsBridgeAvailableNow: false
                ),
            gateDecision: gateDecision,
            sameControllerSyntheticConfigurationResult:
                configurationResult,
            syntheticWebViewResult: webViewResult,
            sideEffectCounters:
                ChromeMV3RuntimeMinimalSmokeSideEffectCounters(
                    contextLoadedIntoController:
                        contextLoaded ? 1 : 0,
                    syntheticConfigurationAttached:
                        configurationAttached ? 1 : 0,
                    syntheticWebViewCreated: webViewCreated ? 1 : 0,
                    syntheticNavigationAttempted: 0,
                    jsBridgeAvailableNow: false,
                    sumiJSInjectionCount: 0,
                    scriptMessageHandlerCount: 0,
                    serviceWorkerWakeCount: 0,
                    runtimeDispatchCount: 0,
                    runtimePortCount: 0,
                    nativeMessagingPortCount: 0,
                    processLaunchCount: 0,
                    storageEventDispatchCount: 0,
                    productUIExposureCount: 0,
                    runtimeLoadable: false,
                    chromeRuntimeAvailableNow: false,
                    productRuntimeExposed: false
                ),
            webKitInternalUncertaintyNotes:
                webKitUncertaintyNotes(
                    contextLoaded: contextLoaded,
                    webViewCreated: webViewCreated
                ),
            teardownResult: teardownResult,
            chromeRuntimeAvailableNow: false,
            jsBridgeAvailableNow: false,
            runtimeLoadable: false,
            productRuntimeExposed: false,
            whyRuntimeLoadableRemainsFalse: [
                "This is a DEBUG/internal smoke harness for an inert fixture, not product runtime support.",
                "The fixture has no background service worker, content scripts, extension pages, native messaging, web-accessible resources, or product UI.",
                "Sumi does not expose chrome.runtime, inject a Sumi JS bridge, register user scripts, dispatch extension messages, open runtime/native ports, launch native hosts, or dispatch storage events.",
                "runtimeLoadable, chromeRuntimeAvailableNow, jsBridgeAvailableNow, and productRuntimeExposed remain false by invariant.",
            ],
            blockers: gateDecision.blockers,
            blockingReasons: gateDecision.blockingReasons,
            warnings: uniqueSorted(
                gateDecision.warnings
                    + webViewResult.warnings
                    + teardownResult.warnings
            ),
            documentationSources: documentationSources()
        )
    }

    static func configurationResult(
        gateDecision: ChromeMV3RuntimeMinimalSmokeGateDecision,
        configurationCreated: Bool,
        configurationAttached: Bool,
        controllerMatchesContext: Bool,
        userScriptCount: Int
    ) -> ChromeMV3RuntimeMinimalSmokeConfigurationResult {
        ChromeMV3RuntimeMinimalSmokeConfigurationResult(
            syntheticConfigurationCreated: configurationCreated,
            syntheticConfigurationAttached: configurationAttached,
            syntheticConfigurationIdentity:
                identity(
                    kind: "syntheticConfiguration",
                    stableID:
                        "synthetic-configuration:\(gateDecision.input.scenario.scenarioID)",
                    present: configurationCreated
                ),
            controllerIdentity:
                identity(
                    kind: "controller",
                    stableID:
                        "controller:\(gateDecision.input.scenario.profileID)",
                    present: gateDecision.input.sameControllerAvailable
                ),
            controllerIdentityMatchesLoadedContextController:
                controllerMatchesContext,
            realNormalTabConfigurationTouched: false,
            helperPreviewMiniFaviconDownloadSurfacesExcluded: true,
            disabledDefaultPathsRemainUnattached: true,
            userScriptCount: userScriptCount
        )
    }

    static func webViewResult(
        state: ChromeMV3RuntimeMinimalSmokeWebViewState,
        identity: ChromeMV3RuntimeMinimalSmokeIdentity?,
        created: Bool,
        sameController: Bool,
        blockingReasons: [String],
        warnings: [String]
    ) -> ChromeMV3RuntimeMinimalSmokeWebViewResult {
        ChromeMV3RuntimeMinimalSmokeWebViewResult(
            state: state,
            syntheticWebViewIdentity: identity,
            syntheticWebViewCreated: created,
            syntheticWebViewUsesSameController: sameController,
            userVisibleWindowCreated: false,
            productTabRegistered: false,
            navigationAttempted: false,
            safeInertURLLoaded: false,
            blockingReasons: uniqueSorted(blockingReasons),
            warnings: uniqueSorted(warnings)
        )
    }

    static func teardownResult(
        webViewCreated: Bool,
        configurationCreated: Bool,
        syntheticConfigurationAttachedAfterTeardown: Bool,
        loadedOwnerDiagnostics:
            ChromeMV3ControllerLoadOwnerDiagnostics?,
        detachedContextReleased: Bool,
        controllerOwnerTornDown: Bool,
        diagnosticsResetForFutureRuns: Bool
    ) -> ChromeMV3RuntimeMinimalSmokeTeardownResult {
        ChromeMV3RuntimeMinimalSmokeTeardownResult(
            state: .completed,
            syntheticWebViewReleaseRequested: webViewCreated,
            syntheticWebViewReleased: webViewCreated,
            syntheticConfigurationReleaseRequested:
                configurationCreated,
            syntheticConfigurationReleased: configurationCreated,
            syntheticConfigurationAttachedAfterTeardown:
                syntheticConfigurationAttachedAfterTeardown,
            loadedContextOwnerTeardownRequested:
                loadedOwnerDiagnostics != nil,
            loadedContextOwnerTornDown:
                loadedOwnerDiagnostics?.teardownComplete ?? false,
            contextUnloadAttempted:
                loadedOwnerDiagnostics?.controllerUnloadAttempted
                    ?? false,
            contextUnloadedFromController:
                loadedOwnerDiagnostics?.contextUnloadedFromController
                    ?? false,
            detachedContextReleased: detachedContextReleased,
            controllerOwnerTornDown: controllerOwnerTornDown,
            generatedArtifactsDeleted: false,
            websiteDataCleared: false,
            diagnosticsResetForFutureRuns:
                diagnosticsResetForFutureRuns,
            warnings: [
                "Smoke teardown releases only synthetic references and DEBUG/internal context/controller owners; generated artifacts and website data are left untouched.",
            ]
        )
    }

    static func identity(
        kind: String,
        stableID: String,
        present: Bool
    ) -> ChromeMV3RuntimeMinimalSmokeIdentity {
        ChromeMV3RuntimeMinimalSmokeIdentity(
            kind: kind,
            stableID: stableID,
            present: present
        )
    }

    private static func steps(
        gateDecision: ChromeMV3RuntimeMinimalSmokeGateDecision,
        configurationAttached: Bool,
        webViewResult: ChromeMV3RuntimeMinimalSmokeWebViewResult,
        teardownResult: ChromeMV3RuntimeMinimalSmokeTeardownResult
    ) -> [ChromeMV3RuntimeMinimalSmokeStep] {
        var steps: [ChromeMV3RuntimeMinimalSmokeStep] = [
            .fixturePolicyEvaluated,
            .sideEffectsObserved,
            .syntheticNavigationSkipped,
        ]
        if gateDecision.input.acceptedWebExtensionObjectAvailable {
            steps.append(.acceptedExtensionObjectObserved)
        }
        if gateDecision.input.detachedContextAvailable {
            steps.append(.detachedContextObserved)
        }
        if gateDecision.input.loadedContextAvailable {
            steps.append(.controllerLoadObserved)
        }
        if gateDecision.input.sameControllerAvailable {
            steps.append(.sameControllerVerified)
        }
        if gateDecision.canCreateSyntheticConfigurationNow {
            steps.append(.syntheticConfigurationCreated)
        }
        if configurationAttached {
            steps.append(.syntheticConfigurationAttached)
        }
        switch webViewResult.state {
        case .created:
            steps.append(.syntheticWebViewCreated)
        case .notRequested, .blocked, .skipped:
            steps.append(.syntheticWebViewSkipped)
        }
        if teardownResult.state == .completed {
            steps.append(.teardownCompleted)
        }
        return Array(Set(steps)).sorted { $0.rawValue < $1.rawValue }
    }

    private static func reportID(
        scenario: ChromeMV3RuntimeMinimalSmokeScenario,
        rootPath: String,
        outcome: ChromeMV3RuntimeMinimalSmokeOutcome,
        webViewState: ChromeMV3RuntimeMinimalSmokeWebViewState
    ) -> String {
        let input = [
            scenario.scenarioID,
            scenario.fixtureID,
            scenario.extensionID,
            scenario.profileID,
            rootPath,
            outcome.rawValue,
            webViewState.rawValue,
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func webKitUncertaintyNotes(
        contextLoaded: Bool,
        webViewCreated: Bool
    ) -> [String] {
        var notes = [
            "Observable Sumi-side counters are deterministic; private WebKit internals are not fully observable from Sumi.",
        ]
        if contextLoaded {
            notes.append(
                "The WKWebExtensionController load method was already observed by the controller-load owner; WebKit-internal side effects remain conservatively unverified."
            )
        }
        if webViewCreated {
            notes.append(
                "A synthetic WKWebView was created without navigation; WebKit-internal process behavior remains conservatively unverified."
            )
        }
        return uniqueSorted(notes)
    }

    private static func documentationSources()
        -> [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    {
        [
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebExtensionController",
                url: "https://developer.apple.com/documentation/webkit/wkwebextensioncontroller",
                note: "A controller manages loaded extension contexts and can be associated with WKWebViewConfiguration."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebExtensionController load method",
                url: "https://developer.apple.com/documentation/webkit/wkwebextensioncontroller/load(_:)",
                note: "Loading starts a context; Sumi confines this to the existing DEBUG/internal controller-load owner."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebViewConfiguration.webExtensionController",
                url: "https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/webextensioncontroller",
                note: "The property associates a web extension controller with a WebView configuration."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebExtensionTab.webView(for:)",
                url: "https://developer.apple.com/documentation/webkit/wkwebextensiontab/webview%28for%3A%29",
                note: "Apple documents the same-controller requirement for tab WebViews."
            ),
            source(
                kind: "localAppleSDKHeaders",
                title: "MacOSX26.5 WebKit headers",
                url: nil,
                note: "The local header says controller loading can start background content and content injection, so the smoke harness requires an inert no-background/no-content fixture."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Manifest file format",
                url: "https://developer.chrome.com/docs/extensions/mv3/manifest",
                note: "Used only for MV3 manifest terminology and minimal manifest shape."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Manifest content scripts",
                url: "https://developer.chrome.com/docs/extensions/reference/manifest/content-scripts",
                note: "Content scripts are treated as injection candidates and blocked for the inert fixture."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Extension service worker lifecycle",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle",
                note: "Used only for MV3 service-worker lifecycle terminology; Sumi does not wake service workers here."
            ),
        ]
    }

    private static func source(
        kind: String,
        title: String,
        url: String?,
        note: String
    ) -> ChromeMV3WebKitObjectAcceptanceDocumentationSource {
        ChromeMV3WebKitObjectAcceptanceDocumentationSource(
            kind: kind,
            title: title,
            url: url,
            note: note
        )
    }
}

#if DEBUG
import WebKit

@available(macOS 15.5, *)
enum ChromeMV3RuntimeMinimalSmokeHarness {
    @MainActor
    static func run(
        scenarioID: String = "runtime-minimal-smoke",
        fixtureID: String? = nil,
        candidate: ChromeMV3RewrittenVariantCandidate,
        extensionsModuleEnabled: Bool,
        explicitInternalSmokeHarnessAllowed: Bool,
        explicitSyntheticWebViewCreationAllowed: Bool,
        objectAcceptanceReport:
            ChromeMV3WebKitObjectAcceptanceReport?,
        runtimeBridgeReadinessReport:
            ChromeMV3RuntimeBridgeReadinessReport?,
        emptyControllerOwner:
            ChromeMV3EmptyControllerOwner?,
        detachedContextOwner:
            ChromeMV3DetachedContextOwner?,
        controllerLoadOwner:
            ChromeMV3ControllerLoadOwner?,
        liveNormalTabAttachmentSnapshot:
            ChromeMV3LiveNormalTabAttachmentRecorderSnapshot? = nil,
        tearDownLoadedContextAndControllerAfterRun: Bool = true,
        diagnosticsResetForFutureRuns: Bool = false
    ) -> ChromeMV3RuntimeMinimalSmokeReport {
        let rootPath = URL(
            fileURLWithPath: candidate.rewrittenVariantRootPath,
            isDirectory: true
        ).standardizedFileURL.path
        let loadDiagnostics = controllerLoadOwner?.diagnostics()
        let controller = emptyControllerOwner?.controller
        let context = detachedContextOwner?.detachedContext
        let accepted = isSmokeTrue(
            objectAcceptanceReport?.objectAcceptedByWebKit
        )
        let detachedAvailable =
            context != nil
                || isSmokeTrue(loadDiagnostics?.contextLoadedIntoController)
        let sameController =
            controller != nil
                && context?.webExtensionController === controller
                && isSmokeTrue(loadDiagnostics?.contextLoadedIntoController)
        let minimalPolicy = ChromeMV3MinimalInertFixturePolicy.evaluate(
            generatedRewrittenRootPath: rootPath,
            acceptedWebExtensionObjectAvailable: accepted,
            detachedContextCreated: detachedAvailable
        )
        let scenario = ChromeMV3RuntimeMinimalSmokeScenario(
            scenarioID: scenarioID,
            fixtureID:
                fixtureID
                    ?? "minimal-inert-fixture:\(candidate.id)",
            extensionID:
                objectAcceptanceReport?.generatedBundleID
                    ?? candidate.id,
            profileID:
                loadDiagnostics?
                .gateDecision
                .input
                .profileIdentifier
                    ?? "unknown-profile"
        )
        let gateInput = ChromeMV3RuntimeMinimalSmokeGateInput(
            scenario: scenario,
            generatedRewrittenRootPath: rootPath,
            extensionsModuleEnabled: extensionsModuleEnabled,
            explicitInternalSmokeHarnessAllowed:
                explicitInternalSmokeHarnessAllowed,
            explicitSyntheticWebViewCreationAllowed:
                explicitSyntheticWebViewCreationAllowed,
            syntheticNavigationRequested: false,
            acceptedWebExtensionObjectAvailable: accepted,
            detachedContextAvailable: detachedAvailable,
            loadedContextAvailable:
                isSmokeTrue(loadDiagnostics?.contextLoadedIntoController),
            sameControllerAvailable: sameController,
            minimalInertFixturePolicy: minimalPolicy,
            controllerLoadGateDecision:
                loadDiagnostics?.gateDecision,
            controllerLoadOwnerDiagnostics: loadDiagnostics,
            liveNormalTabAttachmentSnapshot:
                liveNormalTabAttachmentSnapshot,
            runtimeBridgeReadinessReport:
                runtimeBridgeReadinessReport,
            requestedProductRuntimeExposure: false,
            requestedExtensionCodeExecution: false,
            requestedUserScriptRegistration: false,
            requestedNativeMessagingLaunch: false,
            requestedServiceWorkerWake: false,
            requestedRuntimeDispatch: false,
            requestedStorageEventDispatch: false,
            requestedProductUI: false
        )
        let gateDecision = ChromeMV3RuntimeMinimalSmokeGate.evaluate(
            input: gateInput
        )

        guard gateDecision.canRunSmokeHarnessNow,
              let controller
        else {
            return ChromeMV3RuntimeMinimalSmokeReportGenerator
                .makeBlockedReport(gateDecision: gateDecision)
        }

        var syntheticConfiguration: WKWebViewConfiguration? =
            WKWebViewConfiguration()
        syntheticConfiguration?
            .sumiIsNormalTabWebViewConfiguration = false
        syntheticConfiguration?.webExtensionController = controller
        let configurationAttached =
            syntheticConfiguration?.webExtensionController === controller
        let configurationUserScriptCount =
            syntheticConfiguration?.userContentController.userScripts.count
                ?? 0
        let configurationIdentity =
            ChromeMV3RuntimeMinimalSmokeReportGenerator.identity(
                kind: "syntheticConfiguration",
                stableID:
                    "synthetic-configuration:\(scenario.scenarioID)",
                present: syntheticConfiguration != nil
            )
        let controllerIdentity =
            ChromeMV3RuntimeMinimalSmokeReportGenerator.identity(
                kind: "controller",
                stableID: "controller:\(scenario.profileID)",
                present: true
            )
        let contextIdentity =
            ChromeMV3RuntimeMinimalSmokeReportGenerator.identity(
                kind: "context",
                stableID:
                    "loaded-context:\(scenario.extensionID)",
                present: context != nil
            )
        let configurationResult =
            ChromeMV3RuntimeMinimalSmokeReportGenerator
            .configurationResult(
                gateDecision: gateDecision,
                configurationCreated: syntheticConfiguration != nil,
                configurationAttached: configurationAttached,
                controllerMatchesContext: sameController,
                userScriptCount: configurationUserScriptCount
            )

        var syntheticWebView: WKWebView?
        let webViewIdentity:
            ChromeMV3RuntimeMinimalSmokeIdentity?
        let webViewResult:
            ChromeMV3RuntimeMinimalSmokeWebViewResult
        if gateDecision.canCreateSyntheticWebViewNow,
           configurationAttached,
           let syntheticConfiguration
        {
            syntheticWebView = WKWebView(
                frame: .zero,
                configuration: syntheticConfiguration
            )
            let createdSameController =
                syntheticWebView?.configuration
                .webExtensionController === controller
            webViewIdentity =
                ChromeMV3RuntimeMinimalSmokeReportGenerator.identity(
                    kind: "syntheticWebView",
                    stableID:
                        "synthetic-webview:\(scenario.scenarioID)",
                    present: syntheticWebView != nil
                )
            webViewResult =
                ChromeMV3RuntimeMinimalSmokeReportGenerator
                .webViewResult(
                    state: .created,
                    identity: webViewIdentity,
                    created: syntheticWebView != nil,
                    sameController: createdSameController,
                    blockingReasons: [],
                    warnings: [
                        "Synthetic WKWebView was created without a window, tab registration, or navigation.",
                    ]
                )
        } else {
            webViewIdentity = nil
            webViewResult =
                ChromeMV3RuntimeMinimalSmokeReportGenerator
                .webViewResult(
                    state:
                        gateDecision
                        .canCreateSyntheticWebViewNow
                            ? .skipped
                            : .notRequested,
                    identity: nil,
                    created: false,
                    sameController: false,
                    blockingReasons:
                        gateDecision.canCreateSyntheticWebViewNow
                            ? []
                            : [
                                "Synthetic WKWebView creation requires a separate explicit DEBUG/internal smoke flag.",
                            ],
                    warnings: [
                        "No synthetic WKWebView was created for this smoke run.",
                    ]
                )
        }

        syntheticWebView = nil
        syntheticConfiguration?.webExtensionController = nil
        let attachedAfterTeardown =
            syntheticConfiguration?.webExtensionController != nil
        syntheticConfiguration = nil

        let loadTeardown: ChromeMV3ControllerLoadOwnerDiagnostics?
        let detachedReleased: Bool
        let controllerTornDown: Bool
        if tearDownLoadedContextAndControllerAfterRun {
            loadTeardown = controllerLoadOwner?.tearDown()
            let detachedDiagnostics = detachedContextOwner?.tearDown()
            let controllerDiagnostics = emptyControllerOwner?.tearDown(
                trigger: .explicitReset
            )
            detachedReleased =
                detachedDiagnostics?.state == .released
            controllerTornDown =
                controllerDiagnostics?.controllerState == .tornDown
        } else {
            loadTeardown = nil
            detachedReleased = false
            controllerTornDown = false
        }

        let teardownResult =
            ChromeMV3RuntimeMinimalSmokeReportGenerator
            .teardownResult(
                webViewCreated:
                    webViewResult.syntheticWebViewCreated,
                configurationCreated:
                    configurationResult.syntheticConfigurationCreated,
                syntheticConfigurationAttachedAfterTeardown:
                    attachedAfterTeardown,
                loadedOwnerDiagnostics: loadTeardown,
                detachedContextReleased: detachedReleased,
                controllerOwnerTornDown: controllerTornDown,
                diagnosticsResetForFutureRuns:
                    diagnosticsResetForFutureRuns
            )

        return ChromeMV3RuntimeMinimalSmokeReportGenerator.makeReport(
            gateDecision: gateDecision,
            controllerIdentity: controllerIdentity,
            contextIdentity: contextIdentity,
            syntheticConfigurationIdentity: configurationIdentity,
            syntheticWebViewIdentity: webViewIdentity,
            configurationResult: configurationResult,
            webViewResult: webViewResult,
            teardownResult: teardownResult
        )
    }
}
#endif

private extension ChromeMV3ControllerLoadGateDecision {
    func summaryLikeReportSummary()
        -> ChromeMV3ControllerLoadGateReportSummary
    {
        ChromeMV3ControllerLoadGateReportSummary(
            reportID: "controller-load-gate:\(input.candidateID)",
            reportFileName:
                ChromeMV3ControllerLoadGateReportWriter.reportFileName,
            candidateID: input.candidateID,
            minimalFixtureLoadSafe:
                input.minimalInertFixturePolicy
                .loadSafeForMinimalInertFixture,
            canLoadContextIntoControllerNow:
                canLoadContextIntoControllerNow,
            loadAttemptAllowed: loadAttemptAllowed,
            controllerLoadAttempted: false,
            contextLoadedIntoController: false,
            runtimeLoadable: false,
            chromeRuntimeAvailableNow: false,
            jsBridgeAvailableNow: false,
            canExecuteExtensionCodeNow: false
        )
    }
}

private func uniqueSorted<T: Hashable & Comparable>(_ values: [T]) -> [T] {
    Array(Set(values)).sorted()
}

private func uniqueSorted(_ values: [String]) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}

private func isSmokeTrue(_ value: Bool?) -> Bool {
    value ?? false
}

private func isSmokeTrue(_ value: Bool) -> Bool {
    value
}
