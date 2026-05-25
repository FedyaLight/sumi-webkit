//
//  ChromeMV3ContentScriptLocalFixtureRunner.swift
//  Sumi
//
//  DEBUG/internal loopback fixture runner for WebKit-owned MV3
//  content-script frame diagnostics. This is not product runtime support.
//

import CryptoKit
import Foundation
import Synchronization

enum ChromeMV3ContentScriptLocalFixtureRunnerOutcome:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case blocked
    case attempted
    case passed
    case unverified
    case failed
}

enum ChromeMV3ContentScriptLocalFixtureBlockedReason:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case extensionsModuleDisabled
    case explicitLocalFixtureRunnerNotAllowed
    case explicitLocalHTTPServerNotAllowed
    case explicitSyntheticWebViewCreationNotAllowed
    case explicitSyntheticNavigationNotAllowed
    case explicitTestDOMInspectionNotAllowed
    case acceptedExtensionObjectUnavailable
    case detachedContextMissing
    case contentScriptFixturePolicyFailed
    case controllerLoadGateMissing
    case controllerLoadGateBlocked
    case contextLoadUnavailable
    case sameControllerMissing
    case realNormalTabAttachmentObserved
    case runtimeDispatchAvailable
    case serviceWorkerWakeAvailable
    case nativeMessagingAvailable
    case jsBridgeExposed
    case productRuntimeExposureRequested
    case runtimeLoadabilityInvariantViolation
    case localHTTPFixtureServerUnavailable
    case syntheticWebViewUnavailable
    case syntheticNavigationFailed
    case unsafeObservationMechanism

    var reason: String {
        switch self {
        case .extensionsModuleDisabled:
            return "The extensions module is disabled."
        case .explicitLocalFixtureRunnerNotAllowed:
            return "Explicit DEBUG/internal local fixture runner mode is not enabled."
        case .explicitLocalHTTPServerNotAllowed:
            return "Explicit DEBUG/internal loopback HTTP fixture serving is not enabled."
        case .explicitSyntheticWebViewCreationNotAllowed:
            return "Synthetic WKWebView creation requires its explicit DEBUG/internal flag."
        case .explicitSyntheticNavigationNotAllowed:
            return "Synthetic fixture navigation requires its explicit DEBUG/internal flag."
        case .explicitTestDOMInspectionNotAllowed:
            return "One-pass testDOMInspection requires its explicit DEBUG/internal flag."
        case .acceptedExtensionObjectUnavailable:
            return "An accepted WKWebExtension object is not available."
        case .detachedContextMissing:
            return "A detached WKWebExtensionContext is not available."
        case .contentScriptFixturePolicyFailed:
            return "The DEBUG/internal content-script fixture policy did not pass."
        case .controllerLoadGateMissing:
            return "Controller-load gate diagnostics are missing."
        case .controllerLoadGateBlocked:
            return "Controller-load gate did not allow loading this fixture."
        case .contextLoadUnavailable:
            return "A loaded WKWebExtensionContext was not observed for the fixture."
        case .sameControllerMissing:
            return "The synthetic WKWebView configuration cannot use the same loaded controller."
        case .realNormalTabAttachmentObserved:
            return "A real normal-tab configuration attachment was observed."
        case .runtimeDispatchAvailable:
            return "Runtime message dispatch is available or requested, which is outside this runner."
        case .serviceWorkerWakeAvailable:
            return "Service-worker wake is available or requested, which is outside this runner."
        case .nativeMessagingAvailable:
            return "Native messaging is available or requested, which is outside this runner."
        case .jsBridgeExposed:
            return "The Sumi JavaScript bridge is exposed or injectable."
        case .productRuntimeExposureRequested:
            return "Product runtime exposure was requested."
        case .runtimeLoadabilityInvariantViolation:
            return "runtimeLoadable or product runtime availability invariants were violated."
        case .localHTTPFixtureServerUnavailable:
            return "The loopback HTTP fixture server could not be started safely."
        case .syntheticWebViewUnavailable:
            return "The synthetic WKWebView was not available for local fixture navigation."
        case .syntheticNavigationFailed:
            return "The synthetic WKWebView did not finish local fixture navigation."
        case .unsafeObservationMechanism:
            return "The remaining observation would require a forbidden Sumi injection, bridge, handler, or runtime dispatch path."
        }
    }
}

enum ChromeMV3ContentScriptLocalFixtureNextRecommendedAction:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case proceedToActionPopupHost
    case broadenManualWebKitVerification
    case blockedByContextLoadUnavailable
    case blockedByUnsafeObservationMechanism
}

struct ChromeMV3ContentScriptLocalFixtureRunnerID:
    Codable,
    Equatable,
    Sendable
{
    var rawValue: String
}

struct ChromeMV3ContentScriptLocalFixtureID:
    Codable,
    Equatable,
    Sendable
{
    var rawValue: String
}

