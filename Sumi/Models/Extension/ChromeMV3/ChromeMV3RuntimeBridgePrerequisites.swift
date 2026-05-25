//
//  ChromeMV3RuntimeBridgePrerequisites.swift
//  Sumi
//
//  Deterministic prerequisite reports for the addRuntimeBridgePrerequisites
//  branch. This layer records non-executing future-runtime requirements only;
//  it does not import WebKit, create contexts, load controllers, inject
//  scripts, launch native messaging, or execute extension code.
//

import CryptoKit
import Foundation

enum ChromeMV3RuntimeBridgePrerequisiteCategory:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case runtimeMessaging
    case nativeMessaging
    case storage
    case permissionsAndActiveTab
    case serviceWorkerLifecycle
    case contextCreationDeferred
    case controllerLoadingDeferred

    static func < (
        lhs: ChromeMV3RuntimeBridgePrerequisiteCategory,
        rhs: ChromeMV3RuntimeBridgePrerequisiteCategory
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3RuntimeBridgePrerequisite:
    Codable,
    Equatable,
    Sendable
{
    var category: ChromeMV3RuntimeBridgePrerequisiteCategory
    var required: Bool
    var blockers: [String]
    var requiredFutureAction: String
    var nonExecuting: Bool
}

struct ChromeMV3RuntimeBridgePrerequisitePlan:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var sourceContextReadinessReportID: String
    var sourceContextReadinessReportPath: String
    var nextRequiredPromptCategory:
        ChromeMV3ContextReadinessNextPromptCategory?
    var canRecordPrerequisitesNow: Bool
    var branchImplemented:
        ChromeMV3ContextReadinessNextPromptCategory?
    var prerequisites: [ChromeMV3RuntimeBridgePrerequisite]
    var runtimeLoadable: Bool
    var canLoadContextNow: Bool
    var contextCreationAllowed: Bool
    var controllerLoadAllowed: Bool
    var extensionCodeExecutionAllowed: Bool
    var userScriptRegistrationAllowed: Bool
    var nativeMessagingLaunchAllowed: Bool
    var blockingReasons: [String]
    var warnings: [String]
}

enum ChromeMV3RuntimeBridgePrerequisitesNextRequiredCategory:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case blockedByContextReadinessReport
    case implementRuntimeBridgeComponents
    case resolveUnsupportedAPIs
}

enum ChromeMV3RuntimeBridgeManifestReadStatus:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case loaded
    case missing
    case unreadable
    case corrupt
}

struct ChromeMV3RuntimeBridgeManifestFacts:
    Codable,
    Equatable,
    Sendable
{
    var manifestReadStatus: ChromeMV3RuntimeBridgeManifestReadStatus
    var manifestPath: String
    var manifestSHA256: String?
    var declaredPermissions: [String]
    var optionalPermissions: [String]
    var hostPermissions: [String]
    var optionalHostPermissions: [String]
    var contentScriptsPresent: Bool
    var contentScriptMatchPatterns: [String]
    var actionPopupPresent: Bool
    var backgroundServiceWorkerPresent: Bool
    var storagePermissionPresent: Bool
    var nativeMessagingPermissionPresent: Bool
    var activeTabPermissionPresent: Bool
    var permissionsAPIPresent: Bool
    var warnings: [String]
}

enum ChromeMV3RuntimeBridgeContractStatus:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case modeled
    case blocked
    case notImplemented
}

struct ChromeMV3RuntimeMessagingRouteContract:
    Codable,
    Equatable,
    Sendable
{
    var route: String
    var requiredAPI: String
    var requiresServiceWorkerWakePolicy: Bool
    var requiresTabAddressing: Bool
    var implementedNow: Bool
    var blockedReason: String
}

struct ChromeMV3RuntimeMessagingContract:
    Codable,
    Equatable,
    Sendable
{
    var status: ChromeMV3RuntimeBridgeContractStatus
    var implementedNow: Bool
    var dispatchImplemented: Bool
    var listenerDeliveryImplemented: Bool
    var callbackCompatibilityRequired: Bool
    var promiseCompatibilityRequired: Bool
    var lastErrorRequirement: String
    var timeoutPolicyRequired: Bool
    var timeoutPolicy: String
    var routes: [ChromeMV3RuntimeMessagingRouteContract]
    var portLifecycleRequirements: [String]
    var disconnectReasons: [String]
    var contentScriptMessagingRestrictions: [String]
    var requiredBeforePasswordManagerSupport: Bool
    var requiredBeforeRuntimeLoadability: Bool
    var blockers: [String]
    var futureTestsNeeded: [String]
}

struct ChromeMV3NativeMessagingPrerequisites:
    Codable,
    Equatable,
    Sendable
{
    var status: ChromeMV3RuntimeBridgeContractStatus
    var nativeMessagingDetected: Bool
    var nativeMessagingBlocked: Bool
    var hostManifestLookupImplemented: Bool
    var hostValidationImplemented: Bool
    var userConsentImplemented: Bool
    var processLaunchImplemented: Bool
    var stdioFramingRequired: Bool
    var inboundHostMessageLimitBytes: Int
    var outboundHostMessageLimitBytes: Int64
    var portLifecycleModeled: Bool
    var hostExitBehaviorModeled: Bool
    var disabledModuleBehavior: String
    var noLaunchWhileExtensionsDisabled: Bool
    var noLaunchBeforeExplicitImplementation: Bool
    var requiredBeforePasswordManagerSupport: Bool
    var futureSecurityReviewRequired: Bool
    var blockers: [String]
    var hostManifestLookupRequirements: [String]
    var allowedHostValidationRequirements: [String]
    var futureTestsNeeded: [String]
}

