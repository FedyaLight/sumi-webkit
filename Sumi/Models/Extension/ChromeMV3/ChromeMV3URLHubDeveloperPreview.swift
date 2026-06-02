//
//  ChromeMV3URLHubDeveloperPreview.swift
//  Sumi
//
//  URL-hub developer-preview Chrome MV3 action readout. This is a passive
//  current-page model and does not create ExtensionManager, WebKit runtime,
//  service-worker, content-script endpoint, native-host, timer, or bridge
//  objects while rendering.
//

import CryptoKit
import Foundation

struct ChromeMV3URLHubCurrentPageContext:
    Codable,
    Equatable,
    Sendable
{
    var profileID: String?
    var tabID: String
    var permissionBrokerTabID: Int?
    var documentID: String
    var urlString: String?
    var tabSurface: ChromeMV3WebViewSurface
    var isTopFrame: Bool
    var frameID: Int
    var contentWorld: ChromeMV3ContentScriptWorld

    init(
        profileID: String?,
        tabID: String,
        permissionBrokerTabID: Int? = nil,
        documentID: String = "urlhub-current-page",
        urlString: String?,
        tabSurface: ChromeMV3WebViewSurface,
        isTopFrame: Bool = true,
        frameID: Int = 0,
        contentWorld: ChromeMV3ContentScriptWorld = .isolated
    ) {
        self.profileID = profileID
        self.tabID = tabID
        self.permissionBrokerTabID = permissionBrokerTabID
        self.documentID = documentID
        self.urlString = urlString
        self.tabSurface = tabSurface
        self.isTopFrame = isTopFrame
        self.frameID = frameID
        self.contentWorld = contentWorld
    }
}

struct ChromeMV3URLHubLifetimeReport:
    Codable,
    Equatable,
    Sendable
{
    var disabledModuleObjectsCreated: [String]
    var passiveReadoutObjectsCreated: [String]
    var runtimeObjectsCreated: [String]
    var serviceWorkerWakeAttempted: Bool
    var nativeHostLaunchAttempted: Bool
    var timersOrPollingStarted: Bool
    var artifactWrittenByReadout: Bool
    var diagnostics: [String]

    static let passive =
        ChromeMV3URLHubLifetimeReport(
            disabledModuleObjectsCreated: [],
            passiveReadoutObjectsCreated: [
                "Codable URL-hub section model",
                "Codable URL-hub row model",
                "Codable current-page readiness model",
            ],
            runtimeObjectsCreated: [],
            serviceWorkerWakeAttempted: false,
            nativeHostLaunchAttempted: false,
            timersOrPollingStarted: false,
            artifactWrittenByReadout: false,
            diagnostics: [
                "URL-hub MV3 rendering reads the internal lifecycle registry and ignored artifact state only.",
                "URL-hub MV3 rendering does not create manager, WebKit extension runtime, content-script endpoint, service worker, native host, timers, polling, or product runtime objects.",
                "Diagnostic artifacts are written only by an explicit URL-hub action invocation.",
            ]
        )
}

