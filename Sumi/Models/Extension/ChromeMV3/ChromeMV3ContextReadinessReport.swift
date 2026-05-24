//
//  ChromeMV3ContextReadinessReport.swift
//  Sumi
//
//  Deterministic preflight for a future WKWebExtensionContext creation gate.
//  This file is diagnostics-only: it does not import WebKit, allocate extension
//  objects, create contexts, load controllers, attach configurations, register
//  scripts, launch native messaging, or execute extension code.
//

import CryptoKit
import Foundation

enum ChromeMV3ContextReadinessBlocker:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case objectAcceptanceReportMissing
    case webKitObjectNotAccepted
    case objectAcceptanceBlockersPresent
    case emptyControllerDiagnosticsMissing
    case emptyControllerMissing
    case emptyControllerNotCreated
    case emptyControllerNoLongerEmpty
    case controllerDataStoreIdentityUnresolved
    case controllerDataStoreIdentityPlaceholder
    case controllerDataStoreIdentityMismatch
    case staleAttachedWebViewsPresent
    case auxiliarySurfaceAttached
    case loadabilityInvariantViolation
    case contextCreationInvariantViolation
    case controllerLoadingInvariantViolation
    case extensionExecutionInvariantViolation

    var reason: String {
        switch self {
        case .objectAcceptanceReportMissing:
            return "webkit-object-acceptance-report.json is missing for the generated-rewritten bundle."
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
            return "The controller is no longer empty; contexts, loaded extensions, pending loads, native ports, or registered scripts were observed."
        case .controllerDataStoreIdentityUnresolved:
            return "Controller data-store identity is unresolved."
        case .controllerDataStoreIdentityPlaceholder:
            return "Controller data-store identity is a diagnostic placeholder, not a profile policy match."
        case .controllerDataStoreIdentityMismatch:
            return "Controller data-store identity does not match the profile policy."
        case .staleAttachedWebViewsPresent:
            return "Stale DEBUG-attached normal-tab WebViews are present and require recreation before future context work."
        case .auxiliarySurfaceAttached:
            return "An auxiliary/helper surface was attached; only normal browsing surfaces may participate in future same-controller context work."
        case .loadabilityInvariantViolation:
            return "A loadability flag violated the false-only invariant."
        case .contextCreationInvariantViolation:
            return "Context creation was observed or reported before the context gate exists."
        case .controllerLoadingInvariantViolation:
            return "Controller loading was observed or reported before the loading gate exists."
        case .extensionExecutionInvariantViolation:
            return "Extension code execution, user-script registration, native messaging, or generated bundle loading was observed."
        }
    }
}

enum ChromeMV3ContextReadinessNextPromptCategory:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case fixObjectAcceptance
    case resolveStaleWebViews
    case addContextCreationGate
    case addRuntimeBridgePrerequisites
    case blockedByUnsupportedAPIs
}

enum ChromeMV3ContextReadinessObjectProbeStatus:
    String,
    Codable,
    Sendable
{
    case reportMissing
    case notAttempted
    case blocked
    case created
    case failed
    case released
}

enum ChromeMV3ContextReadinessAvailabilityStatus:
    String,
    Codable,
    Sendable
{
    case missing
    case unavailable
    case available
    case blocked
}

enum ChromeMV3ContextReadinessDataStoreStatus:
    String,
    Codable,
    Sendable
{
    case missing
    case unresolved
    case placeholder
    case mismatched
    case matched
}

enum ChromeMV3ContextReadinessStalePolicy:
    String,
    Codable,
    Sendable
{
    case blocker
    case warning
    case clear
}

struct ChromeMV3ContextReadinessEmptyControllerState:
    Codable,
    Equatable,
    Sendable
{
    var status: ChromeMV3ContextReadinessAvailabilityStatus
    var profileIdentifier: String?
    var controllerState: ChromeMV3EmptyControllerOwnerState?
    var controllerCreated: Bool
    var contextCount: Int
    var loadedExtensionCount: Int
    var attachedWebViewCount: Int
    var nativeMessagingPortCount: Int
    var pendingContextLoads: Int
    var pendingAttachments: Int
    var configurationWebViewHasControllerAttachment: Bool
    var configurationWebViewUserScriptCount: Int
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var blockingReasons: [String]
}

struct ChromeMV3ContextReadinessDataStoreIdentityStatus:
    Codable,
    Equatable,
    Sendable
{
    var status: ChromeMV3ContextReadinessDataStoreStatus
    var profileIdentifier: String?
    var dataStoreIdentityString: String?
    var dataStoreIdentityValue: String?
    var storageKind: ChromeMV3ControllerDataStoreStorageKind?
    var identityResolved: Bool
    var matchesProfilePolicy: Bool
    var usesNonPersistentControllerConfiguration: Bool
    var controllerConfigurationIdentityString: String?
    var notes: [String]
}

struct ChromeMV3ContextReadinessSameControllerStatus:
    Codable,
    Equatable,
    Sendable
{
    var status: ChromeMV3ContextReadinessAvailabilityStatus
    var futureContextControllerMustMatchTabWebViews: Bool
    var normalTabConfigurationsCanUseSameControllerInFuture: Bool
    var eligibleNormalBrowsingSurfaces: [ChromeMV3WebViewSurface]
    var extensionUIHostOnlySurfaces: [ChromeMV3WebViewSurface]
    var ineligibleSurfaces: [ChromeMV3WebViewSurface]
    var helperPreviewMiniFaviconDownloadSurfacesIneligible: Bool
    var requiredFutureActions: [String]
}

struct ChromeMV3ContextReadinessLiveAttachmentStatus:
    Codable,
    Equatable,
    Sendable
{
    var status: ChromeMV3ContextReadinessAvailabilityStatus
    var attachedConfigurationCount: Int
    var createdAttachedWebViewCount: Int
    var staleOrNeedsRecreationCount: Int
    var attachedTabDiagnosticIdentifiers: [String]
    var staleOrNeedsRecreationTabDiagnosticIdentifiers: [String]
    var accidentallyAttachedAuxiliarySurface: Bool
    var auxiliaryAttachmentSequenceNumbers: [Int]
    var contextLoadCalled: Bool
    var webExtensionCreated: Bool
    var webExtensionContextCreated: Bool
    var generatedExtensionBundleLoaded: Bool
    var nativeMessagingLaunched: Bool
}