enum ChromeMV3StorageAreaName:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case local
    case session
    case sync

    static func < (
        lhs: ChromeMV3StorageAreaName,
        rhs: ChromeMV3StorageAreaName
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3StorageAreaPrerequisite:
    Codable,
    Equatable,
    Sendable
{
    var area: ChromeMV3StorageAreaName
    var required: Bool
    var implementedNow: Bool
    var persistenceExpectation: String
    var contentScriptExposureDefault: String
    var decisionRequired: String
    var blockers: [String]
}

struct ChromeMV3StoragePrerequisites:
    Codable,
    Equatable,
    Sendable
{
    var status: ChromeMV3RuntimeBridgeContractStatus
    var storagePermissionPresent: Bool
    var implementedNow: Bool
    var webKitBehaviorSufficientWithoutHostLayer: Bool
    var hostBackedLayerDecisionRequired: Bool
    var profileIsolationVerified: Bool
    var workerUnloadReloadStateVerified: Bool
    var passwordManagerStateRequirements: [String]
    var areas: [ChromeMV3StorageAreaPrerequisite]
    var blockers: [String]
    var futureTestsNeeded: [String]
}

struct ChromeMV3PermissionsActiveTabPrerequisites:
    Codable,
    Equatable,
    Sendable
{
    var status: ChromeMV3RuntimeBridgeContractStatus
    var requiredPermissions: [String]
    var optionalPermissions: [String]
    var hostPermissions: [String]
    var optionalHostPermissions: [String]
    var activeTabDeclared: Bool
    var permissionBrokerImplemented: Bool
    var activeTabImplemented: Bool
    var hostPermissionEvaluationImplemented: Bool
    var userGestureRequirementModeled: Bool
    var grantLifetimeRequirement: String
    var tabNavigationInvalidationRequirement: String
    var permissionPromptUIFutureRequirement: Bool
    var contentScriptExecutionInteraction: String
    var passwordManagerHostAccessRequirement: String
    var requiredBeforeContentScriptExecution: Bool
    var requiredBeforePasswordManagerSupport: Bool
    var blockers: [String]
    var futureTestsNeeded: [String]
}

struct ChromeMV3ServiceWorkerLifecycleReadiness:
    Codable,
    Equatable,
    Sendable
{
    var status: ChromeMV3RuntimeBridgeContractStatus
    var lifecycleCoordinatorImplemented: Bool
    var serviceWorkerWakeImplemented: Bool
    var idleUnloadPolicyModeled: Bool
    var permanentBackgroundForbidden: Bool
    var requiredBeforeContextLoad: Bool
    var requiredBeforeContextLoadReason: String
    var requiredBeforeRuntimeLoadability: Bool
    var wakeReasonsRequired: [String]
    var eventDispatchPrerequisites: [String]
    var idleReleasePolicy: String
    var hardTimeoutPolicy: String
    var longLivedPortPolicy: String
    var nativeMessagingPortPolicy: String
    var alarmWakePolicy: String
    var statePersistenceRequirements: [String]
    var diagnosticsRequired: [String]
    var blockers: [String]
    var futureTestsNeeded: [String]
}

struct ChromeMV3PasswordManagerPrerequisiteSummary:
    Codable,
    Equatable,
    Sendable
{
    var contentScriptsPresent: Bool
    var actionPopupPresent: Bool
    var hostPermissionsPresent: Bool
    var storagePermissionPresent: Bool
    var nativeMessagingPermissionPresent: Bool
    var runtimeMessagingMissing: Bool
    var permissionActiveTabMissing: Bool
    var storageBackendMissingOrDeferred: Bool
    var nativeMessagingMissing: Bool
    var controlledInputPageWorldBehaviorNotVerified: Bool
    var serviceWorkerLifecycleNotVerified: Bool
    var passwordManagerSupportReady: Bool
    var blockers: [String]
    var deferredChecks: [String]
}

struct ChromeMV3UnsupportedDeferredAPISummary:
    Codable,
    Equatable,
    Sendable
{
    var unsupportedAPIs: [ChromeMV3API]
    var deferredAPIs: [ChromeMV3API]
    var unsupportedDeferredAPIsRemainRuntimeBlockers: Bool
}

struct ChromeMV3RuntimeBridgePrerequisitesReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var candidateID: String
    var generatedRewrittenRootPath: String
    var contextReadinessReportID: String
    var contextReadinessReportPath: String
    var contextReadinessReportHash: String
    var contextReadinessConsumerDiagnostic:
        ChromeMV3ContextReadinessReportConsumptionDiagnostic
    var manifestFacts: ChromeMV3RuntimeBridgeManifestFacts
    var runtimeMessagingPrerequisites: ChromeMV3RuntimeMessagingContract
    var nativeMessagingPrerequisites: ChromeMV3NativeMessagingPrerequisites
    var storagePrerequisites: ChromeMV3StoragePrerequisites
    var permissionsActiveTabPrerequisites:
        ChromeMV3PermissionsActiveTabPrerequisites
    var serviceWorkerLifecyclePrerequisites:
        ChromeMV3ServiceWorkerLifecycleReadiness
    var passwordManagerPrerequisiteSummary:
        ChromeMV3PasswordManagerPrerequisiteSummary
    var unsupportedDeferredAPIs: ChromeMV3UnsupportedDeferredAPISummary
    var modeledOnlyComponents: [String]
    var blockedComponents: [String]
    var requiredFutureComponents: [String]
    var unsupportedOrDeferredAPIs: [ChromeMV3API]
    var canCreateContextNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var contextCreationBlockedReason: String
    var contextLoadingBlockedReason: String
    var runtimeLoadableFalseReason: String
    var nextRequiredCategoryAfterThisReport:
        ChromeMV3RuntimeBridgePrerequisitesNextRequiredCategory
    var documentationSources: [ChromeMV3ManifestRewritePreviewSource]
    var warnings: [String]
}

enum ChromeMV3RuntimeBridgePrerequisitesReportError:
    LocalizedError,
    CustomStringConvertible,
    Equatable
{
    case missingContextReadinessReport(String)
    case unreadableContextReadinessReport(String)
    case corruptContextReadinessReport(String)

    var errorDescription: String? {
        switch self {
        case .missingContextReadinessReport(let path):
            return "Missing Chrome MV3 context-readiness report: \(path)"
        case .unreadableContextReadinessReport(let reason):
            return "Unable to read Chrome MV3 context-readiness report: \(reason)"
        case .corruptContextReadinessReport(let reason):
            return "Chrome MV3 context-readiness report is corrupt: \(reason)"
        }
    }

    var description: String {
        errorDescription ?? String(describing: self)
    }
}