struct ChromeMV3ContentScriptLocalOriginID:
    Codable,
    Equatable,
    Comparable,
    Sendable
{
    var rawValue: String

    static func < (
        lhs: ChromeMV3ContentScriptLocalOriginID,
        rhs: ChromeMV3ContentScriptLocalOriginID
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ContentScriptLocalOrigin:
    Codable,
    Equatable,
    Sendable
{
    var id: ChromeMV3ContentScriptLocalOriginID
    var scheme: String
    var host: String
    var port: UInt16
    var loopbackOnly: Bool

    var originString: String {
        "\(scheme)://\(host):\(port)"
    }
}

struct ChromeMV3ContentScriptLocalOriginModel:
    Codable,
    Equatable,
    Sendable
{
    var runnerID: ChromeMV3ContentScriptLocalFixtureRunnerID
    var sameOrigin: ChromeMV3ContentScriptLocalOrigin
    var crossOrigin: ChromeMV3ContentScriptLocalOrigin
    var manifestMatchPattern: String
    var portAllocationStrategy: String

    var topFrameURLString: String {
        sameOrigin.originString + "/top.html"
    }

    var sameOriginFrameURLString: String {
        sameOrigin.originString + "/same-frame.html"
    }

    var crossOriginFrameURLString: String {
        crossOrigin.originString + "/cross-frame.html"
    }

    static func make(
        runnerID: String,
        sameOriginPort: UInt16,
        crossOriginPort: UInt16
    ) -> ChromeMV3ContentScriptLocalOriginModel {
        ChromeMV3ContentScriptLocalOriginModel(
            runnerID:
                ChromeMV3ContentScriptLocalFixtureRunnerID(
                    rawValue: runnerID
                ),
            sameOrigin:
                ChromeMV3ContentScriptLocalOrigin(
                    id: ChromeMV3ContentScriptLocalOriginID(
                        rawValue: "same-origin-loopback"
                    ),
                    scheme: "http",
                    host: "127.0.0.1",
                    port: sameOriginPort,
                    loopbackOnly: true
                ),
            crossOrigin:
                ChromeMV3ContentScriptLocalOrigin(
                    id: ChromeMV3ContentScriptLocalOriginID(
                        rawValue: "cross-origin-loopback"
                    ),
                    scheme: "http",
                    host: "127.0.0.1",
                    port: crossOriginPort,
                    loopbackOnly: true
                ),
            manifestMatchPattern: "http://127.0.0.1/*",
            portAllocationStrategy:
                "deterministic preferred loopback ports with ephemeral fallback when occupied"
        )
    }

    static func preferredPorts(
        runnerID: String
    ) -> (sameOrigin: UInt16, crossOrigin: UInt16) {
        let digest = Array(SHA256.hash(data: Data(runnerID.utf8)))
        let same = 45_000 + UInt16(digest[0]) * 16 + UInt16(digest[1] % 16)
        let crossCandidate =
            45_000 + UInt16(digest[2]) * 16 + UInt16(digest[3] % 16)
        let cross = crossCandidate == same ? same + 1 : crossCandidate
        return (same, cross)
    }
}

struct ChromeMV3ContentScriptLocalFixtureFrameRoute:
    Codable,
    Equatable,
    Sendable
{
    var frameID: String
    var kind: ChromeMV3ContentScriptFrameKind
    var originID: ChromeMV3ContentScriptLocalOriginID?
    var path: String
    var urlString: String
    var parentURLString: String?
    var fixtureElementID: String?
    var responseKind: String
}

struct ChromeMV3ContentScriptLocalFixtureServingPlan:
    Codable,
    Equatable,
    Sendable
{
    var debugInternalOnly: Bool
    var loopbackOnly: Bool
    var externalNetworkUsed: Bool
    var productServer: Bool
    var recurringChecksUsed: Bool
    var userVisibleWindowRequired: Bool
    var productNormalTabRequired: Bool
    var routes: [ChromeMV3ContentScriptLocalFixtureFrameRoute]
}

enum ChromeMV3ContentScriptLocalFixtureRoutes {
    static func routes(
        originModel: ChromeMV3ContentScriptLocalOriginModel
    ) -> [ChromeMV3ContentScriptLocalFixtureFrameRoute] {
        [
            ChromeMV3ContentScriptLocalFixtureFrameRoute(
                frameID: "top",
                kind: .topFrame,
                originID: originModel.sameOrigin.id,
                path: "/top.html",
                urlString: originModel.topFrameURLString,
                parentURLString: nil,
                fixtureElementID: nil,
                responseKind: "topFramePage"
            ),
            ChromeMV3ContentScriptLocalFixtureFrameRoute(
                frameID: "same-origin",
                kind: .sameOriginIframe,
                originID: originModel.sameOrigin.id,
                path: "/same-frame.html",
                urlString: originModel.sameOriginFrameURLString,
                parentURLString: originModel.topFrameURLString,
                fixtureElementID: "same-origin-frame",
                responseKind: "sameOriginIframePage"
            ),
            ChromeMV3ContentScriptLocalFixtureFrameRoute(
                frameID: "cross-origin",
                kind: .crossOriginIframe,
                originID: originModel.crossOrigin.id,
                path: "/cross-frame.html",
                urlString: originModel.crossOriginFrameURLString,
                parentURLString: originModel.topFrameURLString,
                fixtureElementID: "cross-origin-frame",
                responseKind: "crossOriginIframePage"
            ),
            ChromeMV3ContentScriptLocalFixtureFrameRoute(
                frameID: "about-blank",
                kind: .aboutBlankIframe,
                originID: nil,
                path: "about:blank",
                urlString: "about:blank",
                parentURLString: originModel.topFrameURLString,
                fixtureElementID: "about-blank-frame",
                responseKind: "aboutBlankIframe"
            ),
            ChromeMV3ContentScriptLocalFixtureFrameRoute(
                frameID: "data",
                kind: .dataIframe,
                originID: nil,
                path: "data:text/html",
                urlString: "data:text/html,%3C!doctype%20html%3E",
                parentURLString: originModel.topFrameURLString,
                fixtureElementID: "data-frame",
                responseKind: "dataIframe"
            ),
            ChromeMV3ContentScriptLocalFixtureFrameRoute(
                frameID: "blob",
                kind: .blobIframe,
                originID: originModel.sameOrigin.id,
                path: "blob",
                urlString: "blob:\(originModel.sameOrigin.originString)/local-fixture",
                parentURLString: originModel.topFrameURLString,
                fixtureElementID: "blob-frame",
                responseKind: "blobIframe"
            ),
        ].sorted { $0.frameID < $1.frameID }
    }

    static func servingPlan(
        originModel: ChromeMV3ContentScriptLocalOriginModel
    ) -> ChromeMV3ContentScriptLocalFixtureServingPlan {
        ChromeMV3ContentScriptLocalFixtureServingPlan(
            debugInternalOnly: isDebugBuild,
            loopbackOnly:
                originModel.sameOrigin.loopbackOnly
                    && originModel.crossOrigin.loopbackOnly,
            externalNetworkUsed: false,
            productServer: false,
            recurringChecksUsed: false,
            userVisibleWindowRequired: false,
            productNormalTabRequired: false,
            routes: routes(originModel: originModel)
        )
    }

    private static var isDebugBuild: Bool {
#if DEBUG
        true
#else
        false
#endif
    }
}

struct ChromeMV3ContentScriptLocalFixturePrerequisiteState:
    Codable,
    Equatable,
    Sendable
{
    var acceptedWebExtensionObjectAvailable: Bool
    var detachedContextAvailable: Bool
    var controllerLoadGatePresent: Bool
    var controllerLoadGateAllowed: Bool
    var controllerLoadAttempted: Bool
    var contextLoadedIntoController: Bool
    var sameControllerAvailable: Bool
    var blockedByContextLoadUnavailable: Bool
    var webKitErrorMessage: String?
    var diagnostics: [String]
}

struct ChromeMV3ContentScriptLocalFixtureGateInput:
    Codable,
    Equatable,
    Sendable
{
    var runnerID: ChromeMV3ContentScriptLocalFixtureRunnerID
    var fixtureID: ChromeMV3ContentScriptLocalFixtureID
    var generatedRewrittenRootPath: String
    var extensionsModuleEnabled: Bool
    var explicitInternalLocalFixtureRunnerAllowed: Bool
    var explicitLocalHTTPServerAllowed: Bool
    var explicitSyntheticWebViewCreationAllowed: Bool
    var explicitSyntheticNavigationAllowed: Bool
    var explicitTestDOMInspectionAllowed: Bool
    var acceptedWebExtensionObjectAvailable: Bool
    var detachedContextAvailable: Bool
    var contentScriptFixturePolicy:
        ChromeMV3ContentScriptSmokeFixturePolicyResult
    var controllerLoadGateDecision:
        ChromeMV3ControllerLoadGateDecision?
    var controllerLoadOwnerDiagnostics:
        ChromeMV3ControllerLoadOwnerDiagnostics?
    var liveNormalTabAttachmentSnapshot:
        ChromeMV3LiveNormalTabAttachmentRecorderSnapshot?
    var runtimeBridgeReadinessReport:
        ChromeMV3RuntimeBridgeReadinessReport?
    var sameControllerAvailable: Bool
    var requestedProductRuntimeExposure: Bool
    var requestedUserScriptRegistration: Bool
    var requestedRuntimeDispatch: Bool
    var requestedServiceWorkerWake: Bool
    var requestedNativeMessagingLaunch: Bool
    var requestedProductUI: Bool
}

struct ChromeMV3ContentScriptLocalFixtureGateDecision:
    Codable,
    Equatable,
    Sendable
{
    var input: ChromeMV3ContentScriptLocalFixtureGateInput
    var canStartLocalFixtureRunnerNow: Bool
    var canStartLocalHTTPServerNow: Bool
    var canCreateSyntheticWebViewNow: Bool
    var canNavigateSyntheticWebViewNow: Bool
    var canInspectDOMNow: Bool
    var prerequisiteState:
        ChromeMV3ContentScriptLocalFixturePrerequisiteState
    var runtimeLoadable: Bool
    var chromeRuntimeAvailableNow: Bool
    var jsBridgeAvailableNow: Bool
    var productRuntimeExposed: Bool
    var blockers: [ChromeMV3ContentScriptLocalFixtureBlockedReason]
    var blockingReasons: [String]
    var warnings: [String]
}

enum ChromeMV3ContentScriptLocalFixtureGate {
    static func evaluate(
        input: ChromeMV3ContentScriptLocalFixtureGateInput
    ) -> ChromeMV3ContentScriptLocalFixtureGateDecision {
        var blockers: [ChromeMV3ContentScriptLocalFixtureBlockedReason] = []
        var warnings = input.contentScriptFixturePolicy.warnings

        if input.extensionsModuleEnabled == false {
            blockers.append(.extensionsModuleDisabled)
        }
        if input.explicitInternalLocalFixtureRunnerAllowed == false {
            blockers.append(.explicitLocalFixtureRunnerNotAllowed)
        }
        if input.explicitLocalHTTPServerAllowed == false {
            blockers.append(.explicitLocalHTTPServerNotAllowed)
        }
        if input.explicitSyntheticWebViewCreationAllowed == false {
            blockers.append(.explicitSyntheticWebViewCreationNotAllowed)
        }
        if input.explicitSyntheticNavigationAllowed == false {
            blockers.append(.explicitSyntheticNavigationNotAllowed)
        }
        if input.explicitTestDOMInspectionAllowed == false {
            blockers.append(.explicitTestDOMInspectionNotAllowed)
        }
        if input.acceptedWebExtensionObjectAvailable == false {
            blockers.append(.acceptedExtensionObjectUnavailable)
        }
        if input.detachedContextAvailable == false {
            blockers.append(.detachedContextMissing)
        }
        if input.contentScriptFixturePolicy
            .loadSafeForContentScriptSmokeFixture == false {
            blockers.append(.contentScriptFixturePolicyFailed)
        }
        if input.controllerLoadGateDecision == nil {
            blockers.append(.controllerLoadGateMissing)
        } else if input.controllerLoadGateDecision?.loadAttemptAllowed == false {
            blockers.append(.controllerLoadGateBlocked)
        }

        let contextLoaded =
            isSet(
                input.controllerLoadOwnerDiagnostics?
                    .contextLoadedIntoController
            )
        if contextLoaded == false {
            blockers.append(.contextLoadUnavailable)
        }
        if input.sameControllerAvailable == false {
            blockers.append(.sameControllerMissing)
        }

        let liveSnapshot = input.liveNormalTabAttachmentSnapshot
            ?? input.controllerLoadGateDecision?
            .input
            .liveNormalTabAttachmentSnapshot
        if (liveSnapshot?.attachedConfigurationCount ?? 0) > 0
            || (liveSnapshot?.createdAttachedWebViewCount ?? 0) > 0 {
            blockers.append(.realNormalTabAttachmentObserved)
        }

        let readiness = input.runtimeBridgeReadinessReport
        let jsBridge = readiness?.jsBridgeContractReportSummary
        if isSet(jsBridge?.jsBridgeAvailableNow)
            || isSet(jsBridge?.exposedToJSNow)
            || isSet(jsBridge?.canInjectScriptsNow) {
            blockers.append(.jsBridgeExposed)
        }
        if isSet(readiness?.messagingGate.dispatchImplemented)
            || input.requestedRuntimeDispatch {
            blockers.append(.runtimeDispatchAvailable)
        }
        if isSet(
            readiness?.serviceWorkerLifecycleGate
                .serviceWorkerWakeImplemented
        )
            || (input.controllerLoadOwnerDiagnostics?
                .serviceWorkerWakeCount ?? 0) > 0
            || input.requestedServiceWorkerWake {
            blockers.append(.serviceWorkerWakeAvailable)
        }
        if isSet(
            readiness?.nativeMessagingGate
                .nativeMessagingRuntimeImplemented
        )
            || isSet(readiness?.nativeMessagingGate.processLaunchImplemented)
            || (input.controllerLoadOwnerDiagnostics?
                .nativeMessagingPortCount ?? 0) > 0
            || input.requestedNativeMessagingLaunch {
            blockers.append(.nativeMessagingAvailable)
        }
        if input.requestedProductRuntimeExposure
            || input.requestedUserScriptRegistration
            || input.requestedProductUI {
            blockers.append(.productRuntimeExposureRequested)
        }
        if isSet(input.controllerLoadOwnerDiagnostics?.runtimeLoadable)
            || isSet(input.controllerLoadOwnerDiagnostics?
                .chromeRuntimeAvailableNow)
            || isSet(input.controllerLoadOwnerDiagnostics?
                .jsBridgeAvailableNow)
            || isSet(readiness?.runtimeLoadable)
            || isSet(input.controllerLoadGateDecision?.runtimeLoadable)
            || isSet(
                input.controllerLoadGateDecision?
                    .chromeRuntimeAvailableNow
            )
            || isSet(
                input.controllerLoadGateDecision?
                    .jsBridgeAvailableNow
            ) {
            blockers.append(.runtimeLoadabilityInvariantViolation)
        }

        warnings.append(
            "The local fixture runner is DEBUG/internal, loopback-only, and synthetic."
        )
        warnings.append(
            "Observed markers are reported as local WebKit fixture observations, not Chrome parity."
        )

        let uniqueBlockers = Array(Set(blockers)).sorted {
            $0.rawValue < $1.rawValue
        }
        let canRun = uniqueBlockers.isEmpty
        return ChromeMV3ContentScriptLocalFixtureGateDecision(
            input: input,
            canStartLocalFixtureRunnerNow: canRun,
            canStartLocalHTTPServerNow:
                canRun && input.explicitLocalHTTPServerAllowed,
            canCreateSyntheticWebViewNow:
                canRun && input.explicitSyntheticWebViewCreationAllowed,
            canNavigateSyntheticWebViewNow:
                canRun && input.explicitSyntheticNavigationAllowed,
            canInspectDOMNow:
                canRun && input.explicitTestDOMInspectionAllowed,
            prerequisiteState:
                prerequisiteState(input: input, contextLoaded: contextLoaded),
            runtimeLoadable: false,
            chromeRuntimeAvailableNow: false,
            jsBridgeAvailableNow: false,
            productRuntimeExposed: false,
            blockers: uniqueBlockers,
            blockingReasons:
                uniqueSorted(uniqueBlockers.map(\.reason)),
            warnings: uniqueSorted(warnings)
        )
    }

    private static func prerequisiteState(
        input: ChromeMV3ContentScriptLocalFixtureGateInput,
        contextLoaded: Bool
    ) -> ChromeMV3ContentScriptLocalFixturePrerequisiteState {
        let loadDiagnostics = input.controllerLoadOwnerDiagnostics
        return ChromeMV3ContentScriptLocalFixturePrerequisiteState(
            acceptedWebExtensionObjectAvailable:
                input.acceptedWebExtensionObjectAvailable,
            detachedContextAvailable: input.detachedContextAvailable,
            controllerLoadGatePresent:
                input.controllerLoadGateDecision != nil,
            controllerLoadGateAllowed:
                input.controllerLoadGateDecision?
                .loadAttemptAllowed == true,
            controllerLoadAttempted:
                loadDiagnostics?.controllerLoadAttempted ?? false,
            contextLoadedIntoController: contextLoaded,
            sameControllerAvailable: input.sameControllerAvailable,
            blockedByContextLoadUnavailable: contextLoaded == false,
            webKitErrorMessage:
                loadDiagnostics?.webKitError?.message,
            diagnostics: uniqueSorted(
                [
                    contextLoaded
                        ? "WKWebExtensionContext is loaded into the controller."
                        : "blockedByContextLoadUnavailable",
                    loadDiagnostics?.webKitError?.message,
                ].compactMap { $0 }
            )
        )
    }
}

struct ChromeMV3ContentScriptLocalFixtureSetupResult:
    Codable,
    Equatable,
    Sendable
{
    var attempted: Bool
    var serverStarted: Bool
    var loopbackOnly: Bool
    var externalNetworkUsed: Bool
    var sameOrigin: ChromeMV3ContentScriptLocalOrigin?
    var crossOrigin: ChromeMV3ContentScriptLocalOrigin?
    var servingPlan: ChromeMV3ContentScriptLocalFixtureServingPlan
    var blockedReason:
        ChromeMV3ContentScriptLocalFixtureBlockedReason?
    var diagnostics: [String]

    static func notAttempted(
        originModel: ChromeMV3ContentScriptLocalOriginModel,
        reason: ChromeMV3ContentScriptLocalFixtureBlockedReason?,
        diagnostics: [String]
    ) -> ChromeMV3ContentScriptLocalFixtureSetupResult {
        ChromeMV3ContentScriptLocalFixtureSetupResult(
            attempted: false,
            serverStarted: false,
            loopbackOnly: true,
            externalNetworkUsed: false,
            sameOrigin: originModel.sameOrigin,
            crossOrigin: originModel.crossOrigin,
            servingPlan:
                ChromeMV3ContentScriptLocalFixtureRoutes.servingPlan(
                    originModel: originModel
                ),
            blockedReason: reason,
            diagnostics: uniqueSorted(diagnostics)
        )
    }
}

struct ChromeMV3ContentScriptLocalFixtureFrameSnapshot:
    Codable,
    Equatable,
    Sendable
{
    var frameID: String
    var accessible: Bool
    var markerObserved: Bool
    var markerAttributeValue: String?
    var markerTokenValue: String?
    var executionReadyState: String?
    var pageWorldGlobalValue: String?
    var evaluationTarget: String
    var reason: String?
}

struct ChromeMV3ContentScriptLocalFixtureRunAtProof:
    Codable,
    Equatable,
    Sendable
{
    var runAt: String
    var observedAfterLoad: Bool
    var executionReadyState: String?
    var exactRunAtTimingObserved: Bool
    var proofLevel: String
    var reason: String

    static func classify(
        runAt: String,
        snapshot: ChromeMV3ContentScriptLocalFixtureFrameSnapshot?
    ) -> ChromeMV3ContentScriptLocalFixtureRunAtProof {
        let observed = snapshot?.markerObserved == true
        let readyState = snapshot?.executionReadyState
        let exact: Bool
        switch runAt {
        case "document_start":
            exact = readyState == "loading"
        case "document_end":
            exact = readyState == "interactive"
        case "document_idle":
            exact = readyState == "complete"
        default:
            exact = false
        }
        return ChromeMV3ContentScriptLocalFixtureRunAtProof(
            runAt: runAt,
            observedAfterLoad: observed,
            executionReadyState: readyState,
            exactRunAtTimingObserved: exact,
            proofLevel:
                exact
                    ? "readyStateAtExecution"
                    : (observed ? "observedAfterLoadOnly" : "unverified"),
            reason:
                exact
                    ? "The marker captured document.readyState=\(readyState ?? "unknown") during WebKit-owned content-script execution."
                    : "The runner records observed-after-load marker state and does not claim exact run_at scheduling without a matching readyState-at-execution marker."
        )
    }
}

struct ChromeMV3ContentScriptLocalFixtureWorldProof:
    Codable,
    Equatable,
    Sendable
{
    var declaredWorld: String?
    var effectiveWorld: String
    var pageVisibleMarkerObserved: Bool
    var pageWorldGlobalValueObserved: Bool
    var exactWorldExecutionVerified: Bool
    var proofLevel: String
    var reason: String

    static func classify(
        declaredWorld: String?,
        snapshot: ChromeMV3ContentScriptLocalFixtureFrameSnapshot?
    ) -> ChromeMV3ContentScriptLocalFixtureWorldProof {
        let effective = declaredWorld ?? "ISOLATED"
        let markerObserved = snapshot?.markerObserved == true
        let globalObserved =
            (snapshot?.pageWorldGlobalValue?.isEmpty == false)
        let exact: Bool
        if effective == "MAIN" {
            exact = markerObserved && globalObserved
        } else if effective == "ISOLATED" {
            exact = markerObserved && globalObserved == false
        } else {
            exact = false
        }
        return ChromeMV3ContentScriptLocalFixtureWorldProof(
            declaredWorld: declaredWorld,
            effectiveWorld: effective,
            pageVisibleMarkerObserved: markerObserved,
            pageWorldGlobalValueObserved: globalObserved,
            exactWorldExecutionVerified: exact,
            proofLevel:
                exact
                    ? "pageWorldGlobalProbe"
                    : (markerObserved ? "pageVisibleDOMOnly" : "unverified"),
            reason:
                exact
                    ? "The page-world global probe is consistent with \(effective) world while the DOM marker is visible."
                    : "A page-visible DOM marker alone does not prove the exact content world."
        )
    }
}

struct ChromeMV3ContentScriptLocalFixtureMatrixCase:
    Codable,
    Equatable,
    Sendable
{
    var caseID: String
    var runnerID: ChromeMV3ContentScriptLocalFixtureRunnerID
    var fixtureID: ChromeMV3ContentScriptLocalFixtureID
    var route: ChromeMV3ContentScriptLocalFixtureFrameRoute
    var manifestContentScriptMetadata:
        ChromeMV3ContentScriptSmokeManifestContentScriptMetadata
    var manifestMatchPatterns: [String]
    var expectedEligibility: ChromeMV3ContentScriptFrameExpectation
    var expectedReason: String
    var actualObservation:
        ChromeMV3ContentScriptFrameMarkerObservationState
    var markerAttributeValue: String?
    var markerTokenValue: String?
    var observationStrategy: ChromeMV3ContentScriptObservationStrategy
    var observationReason: String
    var blockedReason:
        ChromeMV3ContentScriptLocalFixtureBlockedReason?
    var diagnostics: [String]
    var runAtProof: ChromeMV3ContentScriptLocalFixtureRunAtProof
    var worldProof: ChromeMV3ContentScriptLocalFixtureWorldProof
    var webKitUncertaintyNotes: [String]
}

enum ChromeMV3ContentScriptLocalFixtureMatrix {
    static func makeCases(
        runnerID: ChromeMV3ContentScriptLocalFixtureRunnerID,
        fixtureID: ChromeMV3ContentScriptLocalFixtureID,
        originModel: ChromeMV3ContentScriptLocalOriginModel,
        manifestSummary: ChromeMV3ContentScriptSmokeManifestSummary,
        snapshots:
            [String: ChromeMV3ContentScriptLocalFixtureFrameSnapshot] = [:],
        blockedReason:
            ChromeMV3ContentScriptLocalFixtureBlockedReason? = nil,
        observationStrategy: ChromeMV3ContentScriptObservationStrategy
    ) -> [ChromeMV3ContentScriptLocalFixtureMatrixCase] {
        let routes = ChromeMV3ContentScriptLocalFixtureRoutes.routes(
            originModel: originModel
        )
        let metadata = manifestSummary.contentScriptMetadata.isEmpty
            ? [fallbackMetadata(manifestSummary)]
            : manifestSummary.contentScriptMetadata
        return metadata.flatMap { script in
            routes.map { route in
                makeCase(
                    runnerID: runnerID,
                    fixtureID: fixtureID,
                    route: route,
                    metadata: script,
                    snapshots: snapshots,
                    blockedReason: blockedReason,
                    observationStrategy: observationStrategy
                )
            }
        }.sorted { $0.caseID < $1.caseID }
    }

    private static func makeCase(
        runnerID: ChromeMV3ContentScriptLocalFixtureRunnerID,
        fixtureID: ChromeMV3ContentScriptLocalFixtureID,
        route: ChromeMV3ContentScriptLocalFixtureFrameRoute,
        metadata:
            ChromeMV3ContentScriptSmokeManifestContentScriptMetadata,
        snapshots:
            [String: ChromeMV3ContentScriptLocalFixtureFrameSnapshot],
        blockedReason:
            ChromeMV3ContentScriptLocalFixtureBlockedReason?,
        observationStrategy: ChromeMV3ContentScriptObservationStrategy
    ) -> ChromeMV3ContentScriptLocalFixtureMatrixCase {
        let eligibility = expectedEligibility(route: route, metadata: metadata)
        let snapshot = snapshots[route.frameID]
        let actual = actualObservation(
            expected: eligibility.expected,
            snapshot: snapshot,
            blockedReason: blockedReason
        )
        let reason = observationReason(
            expected: eligibility.expected,
            snapshot: snapshot,
            blockedReason: blockedReason,
            expectedReason: eligibility.reason
        )
        return ChromeMV3ContentScriptLocalFixtureMatrixCase(
            caseID:
                "script-\(metadata.contentScriptIndex)-\(route.frameID)",
            runnerID: runnerID,
            fixtureID: fixtureID,
            route: route,
            manifestContentScriptMetadata: metadata,
            manifestMatchPatterns: metadata.matchPatterns,
            expectedEligibility: eligibility.expected,
            expectedReason: eligibility.reason,
            actualObservation: actual,
            markerAttributeValue: snapshot?.markerAttributeValue,
            markerTokenValue: snapshot?.markerTokenValue,
            observationStrategy: observationStrategy,
            observationReason: reason,
            blockedReason: blockedReason,
            diagnostics:
                uniqueSorted(
                    [
                        snapshot?.reason,
                        blockedReason?.reason,
                    ].compactMap { $0 }
                ),
            runAtProof:
                ChromeMV3ContentScriptLocalFixtureRunAtProof.classify(
                    runAt: metadata.runAt,
                    snapshot: snapshot
                ),
            worldProof:
                ChromeMV3ContentScriptLocalFixtureWorldProof.classify(
                    declaredWorld: metadata.world,
                    snapshot: snapshot
                ),
            webKitUncertaintyNotes:
                uncertaintyNotes(
                    route: route,
                    actual: actual,
                    blockedReason: blockedReason
                )
        )
    }

    private static func expectedEligibility(
        route: ChromeMV3ContentScriptLocalFixtureFrameRoute,
        metadata:
            ChromeMV3ContentScriptSmokeManifestContentScriptMetadata
    ) -> (
        expected: ChromeMV3ContentScriptFrameExpectation,
        reason: String
    ) {
        let directMatch = metadata.matchPatterns.contains {
            ChromeMV3ContentScriptFrameMatrix.matches(
                pattern: $0,
                urlString: route.urlString
            )
        }
        let parentMatch = route.parentURLString.map { parent in
            metadata.matchPatterns.contains {
                ChromeMV3ContentScriptFrameMatrix.matches(
                    pattern: $0,
                    urlString: parent
                )
            }
        } ?? false
        switch route.kind {
        case .topFrame:
            return directMatch
                ? (.eligible, "Top frame URL matches the manifest pattern.")
                : (.blocked, "Top frame URL does not match the manifest pattern.")
        case .sameOriginIframe:
            return metadata.allFrames && directMatch
                ? (.eligible, "all_frames is true and the same-origin iframe URL matches.")
                : (.blocked, "Same-origin iframe requires all_frames plus a direct URL match.")
        case .crossOriginIframe:
            return metadata.allFrames && directMatch
                ? (.eligible, "all_frames is true and the cross-origin iframe URL matches.")
                : (.blocked, "Cross-origin iframe requires all_frames plus a direct URL match.")
        case .aboutBlankIframe:
            if metadata.allFrames
                && metadata.matchOriginAsFallback
                && parentMatch {
                return (
                    .eligible,
                    "match_origin_as_fallback is true and the initiator parent frame matches."
                )
            }
            if metadata.allFrames && metadata.matchAboutBlank && parentMatch {
                return (
                    .eligible,
                    "match_about_blank is true and the parent frame matches."
                )
            }
            return (
                .blocked,
                "about:blank requires all_frames plus match_about_blank or match_origin_as_fallback with a matching parent frame."
            )
        case .dataIframe:
            return metadata.allFrames
                && metadata.matchOriginAsFallback
                && parentMatch
                ? (
                    .eligible,
                    "data: frame eligibility uses match_origin_as_fallback and the matching initiator origin."
                )
                : (
                    .blocked,
                    "Opaque data: frames require all_frames, match_origin_as_fallback, and a matching initiator origin."
                )
        case .blobIframe:
            return metadata.allFrames
                && metadata.matchOriginAsFallback
                && parentMatch
                ? (
                    .eligible,
                    "blob: frame eligibility uses match_origin_as_fallback and the matching initiator origin."
                )
                : (
                    .blocked,
                    "blob: frames require all_frames, match_origin_as_fallback, and a matching initiator origin."
                )
        }
    }

    private static func actualObservation(
        expected: ChromeMV3ContentScriptFrameExpectation,
        snapshot: ChromeMV3ContentScriptLocalFixtureFrameSnapshot?,
        blockedReason:
            ChromeMV3ContentScriptLocalFixtureBlockedReason?
    ) -> ChromeMV3ContentScriptFrameMarkerObservationState {
        if expected == .blocked {
            return .blocked
        }
        if blockedReason != nil {
            return .blocked
        }
        if snapshot?.markerObserved == true {
            return .observed
        }
        if snapshot?.accessible == true {
            return .notObserved
        }
        return .unverified
    }

    private static func observationReason(
        expected: ChromeMV3ContentScriptFrameExpectation,
        snapshot: ChromeMV3ContentScriptLocalFixtureFrameSnapshot?,
        blockedReason:
            ChromeMV3ContentScriptLocalFixtureBlockedReason?,
        expectedReason: String
    ) -> String {
        if expected == .blocked {
            return expectedReason
        }
        if let blockedReason {
            return blockedReason.reason
        }
        if snapshot?.markerObserved == true {
            return "The WebKit-owned content-script DOM marker was observed in this local fixture frame."
        }
        if snapshot?.accessible == true {
            return "The frame was inspected, but the WebKit-owned content-script DOM marker was absent."
        }
        return snapshot?.reason
            ?? "No frame snapshot was available from one-pass testDOMInspection."
    }

    private static func uncertaintyNotes(
        route: ChromeMV3ContentScriptLocalFixtureFrameRoute,
        actual: ChromeMV3ContentScriptFrameMarkerObservationState,
        blockedReason:
            ChromeMV3ContentScriptLocalFixtureBlockedReason?
    ) -> [String] {
        var notes = [
            "Observed means observed in the local WebKit fixture runner, not Chrome parity.",
        ]
        if route.kind == .crossOriginIframe {
            notes.append(
                "Cross-origin internals are read only through frame-targeted WKWebView evaluation in the synthetic WebView."
            )
        }
        if route.kind == .dataIframe {
            notes.append(
                "Opaque data-frame internals require a captured WKFrameInfo; otherwise the case stays unverified."
            )
        }
        if blockedReason == .contextLoadUnavailable {
            notes.append(
                "The case was blocked before local HTTP serving because context load was unavailable."
            )
        }
        if actual != .observed {
            notes.append(
                "No Sumi-owned injection, JS bridge, message handler, runtime dispatch, native port, or product tab path is used to force observation."
            )
        }
        return uniqueSorted(notes)
    }

    private static func fallbackMetadata(
        _ manifestSummary: ChromeMV3ContentScriptSmokeManifestSummary
    ) -> ChromeMV3ContentScriptSmokeManifestContentScriptMetadata {
        ChromeMV3ContentScriptSmokeManifestContentScriptMetadata(
            contentScriptIndex: 0,
            jsPaths: manifestSummary.jsPaths,
            cssPaths: manifestSummary.cssPaths,
            matchPatterns: manifestSummary.matchPatterns,
            excludeMatchPatterns: manifestSummary.excludeMatchPatterns,
            includeGlobs: manifestSummary.includeGlobs,
            excludeGlobs: manifestSummary.excludeGlobs,
            allFrames: manifestSummary.allFramesValues.contains(true),
            matchAboutBlank:
                manifestSummary.matchAboutBlankValues.contains(true),
            matchOriginAsFallback:
                manifestSummary.matchOriginAsFallbackValues.contains(true),
            runAt: manifestSummary.runAtValues.first ?? "document_idle",
            world: manifestSummary.worldValues.first
        )
    }
}

struct ChromeMV3ContentScriptLocalFixtureRunnerReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var outcome: ChromeMV3ContentScriptLocalFixtureRunnerOutcome
    var runnerID: String
    var fixtureID: String
    var serverStarted: Bool
    var contextLoadedIntoController: Bool
    var blockedByContextLoadUnavailable: Bool
    var attemptedCaseIDs: [String]
    var observedCaseIDs: [String]
    var blockedCaseIDs: [String]
    var unverifiedCaseIDs: [String]
    var nextRecommendedAction:
        ChromeMV3ContentScriptLocalFixtureNextRecommendedAction
    var runtimeLoadable: Bool
    var chromeRuntimeAvailableNow: Bool
    var jsBridgeAvailableNow: Bool
    var productRuntimeExposed: Bool
}

struct ChromeMV3ContentScriptLocalFixtureRunnerReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var candidateID: String
    var generatedRewrittenRootPath: String
    var originModel: ChromeMV3ContentScriptLocalOriginModel
    var localFixtureSetupResult:
        ChromeMV3ContentScriptLocalFixtureSetupResult
    var gateDecision: ChromeMV3ContentScriptLocalFixtureGateDecision
    var prerequisiteState:
        ChromeMV3ContentScriptLocalFixturePrerequisiteState
    var matrixCases: [ChromeMV3ContentScriptLocalFixtureMatrixCase]
    var observationStrategy: ChromeMV3ContentScriptObservationStrategy
    var testDOMInspection:
        ChromeMV3ContentScriptTestDOMInspectionSummary
    var navigationCompletionState: String
    var expectedEligibleCaseIDs: [String]
    var observedCaseIDs: [String]
    var blockedCaseIDs: [String]
    var unverifiedCaseIDs: [String]
    var runAtProofLevel: String
    var worldProofLevel: String
    var sideEffectCounters:
        ChromeMV3ContentScriptSmokeRuntimeCounters
    var nextRecommendedAction:
        ChromeMV3ContentScriptLocalFixtureNextRecommendedAction
    var chromeRuntimeAvailableNow: Bool
    var jsBridgeAvailableNow: Bool
    var runtimeLoadable: Bool
    var productRuntimeExposed: Bool
    var whyRuntimeLoadableRemainsFalse: [String]
    var documentationSources:
        [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    var warnings: [String]

    var summary: ChromeMV3ContentScriptLocalFixtureRunnerReportSummary {
        ChromeMV3ContentScriptLocalFixtureRunnerReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            outcome: outcome,
            runnerID: originModel.runnerID.rawValue,
            fixtureID: gateDecision.input.fixtureID.rawValue,
            serverStarted: localFixtureSetupResult.serverStarted,
            contextLoadedIntoController:
                prerequisiteState.contextLoadedIntoController,
            blockedByContextLoadUnavailable:
                prerequisiteState.blockedByContextLoadUnavailable,
            attemptedCaseIDs:
                matrixCases
                .filter { $0.blockedReason == nil }
                .map(\.caseID),
            observedCaseIDs: observedCaseIDs,
            blockedCaseIDs: blockedCaseIDs,
            unverifiedCaseIDs: unverifiedCaseIDs,
            nextRecommendedAction: nextRecommendedAction,
            runtimeLoadable: false,
            chromeRuntimeAvailableNow: false,
            jsBridgeAvailableNow: false,
            productRuntimeExposed: false
        )
    }

    private var outcome: ChromeMV3ContentScriptLocalFixtureRunnerOutcome {
        if gateDecision.canStartLocalFixtureRunnerNow == false {
            return .blocked
        }
        if observedCaseIDs.isEmpty == false,
           unverifiedCaseIDs.isEmpty,
           matrixCases.contains(where: {
               $0.expectedEligibility == .eligible
                   && $0.actualObservation == .notObserved
           }) == false {
            return .passed
        }
        if matrixCases.contains(where: {
            $0.expectedEligibility == .eligible
                && $0.actualObservation == .notObserved
        }) {
            return .failed
        }
        return localFixtureSetupResult.serverStarted ? .unverified : .blocked
    }
}

