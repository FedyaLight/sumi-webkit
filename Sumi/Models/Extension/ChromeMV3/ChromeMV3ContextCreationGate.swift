//
//  ChromeMV3ContextCreationGate.swift
//  Sumi
//
//  DEBUG/internal gate for creating a detached WKWebExtensionContext object.
//  This layer separates object construction from controller loading and keeps
//  extension execution unavailable.
//

import CryptoKit
import Foundation

enum ChromeMV3ContextCreationOwnerState: String, Codable, Sendable {
    case notCreated
    case blocked
    case createdDetached
    case failed
    case released
}

enum ChromeMV3ContextCreationSDKCompatibilityStatus:
    String,
    Codable,
    Sendable
{
    case detachedInitializerAvailable
    case unsupportedByCurrentSDKShape
}

struct ChromeMV3ContextCreationSDKCompatibility:
    Codable,
    Equatable,
    Sendable
{
    var status: ChromeMV3ContextCreationSDKCompatibilityStatus
    var canConstructDetachedContext: Bool
    var contextInitializerSymbol: String?
    var contextFactorySymbol: String?
    var controllerLoadSymbols: [String]
    var webExtensionControllerPropertyFinding: String
    var loadBoundaryFinding: String
    var localSDKHeaderFinding: String

    static let currentAppleSDK =
        ChromeMV3ContextCreationSDKCompatibility(
            status: .detachedInitializerAvailable,
            canConstructDetachedContext: true,
            contextInitializerSymbol: "WKWebExtension" + "Context.init(for:)",
            contextFactorySymbol: "contextForExtension:",
            controllerLoadSymbols: [
                "load" + "ExtensionContext:error:",
                "load(_:)",
            ],
            webExtensionControllerPropertyFinding:
                "WKWebExtensionContext.webExtensionController is nil when the context is not loaded.",
            loadBoundaryFinding:
                "WKWebExtensionController load(_: ) starts background content and content injection; Sumi does not call it here.",
            localSDKHeaderFinding:
                "MacOSX26.5 WebKit headers expose initForExtension:/contextForExtension: and keep loading behind WKWebExtensionController."
        )

    static func unsupported(
        finding: String
    ) -> ChromeMV3ContextCreationSDKCompatibility {
        ChromeMV3ContextCreationSDKCompatibility(
            status: .unsupportedByCurrentSDKShape,
            canConstructDetachedContext: false,
            contextInitializerSymbol: nil,
            contextFactorySymbol: nil,
            controllerLoadSymbols: [
                "load" + "ExtensionContext:error:",
                "load(_:)",
            ],
            webExtensionControllerPropertyFinding:
                "Detached context construction could not be proven with the active SDK.",
            loadBoundaryFinding:
                "Context loading remains blocked.",
            localSDKHeaderFinding: finding
        )
    }
}

enum ChromeMV3ContextCreationGateBlocker:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case extensionsModuleDisabled
    case profileHostDisabled
    case explicitContextCreationNotAllowed
    case acceptedExtensionObjectUnavailable
    case webKitObjectNotAccepted
    case objectAcceptanceBlockersPresent
    case emptyControllerDiagnosticsMissing
    case emptyControllerMissing
    case emptyControllerNotCreated
    case emptyControllerNoLongerEmpty
    case profileIdentityUnavailable
    case controllerDataStoreIdentityUnresolved
    case controllerDataStoreIdentityPlaceholder
    case controllerDataStoreIdentityMismatch
    case staleAttachedWebViewsPresent
    case auxiliarySurfaceAttached
    case runtimeBridgeReadinessMissing
    case runtimeBridgePrerequisitesNotModeled
    case jsBridgeExposed
    case runtimeBridgeInvariantViolation
    case sdkDetachedConstructionUnsupported
    case contextLoadingRequested
    case controllerLoadRequested
    case extensionCodeExecutionRequested
    case userScriptRegistrationRequested
    case nativeMessagingLaunchRequested
    case runtimeLoadabilityInvariantViolation

    var reason: String {
        switch self {
        case .extensionsModuleDisabled:
            return "The extensions module is disabled."
        case .profileHostDisabled:
            return "The Chrome MV3 profile host is disabled."
        case .explicitContextCreationNotAllowed:
            return "Explicit DEBUG/internal WKWebExtensionContext object creation is not allowed."
        case .acceptedExtensionObjectUnavailable:
            return "An accepted/probed WKWebExtension object is not available."
        case .webKitObjectNotAccepted:
            return "The generated-rewritten bundle has not been accepted by WebKit object creation."
        case .objectAcceptanceBlockersPresent:
            return "WebKit object-acceptance blockers remain unresolved."
        case .emptyControllerDiagnosticsMissing:
            return "Empty WKWebExtensionController diagnostics are missing."
        case .emptyControllerMissing:
            return "A gated empty WKWebExtensionController owner is not available."
        case .emptyControllerNotCreated:
            return "The empty WKWebExtensionController has not been created."
        case .emptyControllerNoLongerEmpty:
            return "The controller is no longer empty."
        case .profileIdentityUnavailable:
            return "A concrete Chrome MV3 profile identity is required."
        case .controllerDataStoreIdentityUnresolved:
            return "Controller data-store identity is unresolved."
        case .controllerDataStoreIdentityPlaceholder:
            return "Controller data-store identity is only a diagnostic placeholder."
        case .controllerDataStoreIdentityMismatch:
            return "Controller data-store identity does not match the profile policy."
        case .staleAttachedWebViewsPresent:
            return "Stale DEBUG-attached normal-tab WebViews block context object creation."
        case .auxiliarySurfaceAttached:
            return "An auxiliary/helper surface was attached."
        case .runtimeBridgeReadinessMissing:
            return "Runtime bridge readiness diagnostics are missing."
        case .runtimeBridgePrerequisitesNotModeled:
            return "Runtime bridge prerequisites are not sufficiently modeled for context object creation."
        case .jsBridgeExposed:
            return "The JS bridge is exposed or injectable, which is forbidden for this gate."
        case .runtimeBridgeInvariantViolation:
            return "Runtime bridge readiness reported execution, loading, wake, port, or listener availability."
        case .sdkDetachedConstructionUnsupported:
            return "The active SDK shape does not support safe detached context construction."
        case .contextLoadingRequested:
            return "Context loading was requested, but loading remains blocked."
        case .controllerLoadRequested:
            return "Controller loading was requested, but controller load APIs remain forbidden."
        case .extensionCodeExecutionRequested:
            return "Extension code execution was requested, but execution remains blocked."
        case .userScriptRegistrationRequested:
            return "User script registration was requested, but JS injection remains blocked."
        case .nativeMessagingLaunchRequested:
            return "Native messaging launch was requested, but native messaging remains blocked."
        case .runtimeLoadabilityInvariantViolation:
            return "runtimeLoadable must remain false for context object creation."
        }
    }
}