enum ChromeMV3RuntimeBridgePrerequisitesReportWriter {
    static let reportFileName = "runtime-bridge-prerequisites-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3RuntimeBridgePrerequisitesReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3RuntimeBridgePrerequisitesReport {
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

enum ChromeMV3RuntimeBridgePrerequisitesReportGenerator {
    static func makeReport(
        loadingContextReadinessReportFrom rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> ChromeMV3RuntimeBridgePrerequisitesReport {
        let reportURL = rootURL.standardizedFileURL
            .appendingPathComponent(
                ChromeMV3ContextReadinessReportWriter.reportFileName
            )
        return try makeReport(
            loadingContextReadinessReportAt: reportURL,
            fileManager: fileManager
        )
    }

    static func makeReport(
        loadingContextReadinessReportAt reportURL: URL,
        fileManager: FileManager = .default
    ) throws -> ChromeMV3RuntimeBridgePrerequisitesReport {
        let reportURL = reportURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: reportURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue == false
        else {
            throw ChromeMV3RuntimeBridgePrerequisitesReportError
                .missingContextReadinessReport(reportURL.path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: reportURL)
        } catch {
            throw ChromeMV3RuntimeBridgePrerequisitesReportError
                .unreadableContextReadinessReport(error.localizedDescription)
        }

        let contextReport: ChromeMV3ContextReadinessReport
        do {
            contextReport = try JSONDecoder().decode(
                ChromeMV3ContextReadinessReport.self,
                from: data
            )
        } catch {
            throw ChromeMV3RuntimeBridgePrerequisitesReportError
                .corruptContextReadinessReport(error.localizedDescription)
        }

        let diagnostic = ChromeMV3ContextReadinessReportConsumer.diagnostic(
            fromReportURL: reportURL,
            fileManager: fileManager
        )
        return makeReport(
            contextReadinessReport: contextReport,
            contextReadinessReportPath: reportURL.path,
            contextReadinessReportHash: sha256Hex(data),
            consumptionDiagnostic: diagnostic,
            fileManager: fileManager
        )
    }

    static func makeReport(
        contextReadinessReport report: ChromeMV3ContextReadinessReport,
        contextReadinessReportPath: String,
        contextReadinessReportHash: String? = nil,
        consumptionDiagnostic:
            ChromeMV3ContextReadinessReportConsumptionDiagnostic? = nil,
        fileManager: FileManager = .default
    ) -> ChromeMV3RuntimeBridgePrerequisitesReport {
        let rootURL = URL(
            fileURLWithPath: report.generatedRewrittenRootPath,
            isDirectory: true
        ).standardizedFileURL
        let manifestFacts = loadManifestFacts(
            rootURL: rootURL,
            fileManager: fileManager
        )
        let diagnostic =
            consumptionDiagnostic
            ?? ChromeMV3ContextReadinessReportConsumer.diagnostic(
                fromReportURL: URL(fileURLWithPath: contextReadinessReportPath),
                fileManager: fileManager
            )
        let contextHash = contextReadinessReportHash
            ?? (try? ChromeMV3DeterministicJSON.encodedData(report))
                .map(sha256Hex)
            ?? "missing-context-report-hash"
        let runtimeMessaging = runtimeMessagingContract(report: report)
        let nativeMessaging = nativeMessagingPrerequisites(
            report: report,
            manifestFacts: manifestFacts
        )
        let storage = storagePrerequisites(
            report: report,
            manifestFacts: manifestFacts
        )
        let permissions = permissionsPrerequisites(
            report: report,
            manifestFacts: manifestFacts
        )
        let lifecycle = serviceWorkerLifecyclePrerequisites(report: report)
        let password = passwordManagerSummary(
            report: report,
            runtimeMessaging: runtimeMessaging,
            nativeMessaging: nativeMessaging,
            storage: storage,
            permissions: permissions,
            lifecycle: lifecycle
        )
        let unsupportedDeferred = ChromeMV3UnsupportedDeferredAPISummary(
            unsupportedAPIs: report.runtimeBlockers.unsupportedAPIs.sorted(),
            deferredAPIs: report.runtimeBlockers.deferredAPIs.sorted(),
            unsupportedDeferredAPIsRemainRuntimeBlockers:
                report.runtimeBlockers
                .unsupportedDeferredAPIsRemainRuntimeBlockers
        )
        let reportID = id(
            candidateID: report.candidateID,
            contextReadinessReportHash: contextHash
        )
        let branchReady =
            diagnostic.state == .ready
            && diagnostic.canImplementRecommendedBranch
            && diagnostic.nextRequiredPromptCategory
                == .addRuntimeBridgePrerequisites
        let unsupportedAPIsPresent =
            report.runtimeBlockers.unsupportedAPIs.isEmpty == false

        return ChromeMV3RuntimeBridgePrerequisitesReport(
            schemaVersion: 1,
            id: reportID,
            reportFileName:
                ChromeMV3RuntimeBridgePrerequisitesReportWriter
                .reportFileName,
            candidateID: report.candidateID,
            generatedRewrittenRootPath: rootURL.path,
            contextReadinessReportID: report.id,
            contextReadinessReportPath:
                URL(fileURLWithPath: contextReadinessReportPath)
                .standardizedFileURL
                .path,
            contextReadinessReportHash: contextHash,
            contextReadinessConsumerDiagnostic: diagnostic,
            manifestFacts: manifestFacts,
            runtimeMessagingPrerequisites: runtimeMessaging,
            nativeMessagingPrerequisites: nativeMessaging,
            storagePrerequisites: storage,
            permissionsActiveTabPrerequisites: permissions,
            serviceWorkerLifecyclePrerequisites: lifecycle,
            passwordManagerPrerequisiteSummary: password,
            unsupportedDeferredAPIs: unsupportedDeferred,
            modeledOnlyComponents: modeledOnlyComponents(),
            blockedComponents: blockedComponents(
                nativeMessaging: nativeMessaging,
                password: password
            ),
            requiredFutureComponents: requiredFutureComponents(
                report: report,
                nativeMessaging: nativeMessaging,
                storage: storage,
                permissions: permissions,
                lifecycle: lifecycle
            ),
            unsupportedOrDeferredAPIs: uniqueSortedAPIs(
                report.runtimeBlockers.unsupportedAPIs
                    + report.runtimeBlockers.deferredAPIs
            ),
            canCreateContextNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            contextCreationBlockedReason:
                "Context creation remains blocked because this report models runtime bridge prerequisites only.",
            contextLoadingBlockedReason:
                "Context loading remains blocked until context creation, runtime messaging, permission, storage, native messaging, and lifecycle gates are implemented and verified.",
            runtimeLoadableFalseReason:
                "runtimeLoadable remains false because this layer is non-executing and no Chrome MV3 runtime bridge component is implemented.",
            nextRequiredCategoryAfterThisReport:
                unsupportedAPIsPresent
                    ? .resolveUnsupportedAPIs
                    : (branchReady
                        ? .implementRuntimeBridgeComponents
                        : .blockedByContextReadinessReport),
            documentationSources: documentationSources(),
            warnings: uniqueSorted(
                manifestFacts.warnings
                    + (branchReady ? [] : [
                        "Context-readiness branch consumption did not authorize runtime bridge prerequisite recording.",
                    ])
            )
        )
    }

    private static func runtimeMessagingContract(
        report: ChromeMV3ContextReadinessReport
    ) -> ChromeMV3RuntimeMessagingContract {
        let password = report.passwordManagerReadiness
        let requiredForPassword = password.contentScriptsPresent
            || password.actionPopupPresent
            || password.nativeMessagingPermissionPresent
        return ChromeMV3RuntimeMessagingContract(
            status: .notImplemented,
            implementedNow: false,
            dispatchImplemented: false,
            listenerDeliveryImplemented: false,
            callbackCompatibilityRequired: true,
            promiseCompatibilityRequired: true,
            lastErrorRequirement:
                "Failures must surface through the Chrome-compatible lastError contract for callback callers and matching rejection behavior for Promise callers.",
            timeoutPolicyRequired: true,
            timeoutPolicy:
                "Future dispatch must define deterministic request timeout diagnostics without waking workers from this report.",
            routes: [
                route(
                    "contentScriptToServiceWorker",
                    api: "runtime.sendMessage",
                    wake: true,
                    tab: true
                ),
                route(
                    "extensionPageOrPopupToServiceWorker",
                    api: "runtime.sendMessage",
                    wake: true,
                    tab: false
                ),
                route(
                    "serviceWorkerToTabContentScript",
                    api: "tabs.sendMessage",
                    wake: false,
                    tab: true
                ),
                route(
                    "contentScriptLongLivedPortToExtension",
                    api: "runtime.connect",
                    wake: true,
                    tab: true
                ),
                route(
                    "extensionLongLivedPortToTabContentScript",
                    api: "tabs.connect",
                    wake: false,
                    tab: true
                ),
            ].sorted { $0.route < $1.route },
            portLifecycleRequirements: [
                "Create a named Port object on each endpoint.",
                "Deliver postMessage payloads only while both endpoints remain connected.",
                "Deliver onDisconnect at most once per endpoint.",
                "Stop dispatching new port events after disconnect.",
                "Record sender tab, frame, document, and origin metadata where available.",
            ],
            disconnectReasons: [
                "receivingFrameUnloaded",
                "tabClosedOrNavigated",
                "extensionContextUnloaded",
                "explicitDisconnect",
                "serviceWorkerIdleUnload",
                "unsupportedRoute",
                "timeout",
            ],
            contentScriptMessagingRestrictions: [
                "Content scripts use runtime messaging to reach extension contexts.",
                "Extension contexts use tab-targeted messaging to reach content scripts.",
                "Page-world messages are out of scope and require a separate controlled-input bridge verification.",
            ],
            requiredBeforePasswordManagerSupport: requiredForPassword,
            requiredBeforeRuntimeLoadability: true,
            blockers: uniqueSorted(
                report.runtimeBlockers.runtimeMessagingBlockers
                    + [
                        "Runtime message dispatch is not implemented.",
                        "Runtime message listener delivery is not implemented.",
                        "Port lifecycle is modeled only.",
                    ]
            ),
            futureTestsNeeded: [
                "content script to service worker sendMessage callback response",
                "popup to service worker sendMessage Promise response",
                "service worker to tab content script tabs.sendMessage failure",
                "runtime.connect named Port message ordering",
                "tabs.connect disconnect after tab navigation",
                "lastError and Promise rejection compatibility",
                "request timeout diagnostics without hidden worker wakeups",
            ]
        )
    }

    private static func route(
        _ route: String,
        api: String,
        wake: Bool,
        tab: Bool
    ) -> ChromeMV3RuntimeMessagingRouteContract {
        ChromeMV3RuntimeMessagingRouteContract(
            route: route,
            requiredAPI: api,
            requiresServiceWorkerWakePolicy: wake,
            requiresTabAddressing: tab,
            implementedNow: false,
            blockedReason:
                "Modeled contract only; no message dispatch or listener delivery is wired."
        )
    }

    private static func nativeMessagingPrerequisites(
        report: ChromeMV3ContextReadinessReport,
        manifestFacts: ChromeMV3RuntimeBridgeManifestFacts
    ) -> ChromeMV3NativeMessagingPrerequisites {
        let detected = manifestFacts.nativeMessagingPermissionPresent
            || report.passwordManagerReadiness
            .nativeMessagingPermissionPresent
        var blockers = report.runtimeBlockers.nativeMessagingBlockers
        if detected {
            blockers.append(
                "nativeMessaging permission is detected but native host lookup, validation, consent, and launch are not implemented for Chrome MV3."
            )
        }
        blockers.append(
            "Native messaging remains blocked until an explicit implementation and security review exist."
        )

        return ChromeMV3NativeMessagingPrerequisites(
            status: .blocked,
            nativeMessagingDetected: detected,
            nativeMessagingBlocked: true,
            hostManifestLookupImplemented: false,
            hostValidationImplemented: false,
            userConsentImplemented: false,
            processLaunchImplemented: false,
            stdioFramingRequired: true,
            inboundHostMessageLimitBytes: 1_048_576,
            outboundHostMessageLimitBytes: 4_294_967_296,
            portLifecycleModeled: true,
            hostExitBehaviorModeled: true,
            disabledModuleBehavior:
                "When extensions are disabled, report generation through SumiExtensionsModule returns nil and does not start any native host runtime.",
            noLaunchWhileExtensionsDisabled: true,
            noLaunchBeforeExplicitImplementation: true,
            requiredBeforePasswordManagerSupport: detected,
            futureSecurityReviewRequired: true,
            blockers: uniqueSorted(blockers),
            hostManifestLookupRequirements: [
                "Resolve user-level and system-level host manifest locations per browser/profile policy.",
                "Validate host names before lookup.",
                "Read host manifest JSON without launching the host.",
                "Reject missing, unreadable, or malformed host manifests with deterministic diagnostics.",
            ],
            allowedHostValidationRequirements: [
                "Validate extension origin against host manifest allowed origins.",
                "Validate host executable path policy before any future launch.",
                "Require user consent or enterprise policy before granting native host access.",
                "Record host exit and malformed frame behavior before exposing a native port.",
            ],
            futureTestsNeeded: [
                "permission detection without native host launch",
                "missing host manifest diagnostic",
                "disallowed extension origin diagnostic",
                "oversized inbound native message diagnostic",
                "host exit closes native port and reports reason",
                "disabled module cannot create native messaging runtime",
            ]
        )
    }

    private static func storagePrerequisites(
        report: ChromeMV3ContextReadinessReport,
        manifestFacts: ChromeMV3RuntimeBridgeManifestFacts
    ) -> ChromeMV3StoragePrerequisites {
        let storagePermission = manifestFacts.storagePermissionPresent
            || report.passwordManagerReadiness.storagePermissionPresent
        let profileIsolationVerified =
            report.controllerDataStoreIdentityStatus.matchesProfilePolicy
            && false
        let areas = [
            ChromeMV3StorageAreaPrerequisite(
                area: .local,
                required: storagePermission,
                implementedNow: false,
                persistenceExpectation:
                    "Local extension data persists on device and is cleared when the extension is removed.",
                contentScriptExposureDefault:
                    "Exposed to content scripts by default unless future access-level policy changes it.",
                decisionRequired:
                    "Choose and verify a profile-isolated host-backed local storage layer or a proven WebKit-backed equivalent.",
                blockers: storagePermission
                    ? [
                        "storage.local behavior is not implemented or verified.",
                        "profile-isolated extension storage persistence is not verified.",
                    ]
                    : []
            ),
            ChromeMV3StorageAreaPrerequisite(
                area: .session,
                required: storagePermission,
                implementedNow: false,
                persistenceExpectation:
                    "Session extension data is memory-backed while the extension is loaded and clears on disable, reload, update, or browser restart.",
                contentScriptExposureDefault:
                    "Not exposed to content scripts by default unless future access-level policy changes it.",
                decisionRequired:
                    "Define worker unload and reload semantics before any runtime bridge can depend on session state.",
                blockers: storagePermission
                    ? [
                        "storage.session behavior is not implemented or verified.",
                        "service-worker unload/reload state restoration is not verified.",
                    ]
                    : []
            ),
            ChromeMV3StorageAreaPrerequisite(
                area: .sync,
                required: storagePermission,
                implementedNow: false,
                persistenceExpectation:
                    "Sync data syncs across Chrome browsers when sync is enabled and otherwise behaves locally.",
                contentScriptExposureDefault:
                    "Exposed to content scripts by default unless future access-level policy changes it.",
                decisionRequired:
                    "Decide whether Sumi defers sync or maps it to local-only behavior with explicit diagnostics.",
                blockers: storagePermission
                    ? [
                        "storage.sync is deferred; local-only or sync behavior decision is required.",
                    ]
                    : []
            ),
        ].sorted { $0.area < $1.area }

        return ChromeMV3StoragePrerequisites(
            status: .notImplemented,
            storagePermissionPresent: storagePermission,
            implementedNow: false,
            webKitBehaviorSufficientWithoutHostLayer: false,
            hostBackedLayerDecisionRequired: true,
            profileIsolationVerified: profileIsolationVerified,
            workerUnloadReloadStateVerified: false,
            passwordManagerStateRequirements: [
                "Password-manager fixtures require persistent local state for vault/session metadata.",
                "Password-manager fixtures require session state that survives service-worker idle unload and reload.",
                "Password-manager fixtures require deterministic behavior if sync is unsupported or local-only.",
            ],
            areas: areas,
            blockers: uniqueSorted(
                report.runtimeBlockers.storageBlockers
                    + areas.flatMap(\.blockers)
                    + [
                        "Extension storage backend is not implemented.",
                        "Profile isolation for extension storage is not verified.",
                    ]
            ),
            futureTestsNeeded: [
                "storage.local persists per profile and clears per extension removal",
                "storage.session clears on extension disable and survives worker idle reload only as Chrome specifies",
                "storage.sync reports deferred or local-only behavior explicitly",
                "content script access-level defaults are enforced",
                "private and regular profiles do not share extension storage",
            ]
        )
    }

    private static func permissionsPrerequisites(
        report: ChromeMV3ContextReadinessReport,
        manifestFacts: ChromeMV3RuntimeBridgeManifestFacts
    ) -> ChromeMV3PermissionsActiveTabPrerequisites {
        let hostAccessNeeded = manifestFacts.hostPermissions.isEmpty == false
            || manifestFacts.optionalHostPermissions.isEmpty == false
            || report.passwordManagerReadiness.hostPermissionsPresent
            || manifestFacts.contentScriptsPresent
        return ChromeMV3PermissionsActiveTabPrerequisites(
            status: .notImplemented,
            requiredPermissions: manifestFacts.declaredPermissions,
            optionalPermissions: manifestFacts.optionalPermissions,
            hostPermissions: manifestFacts.hostPermissions,
            optionalHostPermissions: manifestFacts.optionalHostPermissions,
            activeTabDeclared: manifestFacts.activeTabPermissionPresent,
            permissionBrokerImplemented: false,
            activeTabImplemented: false,
            hostPermissionEvaluationImplemented: false,
            userGestureRequirementModeled: true,
            grantLifetimeRequirement:
                "activeTab grants must be tab-scoped, user-gesture-bound, and temporary.",
            tabNavigationInvalidationRequirement:
                "activeTab grants must be invalidated when the tab closes or navigates away from the granted origin.",
            permissionPromptUIFutureRequirement: true,
            contentScriptExecutionInteraction:
                "Content script execution must remain blocked until host permissions, activeTab grants, and injection policy are implemented.",
            passwordManagerHostAccessRequirement:
                "Password-manager fixtures require verified host access before content scripts or popup actions can touch page state.",
            requiredBeforeContentScriptExecution: true,
            requiredBeforePasswordManagerSupport: hostAccessNeeded,
            blockers: uniqueSorted(
                report.runtimeBlockers.permissionActiveTabBlockers
                    + [
                        "Permission broker is not implemented.",
                        "activeTab grant policy is not implemented.",
                        "Host permission evaluation is not implemented.",
                    ]
            ),
            futureTestsNeeded: [
                "required permissions are read without granting runtime access",
                "optional permissions require explicit user gesture",
                "host permissions match URL origins deterministically",
                "activeTab grant expires on cross-origin navigation",
                "permission prompt UI is absent until a future product task",
                "content script execution remains blocked without host access",
            ]
        )
    }

    private static func serviceWorkerLifecyclePrerequisites(
        report: ChromeMV3ContextReadinessReport
    ) -> ChromeMV3ServiceWorkerLifecycleReadiness {
        ChromeMV3ServiceWorkerLifecycleReadiness(
            status: .notImplemented,
            lifecycleCoordinatorImplemented: false,
            serviceWorkerWakeImplemented: false,
            idleUnloadPolicyModeled: true,
            permanentBackgroundForbidden: true,
            requiredBeforeContextLoad: true,
            requiredBeforeContextLoadReason:
                "Loading a context can make MV3 extension events observable, so Sumi needs a lifecycle coordinator before any context load attempt.",
            requiredBeforeRuntimeLoadability: true,
            wakeReasonsRequired: [
                "runtime message",
                "long-lived Port message",
                "extension action event",
                "permission request result",
                "alarm event",
                "native messaging port event",
            ],
            eventDispatchPrerequisites: [
                "Event queue ownership and cancellation policy.",
                "Unsupported API hit diagnostics.",
                "Sender metadata capture for tab, frame, document, and origin.",
                "No service-worker wake while extensions are disabled.",
            ],
            idleReleasePolicy:
                "Future implementation must unload idle workers and avoid permanent hidden background execution.",
            hardTimeoutPolicy:
                "Future implementation must report operations exceeding Chrome-compatible lifecycle timeouts without adding recurring checks here.",
            longLivedPortPolicy:
                "Future implementation must define how active Port traffic affects worker lifetime and diagnostics.",
            nativeMessagingPortPolicy:
                "Future implementation must define native port lifetime without launching native hosts from this prerequisite layer.",
            alarmWakePolicy:
                "Future implementation must model alarm wake behavior without adding schedulers in this layer.",
            statePersistenceRequirements: [
                "Persist state needed after worker unload in extension storage rather than globals.",
                "Restore pending request diagnostics after worker reload.",
                "Keep disabled-runtime state free of worker wakeups.",
            ],
            diagnosticsRequired: [
                "wake reason",
                "duration",
                "pending requests",
                "timeout or unload reason",
                "unsupported API hits",
            ],
            blockers: uniqueSorted(
                report.runtimeBlockers.serviceWorkerLifecycleBlockers
                    + [
                        "Service-worker lifecycle coordinator is not implemented.",
                        "Service-worker wake is not implemented.",
                        "Permanent background execution is forbidden.",
                    ]
            ),
            futureTestsNeeded: [
                "no worker wake while extensions are disabled",
                "runtime message wake records reason and duration",
                "idle unload records pending requests",
                "long-lived Port traffic lifecycle diagnostics",
                "native messaging port lifecycle diagnostics without process launch",
                "unsupported API hit diagnostics",
            ]
        )
    }

    private static func passwordManagerSummary(
        report: ChromeMV3ContextReadinessReport,
        runtimeMessaging: ChromeMV3RuntimeMessagingContract,
        nativeMessaging: ChromeMV3NativeMessagingPrerequisites,
        storage: ChromeMV3StoragePrerequisites,
        permissions: ChromeMV3PermissionsActiveTabPrerequisites,
        lifecycle: ChromeMV3ServiceWorkerLifecycleReadiness
    ) -> ChromeMV3PasswordManagerPrerequisiteSummary {
        let readiness = report.passwordManagerReadiness
        let runtimeMissing = runtimeMessaging.implementedNow == false
        let permissionMissing =
            permissions.permissionBrokerImplemented == false
            || permissions.activeTabImplemented == false
            || permissions.hostPermissionEvaluationImplemented == false
        let storageMissing = storage.implementedNow == false
        let nativeMissing = nativeMessaging.nativeMessagingDetected
            && nativeMessaging.processLaunchImplemented == false
        let pageWorldMissing =
            readiness.controlledInputPageWorldBehaviorVerified == false
        let lifecycleMissing =
            readiness.serviceWorkerLifecycleVerified == false
            || lifecycle.serviceWorkerWakeImplemented == false

        return ChromeMV3PasswordManagerPrerequisiteSummary(
            contentScriptsPresent: readiness.contentScriptsPresent,
            actionPopupPresent: readiness.actionPopupPresent,
            hostPermissionsPresent: readiness.hostPermissionsPresent,
            storagePermissionPresent: readiness.storagePermissionPresent,
            nativeMessagingPermissionPresent:
                readiness.nativeMessagingPermissionPresent,
            runtimeMessagingMissing: runtimeMissing,
            permissionActiveTabMissing: permissionMissing,
            storageBackendMissingOrDeferred: storageMissing,
            nativeMessagingMissing: nativeMissing,
            controlledInputPageWorldBehaviorNotVerified: pageWorldMissing,
            serviceWorkerLifecycleNotVerified: lifecycleMissing,
            passwordManagerSupportReady: false,
            blockers: uniqueSorted(
                readiness.blockers
                    + runtimeMessaging.blockers
                    + permissions.blockers
                    + storage.blockers
                    + (nativeMissing ? nativeMessaging.blockers : [])
                    + lifecycle.blockers
                    + [
                        "Password-manager support is not ready.",
                        "Controlled-input and page-world behavior is not verified.",
                    ]
            ),
            deferredChecks: uniqueSorted(
                readiness.deferredChecks
                    + [
                        "Runtime bridge prerequisites are modeled only.",
                        "No Chrome MV3 runtime support claim is made.",
                    ]
            )
        )
    }

    private static func loadManifestFacts(
        rootURL: URL,
        fileManager: FileManager
    ) -> ChromeMV3RuntimeBridgeManifestFacts {
        let manifestURL = rootURL.standardizedFileURL
            .appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            return manifestFacts(
                status: .missing,
                path: manifestURL.path,
                sha256: nil,
                object: nil,
                warnings: [
                    "manifest.json is missing; manifest-derived runtime prerequisites are incomplete.",
                ]
            )
        }

        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            return manifestFacts(
                status: .unreadable,
                path: manifestURL.path,
                sha256: nil,
                object: nil,
                warnings: [
                    "manifest.json could not be read: \(error.localizedDescription)",
                ]
            )
        }