struct ChromeMV3ContextReadinessStaleNeedsRecreationStatus:
    Codable,
    Equatable,
    Sendable
{
    var policy: ChromeMV3ContextReadinessStalePolicy
    var staleOrNeedsRecreationCount: Int
    var tabDiagnosticIdentifiers: [String]
    var blocksFutureContextEligibility: Bool
    var requiredFutureAction: String?
}

struct ChromeMV3ContextReadinessPasswordManagerBridge:
    Codable,
    Equatable,
    Sendable
{
    var objectAcceptedByWebKit: Bool
    var contentScriptsPresent: Bool
    var actionPopupPresent: Bool
    var hostPermissionsPresent: Bool
    var storagePermissionPresent: Bool
    var nativeMessagingPermissionPresent: Bool
    var nativeMessagingBridgeImplemented: Bool
    var nativeMessagingBlocked: Bool
    var runtimeMessagingBridgeImplemented: Bool
    var permissionBrokerActiveTabImplemented: Bool
    var controlledInputPageWorldBehaviorVerified: Bool
    var serviceWorkerLifecycleVerified: Bool
    var futureContextCreated: Bool
    var runtimeLoadable: Bool
    var blockers: [String]
    var deferredChecks: [String]
}

struct ChromeMV3ContextReadinessRuntimeBlockers:
    Codable,
    Equatable,
    Sendable
{
    var unsupportedAPIs: [ChromeMV3API]
    var deferredAPIs: [ChromeMV3API]
    var nativeMessagingBlockers: [String]
    var runtimeMessagingBlockers: [String]
    var storageBlockers: [String]
    var permissionActiveTabBlockers: [String]
    var serviceWorkerLifecycleBlockers: [String]
    var unsupportedDeferredAPIsRemainRuntimeBlockers: Bool
    var allRuntimeBlockers: [String]
}

struct ChromeMV3ContextReadinessReport: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var candidateID: String
    var generatedRewrittenRootPath: String
    var webKitObjectAcceptanceReportPath: String?
    var webKitObjectAcceptanceReportHash: String?
    var objectAcceptedByWebKit: Bool
    var objectAcceptanceBlockersResolved: Bool
    var objectProbeStatus: ChromeMV3ContextReadinessObjectProbeStatus
    var objectAcceptanceBlockingFindings:
        [ChromeMV3WebKitObjectAcceptanceFinding]
    var emptyControllerState:
        ChromeMV3ContextReadinessEmptyControllerState
    var controllerDataStoreIdentityStatus:
        ChromeMV3ContextReadinessDataStoreIdentityStatus
    var sameControllerFutureRequirementStatus:
        ChromeMV3ContextReadinessSameControllerStatus
    var liveNormalTabAttachmentStatus:
        ChromeMV3ContextReadinessLiveAttachmentStatus
    var staleNeedsRecreationStatus:
        ChromeMV3ContextReadinessStaleNeedsRecreationStatus
    var runtimeBlockers: ChromeMV3ContextReadinessRuntimeBlockers
    var passwordManagerReadiness:
        ChromeMV3ContextReadinessPasswordManagerBridge
    var canCreateContextNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var futureContextEligible: Bool
    var blockers: [ChromeMV3ContextReadinessBlocker]
    var blockingReasons: [String]
    var warnings: [String]
    var requiredFutureActions: [String]
    var nextRequiredPromptCategory:
        ChromeMV3ContextReadinessNextPromptCategory
    var documentationSources:
        [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
}

struct ChromeMV3ContextReadinessGateInput: Codable, Equatable, Sendable {
    var candidate: ChromeMV3RewrittenVariantCandidate
    var objectAcceptanceReport: ChromeMV3WebKitObjectAcceptanceReport?
    var objectAcceptanceReportPath: String?
    var objectAcceptanceReportSHA256: String?
    var objectProbeDiagnostics: ChromeMV3ExtensionObjectProbeDiagnostics?
    var emptyControllerDiagnostics: ChromeMV3EmptyControllerDiagnostics?
    var liveNormalTabAttachmentSnapshot:
        ChromeMV3LiveNormalTabAttachmentRecorderSnapshot?
    var runtimeLoadabilityReport: ChromeMV3RuntimeLoadabilityReport?
    var surfaceMappings: [ChromeMV3WebViewSurfaceMapping]
}

struct ChromeMV3ContextReadinessGateDecision:
    Codable,
    Equatable,
    Sendable
{
    var input: ChromeMV3ContextReadinessGateInput
    var canCreateContextNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var futureContextEligible: Bool
    var blockers: [ChromeMV3ContextReadinessBlocker]
    var blockingReasons: [String]
    var warnings: [String]
    var requiredFutureActions: [String]
    var nextRequiredPromptCategory:
        ChromeMV3ContextReadinessNextPromptCategory
}