struct ChromeMV3ContextCreationSameControllerPrecondition:
    Codable,
    Equatable,
    Sendable
{
    var futureContextControllerMustMatchTabWebViews: Bool
    var normalTabWebViewsMustUseSameControllerBeforeFutureLoad: Bool
    var staleAttachedWebViewsMayRequireRecreationBeforeFutureLoad: Bool
    var auxiliaryHelperPreviewMiniFaviconSurfacesIneligible: Bool
    var eligibleNormalBrowsingSurfaces: [ChromeMV3WebViewSurface]
    var ineligibleSurfaces: [ChromeMV3WebViewSurface]
    var requiredFutureActions: [String]

    static func make(
        liveSnapshot: ChromeMV3LiveNormalTabAttachmentRecorderSnapshot?
    ) -> ChromeMV3ContextCreationSameControllerPrecondition {
        let staleCount = liveSnapshot?.staleOrNeedsRecreationCount ?? 0
        return ChromeMV3ContextCreationSameControllerPrecondition(
            futureContextControllerMustMatchTabWebViews: true,
            normalTabWebViewsMustUseSameControllerBeforeFutureLoad: true,
            staleAttachedWebViewsMayRequireRecreationBeforeFutureLoad:
                staleCount > 0,
            auxiliaryHelperPreviewMiniFaviconSurfacesIneligible: true,
            eligibleNormalBrowsingSurfaces: [.normalTab],
            ineligibleSurfaces:
                ChromeMV3WebViewSurface.allCases
                .filter { $0 != .normalTab }
                .sorted { $0.rawValue < $1.rawValue },
            requiredFutureActions: [
                "Future context/controller load must use the same controller assigned to eligible normal-tab WKWebViewConfiguration instances.",
                "Normal-tab WebViews must be created with the same controller before any future context load.",
                "Stale DEBUG-attached WebViews require recreation before future context loading.",
                "Auxiliary, helper, preview, mini-window, favicon, and download surfaces remain ineligible.",
            ]
        )
    }
}

enum ChromeMV3ContextCreationRuntimeBridgeStatus:
    String,
    Codable,
    Sendable
{
    case missing
    case modeledForContextObjectCreation
    case blocked
}