        let object: [String: Any]
        do {
            guard
                let dictionary = try JSONSerialization
                    .jsonObject(with: data) as? [String: Any]
            else {
                return manifestFacts(
                    status: .corrupt,
                    path: manifestURL.path,
                    sha256: sha256Hex(data),
                    object: nil,
                    warnings: [
                        "manifest.json root is not an object.",
                    ]
                )
            }
            object = dictionary
        } catch {
            return manifestFacts(
                status: .corrupt,
                path: manifestURL.path,
                sha256: sha256Hex(data),
                object: nil,
                warnings: [
                    "manifest.json is not valid JSON: \(error.localizedDescription)",
                ]
            )
        }

        return manifestFacts(
            status: .loaded,
            path: manifestURL.path,
            sha256: sha256Hex(data),
            object: object,
            warnings: []
        )
    }

    private static func manifestFacts(
        status: ChromeMV3RuntimeBridgeManifestReadStatus,
        path: String,
        sha256: String?,
        object: [String: Any]?,
        warnings: [String]
    ) -> ChromeMV3RuntimeBridgeManifestFacts {
        let permissions = stringArray(object?["permissions"])
        let optionalPermissions = stringArray(object?["optional_permissions"])
        let allPermissions = uniqueSorted(
            permissions + optionalPermissions
        )
        let hostPermissions = stringArray(object?["host_permissions"])
        let optionalHostPermissions = stringArray(
            object?["optional_host_permissions"]
        )
        let contentScripts = object?["content_scripts"] as? [[String: Any]]
            ?? []
        let contentScriptMatches = contentScripts
            .flatMap { stringArray($0["matches"]) }
        let action = object?["action"] as? [String: Any]
        let background = object?["background"] as? [String: Any]

        return ChromeMV3RuntimeBridgeManifestFacts(
            manifestReadStatus: status,
            manifestPath: path,
            manifestSHA256: sha256,
            declaredPermissions: permissions,
            optionalPermissions: optionalPermissions,
            hostPermissions: hostPermissions.sorted(),
            optionalHostPermissions: optionalHostPermissions.sorted(),
            contentScriptsPresent: contentScripts.isEmpty == false,
            contentScriptMatchPatterns:
                uniqueSorted(contentScriptMatches),
            actionPopupPresent:
                stringValue(action?["default_popup"]) != nil,
            backgroundServiceWorkerPresent:
                stringValue(background?["service_worker"]) != nil,
            storagePermissionPresent: allPermissions.contains("storage"),
            nativeMessagingPermissionPresent:
                allPermissions.contains("nativeMessaging"),
            activeTabPermissionPresent: allPermissions.contains("activeTab"),
            permissionsAPIPresent: allPermissions.contains("permissions"),
            warnings: uniqueSorted(warnings)
        )
    }