enum ChromeMV3ContextReadinessGate {
    static func evaluate(
        input: ChromeMV3ContextReadinessGateInput
    ) -> ChromeMV3ContextReadinessGateDecision {
        let objectBlockingFindings = ChromeMV3ContextReadinessReportGenerator
            .objectAcceptanceBlockingFindings(in: input.objectAcceptanceReport)
        let emptyController = input.emptyControllerDiagnostics
        let liveSnapshot = input.liveNormalTabAttachmentSnapshot
            ?? emptyController?.liveNormalTabAttachmentSnapshot

        var blockers: [ChromeMV3ContextReadinessBlocker] = []
        var warnings: [String] = []
        var requiredFutureActions: [String] = [
            "Keep context creation disabled until a future explicit DEBUG/internal context-creation gate exists.",
            "Keep controller loading disabled until a later verified loading prompt exists.",
            "Keep runtimeLoadable false until context, loading, messaging, permission, and storage behavior are verified.",
        ]

        guard let objectAcceptanceReport = input.objectAcceptanceReport else {
            blockers.append(.objectAcceptanceReportMissing)
            requiredFutureActions.append(
                "Generate webkit-object-acceptance-report.json from the Prompt 20 object-acceptance preflight."
            )
            return decision(
                input: input,
                blockers: blockers,
                warnings: warnings,
                requiredFutureActions: requiredFutureActions
            )
        }

        if objectAcceptanceReport.objectAcceptedByWebKit == false {
            blockers.append(.webKitObjectNotAccepted)
            requiredFutureActions.append(
                "Fix generated-bundle or WebKit object-acceptance blockers before considering future context creation."
            )
        }

        if objectBlockingFindings.isEmpty == false {
            blockers.append(.objectAcceptanceBlockersPresent)
            requiredFutureActions.append(
                "Resolve all objectBlocking findings in webkit-object-acceptance-report.json."
            )
        }

        guard let emptyController else {
            blockers.append(.emptyControllerDiagnosticsMissing)
            requiredFutureActions.append(
                "Create and report a gated empty WKWebExtensionController owner before future context work."
            )
            return decision(
                input: input,
                blockers: blockers,
                warnings: warnings,
                requiredFutureActions: requiredFutureActions
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

        switch dataStoreStatus(
            emptyController.dataStoreIdentityPolicy
        ).status {
        case .matched:
            break
        case .missing:
            blockers.append(.controllerDataStoreIdentityUnresolved)
        case .unresolved:
            blockers.append(.controllerDataStoreIdentityUnresolved)
        case .placeholder:
            blockers.append(.controllerDataStoreIdentityPlaceholder)
        case .mismatched:
            blockers.append(.controllerDataStoreIdentityMismatch)
        }

        if let liveSnapshot {
            if liveSnapshot.staleOrNeedsRecreationCount > 0 {
                blockers.append(.staleAttachedWebViewsPresent)
                requiredFutureActions.append(
                    "Recreate stale DEBUG-attached normal-tab WebViews before any future context creation or loading attempt."
                )
            }

            if liveSnapshot.accidentallyAttachedAuxiliarySurface {
                blockers.append(.auxiliarySurfaceAttached)
            }

            if liveSnapshot.contextLoadCalled
                || liveSnapshot.generatedExtensionBundleLoaded
            {
                blockers.append(.controllerLoadingInvariantViolation)
            }

            if liveSnapshot.webExtensionContextCreated {
                blockers.append(.contextCreationInvariantViolation)
            }

            if liveSnapshot.nativeMessagingLaunched {
                blockers.append(.extensionExecutionInvariantViolation)
            }
        }

        if input.objectProbeDiagnostics?.runtimeLoadable ?? false
            || objectAcceptanceReport.runtimeLoadable
            || emptyController.runtimeLoadable
            || liveSnapshot?.runtimeLoadable ?? false
            || input.runtimeLoadabilityReport?.runtimeLoadable ?? false
        {
            blockers.append(.loadabilityInvariantViolation)
        }

        if input.objectProbeDiagnostics?.canCreateContextNow ?? false
            || objectAcceptanceReport.canCreateContextNow
        {
            blockers.append(.contextCreationInvariantViolation)
        }

        if input.objectProbeDiagnostics?.canLoadContextNow ?? false
            || objectAcceptanceReport.canLoadContextNow
            || emptyController.canLoadContextNow
            || liveSnapshot?.canLoadContextNow ?? false
        {
            blockers.append(.controllerLoadingInvariantViolation)
        }

        if input.objectProbeDiagnostics?.extensionCodeExecuted ?? false
            || (input.objectProbeDiagnostics?.userScriptRegistrationCount ?? 0) > 0
            || (input.objectProbeDiagnostics?.nativeMessagingPortCount ?? 0) > 0
            || input.objectProbeDiagnostics?.generatedBundleLoadedIntoController ?? false
        {
            blockers.append(.extensionExecutionInvariantViolation)
        }

        if input.runtimeLoadabilityReport == nil {
            warnings.append(
                "Runtime loadability report is missing; runtime blockers are incomplete."
            )
        }

        let runtimeBlockers =
            ChromeMV3ContextReadinessReportGenerator.runtimeBlockers(
                report: input.runtimeLoadabilityReport,
                objectAcceptanceReport: input.objectAcceptanceReport
            )
        if runtimeBlockers.unsupportedAPIs.isEmpty == false {
            requiredFutureActions.append(
                "Resolve unsupported Chrome MV3 APIs before any runtime loading prompt."
            )
        }
        if runtimeBlockers.nativeMessagingBlockers.isEmpty == false
            || runtimeBlockers.runtimeMessagingBlockers.isEmpty == false
            || runtimeBlockers.permissionActiveTabBlockers.isEmpty == false
            || runtimeBlockers.storageBlockers.isEmpty == false
        {
            requiredFutureActions.append(
                "Build runtime messaging, permission, activeTab, storage, and native-messaging prerequisites before claiming runtime support."
            )
        }

        return decision(
            input: input,
            blockers: blockers,
            warnings: warnings,
            requiredFutureActions: requiredFutureActions
        )
    }

    private static func decision(
        input: ChromeMV3ContextReadinessGateInput,
        blockers: [ChromeMV3ContextReadinessBlocker],
        warnings: [String],
        requiredFutureActions: [String]
    ) -> ChromeMV3ContextReadinessGateDecision {
        let uniqueBlockers = Array(Set(blockers)).sorted {
            $0.rawValue < $1.rawValue
        }
        return ChromeMV3ContextReadinessGateDecision(
            input: input,
            canCreateContextNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            futureContextEligible: uniqueBlockers.isEmpty,
            blockers: uniqueBlockers,
            blockingReasons: uniqueSorted(uniqueBlockers.map(\.reason)),
            warnings: uniqueSorted(warnings),
            requiredFutureActions: uniqueSorted(requiredFutureActions),
            nextRequiredPromptCategory:
                ChromeMV3ContextReadinessReportGenerator.nextPromptCategory(
                    blockers: uniqueBlockers,
                    runtimeBlockers:
                        ChromeMV3ContextReadinessReportGenerator
                        .runtimeBlockers(
                            report: input.runtimeLoadabilityReport,
                            objectAcceptanceReport:
                                input.objectAcceptanceReport
                        )
                )
        )
    }

    private static func dataStoreStatus(
        _ diagnostics: ChromeMV3ControllerDataStoreIdentityDiagnostics
    ) -> ChromeMV3ContextReadinessDataStoreIdentityStatus {
        ChromeMV3ContextReadinessReportGenerator
            .dataStoreIdentityStatus(diagnostics)
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { $0.isEmpty == false })).sorted()
    }
}