struct ChromeMV3ContextCreationRuntimeBridgePrerequisitesSummary:
    Codable,
    Equatable,
    Sendable
{
    var status: ChromeMV3ContextCreationRuntimeBridgeStatus
    var readinessReportID: String?
    var messagingDispatcherModelExists: Bool
    var runtimeDispatchAvailable: Bool
    var listenerRegistrationUnavailable: Bool
    var jsBridgeContractExists: Bool
    var jsBridgeExposedToJSNow: Bool
    var jsBridgeInjectionUnavailable: Bool
    var storageModelExists: Bool
    var permissionBrokerExists: Bool
    var serviceWorkerLifecycleCoordinatorExists: Bool
    var serviceWorkerWakeUnavailable: Bool
    var nativeMessagingBlocked: Bool
    var nativeMessagingProcessLaunchUnavailable: Bool
    var nativeMessagingPortUnavailable: Bool
    var contextLoadingUnavailable: Bool
    var runtimeLoadable: Bool
    var modeledEnoughForContextObjectCreation: Bool
    var blockers: [String]
    var warnings: [String]

    static func make(
        readinessReport: ChromeMV3RuntimeBridgeReadinessReport?
    ) -> ChromeMV3ContextCreationRuntimeBridgePrerequisitesSummary {
        guard let readinessReport else {
            return ChromeMV3ContextCreationRuntimeBridgePrerequisitesSummary(
                status: .missing,
                readinessReportID: nil,
                messagingDispatcherModelExists: false,
                runtimeDispatchAvailable: false,
                listenerRegistrationUnavailable: true,
                jsBridgeContractExists: false,
                jsBridgeExposedToJSNow: false,
                jsBridgeInjectionUnavailable: true,
                storageModelExists: false,
                permissionBrokerExists: false,
                serviceWorkerLifecycleCoordinatorExists: false,
                serviceWorkerWakeUnavailable: true,
                nativeMessagingBlocked: true,
                nativeMessagingProcessLaunchUnavailable: true,
                nativeMessagingPortUnavailable: true,
                contextLoadingUnavailable: true,
                runtimeLoadable: false,
                modeledEnoughForContextObjectCreation: false,
                blockers: [
                    "Runtime bridge readiness report is missing.",
                ],
                warnings: []
            )
        }

        let dispatcher = readinessReport
            .runtimeMessageDispatcherSkeletonReportSummary
        let jsBridge = readinessReport.jsBridgeContractReportSummary
        let listener = readinessReport.runtimeListenerContractReportSummary
        let storage = readinessReport.storageBrokerReadinessReportSummary
        let permission = readinessReport.permissionBrokerReadinessReportSummary
        let serviceWorker = readinessReport.serviceWorkerLifecycleReportSummary
        let native = readinessReport.nativeMessagingReadinessReportSummary

        let messagingDispatcherModelExists =
            dispatcher?.modelOnlyDispatchAvailable ?? false
        let runtimeDispatchAvailable =
            (dispatcher?.runtimeDispatchAvailable ?? false)
                || readinessReport.messagingGate.dispatchImplemented
        let listenerRegistrationUnavailable =
            (listener?.canRegisterListenersNow ?? false) == false
                && readinessReport.messagingGate
                .listenerRegistrationImplemented == false
        let jsBridgeContractExists = jsBridge != nil
        let jsBridgeExposedToJSNow = jsBridge?.exposedToJSNow ?? false
        let jsBridgeInjectionUnavailable =
            (jsBridge?.canInjectScriptsNow ?? false) == false
        let storageModelExists = storage != nil
        let permissionBrokerExists =
            permission?.permissionBrokerSkeletonPresent ?? false
        let serviceWorkerLifecycleCoordinatorExists =
            serviceWorker != nil
                && readinessReport.serviceWorkerLifecycleGate
                .lifecycleCoordinatorImplemented
        let serviceWorkerWakeUnavailable =
            (serviceWorker?.canWakeServiceWorkerNow ?? false) == false
                && readinessReport.serviceWorkerLifecycleGate
                .serviceWorkerWakeImplemented == false
        let nativeMessagingBlocked =
            readinessReport.nativeMessagingGate.nativeMessagingBlocked
        let nativeMessagingProcessLaunchUnavailable =
            (native?.processLaunchAllowedNow ?? false) == false
                && readinessReport.nativeMessagingGate
                .processLaunchImplemented == false
        let nativeMessagingPortUnavailable =
            (native?.canOpenPortNow ?? false) == false
        let contextLoadingUnavailable =
            readinessReport.canLoadContextNow == false
                && readinessReport.runtimeLoadable == false

        var blockers: [String] = []
        if messagingDispatcherModelExists == false {
            blockers.append("Runtime message dispatcher model is missing.")
        }
        if runtimeDispatchAvailable {
            blockers.append("Runtime dispatch is available unexpectedly.")
        }
        if listenerRegistrationUnavailable == false {
            blockers.append("Runtime listener registration is available.")
        }
        if jsBridgeContractExists == false {
            blockers.append("JS bridge contract report is missing.")
        }
        if jsBridgeExposedToJSNow {
            blockers.append("JS bridge is exposed to JavaScript.")
        }
        if jsBridgeInjectionUnavailable == false {
            blockers.append("JS bridge injection is available.")
        }
        if storageModelExists == false {
            blockers.append("Storage broker model report is missing.")
        }
        if permissionBrokerExists == false {
            blockers.append("Permission broker model report is missing.")
        }
        if serviceWorkerLifecycleCoordinatorExists == false {
            blockers.append("Service-worker lifecycle model report is missing.")
        }
        if serviceWorkerWakeUnavailable == false {
            blockers.append("Service-worker wake is available.")
        }
        if nativeMessagingBlocked == false {
            blockers.append("Native messaging is not blocked.")
        }
        if nativeMessagingProcessLaunchUnavailable == false {
            blockers.append("Native messaging process launch is available.")
        }
        if nativeMessagingPortUnavailable == false {
            blockers.append("Native messaging ports are available.")
        }
        if contextLoadingUnavailable == false {
            blockers.append("Context loading or runtime loadability is available.")
        }

        let modeledEnough = blockers.isEmpty
        return ChromeMV3ContextCreationRuntimeBridgePrerequisitesSummary(
            status:
                modeledEnough
                    ? .modeledForContextObjectCreation
                    : .blocked,
            readinessReportID: readinessReport.id,
            messagingDispatcherModelExists:
                messagingDispatcherModelExists,
            runtimeDispatchAvailable: runtimeDispatchAvailable,
            listenerRegistrationUnavailable:
                listenerRegistrationUnavailable,
            jsBridgeContractExists: jsBridgeContractExists,
            jsBridgeExposedToJSNow: jsBridgeExposedToJSNow,
            jsBridgeInjectionUnavailable: jsBridgeInjectionUnavailable,
            storageModelExists: storageModelExists,
            permissionBrokerExists: permissionBrokerExists,
            serviceWorkerLifecycleCoordinatorExists:
                serviceWorkerLifecycleCoordinatorExists,
            serviceWorkerWakeUnavailable: serviceWorkerWakeUnavailable,
            nativeMessagingBlocked: nativeMessagingBlocked,
            nativeMessagingProcessLaunchUnavailable:
                nativeMessagingProcessLaunchUnavailable,
            nativeMessagingPortUnavailable: nativeMessagingPortUnavailable,
            contextLoadingUnavailable: contextLoadingUnavailable,
            runtimeLoadable: false,
            modeledEnoughForContextObjectCreation: modeledEnough,
            blockers: uniqueSorted(blockers),
            warnings: uniqueSorted([
                "Runtime bridge prerequisites are modeled only; this does not make the runtime loadable.",
                "Context object creation is separate from controller load and extension execution.",
            ])
        )
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { $0.isEmpty == false })).sorted()
    }
}