enum ChromeMV3ContentScriptLocalFixtureRunnerReportWriter {
    static let reportFileName =
        "runtime-content-script-local-fixture-runner-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3ContentScriptLocalFixtureRunnerReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3ContentScriptLocalFixtureRunnerReport {
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

enum ChromeMV3ContentScriptLocalFixtureRunnerReportGenerator {
    static func makeReport(
        candidate: ChromeMV3RewrittenVariantCandidate,
        originModel: ChromeMV3ContentScriptLocalOriginModel,
        setupResult: ChromeMV3ContentScriptLocalFixtureSetupResult,
        gateDecision: ChromeMV3ContentScriptLocalFixtureGateDecision,
        matrixCases: [ChromeMV3ContentScriptLocalFixtureMatrixCase],
        observationStrategy: ChromeMV3ContentScriptObservationStrategy,
        testDOMInspection:
            ChromeMV3ContentScriptTestDOMInspectionSummary,
        navigationCompletionState: String
    ) -> ChromeMV3ContentScriptLocalFixtureRunnerReport {
        let observed = matrixCases
            .filter { $0.actualObservation == .observed }
            .map(\.caseID)
        let blocked = matrixCases
            .filter { $0.actualObservation == .blocked }
            .map(\.caseID)
        let unverified = matrixCases
            .filter { $0.actualObservation == .unverified }
            .map(\.caseID)
        let expectedEligible = matrixCases
            .filter { $0.expectedEligibility == .eligible }
            .map(\.caseID)
        let nextAction = nextRecommendedAction(
            gateDecision: gateDecision,
            setupResult: setupResult,
            matrixCases: matrixCases
        )
        return ChromeMV3ContentScriptLocalFixtureRunnerReport(
            schemaVersion: 1,
            id: reportID(
                runnerID: gateDecision.input.runnerID.rawValue,
                fixtureID: gateDecision.input.fixtureID.rawValue,
                rootPath: gateDecision.input.generatedRewrittenRootPath,
                serverStarted: setupResult.serverStarted,
                contextLoaded:
                    gateDecision
                    .prerequisiteState
                    .contextLoadedIntoController,
                observed: observed,
                blocked: blocked,
                unverified: unverified
            ),
            reportFileName:
                ChromeMV3ContentScriptLocalFixtureRunnerReportWriter
                .reportFileName,
            candidateID: candidate.id,
            generatedRewrittenRootPath:
                gateDecision.input.generatedRewrittenRootPath,
            originModel: originModel,
            localFixtureSetupResult: setupResult,
            gateDecision: gateDecision,
            prerequisiteState: gateDecision.prerequisiteState,
            matrixCases: matrixCases,
            observationStrategy: observationStrategy,
            testDOMInspection: testDOMInspection,
            navigationCompletionState: navigationCompletionState,
            expectedEligibleCaseIDs: expectedEligible,
            observedCaseIDs: observed,
            blockedCaseIDs: blocked,
            unverifiedCaseIDs: unverified,
            runAtProofLevel:
                aggregateRunAtProofLevel(matrixCases),
            worldProofLevel:
                aggregateWorldProofLevel(matrixCases),
            sideEffectCounters:
                .zero(
                    syntheticConfigurationAttached:
                        setupResult.serverStarted,
                    syntheticWebViewCreated:
                        setupResult.serverStarted,
                    syntheticNavigationAttempted:
                        navigationCompletionState != "notStarted"
                ),
            nextRecommendedAction: nextAction,
            chromeRuntimeAvailableNow: false,
            jsBridgeAvailableNow: false,
            runtimeLoadable: false,
            productRuntimeExposed: false,
            whyRuntimeLoadableRemainsFalse: [
                "This is a DEBUG/internal local WebKit fixture runner, not product runtime support.",
                "The runner uses loopback-only synthetic fixtures and synthetic WKWebViews only.",
                "No Sumi user script, add-user-script path, script handler, JS bridge, runtime message dispatch, runtime port, native messaging port, native process launch, product UI, or normal-tab attachment is used.",
                "runtimeLoadable, chromeRuntimeAvailableNow, jsBridgeAvailableNow, and productRuntimeExposed remain false by invariant.",
            ],
            documentationSources: documentationSources(),
            warnings:
                uniqueSorted(
                    gateDecision.warnings
                        + setupResult.diagnostics
                        + matrixCases.flatMap(\.webKitUncertaintyNotes)
                )
        )
    }