    private static func modeledOnlyComponents() -> [String] {
        [
            "runtime messaging routes",
            "runtime Port lifecycle",
            "native messaging host policy",
            "storage.local prerequisites",
            "storage.session prerequisites",
            "storage.sync prerequisites",
            "permissions and activeTab policy",
            "service-worker lifecycle readiness",
            "password-manager prerequisite summary",
        ].sorted()
    }

    private static func blockedComponents(
        nativeMessaging: ChromeMV3NativeMessagingPrerequisites,
        password: ChromeMV3PasswordManagerPrerequisiteSummary
    ) -> [String] {
        var components = [
            "context creation",
            "context loading",
            "runtime loadability",
            "runtime message dispatch",
            "runtime listener delivery",
            "content script execution",
            "user script registration",
            "service-worker wake",
            "storage API runtime",
            "permission grants",
        ]
        if nativeMessaging.nativeMessagingBlocked {
            components.append("native messaging")
        }
        if password.passwordManagerSupportReady == false {
            components.append("password-manager support")
        }
        return uniqueSorted(components)
    }

    private static func requiredFutureComponents(
        report: ChromeMV3ContextReadinessReport,
        nativeMessaging: ChromeMV3NativeMessagingPrerequisites,
        storage: ChromeMV3StoragePrerequisites,
        permissions: ChromeMV3PermissionsActiveTabPrerequisites,
        lifecycle: ChromeMV3ServiceWorkerLifecycleReadiness
    ) -> [String] {
        var components = [
            "Runtime messaging dispatcher with callback and Promise compatibility.",
            "Port registry with deterministic disconnect diagnostics.",
            "Permission broker for required, optional, host, and activeTab grants.",
            "Profile-isolated extension storage layer or verified WebKit-backed equivalent.",
            "Service-worker lifecycle coordinator with wake and unload diagnostics.",
            "Context creation gate after runtime prerequisites are implemented.",
            "Controller loading gate after context and runtime behavior are verified.",
        ]
        if nativeMessaging.nativeMessagingDetected {
            components.append(
                "Native messaging host lookup, validation, consent, launch policy, and security review."
            )
        }
        if storage.storagePermissionPresent == false {
            components.append(
                "Storage decision remains required before any fixture that declares storage can load."
            )
        }
        if permissions.hostPermissions.isEmpty
            && permissions.optionalHostPermissions.isEmpty
            && report.passwordManagerReadiness.hostPermissionsPresent == false
        {
            components.append(
                "Host permission behavior still requires future fixture coverage."
            )
        }
        if lifecycle.requiredBeforeContextLoad {
            components.append(
                "Lifecycle readiness must be implemented before any future context load attempt."
            )
        }
        components.append(contentsOf: report.requiredFutureActions)
        return uniqueSorted(components)
    }