struct ChromeMV3ContextCreationGateInput:
    Codable,
    Equatable,
    Sendable
{
    var candidateID: String
    var generatedRewrittenRootPath: String
    var extensionsModuleEnabled: Bool
    var profileHostModuleState: ChromeMV3ProfileHostModuleState
    var profileIdentifier: String
    var explicitInternalContextCreationAllowed: Bool
    var acceptedWebExtensionObjectAvailable: Bool
    var objectProbeDiagnostics: ChromeMV3ExtensionObjectProbeDiagnostics?
    var objectAcceptanceReport: ChromeMV3WebKitObjectAcceptanceReport?
    var emptyControllerDiagnostics: ChromeMV3EmptyControllerDiagnostics?
    var liveNormalTabAttachmentSnapshot:
        ChromeMV3LiveNormalTabAttachmentRecorderSnapshot?
    var runtimeBridgeReadinessReport:
        ChromeMV3RuntimeBridgeReadinessReport?
    var sdkCompatibility: ChromeMV3ContextCreationSDKCompatibility
    var requestedContextLoading: Bool
    var requestedControllerLoad: Bool
    var requestedExtensionCodeExecution: Bool
    var requestedUserScriptRegistration: Bool
    var requestedNativeMessagingLaunch: Bool
}

struct ChromeMV3ContextCreationGateDecision:
    Codable,
    Equatable,
    Sendable
{
    var input: ChromeMV3ContextCreationGateInput
    var canCreateContextObjectNow: Bool
    var canLoadContextNow: Bool
    var canExecuteExtensionCodeNow: Bool
    var runtimeLoadable: Bool
    var blockers: [ChromeMV3ContextCreationGateBlocker]
    var blockingReasons: [String]
    var warnings: [String]
    var diagnostics: [String]

    var passed: Bool {
        canCreateContextObjectNow
    }
}