enum ChromeMV3ContextReadinessReportWriter {
    static let reportFileName = "context-readiness-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3ContextReadinessReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3ContextReadinessReport {
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

enum ChromeMV3ContextReadinessReportGenerator {
    struct ObjectAcceptanceReportLoadResult {
        var report: ChromeMV3WebKitObjectAcceptanceReport
        var path: String
        var sha256: String
    }

    static func loadObjectAcceptanceReport(
        fromRewrittenBundleRoot rootURL: URL
    ) -> ObjectAcceptanceReportLoadResult? {
        let reportURL = rootURL.standardizedFileURL
            .appendingPathComponent(
                ChromeMV3WebKitObjectAcceptanceReportWriter.reportFileName
            )
        guard let data = try? Data(contentsOf: reportURL),
              let report = try? JSONDecoder().decode(
                ChromeMV3WebKitObjectAcceptanceReport.self,
                from: data
              )
        else {
            return nil
        }
        return ObjectAcceptanceReportLoadResult(
            report: report,
            path: reportURL.path,
            sha256: sha256Hex(data)
        )
    }

    static func makeReport(
        candidate: ChromeMV3RewrittenVariantCandidate,
        objectAcceptanceReport: ChromeMV3WebKitObjectAcceptanceReport?,
        objectAcceptanceReportPath: String? = nil,
        objectAcceptanceReportSHA256: String? = nil,
        objectProbeDiagnostics: ChromeMV3ExtensionObjectProbeDiagnostics? = nil,
        emptyControllerDiagnostics: ChromeMV3EmptyControllerDiagnostics?,
        liveNormalTabAttachmentSnapshot:
            ChromeMV3LiveNormalTabAttachmentRecorderSnapshot? = nil,
        runtimeLoadabilityReport: ChromeMV3RuntimeLoadabilityReport?,
        surfaceMappings: [ChromeMV3WebViewSurfaceMapping] =
            ChromeMV3WebViewSurfaceInventory.currentSumiMappings
    ) -> ChromeMV3ContextReadinessReport {
        let input = ChromeMV3ContextReadinessGateInput(
            candidate: candidate,
            objectAcceptanceReport: objectAcceptanceReport,
            objectAcceptanceReportPath: objectAcceptanceReportPath,
            objectAcceptanceReportSHA256:
                objectAcceptanceReportSHA256
                    ?? hashForObjectAcceptanceReport(
                        objectAcceptanceReport
                    ),
            objectProbeDiagnostics: objectProbeDiagnostics,
            emptyControllerDiagnostics: emptyControllerDiagnostics,
            liveNormalTabAttachmentSnapshot:
                liveNormalTabAttachmentSnapshot,
            runtimeLoadabilityReport: runtimeLoadabilityReport,
            surfaceMappings: surfaceMappings
        )
        return makeReport(input: input)
    }

    static func makeReport(
        candidate: ChromeMV3RewrittenVariantCandidate,
        loadingObjectAcceptanceReportFrom rootURL: URL,
        objectProbeDiagnostics: ChromeMV3ExtensionObjectProbeDiagnostics? = nil,
        emptyControllerDiagnostics: ChromeMV3EmptyControllerDiagnostics?,
        liveNormalTabAttachmentSnapshot:
            ChromeMV3LiveNormalTabAttachmentRecorderSnapshot? = nil,
        runtimeLoadabilityReport: ChromeMV3RuntimeLoadabilityReport?,
        surfaceMappings: [ChromeMV3WebViewSurfaceMapping] =
            ChromeMV3WebViewSurfaceInventory.currentSumiMappings
    ) -> ChromeMV3ContextReadinessReport {
        let loaded = loadObjectAcceptanceReport(
            fromRewrittenBundleRoot: rootURL
        )
        return makeReport(
            candidate: candidate,
            objectAcceptanceReport: loaded?.report,
            objectAcceptanceReportPath: loaded?.path,
            objectAcceptanceReportSHA256: loaded?.sha256,
            objectProbeDiagnostics: objectProbeDiagnostics,
            emptyControllerDiagnostics: emptyControllerDiagnostics,
            liveNormalTabAttachmentSnapshot:
                liveNormalTabAttachmentSnapshot,
            runtimeLoadabilityReport: runtimeLoadabilityReport,
            surfaceMappings: surfaceMappings
        )
    }