    private static func documentationSources()
        -> [ChromeMV3ManifestRewritePreviewSource]
    {
        [
            source(
                title: "Chrome runtime messaging",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/messaging",
                note: "Defines one-time messages, long-lived Port channels, tab-targeted messaging, and content script message boundaries."
            ),
            source(
                title: "Chrome runtime API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/runtime",
                note: "Defines Port metadata, postMessage, disconnect behavior, and lastError reporting."
            ),
            source(
                title: "Chrome native messaging",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging",
                note: "Defines declared permission, host manifests, stdio JSON framing, size limits, and host lifetime requirements."
            ),
            source(
                title: "Chrome storage API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/storage",
                note: "Defines local, session, and sync storage areas and content script exposure defaults."
            ),
            source(
                title: "Chrome declare permissions",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/declare-permissions",
                note: "Defines required permissions, optional permissions, host permissions, and install/runtime warnings."
            ),
            source(
                title: "Chrome permissions API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/permissions",
                note: "Defines runtime optional permission request and contains checks."
            ),
            source(
                title: "Chrome activeTab",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/activeTab",
                note: "Defines temporary user-gesture-bound tab grants and navigation invalidation."
            ),
            source(
                title: "Chrome extension service-worker lifecycle",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle",
                note: "Defines event-driven wake, idle shutdown, long request limits, alarm lifetime updates, and persistence guidance."
            ),
            source(
                title: "Chrome content scripts",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts",
                note: "Defines isolated content script execution and message API boundaries."
            ),
            ChromeMV3ManifestRewritePreviewSource(
                kind: .currentSumiCode,
                title: "Sumi user-script broker",
                url: nil,
                note: "Existing user-script systems are not used by this prerequisite report and are not modified."
            ),
            ChromeMV3ManifestRewritePreviewSource(
                kind: .currentSumiCode,
                title: "Sumi native messaging runtime remnants",
                url: nil,
                note: "Existing native messaging process code is not called by this prerequisite report."
            ),
            ChromeMV3ManifestRewritePreviewSource(
                kind: .currentSumiCode,
                title: "Sumi module gates and profile storage",
                url: nil,
                note: "SumiExtensionsModule disabled paths return nil, and profile identity diagnostics remain prerequisites for future storage isolation."
            ),
        ]
    }