enum ChromeMV3ContextCreationGate {
    static func evaluate(
        input: ChromeMV3ContextCreationGateInput
    ) -> ChromeMV3ContextCreationGateDecision {
        var blockers: [ChromeMV3ContextCreationGateBlocker] = []
        var warnings: [String] = []
        var diagnostics: [String] = []

        let objectBlockingFindings =
            ChromeMV3ContextReadinessReportGenerator
            .objectAcceptanceBlockingFindings(
                in: input.objectAcceptanceReport
            )
        let dataStoreStatus =
            ChromeMV3ContextReadinessReportGenerator
            .dataStoreIdentityStatus(
                input.emptyControllerDiagnostics?
                    .dataStoreIdentityPolicy
            )
        let liveSnapshot = input.liveNormalTabAttachmentSnapshot
            ?? input.emptyControllerDiagnostics?
            .liveNormalTabAttachmentSnapshot
        let runtimeSummary =
            ChromeMV3ContextCreationRuntimeBridgePrerequisitesSummary
            .make(readinessReport: input.runtimeBridgeReadinessReport)

        if input.extensionsModuleEnabled == false {
            blockers.append(.extensionsModuleDisabled)
        }

        if input.profileHostModuleState != .enabled {
            blockers.append(.profileHostDisabled)
        }

        if input.explicitInternalContextCreationAllowed == false {
            blockers.append(.explicitContextCreationNotAllowed)
        }

        if input.acceptedWebExtensionObjectAvailable == false {
            blockers.append(.acceptedExtensionObjectUnavailable)
        }

        if input.objectAcceptanceReport?.objectAcceptedByWebKit != true {
            blockers.append(.webKitObjectNotAccepted)
        }

        if objectBlockingFindings.isEmpty == false {
            blockers.append(.objectAcceptanceBlockersPresent)
        }

        guard let emptyController = input.emptyControllerDiagnostics else {
            blockers.append(.emptyControllerDiagnosticsMissing)
            return decision(
                input: input,
                blockers: blockers,
                warnings: warnings,
                diagnostics: diagnostics
            )
        }

        if emptyController.controllerCreated == false {
            blockers.append(.emptyControllerMissing)
        }

        if emptyController.controllerState != .createdEmpty {
            blockers.append(.emptyControllerNotCreated)
        }

        if emptyController.contextCount > 0
            || emptyController.loadedExtensionCount > 0
            || emptyController.nativeMessagingPortCount > 0
            || emptyController.pendingContextLoads > 0
            || emptyController.pendingAttachments > 0
            || emptyController.configurationWebViewUserScriptCount > 0
        {
            blockers.append(.emptyControllerNoLongerEmpty)
        }

        if input.profileIdentifier.isResolvedChromeMV3ContextProfile == false {
            blockers.append(.profileIdentityUnavailable)
        }

        switch dataStoreStatus.status {
        case .matched:
            break
        case .missing, .unresolved:
            blockers.append(.controllerDataStoreIdentityUnresolved)
        case .placeholder:
            blockers.append(.controllerDataStoreIdentityPlaceholder)
        case .mismatched:
            blockers.append(.controllerDataStoreIdentityMismatch)
        }

        if let liveSnapshot {
            if liveSnapshot.staleOrNeedsRecreationCount > 0 {
                blockers.append(.staleAttachedWebViewsPresent)
            }
            if liveSnapshot.accidentallyAttachedAuxiliarySurface {
                blockers.append(.auxiliarySurfaceAttached)
            }
            if liveSnapshot.contextLoadCalled
                || liveSnapshot.generatedExtensionBundleLoaded
                || liveSnapshot.nativeMessagingLaunched
                || liveSnapshot.canLoadContextNow
                || liveSnapshot.runtimeLoadable
            {
                blockers.append(.runtimeBridgeInvariantViolation)
            }
        }

        switch runtimeSummary.status {
        case .missing:
            blockers.append(.runtimeBridgeReadinessMissing)
        case .modeledForContextObjectCreation:
            break
        case .blocked:
            blockers.append(.runtimeBridgePrerequisitesNotModeled)
        }

        if runtimeSummary.jsBridgeExposedToJSNow
            || runtimeSummary.jsBridgeInjectionUnavailable == false
        {
            blockers.append(.jsBridgeExposed)
        }

        if runtimeSummary.runtimeDispatchAvailable
            || runtimeSummary.listenerRegistrationUnavailable == false
            || runtimeSummary.serviceWorkerWakeUnavailable == false
            || runtimeSummary.nativeMessagingBlocked == false
            || runtimeSummary.nativeMessagingProcessLaunchUnavailable == false
            || runtimeSummary.nativeMessagingPortUnavailable == false
            || runtimeSummary.contextLoadingUnavailable == false
        {
            blockers.append(.runtimeBridgeInvariantViolation)
        }

        if input.sdkCompatibility.canConstructDetachedContext == false {
            blockers.append(.sdkDetachedConstructionUnsupported)
        }

        if input.requestedContextLoading {
            blockers.append(.contextLoadingRequested)
        }

        if input.requestedControllerLoad {
            blockers.append(.controllerLoadRequested)
        }

        if input.requestedExtensionCodeExecution {
            blockers.append(.extensionCodeExecutionRequested)
        }

        if input.requestedUserScriptRegistration {
            blockers.append(.userScriptRegistrationRequested)
        }

        if input.requestedNativeMessagingLaunch {
            blockers.append(.nativeMessagingLaunchRequested)
        }

        if input.objectProbeDiagnostics?.runtimeLoadable ?? false
            || input.objectAcceptanceReport?.runtimeLoadable ?? false
            || emptyController.runtimeLoadable
            || input.runtimeBridgeReadinessReport?.runtimeLoadable ?? false
            || runtimeSummary.runtimeLoadable
        {
            blockers.append(.runtimeLoadabilityInvariantViolation)
        }

        diagnostics.append(
            "Object acceptance status: \(input.objectAcceptanceReport?.objectAcceptedByWebKit == true ? "accepted" : "not accepted")."
        )
        diagnostics.append(
            "Empty controller state: \(emptyController.controllerState.rawValue)."
        )
        diagnostics.append(
            "Profile data-store status: \(dataStoreStatus.status.rawValue)."
        )
        diagnostics.append(
            "Runtime bridge prerequisite status: \(runtimeSummary.status.rawValue)."
        )
        diagnostics.append(
            "SDK compatibility: \(input.sdkCompatibility.status.rawValue)."
        )

        warnings.append(
            "Context object creation remains detached and must not be interpreted as Chrome MV3 runtime support."
        )

        return decision(
            input: input,
            blockers: blockers,
            warnings: warnings + runtimeSummary.warnings,
            diagnostics: diagnostics
        )
    }