    static func makeReport(
        input: ChromeMV3ContextReadinessGateInput
    ) -> ChromeMV3ContextReadinessReport {
        let decision = ChromeMV3ContextReadinessGate.evaluate(input: input)
        let runtimeBlockers = runtimeBlockers(
            report: input.runtimeLoadabilityReport,
            objectAcceptanceReport: input.objectAcceptanceReport
        )
        let liveSnapshot = input.liveNormalTabAttachmentSnapshot
            ?? input.emptyControllerDiagnostics?
            .liveNormalTabAttachmentSnapshot
        let objectBlockingFindings = objectAcceptanceBlockingFindings(
            in: input.objectAcceptanceReport
        )
        let rootPath = input.objectAcceptanceReport?
            .rewrittenBundleRootPath
            ?? input.candidate.rewrittenVariantRootPath

        return ChromeMV3ContextReadinessReport(
            schemaVersion: 1,
            id: reportID(
                candidate: input.candidate,
                rootPath: rootPath,
                objectAcceptanceReportSHA256:
                    input.objectAcceptanceReportSHA256
            ),
            reportFileName:
                ChromeMV3ContextReadinessReportWriter.reportFileName,
            candidateID: input.candidate.id,
            generatedRewrittenRootPath: rootPath,
            webKitObjectAcceptanceReportPath:
                input.objectAcceptanceReportPath,
            webKitObjectAcceptanceReportHash:
                input.objectAcceptanceReportSHA256,
            objectAcceptedByWebKit:
                input.objectAcceptanceReport?.objectAcceptedByWebKit ?? false,
            objectAcceptanceBlockersResolved:
                input.objectAcceptanceReport != nil
                    && objectBlockingFindings.isEmpty,
            objectProbeStatus: objectProbeStatus(
                report: input.objectAcceptanceReport,
                diagnostics: input.objectProbeDiagnostics
            ),
            objectAcceptanceBlockingFindings: objectBlockingFindings,
            emptyControllerState:
                emptyControllerState(input.emptyControllerDiagnostics),
            controllerDataStoreIdentityStatus:
                dataStoreIdentityStatus(
                    input.emptyControllerDiagnostics?
                    .dataStoreIdentityPolicy
                ),
            sameControllerFutureRequirementStatus:
                sameControllerStatus(
                    emptyControllerDiagnostics:
                        input.emptyControllerDiagnostics,
                    liveSnapshot: liveSnapshot,
                    surfaceMappings: input.surfaceMappings
                ),
            liveNormalTabAttachmentStatus:
                liveAttachmentStatus(liveSnapshot),
            staleNeedsRecreationStatus:
                staleStatus(liveSnapshot),
            runtimeBlockers: runtimeBlockers,
            passwordManagerReadiness:
                passwordManagerReadiness(
                    objectAcceptedByWebKit:
                        input.objectAcceptanceReport?
                        .objectAcceptedByWebKit ?? false,
                    report: input.runtimeLoadabilityReport
                ),
            canCreateContextNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            futureContextEligible: decision.futureContextEligible,
            blockers: decision.blockers,
            blockingReasons: decision.blockingReasons,
            warnings: decision.warnings,
            requiredFutureActions: decision.requiredFutureActions,
            nextRequiredPromptCategory:
                decision.nextRequiredPromptCategory,
            documentationSources: documentationSources()
        )
    }

    static func objectAcceptanceBlockingFindings(
        in report: ChromeMV3WebKitObjectAcceptanceReport?
    ) -> [ChromeMV3WebKitObjectAcceptanceFinding] {
        guard let report else { return [] }
        return report.classificationFindings
            .filter { $0.severity == .objectBlocking }
            .sorted(by: objectAcceptanceFindingSort)
    }

    static func dataStoreIdentityStatus(
        _ diagnostics: ChromeMV3ControllerDataStoreIdentityDiagnostics?
    ) -> ChromeMV3ContextReadinessDataStoreIdentityStatus {
        guard let diagnostics else {
            return ChromeMV3ContextReadinessDataStoreIdentityStatus(
                status: .missing,
                profileIdentifier: nil,
                dataStoreIdentityString: nil,
                dataStoreIdentityValue: nil,
                storageKind: nil,
                identityResolved: false,
                matchesProfilePolicy: false,
                usesNonPersistentControllerConfiguration: false,
                controllerConfigurationIdentityString: nil,
                notes: ["No data-store identity diagnostics were supplied."]
            )
        }

        let status: ChromeMV3ContextReadinessDataStoreStatus
        if diagnostics.identityResolved == false {
            status = .unresolved
        } else if diagnostics.storageKind == .placeholder {
            status = .placeholder
        } else if diagnostics.dataStoreIdentityValue
            != diagnostics.profileIdentifier
        {
            status = .mismatched
        } else if diagnostics.allowedForFuturePersistentProfileUse
            || diagnostics.allowedForFutureEphemeralPrivateProfileUse
        {
            status = .matched
        } else {
            status = .mismatched
        }

        return ChromeMV3ContextReadinessDataStoreIdentityStatus(
            status: status,
            profileIdentifier: diagnostics.profileIdentifier,
            dataStoreIdentityString: diagnostics.dataStoreIdentityString,
            dataStoreIdentityValue: diagnostics.dataStoreIdentityValue,
            storageKind: diagnostics.storageKind,
            identityResolved: diagnostics.identityResolved,
            matchesProfilePolicy: status == .matched,
            usesNonPersistentControllerConfiguration:
                diagnostics.usesNonPersistentControllerConfiguration,
            controllerConfigurationIdentityString:
                diagnostics.controllerConfigurationIdentityString,
            notes: diagnostics.notes
        )
    }