struct ChromeMV3URLHubCurrentPageReadiness:
    Codable,
    Equatable,
    Sendable
{
    var currentURL: String
    var currentOrigin: String?
    var requiredSyntheticDiagnosticURL: String
    var currentPageIsSyntheticDiagnosticPage: Bool
    var tabSurface: ChromeMV3WebViewSurface
    var normalTabSurface: Bool
    var passiveHostAccessDecision: ChromeMV3HostAccessDecision
    var actionHostAccessDecision: ChromeMV3HostAccessDecision
    var productRuntimeGateState: String
    var productDefaultRuntimeAvailable: Bool
    var localExperimentalGateOpen: Bool
    var extensionEnabled: Bool
    var profileEnabled: Bool
    var reviewedResource: ChromeMV3ProductNormalTabReviewedResource
    var blockedByModule: Bool
    var blockedByExtension: Bool
    var blockedByProfile: Bool
    var blockedByLocalExperimentalGate: Bool
    var blockedBySurface: Bool
    var blockedByAuxiliarySurface: Bool
    var blockedByScheme: Bool
    var blockedByPermission: Bool
    var blockedByMissingReviewedResource: Bool
    var blockedByWorld: Bool
    var blockedByFrame: Bool
    var blockedByRuntimeGate: Bool
    var blockedByNonSyntheticOrigin: Bool
    var blockers: [ChromeMV3ProductNormalTabReadinessBlocker]
    var explicitDiagnosticActionCanRun: Bool
    var productRuntimeStayedOff: Bool
    var diagnostics: [String]

    static func make(
        preflight: ChromeMV3ProductNormalTabReadinessPreflight,
        passiveHostAccessDecision: ChromeMV3HostAccessDecision,
        requiredSyntheticDiagnosticURL: String,
        currentPageIsSyntheticDiagnosticPage: Bool,
        productRuntimeGateState: String,
        localExperimentalGateOpen: Bool
    ) -> Self {
        let syntheticPathBlocker =
            currentPageIsSyntheticDiagnosticPage
                ? []
                : [ChromeMV3ProductNormalTabReadinessBlocker.blockedByNonSyntheticOrigin]
        let blockers = Array(Set(preflight.blockers + syntheticPathBlocker))
            .sorted()
        let blockedByNonSyntheticOrigin =
            preflight.blockedByNonSyntheticOrigin
                || currentPageIsSyntheticDiagnosticPage == false
        return ChromeMV3URLHubCurrentPageReadiness(
            currentURL: preflight.urlString,
            currentOrigin:
                ChromeMV3RuntimeMessagingURL.origin(from: preflight.urlString),
            requiredSyntheticDiagnosticURL: requiredSyntheticDiagnosticURL,
            currentPageIsSyntheticDiagnosticPage:
                currentPageIsSyntheticDiagnosticPage,
            tabSurface: preflight.tabSurface,
            normalTabSurface: preflight.tabSurface == .normalTab,
            passiveHostAccessDecision: passiveHostAccessDecision,
            actionHostAccessDecision: preflight.hostAccessDecision,
            productRuntimeGateState: productRuntimeGateState,
            productDefaultRuntimeAvailable:
                preflight.policy.productDefaultRuntimeAvailable,
            localExperimentalGateOpen: localExperimentalGateOpen,
            extensionEnabled: preflight.blockedByExtension == false,
            profileEnabled: preflight.blockedByProfile == false,
            reviewedResource: preflight.reviewedResource,
            blockedByModule: preflight.blockedByModule,
            blockedByExtension: preflight.blockedByExtension,
            blockedByProfile: preflight.blockedByProfile,
            blockedByLocalExperimentalGate:
                preflight.blockedByLocalExperimentalGate,
            blockedBySurface: preflight.blockedBySurface,
            blockedByAuxiliarySurface: preflight.blockedByAuxiliarySurface,
            blockedByScheme: preflight.blockedByScheme,
            blockedByPermission: preflight.blockedByPermission,
            blockedByMissingReviewedResource:
                preflight.blockedByMissingReviewedResource,
            blockedByWorld: preflight.blockedByWorld,
            blockedByFrame: preflight.blockedByFrame,
            blockedByRuntimeGate: preflight.blockedByRuntimeGate,
            blockedByNonSyntheticOrigin: blockedByNonSyntheticOrigin,
            blockers: blockers,
            explicitDiagnosticActionCanRun: blockers.isEmpty,
            productRuntimeStayedOff:
                preflight.policy.productDefaultRuntimeAvailable == false,
            diagnostics:
                uniqueSortedURLHubMV3(
                    preflight.diagnostics
                        + [
                            currentPageIsSyntheticDiagnosticPage
                                ? "Current URL matches the local synthetic diagnostic page."
                                : "Current URL is not the local synthetic diagnostic page.",
                            "Product runtime gate state: \(productRuntimeGateState).",
                            "Product/default runtime stayed off: \(preflight.policy.productDefaultRuntimeAvailable == false).",
                        ]
                )
        )
    }
}