    private static func decision(
        input: ChromeMV3ContextCreationGateInput,
        blockers: [ChromeMV3ContextCreationGateBlocker],
        warnings: [String],
        diagnostics: [String]
    ) -> ChromeMV3ContextCreationGateDecision {
        let uniqueBlockers = Array(Set(blockers)).sorted {
            $0.rawValue < $1.rawValue
        }
        return ChromeMV3ContextCreationGateDecision(
            input: input,
            canCreateContextObjectNow: uniqueBlockers.isEmpty,
            canLoadContextNow: false,
            canExecuteExtensionCodeNow: false,
            runtimeLoadable: false,
            blockers: uniqueBlockers,
            blockingReasons:
                uniqueSorted(uniqueBlockers.map(\.reason)),
            warnings: uniqueSorted(warnings),
            diagnostics: uniqueSorted(diagnostics)
        )
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { $0.isEmpty == false })).sorted()
    }
}

struct ChromeMV3DetachedContextOwnerDiagnostics:
    Codable,
    Equatable,
    Sendable
{
    var state: ChromeMV3ContextCreationOwnerState
    var gateDecision: ChromeMV3ContextCreationGateDecision
    var contextObjectCreated: Bool
    var contextLoadedIntoController: Bool
    var controllerLoadCount: Int
    var extensionCodeExecuted: Bool
    var serviceWorkerWakeCount: Int
    var scriptInjectionCount: Int
    var nativeMessagingPortCount: Int
    var runtimeLoadable: Bool
    var canLoadContextNow: Bool
    var canExecuteExtensionCodeNow: Bool
    var generatedArtifactsDeleted: Bool
    var websiteDataCleared: Bool
    var existingWebViewsDetachedOrReattached: Bool
    var emptyControllerAffectedByTeardown: Bool
    var error: ChromeMV3ExtensionObjectProbeErrorDiagnostic?
    var blockingReasons: [String]
    var warnings: [String]
}

extension ChromeMV3DetachedContextOwnerDiagnostics {
    static func make(
        state: ChromeMV3ContextCreationOwnerState,
        gateDecision: ChromeMV3ContextCreationGateDecision,
        contextObjectCreated: Bool,
        error: ChromeMV3ExtensionObjectProbeErrorDiagnostic? = nil
    ) -> ChromeMV3DetachedContextOwnerDiagnostics {
        ChromeMV3DetachedContextOwnerDiagnostics(
            state: state,
            gateDecision: gateDecision,
            contextObjectCreated: contextObjectCreated,
            contextLoadedIntoController: false,
            controllerLoadCount: 0,
            extensionCodeExecuted: false,
            serviceWorkerWakeCount: 0,
            scriptInjectionCount: 0,
            nativeMessagingPortCount: 0,
            runtimeLoadable: false,
            canLoadContextNow: false,
            canExecuteExtensionCodeNow: false,
            generatedArtifactsDeleted: false,
            websiteDataCleared: false,
            existingWebViewsDetachedOrReattached: false,
            emptyControllerAffectedByTeardown: false,
            error: error,
            blockingReasons: gateDecision.blockingReasons,
            warnings: gateDecision.warnings
        )
    }
}

struct ChromeMV3ContextCreationGateReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var candidateID: String
    var detachedContextOwnerState: ChromeMV3ContextCreationOwnerState
    var canCreateContextObjectNow: Bool
    var contextObjectCreated: Bool
    var canLoadContextNow: Bool
    var contextLoadedIntoController: Bool
    var canExecuteExtensionCodeNow: Bool
    var runtimeLoadable: Bool
    var sdkCompatibilityStatus:
        ChromeMV3ContextCreationSDKCompatibilityStatus
}