    private static func reportID(
        runnerID: String,
        fixtureID: String,
        rootPath: String,
        serverStarted: Bool,
        contextLoaded: Bool,
        observed: [String],
        blocked: [String],
        unverified: [String]
    ) -> String {
        let input = [
            runnerID,
            fixtureID,
            rootPath,
            String(serverStarted),
            String(contextLoaded),
            observed.sorted().joined(separator: ","),
            blocked.sorted().joined(separator: ","),
            unverified.sorted().joined(separator: ","),
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func nextRecommendedAction(
        gateDecision: ChromeMV3ContentScriptLocalFixtureGateDecision,
        setupResult: ChromeMV3ContentScriptLocalFixtureSetupResult,
        matrixCases: [ChromeMV3ContentScriptLocalFixtureMatrixCase]
    ) -> ChromeMV3ContentScriptLocalFixtureNextRecommendedAction {
        if gateDecision.prerequisiteState.blockedByContextLoadUnavailable {
            return .blockedByContextLoadUnavailable
        }
        if gateDecision.canStartLocalFixtureRunnerNow == false
            || setupResult.serverStarted == false {
            return .blockedByUnsafeObservationMechanism
        }
        let eligible = matrixCases.filter {
            $0.expectedEligibility == .eligible
        }
        if eligible.isEmpty == false,
           eligible.allSatisfy({ $0.actualObservation == .observed }),
           matrixCases.allSatisfy({
               $0.worldProof.exactWorldExecutionVerified
                   || $0.worldProof.pageVisibleMarkerObserved == false
                   || $0.expectedEligibility == .blocked
           }) {
            return .proceedToActionPopupHost
        }
        return .broadenManualWebKitVerification
    }

    private static func aggregateRunAtProofLevel(
        _ cases: [ChromeMV3ContentScriptLocalFixtureMatrixCase]
    ) -> String {
        if cases.contains(where: { $0.runAtProof.exactRunAtTimingObserved }) {
            return "someExactReadyStateProof"
        }
        if cases.contains(where: { $0.runAtProof.observedAfterLoad }) {
            return "observedAfterLoadOnly"
        }
        return "unverified"
    }

    private static func aggregateWorldProofLevel(
        _ cases: [ChromeMV3ContentScriptLocalFixtureMatrixCase]
    ) -> String {
        if cases.contains(where: { $0.worldProof.exactWorldExecutionVerified }) {
            return "somePageWorldGlobalProof"
        }
        if cases.contains(where: { $0.worldProof.pageVisibleMarkerObserved }) {
            return "pageVisibleDOMOnly"
        }
        return "unverified"
    }

    private static func documentationSources()
        -> [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    {
        [
            source(
                kind: "chromeDocumentation",
                title: "Manifest content scripts",
                url: "https://developer.chrome.com/docs/extensions/reference/manifest/content-scripts",
                note: "Used for content_scripts, matches, all_frames, match_about_blank, match_origin_as_fallback, run_at, and world matrix fields."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Content scripts",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts",
                note: "Used for DOM access, frame, and MAIN/ISOLATED world semantics."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebView.evaluateJavaScript",
                url: "https://developer.apple.com/documentation/webkit/wkwebview/evaluatejavascript%28_%3Acompletionhandler%3A%29",
                note: "Used for one-pass testDOMInspection only."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKNavigationDelegate",
                url: "https://developer.apple.com/documentation/webkit/wknavigationdelegate",
                note: "Used to wait for synthetic fixture navigation completion and capture frame metadata."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebViewConfiguration.webExtensionController",
                url: "https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/webextensioncontroller",
                note: "Used only on same-controller synthetic WKWebViewConfiguration."
            ),
            source(
                kind: "localAppleSDKHeaders",
                title: "MacOSX26.5 WebKit headers",
                url: nil,
                note: "Headers confirm page-world evaluation defaults, content-world DOM visibility, controller load behavior, and same-controller WebView requirements."
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
@preconcurrency import Network
import WebKit

@available(macOS 15.5, *)
@MainActor
private final class ChromeMV3ContentScriptLocalFixtureNavigationObserver:
    NSObject,
    WKNavigationDelegate
{
    private var awaitedNavigation: WKNavigation?
    private var completion:
        ChromeMV3ContentScriptSmokeNavigationCompletion?
    private var continuation:
        CheckedContinuation<
            ChromeMV3ContentScriptSmokeNavigationCompletion,
            Never
        >?
    private var frameInfos: [String: WKFrameInfo] = [:]

    func waitForCompletion(
        navigation: WKNavigation?
    ) async -> ChromeMV3ContentScriptSmokeNavigationCompletion {
        guard let navigation else {
            return .notStarted
        }
        awaitedNavigation = navigation
        if let completion {
            return completion
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func frameInfo(frameID: String) -> WKFrameInfo? {
        frameInfos[frameID]
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler:
            @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        _ = webView
        captureFrameInfo(from: navigationAction)
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        _ = webView
        guard isAwaited(navigation) else { return }
        finish(
            ChromeMV3ContentScriptSmokeNavigationCompletion(
                state: .finished,
                errorDescription: nil
            )
        )
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        _ = webView
        guard isAwaited(navigation) else { return }
        finish(
            ChromeMV3ContentScriptSmokeNavigationCompletion(
                state: .failed,
                errorDescription: error.localizedDescription
            )
        )
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        _ = webView
        guard isAwaited(navigation) else { return }
        finish(
            ChromeMV3ContentScriptSmokeNavigationCompletion(
                state: .failed,
                errorDescription: error.localizedDescription
            )
        )
    }

    private func captureFrameInfo(
        from action: WKNavigationAction
    ) {
        guard let frame = action.targetFrame,
              let url = action.request.url,
              let frameID = frameID(for: url, isMainFrame: frame.isMainFrame)
        else { return }
        frameInfos[frameID] = frame
    }

    private func frameID(for url: URL, isMainFrame: Bool) -> String? {
        if isMainFrame {
            return "top"
        }
        switch url.scheme {
        case "http":
            if url.path == "/same-frame.html" {
                return "same-origin"
            }
            if url.path == "/cross-frame.html" {
                return "cross-origin"
            }
        case "about":
            return "about-blank"
        case "data":
            return "data"
        case "blob":
            return "blob"
        default:
            return nil
        }
        return nil
    }

    private func isAwaited(_ navigation: WKNavigation?) -> Bool {
        guard let awaitedNavigation else {
            return true
        }
        return navigation === awaitedNavigation
    }

    private func finish(
        _ completion:
            ChromeMV3ContentScriptSmokeNavigationCompletion
    ) {
        guard self.completion == nil else { return }
        self.completion = completion
        continuation?.resume(returning: completion)
        continuation = nil
    }
}

@available(macOS 15.5, *)
private final class ChromeMV3LocalHTTPRouteStore: Sendable {
    private let routes = Mutex<[String: String]>([:])

    func update(_ values: [String: String]) {
        routes.withLock { current in
            current = values
        }
    }

    func body(for path: String) -> String? {
        routes.withLock { current in
            current[path]
        }
    }
}

@available(macOS 15.5, *)
private final class ChromeMV3LocalHTTPOriginServer {
    private let listener: NWListener
    private let queue: DispatchQueue
    private let routeStore = ChromeMV3LocalHTTPRouteStore()

    var port: UInt16 {
        listener.port.map { UInt16($0.rawValue) } ?? 0
    }

    init(preferredPort: UInt16, queueLabel: String) throws {
        queue = DispatchQueue(label: queueLabel)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint =
            NWEndpoint.hostPort(
                host: .ipv4(IPv4Address("127.0.0.1")!),
                port: NWEndpoint.Port(rawValue: preferredPort) ?? .any
            )
        listener = try NWListener(using: parameters)
    }

    convenience init(queueLabel: String) throws {
        try self.init(preferredPort: 0, queueLabel: queueLabel)
    }

    func update(routes: [String: String]) {
        routeStore.update(routes)
    }

    func start() async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            let didResume = Mutex(false)
            let routeStore = self.routeStore
            let queue = self.queue
            listener.newConnectionHandler = { connection in
                Self.handle(
                    connection: connection,
                    routeStore: routeStore,
                    queue: queue
                )
            }
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard didResume.withLock({
                        if $0 { return false }
                        $0 = true
                        return true
                    }) else { return }
                    continuation.resume(returning: ())
                case .failed(let error):
                    guard didResume.withLock({
                        if $0 { return false }
                        $0 = true
                        return true
                    }) else { return }
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
    }

    private static func handle(
        connection: NWConnection,
        routeStore: ChromeMV3LocalHTTPRouteStore,
        queue: DispatchQueue
    ) {
        connection.start(queue: queue)
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 8192
        ) { data, _, _, _ in
            Self.respond(
                to: connection,
                data: data,
                routeStore: routeStore
            )
        }
    }

    private static func respond(
        to connection: NWConnection,
        data: Data?,
        routeStore: ChromeMV3LocalHTTPRouteStore
    ) {
        let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let path = Self.requestPath(request)
        let routedBody = routeStore.body(for: path)
        let body = routedBody ?? Self.notFoundHTML(path: path)
        let status = routedBody == nil ? "404 Not Found" : "200 OK"
        let bodyData = Data(body.utf8)
        let header = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(bodyData.count)\r
        Cache-Control: no-store\r
        Connection: close\r
        \r

        """
        var response = Data(header.utf8)
        response.append(bodyData)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func requestPath(_ request: String) -> String {
        guard let line = request.split(separator: "\r\n").first else {
            return "/"
        }
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return "/" }
        let raw = String(parts[1])
        return URL(string: "http://127.0.0.1\(raw)")?.path ?? raw
    }

    private static func notFoundHTML(path: String) -> String {
        """
        <!doctype html><meta charset="utf-8"><title>missing</title>
        <html data-route="missing"><body>Missing \(path)</body></html>
        """
    }
}

@available(macOS 15.5, *)
private final class ChromeMV3ContentScriptLocalHTTPFixtureServer {
    let originModel: ChromeMV3ContentScriptLocalOriginModel
    private let sameServer: ChromeMV3LocalHTTPOriginServer
    private let crossServer: ChromeMV3LocalHTTPOriginServer

    private init(
        originModel: ChromeMV3ContentScriptLocalOriginModel,
        sameServer: ChromeMV3LocalHTTPOriginServer,
        crossServer: ChromeMV3LocalHTTPOriginServer
    ) {
        self.originModel = originModel
        self.sameServer = sameServer
        self.crossServer = crossServer
    }

    static func start(
        runnerID: String
    ) async throws -> ChromeMV3ContentScriptLocalHTTPFixtureServer {
        let preferred =
            ChromeMV3ContentScriptLocalOriginModel.preferredPorts(
                runnerID: runnerID
            )
        let sameServer =
            try await startOriginServer(
                preferredPort: preferred.sameOrigin,
                queueLabel:
                    "Sumi.ChromeMV3.LocalFixture.same.\(runnerID)"
            )
        let crossServer =
            try await startOriginServer(
                preferredPort: preferred.crossOrigin,
                queueLabel:
                    "Sumi.ChromeMV3.LocalFixture.cross.\(runnerID)"
            )
        let originModel = ChromeMV3ContentScriptLocalOriginModel.make(
            runnerID: runnerID,
            sameOriginPort: sameServer.port,
            crossOriginPort: crossServer.port
        )
        sameServer.update(
            routes: [
                "/top.html": topHTML(originModel: originModel),
                "/same-frame.html":
                    frameHTML(route: "same-origin-frame"),
            ]
        )
        crossServer.update(
            routes: [
                "/cross-frame.html":
                    frameHTML(route: "cross-origin-frame"),
            ]
        )
        return ChromeMV3ContentScriptLocalHTTPFixtureServer(
            originModel: originModel,
            sameServer: sameServer,
            crossServer: crossServer
        )
    }

    func stop() {
        sameServer.stop()
        crossServer.stop()
    }

    private static func startOriginServer(
        preferredPort: UInt16,
        queueLabel: String
    ) async throws -> ChromeMV3LocalHTTPOriginServer {
        do {
            let server = try ChromeMV3LocalHTTPOriginServer(
                preferredPort: preferredPort,
                queueLabel: queueLabel
            )
            try await server.start()
            return server
        } catch {
            let server = try ChromeMV3LocalHTTPOriginServer(
                queueLabel: queueLabel + ".fallback"
            )
            try await server.start()
            return server
        }
    }

    private static func topHTML(
        originModel: ChromeMV3ContentScriptLocalOriginModel
    ) -> String {
        let dataHTML = """
        <!doctype html><html data-route="data-frame"><head><meta charset="utf-8"><title>data</title></head><body>data</body></html>
        """
        let encodedData = dataHTML
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            ?? ""
        let blobHTML = """
        <!doctype html><html data-route="blob-frame"><head><meta charset="utf-8"><title>blob</title></head><body>blob</body></html>
        """
        let escapedBlob = blobHTML
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
        return """
        <!doctype html>
        <html data-route="top-frame">
        <head>
          <meta charset="utf-8">
          <title>Sumi MV3 local fixture</title>
        </head>
        <body>
          <iframe id="same-origin-frame" src="\(originModel.sameOriginFrameURLString)"></iframe>
          <iframe id="cross-origin-frame" src="\(originModel.crossOriginFrameURLString)"></iframe>
          <iframe id="about-blank-frame" src="about:blank"></iframe>
          <iframe id="data-frame" src="data:text/html,\(encodedData)"></iframe>
          <iframe id="blob-frame"></iframe>
          <script>
            const blob = new Blob([`\(escapedBlob)`], { type: "text/html" });
            document.getElementById("blob-frame").src = URL.createObjectURL(blob);
          </script>
        </body>
        </html>
        """
    }

    private static func frameHTML(route: String) -> String {
        """
        <!doctype html>
        <html data-route="\(route)">
        <head><meta charset="utf-8"><title>\(route)</title></head>
        <body>\(route)</body>
        </html>
        """
    }
}

@available(macOS 15.5, *)
@MainActor
private enum ChromeMV3ContentScriptLocalFixtureDOMInspection {
    static func inspect(
        webView: WKWebView,
        navigationCompletion:
            ChromeMV3ContentScriptSmokeNavigationCompletion,
        navigationObserver:
            ChromeMV3ContentScriptLocalFixtureNavigationObserver,
        routes: [ChromeMV3ContentScriptLocalFixtureFrameRoute]
    ) async -> (
        summary: ChromeMV3ContentScriptTestDOMInspectionSummary,
        snapshots: [String: ChromeMV3ContentScriptLocalFixtureFrameSnapshot]
    ) {
        guard navigationCompletion.state == .finished else {
            return (
                ChromeMV3ContentScriptTestDOMInspectionSummary(
                    attempted: true,
                    navigationCompletionState:
                        navigationCompletion.state.rawValue,
                    javaScriptEvaluationCompleted: false,
                    readOnlyDOMInspection: true,
                    persistentScriptRegistered: false,
                    scriptMessageHandlerRegistered: false,
                    jsBridgeUsed: false,
                    scheduledClockOrRepeatedChecksUsed: false,
                    inspectedFrameIDs: [],
                    diagnostics:
                        uniqueSorted(
                            [
                                navigationCompletion.errorDescription,
                                "Synthetic local fixture navigation did not finish.",
                            ].compactMap { $0 }
                        )
                ),
                [:]
            )
        }

        var snapshots: [String: ChromeMV3ContentScriptLocalFixtureFrameSnapshot] = [:]
        var diagnostics: [String] = []
        for route in routes {
            let frame = route.frameID == "top"
                ? nil
                : navigationObserver.frameInfo(frameID: route.frameID)
            do {
                let snapshot = try await evaluateSnapshot(
                    webView: webView,
                    frame: frame,
                    frameID: route.frameID
                )
                snapshots[route.frameID] = snapshot
            } catch {
                snapshots[route.frameID] =
                    ChromeMV3ContentScriptLocalFixtureFrameSnapshot(
                        frameID: route.frameID,
                        accessible: false,
                        markerObserved: false,
                        markerAttributeValue: nil,
                        markerTokenValue: nil,
                        executionReadyState: nil,
                        pageWorldGlobalValue: nil,
                        evaluationTarget:
                            frame == nil ? "mainFrame" : "capturedFrame",
                        reason: error.localizedDescription
                    )
                diagnostics.append(
                    "\(route.frameID): \(error.localizedDescription)"
                )
            }
        }

        return (
            ChromeMV3ContentScriptTestDOMInspectionSummary(
                attempted: true,
                navigationCompletionState:
                    navigationCompletion.state.rawValue,
                javaScriptEvaluationCompleted:
                    snapshots.values.contains { $0.accessible },
                readOnlyDOMInspection: true,
                persistentScriptRegistered: false,
                scriptMessageHandlerRegistered: false,
                jsBridgeUsed: false,
                scheduledClockOrRepeatedChecksUsed: false,
                inspectedFrameIDs: uniqueSorted(Array(snapshots.keys)),
                diagnostics: uniqueSorted(diagnostics)
            ),
            snapshots
        )
    }

    private static func evaluateSnapshot(
        webView: WKWebView,
        frame: WKFrameInfo?,
        frameID: String
    ) async throws -> ChromeMV3ContentScriptLocalFixtureFrameSnapshot {
        if frameID != "top", frame == nil {
            return ChromeMV3ContentScriptLocalFixtureFrameSnapshot(
                frameID: frameID,
                accessible: false,
                markerObserved: false,
                markerAttributeValue: nil,
                markerTokenValue: nil,
                executionReadyState: nil,
                pageWorldGlobalValue: nil,
                evaluationTarget: "missingCapturedFrame",
                reason: "No WKFrameInfo was captured for this local fixture frame."
            )
        }
        let json = try await evaluate(script: snapshotScript(), in: frame, webView: webView)
        return decode(json: json, frameID: frameID, target: frame == nil ? "mainFrame" : "capturedFrame")
    }

    private static func evaluate(
        script: String,
        in frame: WKFrameInfo?,
        webView: WKWebView
    ) async throws -> String {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<String, Error>) in
            webView.evaluateJavaScript(script, in: frame, in: .page) { result in
                switch result {
                case .success(let value):
                    if let string = value as? String {
                        continuation.resume(returning: string)
                    } else {
                        continuation.resume(
                            throwing:
                                NSError(
                                    domain:
                                        "Sumi.ChromeMV3LocalFixtureInspection",
                                    code: 1,
                                    userInfo: [
                                        NSLocalizedDescriptionKey:
                                            "DOM inspection did not return JSON.",
                                    ]
                                )
                        )
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func snapshotScript() -> String {
        """
        (() => {
          const marker = "sumiChromeMV3ContentScriptSmokeMarker";
          const root = document.documentElement;
          if (!root) {
            return JSON.stringify({
              accessible: false,
              markerObserved: false,
              markerAttributeValue: null,
              markerTokenValue: null,
              executionReadyState: null,
              pageWorldGlobalValue: null,
              reason: "missing-document-root"
            });
          }
          const markerAttributeValue = root.getAttribute("data-sumi-mv3-content-script-smoke") || "";
          const markerTokenValue = root.getAttribute("data-sumi-mv3-content-script-smoke-marker") || "";
          const executionReadyState = root.getAttribute("data-sumi-mv3-content-script-ready-state") || "";
          const pageWorldGlobalValue = window.__sumiMV3LocalFixtureWorldProbe || "";
          return JSON.stringify({
            accessible: true,
            markerObserved: markerAttributeValue.length > 0 && markerTokenValue === marker,
            markerAttributeValue,
            markerTokenValue,
            executionReadyState,
            pageWorldGlobalValue,
            reason: null
          });
        })();
        """
    }

    private static func decode(
        json: String,
        frameID: String,
        target: String
    ) -> ChromeMV3ContentScriptLocalFixtureFrameSnapshot {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else {
            return ChromeMV3ContentScriptLocalFixtureFrameSnapshot(
                frameID: frameID,
                accessible: false,
                markerObserved: false,
                markerAttributeValue: nil,
                markerTokenValue: nil,
                executionReadyState: nil,
                pageWorldGlobalValue: nil,
                evaluationTarget: target,
                reason: "Snapshot JSON could not be decoded."
            )
        }
        return ChromeMV3ContentScriptLocalFixtureFrameSnapshot(
            frameID: frameID,
            accessible: boolValue(object["accessible"]) ?? false,
            markerObserved: boolValue(object["markerObserved"]) ?? false,
            markerAttributeValue: stringValue(object["markerAttributeValue"]),
            markerTokenValue: stringValue(object["markerTokenValue"]),
            executionReadyState: stringValue(object["executionReadyState"]),
            pageWorldGlobalValue: stringValue(object["pageWorldGlobalValue"]),
            evaluationTarget: target,
            reason: stringValue(object["reason"])
        )
    }
}

@available(macOS 15.5, *)
enum ChromeMV3ContentScriptLocalFixtureRunner {
    @MainActor
    static func run(
        runnerID: String = "runtime-content-script-local-fixture-runner",
        fixtureID: String? = nil,
        candidate: ChromeMV3RewrittenVariantCandidate,
        extensionsModuleEnabled: Bool,
        explicitInternalLocalFixtureRunnerAllowed: Bool,
        explicitLocalHTTPServerAllowed: Bool,
        explicitSyntheticWebViewCreationAllowed: Bool,
        explicitSyntheticNavigationAllowed: Bool,
        explicitTestDOMInspectionAllowed: Bool,
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
        tearDownLoadedContextAndControllerAfterRun: Bool = true
    ) async -> ChromeMV3ContentScriptLocalFixtureRunnerReport {
        let preferred =
            ChromeMV3ContentScriptLocalOriginModel.preferredPorts(
                runnerID: runnerID
            )
        let preferredOriginModel =
            ChromeMV3ContentScriptLocalOriginModel.make(
                runnerID: runnerID,
                sameOriginPort: preferred.sameOrigin,
                crossOriginPort: preferred.crossOrigin
            )
        let rootPath = URL(
            fileURLWithPath: candidate.rewrittenVariantRootPath,
            isDirectory: true
        ).standardizedFileURL.path
        let loadDiagnostics = controllerLoadOwner?.diagnostics()
        let controller = emptyControllerOwner?.controller
        let context = detachedContextOwner?.detachedContext
        let accepted =
            objectAcceptanceReport?.objectAcceptedByWebKit == true
        let detachedAvailable =
            context != nil
                || isSet(loadDiagnostics?.contextLoadedIntoController)
        let sameController =
            controller != nil
                && context?.webExtensionController === controller
                && isSet(loadDiagnostics?.contextLoadedIntoController)
        let contentPolicy = ChromeMV3ContentScriptSmokeFixturePolicy.evaluate(
            generatedRewrittenRootPath: rootPath,
            acceptedWebExtensionObjectAvailable: accepted,
            detachedContextCreated: detachedAvailable,
            options:
                ChromeMV3ContentScriptSmokeFixturePolicyOptions(
                    allowedTestOriginHosts: ["127.0.0.1", "localhost"],
                    allowBroadPatternsForExplicitTestFixture: false
                )
        )
        let resolvedFixtureID =
            ChromeMV3ContentScriptLocalFixtureID(
                rawValue:
                    fixtureID
                        ?? "content-script-local-fixture:\(candidate.id)"
            )
        let gateInput = ChromeMV3ContentScriptLocalFixtureGateInput(
            runnerID:
                ChromeMV3ContentScriptLocalFixtureRunnerID(
                    rawValue: runnerID
                ),
            fixtureID: resolvedFixtureID,
            generatedRewrittenRootPath: rootPath,
            extensionsModuleEnabled: extensionsModuleEnabled,
            explicitInternalLocalFixtureRunnerAllowed:
                explicitInternalLocalFixtureRunnerAllowed,
            explicitLocalHTTPServerAllowed:
                explicitLocalHTTPServerAllowed,
            explicitSyntheticWebViewCreationAllowed:
                explicitSyntheticWebViewCreationAllowed,
            explicitSyntheticNavigationAllowed:
                explicitSyntheticNavigationAllowed,
            explicitTestDOMInspectionAllowed:
                explicitTestDOMInspectionAllowed,
            acceptedWebExtensionObjectAvailable: accepted,
            detachedContextAvailable: detachedAvailable,
            contentScriptFixturePolicy: contentPolicy,
            controllerLoadGateDecision: loadDiagnostics?.gateDecision,
            controllerLoadOwnerDiagnostics: loadDiagnostics,
            liveNormalTabAttachmentSnapshot:
                liveNormalTabAttachmentSnapshot,
            runtimeBridgeReadinessReport: runtimeBridgeReadinessReport,
            sameControllerAvailable: sameController,
            requestedProductRuntimeExposure: false,
            requestedUserScriptRegistration: false,
            requestedRuntimeDispatch: false,
            requestedServiceWorkerWake: false,
            requestedNativeMessagingLaunch: false,
            requestedProductUI: false
        )
        let gateDecision =
            ChromeMV3ContentScriptLocalFixtureGate.evaluate(
                input: gateInput
            )

        guard gateDecision.canStartLocalFixtureRunnerNow else {
            let cases =
                ChromeMV3ContentScriptLocalFixtureMatrix.makeCases(
                    runnerID: gateInput.runnerID,
                    fixtureID: resolvedFixtureID,
                    originModel: preferredOriginModel,
                    manifestSummary: contentPolicy.manifestSummary,
                    blockedReason:
                        gateDecision.prerequisiteState
                            .blockedByContextLoadUnavailable
                            ? .contextLoadUnavailable
                            : gateDecision.blockers.first,
                    observationStrategy: .none
                )
            return ChromeMV3ContentScriptLocalFixtureRunnerReportGenerator
                .makeReport(
                    candidate: candidate,
                    originModel: preferredOriginModel,
                    setupResult: .notAttempted(
                        originModel: preferredOriginModel,
                        reason: gateDecision.blockers.first,
                        diagnostics: gateDecision.blockingReasons
                    ),
                    gateDecision: gateDecision,
                    matrixCases: cases,
                    observationStrategy: .none,
                    testDOMInspection: .notAttempted,
                    navigationCompletionState: "notStarted"
                )
        }

        var server: ChromeMV3ContentScriptLocalHTTPFixtureServer?
        do {
            server =
                try await ChromeMV3ContentScriptLocalHTTPFixtureServer
                .start(runnerID: runnerID)
        } catch {
            let cases =
                ChromeMV3ContentScriptLocalFixtureMatrix.makeCases(
                    runnerID: gateInput.runnerID,
                    fixtureID: resolvedFixtureID,
                    originModel: preferredOriginModel,
                    manifestSummary: contentPolicy.manifestSummary,
                    blockedReason: .localHTTPFixtureServerUnavailable,
                    observationStrategy: .none
                )
            return ChromeMV3ContentScriptLocalFixtureRunnerReportGenerator
                .makeReport(
                    candidate: candidate,
                    originModel: preferredOriginModel,
                    setupResult: .notAttempted(
                        originModel: preferredOriginModel,
                        reason: .localHTTPFixtureServerUnavailable,
                        diagnostics: [error.localizedDescription]
                    ),
                    gateDecision: gateDecision,
                    matrixCases: cases,
                    observationStrategy: .none,
                    testDOMInspection: .notAttempted,
                    navigationCompletionState: "notStarted"
                )
        }

        guard let server else {
            preconditionFailure("Server creation branch must return or assign.")
        }
        defer {
            server.stop()
        }

        let originModel = server.originModel
        let routes = ChromeMV3ContentScriptLocalFixtureRoutes.routes(
            originModel: originModel
        )
        var setupResult = ChromeMV3ContentScriptLocalFixtureSetupResult(
            attempted: true,
            serverStarted: true,
            loopbackOnly: true,
            externalNetworkUsed: false,
            sameOrigin: originModel.sameOrigin,
            crossOrigin: originModel.crossOrigin,
            servingPlan:
                ChromeMV3ContentScriptLocalFixtureRoutes.servingPlan(
                    originModel: originModel
                ),
            blockedReason: nil,
            diagnostics: [
                "Loopback-only local HTTP fixtures started for a synthetic WKWebView.",
            ]
        )

        var syntheticConfiguration: WKWebViewConfiguration?
        var syntheticWebView: WKWebView?
        var navigationObserver:
            ChromeMV3ContentScriptLocalFixtureNavigationObserver?
        var navigationCompletion =
            ChromeMV3ContentScriptSmokeNavigationCompletion.notStarted
        var summary =
            ChromeMV3ContentScriptTestDOMInspectionSummary.notAttempted
        var snapshots: [String: ChromeMV3ContentScriptLocalFixtureFrameSnapshot] = [:]

        if gateDecision.canCreateSyntheticWebViewNow,
           let controller {
            syntheticConfiguration = WKWebViewConfiguration()
            syntheticConfiguration?
                .sumiIsNormalTabWebViewConfiguration = false
            syntheticConfiguration?.webExtensionController = controller
            syntheticWebView = WKWebView(
                frame: .zero,
                configuration: syntheticConfiguration!
            )
        }

        if gateDecision.canNavigateSyntheticWebViewNow,
           let syntheticWebView,
           let url = URL(string: originModel.topFrameURLString) {
            navigationObserver =
                ChromeMV3ContentScriptLocalFixtureNavigationObserver()
            syntheticWebView.navigationDelegate = navigationObserver
            let navigation = syntheticWebView.load (URLRequest(url: url))
            navigationCompletion =
                await navigationObserver?.waitForCompletion(
                    navigation: navigation
                ) ?? .notStarted
        } else {
            setupResult.blockedReason = .syntheticWebViewUnavailable
            setupResult.diagnostics.append(
                ChromeMV3ContentScriptLocalFixtureBlockedReason
                    .syntheticWebViewUnavailable
                    .reason
            )
        }

        if gateDecision.canInspectDOMNow,
           let syntheticWebView,
           let navigationObserver {
            let inspection =
                await ChromeMV3ContentScriptLocalFixtureDOMInspection
                .inspect(
                    webView: syntheticWebView,
                    navigationCompletion: navigationCompletion,
                    navigationObserver: navigationObserver,
                    routes: routes
                )
            summary = inspection.summary
            snapshots = inspection.snapshots
        }

        let blockedReason:
            ChromeMV3ContentScriptLocalFixtureBlockedReason?
        if navigationCompletion.state == .finished {
            blockedReason = nil
        } else {
            blockedReason = .syntheticNavigationFailed
        }
        let cases =
            ChromeMV3ContentScriptLocalFixtureMatrix.makeCases(
                runnerID: gateInput.runnerID,
                fixtureID: resolvedFixtureID,
                originModel: originModel,
                manifestSummary: contentPolicy.manifestSummary,
                snapshots: snapshots,
                blockedReason: blockedReason,
                observationStrategy: .testDOMInspection
            )

        syntheticWebView?.navigationDelegate = nil
        syntheticWebView = nil
        syntheticConfiguration?.webExtensionController = nil
        syntheticConfiguration = nil

        if tearDownLoadedContextAndControllerAfterRun {
            _ = controllerLoadOwner?.tearDown()
            _ = detachedContextOwner?.tearDown()
            _ = emptyControllerOwner?.tearDown(trigger: .explicitReset)
        }

        return ChromeMV3ContentScriptLocalFixtureRunnerReportGenerator
            .makeReport(
                candidate: candidate,
                originModel: originModel,
                setupResult: setupResult,
                gateDecision: gateDecision,
                matrixCases: cases,
                observationStrategy: .testDOMInspection,
                testDOMInspection: summary,
                navigationCompletionState:
                    navigationCompletion.state.rawValue
            )
    }
}
#endif

private func uniqueSorted(_ values: [String]) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}

private func stringValue(_ value: Any?) -> String? {
    if let string = value as? String {
        return string
    }
    if let number = value as? NSNumber {
        return number.stringValue
    }
    return nil
}

private func boolValue(_ value: Any?) -> Bool? {
    if let bool = value as? Bool {
        return bool
    }
    if let number = value as? NSNumber {
        return number.boolValue
    }
    if let string = value as? String {
        switch string.lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }
    return nil
}

private func isSet(_ value: Bool?) -> Bool {
    value == true
}