    static func runtimeBlockers(
        report: ChromeMV3RuntimeLoadabilityReport?,
        objectAcceptanceReport: ChromeMV3WebKitObjectAcceptanceReport?
    ) -> ChromeMV3ContextReadinessRuntimeBlockers {
        let unsupportedAPIs = uniqueSortedAPIs(
            (report?.unsupportedAPIs ?? [])
                + (objectAcceptanceReport?.staticInspection
                    .installReportUnsupportedAPIs ?? [])
        )
        let deferredAPIs = uniqueSortedAPIs(
            (report?.deferredAPIs ?? [])
                + (objectAcceptanceReport?.staticInspection
                    .installReportDeferredAPIs ?? [])
        )
        let allBlockers = uniqueSorted(
            (report?.blockers ?? [])
                + (objectAcceptanceReport?
                    .remainingRuntimeContextBlockers ?? [])
        )

        let password = report?.passwordManagerReadiness
        var nativeMessagingBlockers = allBlockers
            .filter {
                $0.localizedCaseInsensitiveContains("native")
            }
        if password?.nativeMessagingDetected == true {
            nativeMessagingBlockers.append(
                "nativeMessaging permission is present but the bridge is not implemented."
            )
        }

        var runtimeMessagingBlockers = allBlockers
            .filter {
                $0.localizedCaseInsensitiveContains("runtime messaging")
            }
        if password?.runtimeMessagingImplemented == false,
           password?.contentScriptsPresent == true
        {
            runtimeMessagingBlockers.append(
                "Runtime messaging bridge is not implemented."
            )
        }

        var storageBlockers = allBlockers
            .filter {
                $0.localizedCaseInsensitiveContains("storage")
            }
        if password?.storagePermissionPresent == true {
            storageBlockers.append(
                "Storage permission is present but storage behavior is not verified."
            )
        }

        var permissionBlockers = allBlockers
            .filter {
                $0.localizedCaseInsensitiveContains("permission")
                    || $0.localizedCaseInsensitiveContains("activeTab")
            }
        if password?.hostPermissionsPresent == true {
            permissionBlockers.append(
                "Host permissions are present but permission broker and activeTab behavior are not implemented."
            )
        }
        if deferredAPIs.contains(.permissions)
            || deferredAPIs.contains(.activeTab)
        {
            permissionBlockers.append(
                "permissions or activeTab remains deferred."
            )
        }

        var serviceWorkerBlockers = allBlockers
            .filter {
                $0.localizedCaseInsensitiveContains("service-worker")
                    || $0.localizedCaseInsensitiveContains("service worker")
            }
        if password?.serviceWorkerLifecycleVerified == false,
           password?.contentScriptsPresent == true
        {
            serviceWorkerBlockers.append(
                "Service-worker lifecycle is not verified."
            )
        }

        return ChromeMV3ContextReadinessRuntimeBlockers(
            unsupportedAPIs: unsupportedAPIs,
            deferredAPIs: deferredAPIs,
            nativeMessagingBlockers:
                uniqueSorted(nativeMessagingBlockers),
            runtimeMessagingBlockers:
                uniqueSorted(runtimeMessagingBlockers),
            storageBlockers: uniqueSorted(storageBlockers),
            permissionActiveTabBlockers:
                uniqueSorted(permissionBlockers),
            serviceWorkerLifecycleBlockers:
                uniqueSorted(serviceWorkerBlockers),
            unsupportedDeferredAPIsRemainRuntimeBlockers:
                unsupportedAPIs.isEmpty == false
                    || deferredAPIs.isEmpty == false,
            allRuntimeBlockers: allBlockers
        )
    }

    static func nextPromptCategory(
        blockers: [ChromeMV3ContextReadinessBlocker],
        runtimeBlockers: ChromeMV3ContextReadinessRuntimeBlockers
    ) -> ChromeMV3ContextReadinessNextPromptCategory {
        let blockerSet = Set(blockers)
        if blockerSet.contains(.objectAcceptanceReportMissing)
            || blockerSet.contains(.webKitObjectNotAccepted)
            || blockerSet.contains(.objectAcceptanceBlockersPresent)
        {
            return .fixObjectAcceptance
        }

        if blockerSet.contains(.staleAttachedWebViewsPresent) {
            return .resolveStaleWebViews
        }

        if runtimeBlockers.unsupportedAPIs.isEmpty == false {
            return .blockedByUnsupportedAPIs
        }

        if runtimeBlockers.nativeMessagingBlockers.isEmpty == false
            || runtimeBlockers.runtimeMessagingBlockers.isEmpty == false
            || runtimeBlockers.storageBlockers.isEmpty == false
            || runtimeBlockers.permissionActiveTabBlockers.isEmpty == false
            || runtimeBlockers.serviceWorkerLifecycleBlockers.isEmpty == false
        {
            return .addRuntimeBridgePrerequisites
        }

        return .addContextCreationGate
    }

    private static func objectProbeStatus(
        report: ChromeMV3WebKitObjectAcceptanceReport?,
        diagnostics: ChromeMV3ExtensionObjectProbeDiagnostics?
    ) -> ChromeMV3ContextReadinessObjectProbeStatus {
        if let diagnostics {
            return status(for: diagnostics.state)
        }
        guard let report else { return .reportMissing }
        return status(for: report.probeResult)
    }