struct ChromeMV3URLHubDiagnosticAction:
    Codable,
    Equatable,
    Sendable
{
    enum Capability:
        String,
        Codable,
        CaseIterable,
        Comparable,
        Sendable
    {
        case reviewedGeneratedResourceNormalTabSmoke

        static func < (lhs: Capability, rhs: Capability) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    var actionID: ChromeMV3ExtensionManagerActionKind
    var capabilityID: Capability
    var capabilityAvailable: Bool
    var title: String
    var available: Bool
    var disabledReason: String?
    var unavailableDiagnostics:
        [ChromeMV3ExtensionManagerBlockedDiagnostic]
    var lastRunStatus: ChromeMV3ExtensionManagerActionStatus?
    var lastArtifactPath: String?
    var lastDOMFillSucceeded: Bool?
    var lastTeardownCompleted: Bool?
    var lastRetainedObjectCount: Int?
    var notProductSupportLabel: String
}

struct ChromeMV3URLHubExtensionRow:
    Identifiable,
    Codable,
    Equatable,
    Sendable
{
    var id: String { "\(profileID):\(extensionID)" }
    var profileID: String
    var extensionID: String
    var displayName: String
    var displayVersion: String
    var iconFileSystemPath: String?
    var sourceType: ChromeMV3InstalledExtensionSourceType
    var sourceDescriptor: String
    var installed: Bool
    var installIntakeStatus: ChromeMV3LifecycleState
    var enabled: Bool
    var generatedBundleAvailable: Bool
    var generatedBundleRecordID: String?
    var generatedBundleHash: String?
    var manifestHash: String?
    var originalBundleContentHash: String?
    var productSupportClaim: Bool
    var developerPreviewLabel: String
    var notProductSupportLabel: String
    var readiness: ChromeMV3URLHubCurrentPageReadiness
    var diagnosticAction: ChromeMV3URLHubDiagnosticAction
}

struct ChromeMV3URLHubSectionViewModel:
    Codable,
    Equatable,
    Sendable
{
    static let schemaVersion = 1

    var schemaVersion: Int
    var generatedAt: Date
    var currentPage: ChromeMV3URLHubCurrentPageContext
    var gate: ChromeMV3ExtensionManagerGate
    var rows: [ChromeMV3URLHubExtensionRow]
    var lifetime: ChromeMV3URLHubLifetimeReport
    var diagnostics: [String]
}

enum ChromeMV3URLHubDeveloperPreviewModelBuilder {
    static let syntheticDiagnosticURLString = "https://sumi.local.test/login"
    static let notProductSupportLabel =
        "Diagnostic only - not product support"
    static let developerPreviewLabel =
        "Local experimental developer preview"

    static func makeSection(
        rootURL: URL,
        gate: ChromeMV3ExtensionManagerGate,
        currentPage: ChromeMV3URLHubCurrentPageContext,
        now: Date = Date()
    ) -> ChromeMV3URLHubSectionViewModel {
        guard gate.managerAvailableInDeveloperPreview else {
            return ChromeMV3URLHubSectionViewModel(
                schemaVersion: ChromeMV3URLHubSectionViewModel.schemaVersion,
                generatedAt: now,
                currentPage: currentPage,
                gate: gate,
                rows: [],
                lifetime: .passive,
                diagnostics:
                    gate.diagnostics.map(\.message).sorted()
                        + [
                            "URL-hub MV3 section is inert because the developer-preview gate is closed.",
                        ]
            )
        }

        let registry = ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
        let profileFilter = currentPage.profileID
        let rows = registry.listInstalledExtensionStates()
            .filter { state in
                guard let profileFilter else { return true }
                return state.profileID == profileFilter
            }
            .compactMap { state -> ChromeMV3URLHubExtensionRow? in
                guard
                    let record = registry.loadLifecycleRecord(
                        profileID: state.profileID,
                        extensionID: state.extensionID
                    )
                else {
                    return nil
                }
                let report = registry.latestEndToEndDiagnosticsReport(
                    profileID: state.profileID,
                    extensionID: state.extensionID
                )
                return makeRow(
                    rootURL: rootURL,
                    state: state,
                    record: record,
                    report: report,
                    gate: gate,
                    currentPage: currentPage
                )
            }
            .sorted {
                if $0.displayName != $1.displayName {
                    return $0.displayName < $1.displayName
                }
                return $0.extensionID < $1.extensionID
            }

        return ChromeMV3URLHubSectionViewModel(
            schemaVersion: ChromeMV3URLHubSectionViewModel.schemaVersion,
            generatedAt: now,
            currentPage: currentPage,
            gate: gate,
            rows: rows,
            lifetime: .passive,
            diagnostics:
                uniqueSortedURLHubMV3(
                    [
                        rows.isEmpty
                            ? "No installed local MV3 extension states matched the current profile."
                            : "URL-hub MV3 section loaded \(rows.count) installed local MV3 extension state record(s) from shared lifecycle state.",
                        "URL-hub is the current-page/action surface; Settings remains the management surface.",
                        "Passive URL-hub render did not execute diagnostic smoke or write artifacts.",
                    ]
                )
        )
    }

    private static func makeRow(
        rootURL: URL,
        state: ChromeMV3InstalledExtensionState,
        record: ChromeMV3ExtensionLifecycleRecord,
        report: ChromeMV3EndToEndInstallDiagnosticsReport?,
        gate: ChromeMV3ExtensionManagerGate,
        currentPage: ChromeMV3URLHubCurrentPageContext
    ) -> ChromeMV3URLHubExtensionRow {
        let manifestSummary =
            ChromeMV3ExtensionManagerManifestSummaryViewState.make(
                summary: report?.managerActiveManifestSummary,
                record: record
            )
        let reviewedResource = reviewedResource(record: record, report: report)
        let broker = permissionBroker(
            rootURL: rootURL,
            record: record,
            manifestSummary: manifestSummary
        )
        let currentURL = currentPage.urlString ?? "about:blank"
        let passiveHostDecision = broker.hostAccessDecision(
            url: currentURL,
            tabID: currentPage.permissionBrokerTabID
        )
        let actionHostDecision = actionHostAccessDecision(
            passiveDecision: passiveHostDecision,
            broker: broker,
            currentURL: currentURL,
            tabID: currentPage.permissionBrokerTabID,
            currentPageIsSyntheticDiagnosticPage:
                currentURL == syntheticDiagnosticURLString
        )
        let manualSmokeAction =
            ChromeMV3ExtensionManagerManualSmokeActionRecord.make(
                rootURL: rootURL,
                record: record,
                gate: gate,
                readiness: managerActionReadiness(
                    record: record,
                    report: report,
                    reviewedResource: reviewedResource,
                    gate: gate
                ),
                lastArtifact:
                    ChromeMV3ExtensionManagerManualSmokeArtifactWriter
                    .latestArtifact(
                        rootURL: rootURL,
                        profileID: record.profileID,
                        extensionID: record.extensionID
                    )
            )
        let preflight =
            ChromeMV3ProductNormalTabReadinessPreflightEvaluator.evaluate(
                input: ChromeMV3ProductNormalTabReadinessPreflightInput(
                    profileID: record.profileID,
                    extensionID: record.extensionID,
                    tabID: currentPage.tabID,
                    documentID: currentPage.documentID,
                    urlString: currentURL,
                    moduleEnabled: gate.managerAvailableInDeveloperPreview,
                    extensionEnabled:
                        record.runtimeState.internalRuntimeEnabled,
                    profileEnabled: record.lifecycleState != .uninstalled
                        && record.lifecycleState != .corrupt,
                    localExperimentalProductGateAllowed:
                        gate.managerAvailableInDeveloperPreview,
                    runtimeGateAllowsReadiness: manualSmokeAction.available,
                    contentScriptRouteReady: manualSmokeAction.available,
                    serviceWorkerRouteReady: true,
                    tabSurface: currentPage.tabSurface,
                    syntheticHTTPSOrigin:
                        ChromeMV3RuntimeMessagingURL.origin(
                            from: syntheticDiagnosticURLString
                        ) ?? "https://sumi.local.test",
                    frameID: currentPage.frameID,
                    isTopFrame: currentPage.isTopFrame,
                    contentWorld: currentPage.contentWorld,
                    hostAccessDecision: actionHostDecision,
                    reviewedResource: reviewedResource,
                    teardownPending: false
                )
            )
        let productGateState =
            ChromeMV3ProductRuntimeGateSet
            .defaultBlocked(report: report, lifecycleRecord: record)
            .globalProductRuntimeGate
            .state
            .rawValue
        let readiness = ChromeMV3URLHubCurrentPageReadiness.make(
            preflight: preflight,
            passiveHostAccessDecision: passiveHostDecision,
            requiredSyntheticDiagnosticURL: syntheticDiagnosticURLString,
            currentPageIsSyntheticDiagnosticPage:
                currentURL == syntheticDiagnosticURLString,
            productRuntimeGateState: productGateState,
            localExperimentalGateOpen: gate.managerAvailableInDeveloperPreview
        )
        let action = diagnosticAction(
            readiness: readiness,
            managerAction: manualSmokeAction
        )
        return ChromeMV3URLHubExtensionRow(
            profileID: state.profileID,
            extensionID: state.extensionID,
            displayName: state.displayName,
            displayVersion: state.displayVersion,
            iconFileSystemPath: nil,
            sourceType: state.sourceType,
            sourceDescriptor: state.sourceDescriptor,
            installed: state.installed,
            installIntakeStatus: state.installIntakeStatus,
            enabled: state.enabled,
            generatedBundleAvailable: state.generatedBundleState
                .generatedBundleAvailable,
            generatedBundleRecordID: state.generatedBundleRecordID,
            generatedBundleHash: state.generatedBundleHash,
            manifestHash: state.manifestHash,
            originalBundleContentHash: state.originalBundleContentHash,
            productSupportClaim: state.productSupportClaim,
            developerPreviewLabel: state.localExperimentalLabel,
            notProductSupportLabel: notProductSupportLabel,
            readiness: readiness,
            diagnosticAction: action
        )
    }

    private static func managerActionReadiness(
        record: ChromeMV3ExtensionLifecycleRecord,
        report: ChromeMV3EndToEndInstallDiagnosticsReport?,
        reviewedResource: ChromeMV3ProductNormalTabReviewedResource,
        gate: ChromeMV3ExtensionManagerGate
    ) -> ChromeMV3ProductNormalTabReadinessReport {
        let hostDecision = ChromeMV3HostAccessDecision(
            url: syntheticDiagnosticURLString,
            origin:
                ChromeMV3RuntimeMessagingURL.origin(
                    from: syntheticDiagnosticURLString
                ),
            status: .allowed,
            grantSource: .activeTabGrant,
            hasHostAccess: true,
            allowedByHostPermission: false,
            allowedByOptionalHostPermission: false,
            allowedByActiveTab: true,
            matchingHostPatterns: [
                "activeTab:\(ChromeMV3RuntimeMessagingURL.origin(from: syntheticDiagnosticURLString) ?? "invalid")",
            ],
            optionalHostPatternsThatCouldPrompt: [],
            invalidHostPatterns: [],
            unsupportedHostPatterns: [],
            deniedByPattern: false,
            revokedByPattern: false,
            wouldNeedPrompt: false,
            missingReason: .none,
            diagnostics: [
                "URL-hub manager action readiness models activeTab only for the synthetic diagnostic URL and only for explicit invocation.",
            ]
        )
        let preflight =
            ChromeMV3ProductNormalTabReadinessPreflightEvaluator.evaluate(
                input: ChromeMV3ProductNormalTabReadinessPreflightInput(
                    profileID: record.profileID,
                    extensionID: record.extensionID,
                    tabID: "urlhub-manager-action",
                    documentID: "urlhub-manager-action-readiness",
                    urlString: syntheticDiagnosticURLString,
                    moduleEnabled: gate.managerAvailableInDeveloperPreview,
                    extensionEnabled:
                        record.runtimeState.internalRuntimeEnabled,
                    profileEnabled: record.lifecycleState != .uninstalled
                        && record.lifecycleState != .corrupt,
                    localExperimentalProductGateAllowed:
                        gate.managerAvailableInDeveloperPreview,
                    runtimeGateAllowsReadiness: true,
                    contentScriptRouteReady: true,
                    serviceWorkerRouteReady: true,
                    tabSurface: .normalTab,
                    syntheticHTTPSOrigin:
                        ChromeMV3RuntimeMessagingURL.origin(
                            from: syntheticDiagnosticURLString
                        ) ?? "https://sumi.local.test",
                    frameID: 0,
                    isTopFrame: true,
                    contentWorld: .isolated,
                    hostAccessDecision: hostDecision,
                    reviewedResource: reviewedResource,
                    teardownPending: false
                )
            )
        let plan =
            ChromeMV3ProductNormalTabReviewedFileInjectionPlan.make(
                preflight: preflight
            )
        return ChromeMV3ProductNormalTabReadinessReport(
            policy: preflight.policy,
            preflight: preflight,
            injectionPlan: plan,
            lifecycle: .planOnly,
            manualSmokeReadiness:
                ChromeMV3ProductNormalTabManualSmokeReadiness.make(
                    preflight: preflight,
                    plan: plan
                ),
            diagnostics:
                uniqueSortedURLHubMV3(
                    preflight.diagnostics + plan.diagnostics
                )
        )
    }

    private static func permissionBroker(
        rootURL: URL,
        record: ChromeMV3ExtensionLifecycleRecord,
        manifestSummary:
            ChromeMV3ExtensionManagerManifestSummaryViewState
    ) -> ChromeMV3PermissionBroker {
        let persisted = ChromeMV3DeveloperPreviewPermissionStateStore(
            rootURL: rootURL
        )
        .loadRecord(
            profileID: record.profileID,
            extensionID: record.extensionID
        )
        let permissionSnapshot = persisted?.permissionRuntimeSnapshot
            .permissionStore
        let activeTabGrants = persisted?.permissionRuntimeSnapshot
            .activeTabStore
            .grantRecords
            .map(\.grant) ?? []
        return ChromeMV3PermissionBroker(
            state: ChromeMV3PermissionBrokerState(
                extensionID: record.extensionID,
                profileID: record.profileID,
                requiredPermissions: manifestSummary.permissions,
                optionalPermissions: manifestSummary.optionalPermissions,
                grantedOptionalPermissions:
                    permissionSnapshot?.grantedOptionalAPIPermissions ?? [],
                hostPermissions: manifestSummary.hostPermissions,
                optionalHostPermissions:
                    manifestSummary.optionalHostPermissions,
                grantedOptionalHostPermissions:
                    permissionSnapshot?.grantedOptionalHostPermissions ?? [],
                deniedPermissions:
                    permissionSnapshot?.deniedPermissions ?? [],
                revokedPermissions:
                    permissionSnapshot?.revokedPermissions ?? [],
                unavailablePermissions:
                    permissionSnapshot?.deferredPermissions ?? [],
                unsupportedPermissions:
                    permissionSnapshot?.unsupportedPermissions ?? [],
                activeTabGrants: activeTabGrants,
                diagnostics:
                    persisted?.diagnostics ?? [
                        "No persisted URL-hub developer-preview permission state was loaded.",
                    ]
            )
        )
    }

    private static func actionHostAccessDecision(
        passiveDecision: ChromeMV3HostAccessDecision,
        broker: ChromeMV3PermissionBroker,
        currentURL: String,
        tabID: Int?,
        currentPageIsSyntheticDiagnosticPage: Bool
    ) -> ChromeMV3HostAccessDecision {
        if passiveDecision.hasHostAccess {
            return passiveDecision
        }
        guard broker.activeTabPermissionDeclared,
              currentPageIsSyntheticDiagnosticPage,
              let origin = ChromeMV3RuntimeMessagingURL.origin(from: currentURL)
        else {
            return passiveDecision
        }
        return ChromeMV3HostAccessDecision(
            url: currentURL,
            origin: origin,
            status: .allowed,
            grantSource: .activeTabGrant,
            hasHostAccess: true,
            allowedByHostPermission: false,
            allowedByOptionalHostPermission: false,
            allowedByActiveTab: true,
            matchingHostPatterns: ["activeTab:\(origin)"],
            optionalHostPatternsThatCouldPrompt:
                passiveDecision.optionalHostPatternsThatCouldPrompt,
            invalidHostPatterns: passiveDecision.invalidHostPatterns,
            unsupportedHostPatterns: passiveDecision.unsupportedHostPatterns,
            deniedByPattern: passiveDecision.deniedByPattern,
            revokedByPattern: passiveDecision.revokedByPattern,
            wouldNeedPrompt: false,
            missingReason: .none,
            diagnostics:
                passiveDecision.diagnostics
                    + [
                        "URL-hub explicit diagnostic action would model an activeTab grant for tab \(tabID.map(String.init) ?? "unmapped") only after the user invokes the action; passive readout does not persist a grant.",
                    ]
        )
    }

    private static func reviewedResource(
        record: ChromeMV3ExtensionLifecycleRecord,
        report: ChromeMV3EndToEndInstallDiagnosticsReport?
    ) -> ChromeMV3ProductNormalTabReviewedResource {
        let activeVersion =
            record.activeGeneratedVersionID.flatMap { activeID in
                record.generatedBundleVersions.first { $0.id == activeID }
            }
            ?? report?.generatedBundleVersionState.last {
                $0.state == .active || $0.state == .rollbackActive
            }
            ?? record.generatedBundleVersions.last {
                $0.state == .active || $0.state == .rollbackActive
            }
            ?? record.generatedBundleVersions.last
        let reviewedPath =
            ChromeMV3LocalExperimentalProgrammaticInjectionResourceCatalog
            .bitwardenDetectFillBootstrapFile
        let hash = activeVersion.flatMap {
            generatedResourceSHA256(
                rootPath: $0.generatedBundleRootPath,
                relativePath: reviewedPath
            )
        }
        return ChromeMV3ProductNormalTabReviewedResource.bootstrapAutofill(
            generatedBundleRootPath: activeVersion?.generatedBundleRootPath,
            copiedResourcePaths:
                activeVersion?.generatedBundleRecord.copiedResourcePaths ?? [],
            hash: hash
        )
    }

    private static func diagnosticAction(
        readiness: ChromeMV3URLHubCurrentPageReadiness,
        managerAction: ChromeMV3ExtensionManagerManualSmokeActionRecord
    ) -> ChromeMV3URLHubDiagnosticAction {
        var diagnostics = managerAction.unavailableDiagnostics
        if readiness.explicitDiagnosticActionCanRun == false {
            diagnostics.append(
                .make(
                    .manualSmokeUnavailable,
                    severity: .productBlocked,
                    message:
                        "URL-hub current-page diagnostic is blocked by \(readiness.blockers.map(\.rawValue).joined(separator: ", ")).",
                    remediation:
                        "Open the synthetic diagnostic URL in a normal tab and keep the internal local experimental gates satisfied."
                )
            )
        }
        let blockingDiagnostics = diagnostics.filter {
            $0.severity != .info
        }
        let capabilityAvailable =
            readiness.reviewedResource.present
                && readiness.reviewedResource.generatedResourceHash != nil
        let available = managerAction.available
            && readiness.explicitDiagnosticActionCanRun
            && capabilityAvailable
            && blockingDiagnostics.isEmpty
        let lastDOMFillSucceeded =
            managerAction.lastRunStatus == nil
                ? nil
                : managerAction.lastBlockers.isEmpty
        return ChromeMV3URLHubDiagnosticAction(
            actionID: .runBitwardenManualSmoke,
            capabilityID: .reviewedGeneratedResourceNormalTabSmoke,
            capabilityAvailable: capabilityAvailable,
            title: "Run diagnostic smoke",
            available: available,
            disabledReason:
                available
                    ? nil
                    : (
                        readiness.blockers.isEmpty
                            ? managerAction.disabledReason
                            : "Blocked by \(readiness.blockers.map(\.rawValue).joined(separator: ", "))."
                    ),
            unavailableDiagnostics:
                Array(
                    Dictionary(grouping: diagnostics, by: \.code)
                        .compactMap { $0.value.first }
                ).sorted { $0.code < $1.code },
            lastRunStatus: managerAction.lastRunStatus,
            lastArtifactPath: managerAction.lastArtifactPath,
            lastDOMFillSucceeded: lastDOMFillSucceeded,
            lastTeardownCompleted:
                managerAction.lastTeardownStatus.map { $0 == "completed" },
            lastRetainedObjectCount: managerAction.lastRetainedObjectCount,
            notProductSupportLabel: notProductSupportLabel
        )
    }

    private static func generatedResourceSHA256(
        rootPath: String,
        relativePath: String
    ) -> String? {
        let fileURL = URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

extension SumiExtensionsModule {
    func chromeMV3URLHubSectionViewModelIfEnabled(
        rootURL: URL =
            ChromeMV3ExtensionManagerStoreLocation.defaultRootURL(),
        currentPage: ChromeMV3URLHubCurrentPageContext,
        now: Date = Date()
    ) -> ChromeMV3URLHubSectionViewModel? {
        guard isEnabled else { return nil }
        let gate = chromeMV3ExtensionManagerGate()
        guard gate.managerAvailableInDeveloperPreview else { return nil }
        return ChromeMV3URLHubDeveloperPreviewModelBuilder.makeSection(
            rootURL: rootURL,
            gate: gate,
            currentPage: currentPage,
            now: now
        )
    }

    func chromeMV3RunURLHubDiagnosticSmokeThroughURLHub(
        rootURL: URL =
            ChromeMV3ExtensionManagerStoreLocation.defaultRootURL(),
        profileID: String,
        extensionID: String,
        currentPage: ChromeMV3URLHubCurrentPageContext,
        now: @escaping () -> Date = Date.init
    ) async -> ChromeMV3ExtensionManagerActionResult {
        guard
            let section = chromeMV3URLHubSectionViewModelIfEnabled(
                rootURL: rootURL,
                currentPage: currentPage,
                now: now()
            ),
            let row = section.rows.first(where: {
                $0.profileID == profileID && $0.extensionID == extensionID
            })
        else {
            return .blocked(
                action: .runBitwardenManualSmoke,
                diagnostics: [
                    .manualSmokeLocalExperimentalGateClosed,
                    .manualSmokeNotProductSupport,
                ]
            )
        }

        guard row.diagnosticAction.available else {
            return .blocked(
                action: .runBitwardenManualSmoke,
                diagnostics: row.diagnosticAction.unavailableDiagnostics
            )
        }

        return await chromeMV3RunBitwardenManualSmokeThroughManager(
            rootURL: rootURL,
            profileID: profileID,
            extensionID: extensionID,
            now: now
        )
    }
}

private func uniqueSortedURLHubMV3(_ values: [String]) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}