struct ChromeMV3ContextCreationGateReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var candidateID: String
    var generatedRewrittenRootPath: String
    var objectProbeStatus: ChromeMV3ContextReadinessObjectProbeStatus
    var objectAcceptedByWebKit: Bool
    var objectAcceptanceStatus: ChromeMV3ContextReadinessAvailabilityStatus
    var acceptedWebExtensionObjectAvailable: Bool
    var controllerOwnerStatus: ChromeMV3ContextReadinessAvailabilityStatus
    var profileDataStoreIdentityStatus:
        ChromeMV3ContextReadinessDataStoreIdentityStatus
    var staleWebViewStatus:
        ChromeMV3ContextReadinessStaleNeedsRecreationStatus
    var sameControllerWebViewPrecondition:
        ChromeMV3ContextCreationSameControllerPrecondition
    var sdkCompatibilityStatus:
        ChromeMV3ContextCreationSDKCompatibility
    var detachedContextOwnerDiagnostics:
        ChromeMV3DetachedContextOwnerDiagnostics
    var runtimeBridgePrerequisitesSummary:
        ChromeMV3ContextCreationRuntimeBridgePrerequisitesSummary
    var canCreateContextObjectNow: Bool
    var contextObjectCreated: Bool
    var canLoadContextNow: Bool
    var contextLoadedIntoController: Bool
    var canExecuteExtensionCodeNow: Bool
    var extensionCodeExecuted: Bool
    var runtimeLoadable: Bool
    var whyExtensionCodeStillDoesNotExecute: [String]
    var blockers: [ChromeMV3ContextCreationGateBlocker]
    var blockingReasons: [String]
    var warnings: [String]
    var diagnostics: [String]
    var documentationSources:
        [ChromeMV3WebKitObjectAcceptanceDocumentationSource]

    var summary: ChromeMV3ContextCreationGateReportSummary {
        ChromeMV3ContextCreationGateReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            candidateID: candidateID,
            detachedContextOwnerState:
                detachedContextOwnerDiagnostics.state,
            canCreateContextObjectNow: canCreateContextObjectNow,
            contextObjectCreated: contextObjectCreated,
            canLoadContextNow: canLoadContextNow,
            contextLoadedIntoController: contextLoadedIntoController,
            canExecuteExtensionCodeNow: canExecuteExtensionCodeNow,
            runtimeLoadable: runtimeLoadable,
            sdkCompatibilityStatus: sdkCompatibilityStatus.status
        )
    }
}

enum ChromeMV3ContextCreationGateReportWriter {
    static let reportFileName = "runtime-context-creation-gate-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3ContextCreationGateReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3ContextCreationGateReport {
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

enum ChromeMV3ContextCreationGateReportGenerator {
    static func makeReport(
        decision: ChromeMV3ContextCreationGateDecision,
        detachedContextOwnerDiagnostics:
            ChromeMV3DetachedContextOwnerDiagnostics? = nil
    ) -> ChromeMV3ContextCreationGateReport {
        let input = decision.input
        let ownerDiagnostics = detachedContextOwnerDiagnostics
            ?? ChromeMV3DetachedContextOwnerDiagnostics.make(
                state:
                    decision.canCreateContextObjectNow
                        ? .notCreated
                        : .blocked,
                gateDecision: decision,
                contextObjectCreated: false
            )
        let dataStoreStatus =
            ChromeMV3ContextReadinessReportGenerator
            .dataStoreIdentityStatus(
                input.emptyControllerDiagnostics?
                    .dataStoreIdentityPolicy
            )
        let liveSnapshot = input.liveNormalTabAttachmentSnapshot
            ?? input.emptyControllerDiagnostics?
            .liveNormalTabAttachmentSnapshot
        let staleStatus = staleStatus(liveSnapshot)
        let runtimeSummary =
            ChromeMV3ContextCreationRuntimeBridgePrerequisitesSummary
            .make(readinessReport: input.runtimeBridgeReadinessReport)

        return ChromeMV3ContextCreationGateReport(
            schemaVersion: 1,
            id: id(
                candidateID: input.candidateID,
                generatedRewrittenRootPath:
                    input.generatedRewrittenRootPath,
                runtimeBridgeReadinessReportID:
                    input.runtimeBridgeReadinessReport?.id,
                state: ownerDiagnostics.state
            ),
            reportFileName:
                ChromeMV3ContextCreationGateReportWriter.reportFileName,
            candidateID: input.candidateID,
            generatedRewrittenRootPath:
                input.generatedRewrittenRootPath,
            objectProbeStatus:
                objectProbeStatus(input.objectProbeDiagnostics),
            objectAcceptedByWebKit:
                input.objectAcceptanceReport?.objectAcceptedByWebKit
                    ?? false,
            objectAcceptanceStatus:
                input.objectAcceptanceReport?.objectAcceptedByWebKit == true
                    ? .available
                    : .blocked,
            acceptedWebExtensionObjectAvailable:
                input.acceptedWebExtensionObjectAvailable,
            controllerOwnerStatus:
                controllerOwnerStatus(input.emptyControllerDiagnostics),
            profileDataStoreIdentityStatus: dataStoreStatus,
            staleWebViewStatus: staleStatus,
            sameControllerWebViewPrecondition:
                .make(liveSnapshot: liveSnapshot),
            sdkCompatibilityStatus: input.sdkCompatibility,
            detachedContextOwnerDiagnostics: ownerDiagnostics,
            runtimeBridgePrerequisitesSummary: runtimeSummary,
            canCreateContextObjectNow:
                decision.canCreateContextObjectNow,
            contextObjectCreated:
                ownerDiagnostics.contextObjectCreated,
            canLoadContextNow: false,
            contextLoadedIntoController: false,
            canExecuteExtensionCodeNow: false,
            extensionCodeExecuted: false,
            runtimeLoadable: false,
            whyExtensionCodeStillDoesNotExecute: [
                "The detached context owner never calls WKWebExtensionController load APIs.",
                "The context is not loaded into the empty controller.",
                "No service-worker wake, event dispatch, message port, native messaging, JS injection, or listener registration path is enabled.",
                "runtimeLoadable remains false.",
            ],
            blockers: decision.blockers,
            blockingReasons: decision.blockingReasons,
            warnings: decision.warnings,
            diagnostics: decision.diagnostics,
            documentationSources: documentationSources()
        )
    }