    private static func status(
        for state: ChromeMV3ExtensionObjectProbeState
    ) -> ChromeMV3ContextReadinessObjectProbeStatus {
        switch state {
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

    private static func emptyControllerState(
        _ diagnostics: ChromeMV3EmptyControllerDiagnostics?
    ) -> ChromeMV3ContextReadinessEmptyControllerState {
        guard let diagnostics else {
            return ChromeMV3ContextReadinessEmptyControllerState(
                status: .missing,
                profileIdentifier: nil,
                controllerState: nil,
                controllerCreated: false,
                contextCount: 0,
                loadedExtensionCount: 0,
                attachedWebViewCount: 0,
                nativeMessagingPortCount: 0,
                pendingContextLoads: 0,
                pendingAttachments: 0,
                configurationWebViewHasControllerAttachment: false,
                configurationWebViewUserScriptCount: 0,
                canLoadContextNow: false,
                runtimeLoadable: false,
                blockingReasons: [
                    "Empty controller diagnostics were not supplied.",
                ]
            )
        }

        let empty = diagnostics.controllerCreated
            && diagnostics.controllerState == .createdEmpty
            && diagnostics.contextCount == 0
            && diagnostics.loadedExtensionCount == 0
            && diagnostics.nativeMessagingPortCount == 0
            && diagnostics.pendingContextLoads == 0
            && diagnostics.pendingAttachments == 0
            && diagnostics.configurationWebViewUserScriptCount == 0

        return ChromeMV3ContextReadinessEmptyControllerState(
            status: empty ? .available : .blocked,
            profileIdentifier: diagnostics.profileIdentifier,
            controllerState: diagnostics.controllerState,
            controllerCreated: diagnostics.controllerCreated,
            contextCount: diagnostics.contextCount,
            loadedExtensionCount: diagnostics.loadedExtensionCount,
            attachedWebViewCount: diagnostics.attachedWebViewCount,
            nativeMessagingPortCount: diagnostics.nativeMessagingPortCount,
            pendingContextLoads: diagnostics.pendingContextLoads,
            pendingAttachments: diagnostics.pendingAttachments,
            configurationWebViewHasControllerAttachment:
                diagnostics.configurationWebViewHasControllerAttachment,
            configurationWebViewUserScriptCount:
                diagnostics.configurationWebViewUserScriptCount,
            canLoadContextNow: false,
            runtimeLoadable: false,
            blockingReasons: diagnostics.blockingReasons
        )
    }

    private static func sameControllerStatus(
        emptyControllerDiagnostics: ChromeMV3EmptyControllerDiagnostics?,
        liveSnapshot: ChromeMV3LiveNormalTabAttachmentRecorderSnapshot?,
        surfaceMappings: [ChromeMV3WebViewSurfaceMapping]
    ) -> ChromeMV3ContextReadinessSameControllerStatus {
        let staleCount = liveSnapshot?.staleOrNeedsRecreationCount ?? 0
        let emptyControllerAvailable =
            emptyControllerDiagnostics?.controllerCreated == true
                && emptyControllerDiagnostics?.controllerState
                    == .createdEmpty
        let dataStoreMatches = dataStoreIdentityStatus(
            emptyControllerDiagnostics?.dataStoreIdentityPolicy
        ).matchesProfilePolicy
        let canUseSameController = emptyControllerAvailable
            && dataStoreMatches
            && staleCount == 0
            && liveSnapshot?.accidentallyAttachedAuxiliarySurface != true

        let eligibleNormalBrowsing = uniqueSortedSurfaces(
            surfaceMappings
                .filter { $0.futureEligibility == .futureEligible }
                .map(\.surface)
        )
        let extensionUIHostOnly = uniqueSortedSurfaces(
            surfaceMappings
                .filter {
                    $0.futureEligibility
                        == .futureEligibleThroughExtensionUIHostOnly
                }
                .map(\.surface)
        )
        let ineligible = uniqueSortedSurfaces(
            surfaceMappings
                .filter {
                    $0.futureEligibility == .notEligible
                        || $0.futureEligibility == .neverEligible
                        || $0.futureEligibility
                            == .eligibleAfterPromotionAndReevaluation
                }
                .map(\.surface)
        )

        return ChromeMV3ContextReadinessSameControllerStatus(
            status: canUseSameController ? .available : .blocked,
            futureContextControllerMustMatchTabWebViews: true,
            normalTabConfigurationsCanUseSameControllerInFuture:
                canUseSameController,
            eligibleNormalBrowsingSurfaces: eligibleNormalBrowsing,
            extensionUIHostOnlySurfaces: extensionUIHostOnly,
            ineligibleSurfaces: ineligible,
            helperPreviewMiniFaviconDownloadSurfacesIneligible: true,
            requiredFutureActions: [
                "Future context/controller must match the controller assigned to eligible tab WKWebViewConfiguration instances.",
                "Normal-tab WebViews can participate only when their configurations were created with the same controller.",
                "Stale DEBUG-attached WebViews must be recreated before they can be considered eligible.",
                "Helper, preview, mini-window, favicon, download, and extension-owned auxiliary surfaces remain ineligible for normal-tab same-controller participation.",
            ]
        )
    }

    private static func liveAttachmentStatus(
        _ snapshot: ChromeMV3LiveNormalTabAttachmentRecorderSnapshot?
    ) -> ChromeMV3ContextReadinessLiveAttachmentStatus {
        guard let snapshot else {
            return ChromeMV3ContextReadinessLiveAttachmentStatus(
                status: .missing,
                attachedConfigurationCount: 0,
                createdAttachedWebViewCount: 0,
                staleOrNeedsRecreationCount: 0,
                attachedTabDiagnosticIdentifiers: [],
                staleOrNeedsRecreationTabDiagnosticIdentifiers: [],
                accidentallyAttachedAuxiliarySurface: false,
                auxiliaryAttachmentSequenceNumbers: [],
                contextLoadCalled: false,
                webExtensionCreated: false,
                webExtensionContextCreated: false,
                generatedExtensionBundleLoaded: false,
                nativeMessagingLaunched: false
            )
        }

        let blocked = snapshot.staleOrNeedsRecreationCount > 0
            || snapshot.accidentallyAttachedAuxiliarySurface
            || snapshot.contextLoadCalled
            || snapshot.webExtensionContextCreated
            || snapshot.generatedExtensionBundleLoaded
            || snapshot.nativeMessagingLaunched

        return ChromeMV3ContextReadinessLiveAttachmentStatus(
            status: blocked ? .blocked : .available,
            attachedConfigurationCount: snapshot.attachedConfigurationCount,
            createdAttachedWebViewCount:
                snapshot.createdAttachedWebViewCount,
            staleOrNeedsRecreationCount:
                snapshot.staleOrNeedsRecreationCount,
            attachedTabDiagnosticIdentifiers:
                snapshot.attachedTabDiagnosticIdentifiers,
            staleOrNeedsRecreationTabDiagnosticIdentifiers:
                snapshot.staleOrNeedsRecreationTabDiagnosticIdentifiers,
            accidentallyAttachedAuxiliarySurface:
                snapshot.accidentallyAttachedAuxiliarySurface,
            auxiliaryAttachmentSequenceNumbers:
                snapshot.auxiliaryAttachmentSequenceNumbers,
            contextLoadCalled: snapshot.contextLoadCalled,
            webExtensionCreated: snapshot.webExtensionCreated,
            webExtensionContextCreated: snapshot.webExtensionContextCreated,
            generatedExtensionBundleLoaded:
                snapshot.generatedExtensionBundleLoaded,
            nativeMessagingLaunched: snapshot.nativeMessagingLaunched
        )
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
            requiredFutureAction: staleCount > 0
                ? "Recreate stale DEBUG-attached WebViews before a future context creation or loading attempt."
                : nil
        )
    }

    private static func passwordManagerReadiness(
        objectAcceptedByWebKit: Bool,
        report: ChromeMV3RuntimeLoadabilityReport?
    ) -> ChromeMV3ContextReadinessPasswordManagerBridge {
        let readiness = report?.passwordManagerReadiness
        var blockers = readiness?.blockers ?? []
        if readiness?.nativeMessagingDetected == true {
            blockers.append(
                "nativeMessaging permission is present but bridge implementation is deferred."
            )
        }
        if readiness?.hostPermissionsPresent == true {
            blockers.append(
                "Host permissions are present but permission broker and activeTab behavior are deferred."
            )
        }
        if readiness?.storagePermissionPresent == true {
            blockers.append(
                "Storage permission is present but storage behavior is not verified."
            )
        }

        return ChromeMV3ContextReadinessPasswordManagerBridge(
            objectAcceptedByWebKit: objectAcceptedByWebKit,
            contentScriptsPresent: readiness?.contentScriptsPresent ?? false,
            actionPopupPresent: readiness?.actionPopupPresent ?? false,
            hostPermissionsPresent:
                readiness?.hostPermissionsPresent ?? false,
            storagePermissionPresent:
                readiness?.storagePermissionPresent ?? false,
            nativeMessagingPermissionPresent:
                readiness?.nativeMessagingDetected ?? false,
            nativeMessagingBridgeImplemented: false,
            nativeMessagingBlocked:
                readiness?.nativeMessagingBlocked ?? false,
            runtimeMessagingBridgeImplemented:
                readiness?.runtimeMessagingImplemented ?? false,
            permissionBrokerActiveTabImplemented: false,
            controlledInputPageWorldBehaviorVerified:
                readiness?.controlledInputPageWorldBehaviorVerified
                    ?? false,
            serviceWorkerLifecycleVerified:
                readiness?.serviceWorkerLifecycleVerified ?? false,
            futureContextCreated: false,
            runtimeLoadable: false,
            blockers: uniqueSorted(blockers),
            deferredChecks: uniqueSorted(readiness?.deferredChecks ?? [])
        )
    }

    private static func hashForObjectAcceptanceReport(
        _ report: ChromeMV3WebKitObjectAcceptanceReport?
    ) -> String? {
        guard let report,
              let data = try? ChromeMV3DeterministicJSON.encodedData(report)
        else {
            return nil
        }
        return sha256Hex(data)
    }

    private static func reportID(
        candidate: ChromeMV3RewrittenVariantCandidate,
        rootPath: String,
        objectAcceptanceReportSHA256: String?
    ) -> String {
        let seed = [
            candidate.id,
            rootPath,
            objectAcceptanceReportSHA256 ?? "missing-object-report",
            candidate.runtimeLoadabilityReportSHA256
                ?? "missing-runtime-report-hash",
        ].joined(separator: "|")
        return "context-readiness-\(sha256Hex(Data(seed.utf8)).prefix(32))"
    }

    private static func documentationSources()
        -> [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    {
        [
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebExtensionController",
                url: "https://developer.apple.com/documentation/webkit/wkwebextensioncontroller",
                note: "A controller manages loaded extension contexts and is associated with WKWebViewConfiguration.webExtensionController."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebExtensionContext",
                url: "https://developer.apple.com/documentation/webkit/wkwebextensioncontext",
                note: "A context represents an extension runtime environment; Sumi does not create one in this preflight."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebExtensionController.Configuration",
                url: "https://developer.apple.com/documentation/webkit/wkwebextensioncontroller/configuration",
                note: "Persistent, non-persistent, and unique persistent controller storage configuration shapes inform profile policy."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebViewConfiguration.webExtensionController",
                url: "https://developer.apple.com/documentation/webkit/wkwebviewconfiguration/webextensioncontroller",
                note: "Eligible tab configurations must be associated with the future matching controller before WebViews are created."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebExtensionTab.webView(for:)",
                url: "https://developer.apple.com/documentation/webkit/wkwebextensiontab/webview%28for%3A%29",
                note: "The tab WebView's configuration must use the same controller as the context controller."
            ),
            source(
                kind: "localAppleSDKHeaders",
                title: "MacOSX26.5 WebKit WKWebExtension headers",
                url: nil,
                note: "Local SDK headers confirm load(_:) starts background content/injection and confirm same-controller tab WebView requirements."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Chrome runtime API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/runtime",
                note: "Runtime messaging and service-worker lifecycle remain runtime prerequisites, not support claims."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Chrome native messaging",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging",
                note: "nativeMessaging requires declared permission and a native host bridge; Sumi does not launch one here."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Chrome message passing",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/messaging",
                note: "Message passing between content scripts, extension pages, and service workers remains unimplemented for runtime support."
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

    private static func objectAcceptanceFindingSort(
        _ lhs: ChromeMV3WebKitObjectAcceptanceFinding,
        _ rhs: ChromeMV3WebKitObjectAcceptanceFinding
    ) -> Bool {
        if lhs.category == rhs.category {
            if lhs.severity == rhs.severity {
                if lhs.source == rhs.source {
                    return lhs.message < rhs.message
                }
                return lhs.source < rhs.source
            }
            return lhs.severity < rhs.severity
        }
        return lhs.category < rhs.category
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { $0.isEmpty == false })).sorted()
    }

    private static func uniqueSortedAPIs(
        _ values: [ChromeMV3API]
    ) -> [ChromeMV3API] {
        Array(Set(values)).sorted()
    }

    private static func uniqueSortedSurfaces(
        _ values: [ChromeMV3WebViewSurface]
    ) -> [ChromeMV3WebViewSurface] {
        Array(Set(values)).sorted { $0.rawValue < $1.rawValue }
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