    private static func source(
        title: String,
        url: String,
        note: String
    ) -> ChromeMV3ManifestRewritePreviewSource {
        ChromeMV3ManifestRewritePreviewSource(
            kind: .chromeDocumentation,
            title: title,
            url: url,
            note: note
        )
    }

    private static func id(
        candidateID: String,
        contextReadinessReportHash: String
    ) -> String {
        let seed = [
            "runtime-bridge-prerequisites",
            candidateID,
            contextReadinessReportHash,
        ].joined(separator: "|")
        return "runtime-bridge-prerequisites-\(sha256Hex(Data(seed.utf8)).prefix(32))"
    }

    private static func stringArray(_ value: Any?) -> [String] {
        (value as? [String] ?? []).sorted()
    }

    private static func stringValue(_ value: Any?) -> String? {
        value as? String
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { $0.isEmpty == false })).sorted()
    }

    private static func uniqueSortedAPIs(
        _ apis: [ChromeMV3API]
    ) -> [ChromeMV3API] {
        Array(Set(apis)).sorted()
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

enum ChromeMV3RuntimeBridgePrerequisitePlanner {
    static func plan(
        report: ChromeMV3ContextReadinessReport,
        consumptionDiagnostic:
            ChromeMV3ContextReadinessReportConsumptionDiagnostic
    ) -> ChromeMV3RuntimeBridgePrerequisitePlan {
        let bridgeReport =
            ChromeMV3RuntimeBridgePrerequisitesReportGenerator.makeReport(
                contextReadinessReport: report,
                contextReadinessReportPath:
                    consumptionDiagnostic.reportPath,
                consumptionDiagnostic: consumptionDiagnostic
            )
        let branch =
            consumptionDiagnostic.nextRequiredPromptCategory
        var blockers: [String] = []
        var warnings = bridgeReport.warnings + [
            "Runtime bridge prerequisites are diagnostic models only; Sumi still does not claim Chrome MV3 runtime support.",
        ]

        if consumptionDiagnostic.state != .ready
            || consumptionDiagnostic.canImplementRecommendedBranch == false
        {
            blockers.append(
                "Generated context-readiness report was not consumed successfully."
            )
        }

        if branch != .addRuntimeBridgePrerequisites {
            blockers.append(
                "Generated context-readiness report did not select addRuntimeBridgePrerequisites."
            )
        }

        if report.runtimeLoadable {
            blockers.append("runtimeLoadable must remain false.")
        }

        if report.canLoadContextNow {
            blockers.append("canLoadContextNow must remain false.")
        }

        let prerequisites = [
            prerequisite(
                category: .runtimeMessaging,
                blockers: bridgeReport.runtimeMessagingPrerequisites.blockers,
                action: "Implement the runtime messaging contract without changing runtimeLoadable until verified."
            ),
            prerequisite(
                category: .nativeMessaging,
                blockers: bridgeReport.nativeMessagingPrerequisites.blockers,
                action: "Implement native messaging validation, consent, and lifecycle in a future security-reviewed task."
            ),
            prerequisite(
                category: .storage,
                blockers: bridgeReport.storagePrerequisites.blockers,
                action: "Implement or verify storage behavior without writing extension storage from this prerequisite layer."
            ),
            prerequisite(
                category: .permissionsAndActiveTab,
                blockers: bridgeReport
                    .permissionsActiveTabPrerequisites
                    .blockers,
                action: "Implement permission broker and activeTab prerequisites without granting runtime permissions here."
            ),
            prerequisite(
                category: .serviceWorkerLifecycle,
                blockers: bridgeReport
                    .serviceWorkerLifecyclePrerequisites
                    .blockers,
                action: "Implement service-worker lifecycle coordination without permanent background execution."
            ),
            prerequisite(
                category: .contextCreationDeferred,
                blockers: [
                    bridgeReport.contextCreationBlockedReason,
                ],
                action: "Keep context construction behind a future generated addContextCreationGate report."
            ),
            prerequisite(
                category: .controllerLoadingDeferred,
                blockers: [
                    bridgeReport.contextLoadingBlockedReason,
                ],
                action: "Keep controller loading absent until context and runtime behavior are separately verified."
            ),
        ].sorted { lhs, rhs in
            lhs.category < rhs.category
        }

        if prerequisites.filter(\.required).isEmpty {
            warnings.append(
                "No concrete runtime bridge blocker arrays were present; only deferred context/loading prerequisites were recorded."
            )
        }

        return ChromeMV3RuntimeBridgePrerequisitePlan(
            schemaVersion: 1,
            sourceContextReadinessReportID: report.id,
            sourceContextReadinessReportPath:
                consumptionDiagnostic.reportPath,
            nextRequiredPromptCategory: branch,
            canRecordPrerequisitesNow: blockers.isEmpty,
            branchImplemented:
                blockers.isEmpty ? .addRuntimeBridgePrerequisites : nil,
            prerequisites: prerequisites,
            runtimeLoadable: false,
            canLoadContextNow: false,
            contextCreationAllowed: false,
            controllerLoadAllowed: false,
            extensionCodeExecutionAllowed: false,
            userScriptRegistrationAllowed: false,
            nativeMessagingLaunchAllowed: false,
            blockingReasons: uniqueSorted(blockers),
            warnings: uniqueSorted(warnings)
        )
    }

    private static func prerequisite(
        category: ChromeMV3RuntimeBridgePrerequisiteCategory,
        blockers: [String],
        action: String
    ) -> ChromeMV3RuntimeBridgePrerequisite {
        ChromeMV3RuntimeBridgePrerequisite(
            category: category,
            required: blockers.isEmpty == false,
            blockers: uniqueSorted(blockers),
            requiredFutureAction: action,
            nonExecuting: true
        )
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { $0.isEmpty == false })).sorted()
    }
}