    private static func controllerOwnerStatus(
        _ diagnostics: ChromeMV3EmptyControllerDiagnostics?
    ) -> ChromeMV3ContextReadinessAvailabilityStatus {
        guard let diagnostics else { return .missing }
        let empty = diagnostics.controllerCreated
            && diagnostics.controllerState == .createdEmpty
            && diagnostics.contextCount == 0
            && diagnostics.loadedExtensionCount == 0
            && diagnostics.nativeMessagingPortCount == 0
            && diagnostics.pendingContextLoads == 0
            && diagnostics.pendingAttachments == 0
            && diagnostics.configurationWebViewUserScriptCount == 0
        return empty ? .available : .blocked
    }

    private static func objectProbeStatus(
        _ diagnostics: ChromeMV3ExtensionObjectProbeDiagnostics?
    ) -> ChromeMV3ContextReadinessObjectProbeStatus {
        guard let diagnostics else { return .reportMissing }
        switch diagnostics.state {
        case .notAttempted:
            return .notAttempted
        case .blocked:
            return .blocked
        case .created:
            return .created
        case .failed:
            return .failed
        case .released:
            return .released
        }
    }

    private static func staleStatus(
        _ snapshot: ChromeMV3LiveNormalTabAttachmentRecorderSnapshot?
    ) -> ChromeMV3ContextReadinessStaleNeedsRecreationStatus {
        let staleCount = snapshot?.staleOrNeedsRecreationCount ?? 0
        return ChromeMV3ContextReadinessStaleNeedsRecreationStatus(
            policy: staleCount > 0 ? .blocker : .clear,
            staleOrNeedsRecreationCount: staleCount,
            tabDiagnosticIdentifiers:
                snapshot?.staleOrNeedsRecreationTabDiagnosticIdentifiers
                    ?? [],
            blocksFutureContextEligibility: staleCount > 0,
            requiredFutureAction:
                staleCount > 0
                    ? "Recreate stale DEBUG-attached WebViews before any future context load."
                    : nil
        )
    }

    private static func documentationSources()
        -> [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    {
        [
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebExtensionContext",
                url: "https://developer.apple.com/documentation/webkit/wkwebextensioncontext",
                note: "A context is the runtime environment object; Sumi constructs it only detached in this gate."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebExtensionController",
                url: "https://developer.apple.com/documentation/webkit/wkwebextensioncontroller",
                note: "Controller load APIs start extension runtime behavior and remain forbidden here."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebViewConfiguration.webExtensionController",
                url: "https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/webextensioncontroller",
                note: "Future eligible tab WebViews must be configured with the matching controller before loading."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebExtensionTab.webView(for:)",
                url: "https://developer.apple.com/documentation/webkit/wkwebextensiontab/webview%28for%3A%29",
                note: "The tab WebView must use the same controller as the context controller."
            ),
            source(
                kind: "localAppleSDKHeaders",
                title: "MacOSX26.5 WebKit WKWebExtension headers",
                url: nil,
                note: "Headers expose initForExtension:/contextForExtension:, webExtensionController nil while detached, and " + "load" + "ExtensionContext:error: as the execution boundary."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Chrome extension service-worker lifecycle",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle",
                note: "MV3 service-worker wake and event dispatch remain unavailable in Sumi."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Chrome native messaging",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging",
                note: "Native messaging remains blocked and no native host process is launched."
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

    private static func id(
        candidateID: String,
        generatedRewrittenRootPath: String,
        runtimeBridgeReadinessReportID: String?,
        state: ChromeMV3ContextCreationOwnerState
    ) -> String {
        let seed = [
            "runtime-context-creation-gate",
            candidateID,
            generatedRewrittenRootPath,
            runtimeBridgeReadinessReportID
                ?? "missing-runtime-bridge-readiness",
            state.rawValue,
        ].joined(separator: "|")
        return "runtime-context-creation-gate-\(sha256Hex(Data(seed.utf8)).prefix(32))"
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private extension String {
    var isResolvedChromeMV3ContextProfile: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty == false
            && trimmed != ChromeMV3ProfileHost.unresolvedProfileIdentifier
    }
}
