//
//  ChromeMV3CompatibilityDiagnostics.swift
//  Sumi
//
//  Internal/developer-preview Chrome MV3 diagnostics. This file converts
//  lifecycle reports into readable records and DEBUG-only views. It does not
//  load extension runtime, attach to product tabs, or expose product install UI.
//

import CryptoKit
import Foundation

enum ChromeMV3CompatibilityMatrixStatus:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case internalSyntheticReady
    case webKitSyntheticExecuted = "WebKitSyntheticExecuted"
    case fixtureOnly
    case partial
    case deferred
    case unsupported
    case productBlocked
    case fatal
    case notRequired

    static func < (
        lhs: ChromeMV3CompatibilityMatrixStatus,
        rhs: ChromeMV3CompatibilityMatrixStatus
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3CompatibilityReadinessLevel:
    String,
    Codable,
    Comparable,
    Sendable
{
    case ready
    case partial
    case blocked

    static func < (
        lhs: ChromeMV3CompatibilityReadinessLevel,
        rhs: ChromeMV3CompatibilityReadinessLevel
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3InternalLifecycleAction:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case rebuild
    case updateFromSource
    case uninstall
    case reset
    case runDiagnostics
    case recover
    case runCleanup
    case runFinalReadiness
    case exportReportJSON

    static func < (
        lhs: ChromeMV3InternalLifecycleAction,
        rhs: ChromeMV3InternalLifecycleAction
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3InternalExtensionIdentity:
    Codable,
    Equatable,
    Sendable
{
    var profileID: String
    var extensionID: String
    var displayName: String
    var displayVersion: String
    var installID: String?
    var sourceKind: ChromeMV3PackageSourceKind?
    var sourcePath: String?
}

struct ChromeMV3GeneratedBundleVersionViewState:
    Identifiable,
    Codable,
    Equatable,
    Sendable
{
    var id: String
    var sequence: Int
    var state: ChromeMV3GeneratedBundleVersionState
    var versionRootPath: String
    var generatedBundleRootPath: String
    var rewrittenVariantRootPath: String?
    var runtimeLoadabilityReportPath: String?
    var runtimeLoadable: Bool
    var isActive: Bool
    var isPreviousWorking: Bool
    var isCandidate: Bool
}

struct ChromeMV3GeneratedBundleViewState:
    Codable,
    Equatable,
    Sendable
{
    var activeVersionID: String?
    var previousWorkingVersionID: String?
    var candidateVersionID: String?
    var versions: [ChromeMV3GeneratedBundleVersionViewState]
    var generatedBundleAvailable: Bool
    var failedCandidateCount: Int
}

struct ChromeMV3DiagnosticsProductExposureFlags:
    Codable,
    Equatable,
    Sendable
{
    var internalDiagnosticsUIAvailable: Bool
    var developerPreviewLifecycleAvailable: Bool
    var internalSyntheticRuntimeDiagnosticsAvailable: Bool
    var productRuntimeAvailable: Bool
    var actionPopupUIAvailableInDeveloperPreview: Bool
    var actionPopupUIAvailableInPublicProduct: Bool
    var optionsUIAvailableInDeveloperPreview: Bool
    var optionsUIAvailableInPublicProduct: Bool
    var popupOptionsRuntimeAllowed: Bool
    var popupOptionsBridgeAllowed: Bool
    var popupOptionsJSBridgeAvailableInDeveloperPreview: Bool
    var popupOptionsJSBridgeAvailableInPublicProduct: Bool
    var popupOptionsRuntimeNamespaceAllowed: Bool
    var popupOptionsStorageNamespaceAllowed: Bool
    var popupOptionsPermissionsNamespaceAllowed: Bool
    var popupOptionsTabsNamespaceAllowed: Bool
    var popupOptionsScriptingNamespaceAllowed: Bool
    var popupOptionsNativeMessagingNamespaceAllowed: Bool
    var popupOptionsBlockedAPIs: [String]
    var popupOptionsProductBlockedReason: String?
    var normalTabRuntimeBridgeAvailable: Bool
    var contentScriptAttachmentAvailableInProduct: Bool
    var contentScriptAttachmentAvailableInDeveloperPreview: Bool
    var contentScriptAttachmentAvailableInPublicProduct: Bool
    var contentScriptBridgeAvailableInDeveloperPreview: Bool
    var contentScriptBridgeAvailableInPublicProduct: Bool
    var staticContentScriptsAllowed: Bool
    var dynamicScriptingAllowed: Bool
    var normalTabGeneralRuntimeAvailable: Bool
    var contentScriptBlockedReason: String?
    var runtimeLoadable: Bool
    var productExtensionUIAvailable: Bool
    var productNetworkEnforcementAvailable: Bool
    var productRuntimeExposed: Bool

    static func internalDeveloperPreview(
        diagnosticsUIAvailable: Bool,
        lifecycleAvailable: Bool,
        syntheticDiagnosticsAvailable: Bool,
        popupOptionsGate:
            ChromeMV3ProductPopupOptionsUIGateRecord =
                ChromeMV3ProductPopupOptionsUIGateRecord.evaluate(
                    moduleEnabled: false
                )
    ) -> ChromeMV3DiagnosticsProductExposureFlags {
        ChromeMV3DiagnosticsProductExposureFlags(
            internalDiagnosticsUIAvailable: diagnosticsUIAvailable,
            developerPreviewLifecycleAvailable: lifecycleAvailable,
            internalSyntheticRuntimeDiagnosticsAvailable:
                syntheticDiagnosticsAvailable,
            productRuntimeAvailable: false,
            actionPopupUIAvailableInDeveloperPreview:
                popupOptionsGate.actionPopupUIAvailableInDeveloperPreview,
            actionPopupUIAvailableInPublicProduct:
                popupOptionsGate.actionPopupUIAvailableInPublicProduct,
            optionsUIAvailableInDeveloperPreview:
                popupOptionsGate.optionsUIAvailableInDeveloperPreview,
            optionsUIAvailableInPublicProduct:
                popupOptionsGate.optionsUIAvailableInPublicProduct,
            popupOptionsRuntimeAllowed:
                popupOptionsGate.popupOptionsRuntimeAllowed,
            popupOptionsBridgeAllowed:
                popupOptionsGate.popupOptionsBridgeAllowed,
            popupOptionsJSBridgeAvailableInDeveloperPreview:
                popupOptionsGate
                    .popupOptionsJSBridgeAvailableInDeveloperPreview,
            popupOptionsJSBridgeAvailableInPublicProduct:
                popupOptionsGate
                    .popupOptionsJSBridgeAvailableInPublicProduct,
            popupOptionsRuntimeNamespaceAllowed:
                popupOptionsGate.popupOptionsRuntimeNamespaceAllowed,
            popupOptionsStorageNamespaceAllowed:
                popupOptionsGate.popupOptionsStorageNamespaceAllowed,
            popupOptionsPermissionsNamespaceAllowed:
                popupOptionsGate.popupOptionsPermissionsNamespaceAllowed,
            popupOptionsTabsNamespaceAllowed:
                popupOptionsGate.popupOptionsTabsNamespaceAllowed,
            popupOptionsScriptingNamespaceAllowed:
                popupOptionsGate.popupOptionsScriptingNamespaceAllowed,
            popupOptionsNativeMessagingNamespaceAllowed:
                popupOptionsGate
                    .popupOptionsNativeMessagingNamespaceAllowed,
            popupOptionsBlockedAPIs:
                popupOptionsGate.popupOptionsBlockedAPIs,
            popupOptionsProductBlockedReason:
                popupOptionsGate.popupOptionsProductBlockedReason,
            normalTabRuntimeBridgeAvailable: false,
            contentScriptAttachmentAvailableInProduct: false,
            contentScriptAttachmentAvailableInDeveloperPreview: false,
            contentScriptAttachmentAvailableInPublicProduct: false,
            contentScriptBridgeAvailableInDeveloperPreview: false,
            contentScriptBridgeAvailableInPublicProduct: false,
            staticContentScriptsAllowed: false,
            dynamicScriptingAllowed: false,
            normalTabGeneralRuntimeAvailable: false,
            contentScriptBlockedReason:
                ChromeMV3ContentScriptProductGateRecord.defaultBlocked()
                    .contentScriptBlockedReason,
            runtimeLoadable: false,
            productExtensionUIAvailable: false,
            productNetworkEnforcementAvailable: false,
            productRuntimeExposed: false
        )
    }
}

struct ChromeMV3CompatibilityAPIMatrixRow:
    Identifiable,
    Codable,
    Equatable,
    Sendable
{
    var id: String
    var group: String
    var apiNamespace: String
    var displayName: String
    var chromeDocumentationURL: String
    var statuses: [ChromeMV3CompatibilityMatrixStatus]
    var requiredByCurrentExtension: Bool
    var internalSyntheticCoverageAvailable: Bool
    var webKitSyntheticExecutionAvailable: Bool
    var productBlocked: Bool
    var missingFromCurrentDiagnostics: Bool
    var blockerIDs: [String]
    var notes: [String]
}

struct ChromeMV3CompatibilityBlockerGroup:
    Identifiable,
    Codable,
    Equatable,
    Sendable
{
    var id: String
    var groupKind: String
    var key: String
    var title: String
    var blockers: [ChromeMV3APIBlockerRecord]
}

struct ChromeMV3InternalLifecycleActionDescriptor:
    Identifiable,
    Codable,
    Equatable,
    Sendable
{
    var id: ChromeMV3InternalLifecycleAction { action }
    var action: ChromeMV3InternalLifecycleAction
    var title: String
    var internalOnly: Bool
    var mutatesLifecycle: Bool
    var requiresEnabledModule: Bool
    var enabledForCurrentRecord: Bool
    var note: String
}

struct ChromeMV3CompatibilityReadinessSummary:
    Codable,
    Equatable,
    Sendable
{
    var level: ChromeMV3CompatibilityReadinessLevel
    var internalDeveloperPreviewReady: Bool
    var reportAvailable: Bool
    var generatedBundleAvailable: Bool
    var internalSyntheticRuntimeDiagnosticsAvailable: Bool
    var requiredSyntheticReportsPresent: [String]
    var missingSyntheticReports: [String]
    var fatalInstallBlockerCount: Int
    var fatalRuntimeBlockerCount: Int
    var productEnablementBlockerCount: Int
    var unsupportedAPICount: Int
    var nextRecommendedAction: String
}

struct ChromeMV3CompatibilityReportViewModel:
    Codable,
    Equatable,
    Sendable
{
    static let schemaVersion = 1

    var schemaVersion: Int
    var reportID: String
    var generatedAt: Date
    var extensionIdentity: ChromeMV3InternalExtensionIdentity
    var lifecycleState: ChromeMV3LifecycleState?
    var installImportState: ChromeMV3LifecycleOperationSummary?
    var updateRebuildState: ChromeMV3LifecycleOperationSummary?
    var uninstallResetState: ChromeMV3LifecycleOperationSummary?
    var crashRecoveryStatus: ChromeMV3LifecycleRecoveryStatus
    var generatedBundleState: ChromeMV3GeneratedBundleViewState
    var readinessSummary: ChromeMV3CompatibilityReadinessSummary
    var apiSupportMatrix: [ChromeMV3CompatibilityAPIMatrixRow]
    var blockersBySeverity: [ChromeMV3CompatibilityBlockerGroup]
    var blockersBySource: [ChromeMV3CompatibilityBlockerGroup]
    var blockersByAPI: [ChromeMV3CompatibilityBlockerGroup]
    var blockersByManifestKey: [ChromeMV3CompatibilityBlockerGroup]
    var blockersByResourcePath: [ChromeMV3CompatibilityBlockerGroup]
    var productFlags: ChromeMV3DiagnosticsProductExposureFlags
    var productEnablementPreflight:
        ChromeMV3ProductEnablementPreflightSection
    var internalLifecycleActions: [ChromeMV3InternalLifecycleActionDescriptor]
    var nextRecommendedAction: String

    init(
        report: ChromeMV3EndToEndInstallDiagnosticsReport,
        lifecycleRecord: ChromeMV3ExtensionLifecycleRecord?
    ) {
        let activeVersionID = lifecycleRecord?.activeGeneratedVersionID
            ?? report.generatedBundleVersionState.last {
                $0.state == .active || $0.state == .rollbackActive
            }?.id
        let previousWorkingVersionID =
            lifecycleRecord?.previousWorkingGeneratedVersionID
            ?? report.generatedBundleVersionState.last {
                $0.state == .previousWorking
            }?.id
        let candidateVersionID = lifecycleRecord?.candidateGeneratedVersionID
            ?? report.generatedBundleVersionState.last {
                $0.state == .candidate
            }?.id
        let identity = ChromeMV3InternalExtensionIdentity(
            profileID: lifecycleRecord?.profileID
                ?? "internal-debug-profile",
            extensionID: lifecycleRecord?.extensionID ?? report.id,
            displayName: lifecycleRecord?.displayName
                ?? report.activeManifestSummary?.name
                ?? "Unknown internal MV3 extension",
            displayVersion: lifecycleRecord?.displayVersion
                ?? report.activeManifestSummary?.version
                ?? "unknown",
            installID: lifecycleRecord?.installID,
            sourceKind: lifecycleRecord?.sourceKind,
            sourcePath: lifecycleRecord?.sourcePath
        )
        let bundleVersions = report.generatedBundleVersionState.map {
            ChromeMV3GeneratedBundleVersionViewState(
                id: $0.id,
                sequence: $0.sequence,
                state: $0.state,
                versionRootPath: $0.versionRootPath,
                generatedBundleRootPath: $0.generatedBundleRootPath,
                rewrittenVariantRootPath: $0.rewrittenVariantRootPath,
                runtimeLoadabilityReportPath: $0.runtimeLoadabilityReportPath,
                runtimeLoadable: $0.runtimeLoadable,
                isActive: $0.id == activeVersionID,
                isPreviousWorking: $0.id == previousWorkingVersionID,
                isCandidate: $0.id == candidateVersionID
            )
        }
        let bundleState = ChromeMV3GeneratedBundleViewState(
            activeVersionID: activeVersionID,
            previousWorkingVersionID: previousWorkingVersionID,
            candidateVersionID: candidateVersionID,
            versions: bundleVersions.sorted { $0.sequence < $1.sequence },
            generatedBundleAvailable:
                report.lifecycleAvailability.generatedBundleAvailable,
            failedCandidateCount: bundleVersions.filter {
                $0.state == .failed || $0.state == .candidate
            }.count
        )
        let matrix = ChromeMV3CompatibilityAPIMatrixBuilder.build(report: report)
        let productFlags = ChromeMV3DiagnosticsProductExposureFlags
            .internalDeveloperPreview(
                diagnosticsUIAvailable: ChromeMV3InternalDiagnosticsGate
                    .uiAvailable,
                lifecycleAvailable:
                    report.lifecycleAvailability
                    .extensionInstalledInInternalRegistry,
                syntheticDiagnosticsAvailable:
                    report.lifecycleAvailability
                    .internalSyntheticRuntimeDiagnosticsAvailable,
                popupOptionsGate:
                    ChromeMV3ProductPopupOptionsUIGateRecord.evaluate(
                        moduleEnabled:
                            report.lifecycleAvailability
                            .extensionInstalledInInternalRegistry,
                        lifecycleRecord: lifecycleRecord
                    )
            )
        let productEnablementPreflight =
            ChromeMV3ProductEnablementPreflightSection.make(
                report: report,
                lifecycleRecord: lifecycleRecord
            )
        let readiness = ChromeMV3CompatibilityReadinessSummary.make(
            report: report,
            matrix: matrix
        )
        self.schemaVersion = Self.schemaVersion
        self.reportID = report.id
        self.generatedAt = report.generatedAt
        self.extensionIdentity = identity
        self.lifecycleState = report.registryLifecycleState
        self.installImportState = report.installImportResult
        self.updateRebuildState = report.updateRebuildResult
        self.uninstallResetState = report.uninstallResetResult
        self.crashRecoveryStatus = report.crashRecoveryStatus
        self.generatedBundleState = bundleState
        self.readinessSummary = readiness
        self.apiSupportMatrix = matrix
        self.blockersBySeverity = ChromeMV3CompatibilityBlockerGrouper
            .groups(
                report.blockerTaxonomy,
                kind: "severity",
                key: { $0.severity.rawValue },
                title: { "Severity: \($0)" }
            )
        self.blockersBySource = ChromeMV3CompatibilityBlockerGrouper.groups(
            report.blockerTaxonomy,
            kind: "source",
            key: { $0.source.rawValue },
            title: { "Source: \($0)" }
        )
        self.blockersByAPI = ChromeMV3CompatibilityBlockerGrouper.groups(
            report.blockerTaxonomy,
            kind: "api",
            key: { blocker in
                [
                    blocker.apiNamespace ?? "none",
                    blocker.apiMethod ?? "",
                ]
                .joined(separator: ".")
            },
            title: { "API: \($0)" }
        )
        self.blockersByManifestKey = ChromeMV3CompatibilityBlockerGrouper
            .groups(
                report.blockerTaxonomy.filter { $0.manifestKey != nil },
                kind: "manifestKey",
                key: { $0.manifestKey ?? "none" },
                title: { "Manifest: \($0)" }
            )
        self.blockersByResourcePath = ChromeMV3CompatibilityBlockerGrouper
            .groups(
                report.blockerTaxonomy.filter { $0.filePath != nil },
                kind: "resourcePath",
                key: { $0.filePath ?? "none" },
                title: { "Resource: \($0)" }
            )
        self.productFlags = productFlags
        self.productEnablementPreflight = productEnablementPreflight
        self.internalLifecycleActions = ChromeMV3InternalLifecycleActionDescriptor
            .all(for: lifecycleRecord, report: report)
        self.nextRecommendedAction = report.aggregateAPICompatibility
            .nextRecommendedAction
    }
}

enum ChromeMV3InternalDiagnosticsGate {
    #if DEBUG
        static let uiAvailable = true
    #else
        static let uiAvailable = false
    #endif
}

struct ChromeMV3ProductRuntimeHardeningGuardReport:
    Codable,
    Equatable,
    Sendable
{
    var productRuntimeAvailable: Bool
    var actionPopupUIAvailableInDeveloperPreview: Bool
    var actionPopupUIAvailableInPublicProduct: Bool
    var optionsUIAvailableInDeveloperPreview: Bool
    var optionsUIAvailableInPublicProduct: Bool
    var popupOptionsRuntimeAllowed: Bool
    var popupOptionsBridgeAllowed: Bool
    var popupOptionsJSBridgeAvailableInDeveloperPreview: Bool
    var popupOptionsJSBridgeAvailableInPublicProduct: Bool
    var contentScriptAttachmentAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var productExtensionUIAvailable: Bool
    var productNetworkEnforcementAvailable: Bool
    var productRuntimeExposed: Bool
    var productNormalTabRuntimeBridgeInstalled: Bool
    var productPermissionPromptInstalled: Bool
    var productNetworkRuleAttachmentInstalled: Bool
    var productSidePanelOffscreenIdentityRuntimeInstalled: Bool
    var passes: Bool

    static let blocked = ChromeMV3ProductRuntimeHardeningGuardReport(
        productRuntimeAvailable: false,
        actionPopupUIAvailableInDeveloperPreview: false,
        actionPopupUIAvailableInPublicProduct: false,
        optionsUIAvailableInDeveloperPreview: false,
        optionsUIAvailableInPublicProduct: false,
        popupOptionsRuntimeAllowed: false,
        popupOptionsBridgeAllowed: false,
        popupOptionsJSBridgeAvailableInDeveloperPreview: false,
        popupOptionsJSBridgeAvailableInPublicProduct: false,
        contentScriptAttachmentAvailableInProduct: false,
        normalTabRuntimeBridgeAvailable: false,
        runtimeLoadable: false,
        productExtensionUIAvailable: false,
        productNetworkEnforcementAvailable: false,
        productRuntimeExposed: false,
        productNormalTabRuntimeBridgeInstalled: false,
        productPermissionPromptInstalled: false,
        productNetworkRuleAttachmentInstalled: false,
        productSidePanelOffscreenIdentityRuntimeInstalled: false,
        passes: true
    )
}

enum ChromeMV3ChecklistStatus:
    String,
    Codable,
    Comparable,
    Sendable
{
    case pass
    case partial
    case blocked

    static func < (
        lhs: ChromeMV3ChecklistStatus,
        rhs: ChromeMV3ChecklistStatus
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ChecklistItem: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var status: ChromeMV3ChecklistStatus
    var evidence: String
    var nextAction: String
}

struct ChromeMV3PerformanceBudgetReport:
    Codable,
    Equatable,
    Sendable
{
    static let fileName = "runtime-mv3-performance-budget-report.json"

    var schemaVersion: Int
    var items: [ChromeMV3ChecklistItem]
    var passed: Bool

    static func currentInternalDeveloperPreview() -> Self {
        let items = [
            ChromeMV3ChecklistItem(
                id: "disabled-module-zero-runtime-work",
                title: "Disabled extension module performs zero runtime work",
                status: .pass,
                evidence:
                    "Disabled module guards return before lifecycle registry or runtime objects are inspected.",
                nextAction:
                    "Keep disabled-state tests in every product enablement phase."
            ),
            ChromeMV3ChecklistItem(
                id: "no-background-scheduling",
                title: "No background scheduling loops",
                status: .pass,
                evidence:
                    "Diagnostics, cleanup, and report writes are explicit calls only.",
                nextAction:
                    "Do not add automatic checks before a product performance plan exists."
            ),
            ChromeMV3ChecklistItem(
                id: "no-hidden-webviews",
                title: "No hidden WebViews outside explicit synthetic harnesses",
                status: .pass,
                evidence:
                    "Product flags keep normal tab runtime and offscreen product runtime unavailable.",
                nextAction:
                    "Require a separate hidden-surface design before product offscreen work."
            ),
            ChromeMV3ChecklistItem(
                id: "native-host-fixture-only",
                title: "Native messaging remains fixture-only",
                status: .pass,
                evidence:
                    "Diagnostics records do not launch arbitrary native hosts.",
                nextAction:
                    "Keep host lookup under fixture-root validation until product policy exists."
            ),
            ChromeMV3ChecklistItem(
                id: "explicit-artifact-operations",
                title: "Generated bundle and report operations are explicit",
                status: .pass,
                evidence:
                    "Install, update, rebuild, cleanup, and readiness reports run only through internal calls.",
                nextAction:
                    "Keep report refresh out of startup and normal-tab paths."
            ),
            ChromeMV3ChecklistItem(
                id: "normal-tabs-zero-overhead",
                title: "Normal tabs have no MV3 overhead while product runtime is disabled",
                status: .pass,
                evidence:
                    "Product runtime, normal-tab bridge, and product network enforcement flags are false.",
                nextAction:
                    "Measure normal-tab overhead before any product runtime gate can change."
            ),
        ]
        return ChromeMV3PerformanceBudgetReport(
            schemaVersion: 1,
            items: items,
            passed: items.allSatisfy { $0.status == .pass }
        )
    }
}

struct ChromeMV3ThreatModelChecklistReport:
    Codable,
    Equatable,
    Sendable
{
    static let fileName = "runtime-mv3-threat-model-checklist-report.json"

    var schemaVersion: Int
    var scope: String
    var trustBoundaries: [ChromeMV3ChecklistItem]
    var productEnablementPrerequisites: [String]
    var passed: Bool

    static func currentInternalDeveloperPreview() -> Self {
        let boundaries = [
            ChromeMV3ChecklistItem(
                id: "package-intake",
                title: "Extension package intake",
                status: .partial,
                evidence:
                    "Unpacked MV3 intake validates manifest shape and resource paths for internal diagnostics.",
                nextAction:
                    "Add product-grade package provenance, signing, and user consent before public install."
            ),
            ChromeMV3ChecklistItem(
                id: "path-resource-validation",
                title: "Path traversal and resource validation",
                status: .pass,
                evidence:
                    "Generated-bundle writers reject unsafe or escaping resource paths.",
                nextAction:
                    "Keep all resource copies rooted in staged original bundles."
            ),
            ChromeMV3ChecklistItem(
                id: "generated-bundle-boundary",
                title: "Generated bundle trust boundary",
                status: .pass,
                evidence:
                    "Generated bundles are diagnostics artifacts and remain non-loadable in product.",
                nextAction:
                    "Require a product loading review before any generated bundle is attached."
            ),
            ChromeMV3ChecklistItem(
                id: "js-bridge-boundary",
                title: "JS bridge boundary",
                status: .blocked,
                evidence:
                    "Normal-tab JS bridge exposure is unavailable in this phase.",
                nextAction:
                    "Design product bridge isolation, permission checks, and test coverage in a later phase."
            ),
            ChromeMV3ChecklistItem(
                id: "native-messaging-boundary",
                title: "Native messaging process boundary",
                status: .blocked,
                evidence:
                    "Only fixture native messaging is allowed; arbitrary host launch remains blocked.",
                nextAction:
                    "Define host discovery, signing, consent, and teardown before product use."
            ),
            ChromeMV3ChecklistItem(
                id: "identity-token-boundary",
                title: "Identity and token boundary",
                status: .blocked,
                evidence:
                    "OAuth and external auth network flows are product-blocked.",
                nextAction:
                    "Design token storage, account isolation, revocation, and consent before enabling."
            ),
            ChromeMV3ChecklistItem(
                id: "network-enforcement-boundary",
                title: "DNR and network enforcement boundary",
                status: .blocked,
                evidence:
                    "Product request observation, blocking, and declarative enforcement are unavailable.",
                nextAction:
                    "Keep optional Sumi adblock/tracking modules separate from MV3 diagnostics."
            ),
            ChromeMV3ChecklistItem(
                id: "permission-active-tab-boundary",
                title: "Permission and activeTab boundary",
                status: .partial,
                evidence:
                    "Internal permission diagnostics exist, but product prompts and normal-tab grant flow are absent.",
                nextAction:
                    "Add product UX, storage, revocation, and audit before user-facing grants."
            ),
            ChromeMV3ChecklistItem(
                id: "offscreen-hidden-surface-boundary",
                title: "Offscreen and hidden WebView boundary",
                status: .blocked,
                evidence:
                    "Offscreen documents are model/synthetic diagnostics only.",
                nextAction:
                    "Require explicit lifecycle, memory, visibility, and teardown policy before product use."
            ),
        ]
        return ChromeMV3ThreatModelChecklistReport(
            schemaVersion: 1,
            scope: "Internal Chrome MV3 developer-preview diagnostics",
            trustBoundaries: boundaries,
            productEnablementPrerequisites: [
                "Product normal-tab runtime bridge design and tests.",
                "Product permission UI and revocation model.",
                "Product network enforcement policy separate from Sumi adblock/tracking modules.",
                "Product native messaging host policy.",
                "Product identity and token security design.",
                "Measured normal-tab performance budget.",
            ],
            passed: boundaries.allSatisfy { $0.status != .blocked }
        )
    }
}

struct ChromeMV3ArtifactCleanupReport:
    Codable,
    Equatable,
    Sendable
{
    static let fileName = "runtime-mv3-artifact-cleanup-report.json"

    var schemaVersion: Int
    var generatedAt: Date
    var profileID: String
    var extensionID: String
    var removedGeneratedVersionIDs: [String]
    var preservedGeneratedVersionIDs: [String]
    var corruptReportRemoved: Bool
    var crashMarkerRemoved: Bool
    var uninstalledTombstonePreserved: Bool
    var internalRuntimeStateReset: Bool
    var productProfileDataDeleted: Bool
    var diagnostics: [String]
}

struct ChromeMV3FoundationReadinessReport:
    Codable,
    Equatable,
    Sendable
{
    static let fileName = "runtime-mv3-foundation-readiness-report.json"

    var schemaVersion: Int
    var generatedAt: Date
    var viewModel: ChromeMV3CompatibilityReportViewModel?
    var apiMatrix: [ChromeMV3CompatibilityAPIMatrixRow]
    var blockerSummary: [ChromeMV3CompatibilityBlockerGroup]
    var securityChecklist: ChromeMV3ThreatModelChecklistReport
    var performanceBudget: ChromeMV3PerformanceBudgetReport
    var artifactCleanup: ChromeMV3ArtifactCleanupReport?
    var productRuntimeGuard: ChromeMV3ProductRuntimeHardeningGuardReport
    var productEnablementPreflight:
        ChromeMV3ProductEnablementPreflightSection?
    var missingRequiredInternalReports: [String]
    var finalPhaseStatus: ChromeMV3FoundationPhaseStatus
}

struct ChromeMV3FoundationPhaseStatus:
    Codable,
    Equatable,
    Sendable
{
    var internalDeveloperPreviewReady: Bool
    var readinessLevel: ChromeMV3CompatibilityReadinessLevel
    var productRuntimeAvailable: Bool
    var actionPopupUIAvailableInDeveloperPreview: Bool
    var actionPopupUIAvailableInPublicProduct: Bool
    var optionsUIAvailableInDeveloperPreview: Bool
    var optionsUIAvailableInPublicProduct: Bool
    var popupOptionsRuntimeAllowed: Bool
    var popupOptionsBridgeAllowed: Bool
    var popupOptionsJSBridgeAvailableInDeveloperPreview: Bool
    var popupOptionsJSBridgeAvailableInPublicProduct: Bool
    var contentScriptAttachmentAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var productExtensionUIAvailable: Bool
    var productNetworkEnforcementAvailable: Bool
    var productRuntimeExposed: Bool
    var nextRecommendedAction: String

    static func make(
        viewModel: ChromeMV3CompatibilityReportViewModel?,
        missingRequiredInternalReports: [String]
    ) -> Self {
        let ready = viewModel?.readinessSummary.internalDeveloperPreviewReady
            == true
            && missingRequiredInternalReports.isEmpty
        let level: ChromeMV3CompatibilityReadinessLevel
        if ready {
            level = .ready
        } else if viewModel == nil {
            level = .blocked
        } else {
            level = .partial
        }
        return ChromeMV3FoundationPhaseStatus(
            internalDeveloperPreviewReady: ready,
            readinessLevel: level,
            productRuntimeAvailable: false,
            actionPopupUIAvailableInDeveloperPreview:
                viewModel?.productFlags
                    .actionPopupUIAvailableInDeveloperPreview ?? false,
            actionPopupUIAvailableInPublicProduct: false,
            optionsUIAvailableInDeveloperPreview:
                viewModel?.productFlags
                    .optionsUIAvailableInDeveloperPreview ?? false,
            optionsUIAvailableInPublicProduct: false,
            popupOptionsRuntimeAllowed:
                viewModel?.productFlags.popupOptionsRuntimeAllowed ?? false,
            popupOptionsBridgeAllowed:
                viewModel?.productFlags.popupOptionsBridgeAllowed ?? false,
            popupOptionsJSBridgeAvailableInDeveloperPreview:
                viewModel?.productFlags
                    .popupOptionsJSBridgeAvailableInDeveloperPreview ?? false,
            popupOptionsJSBridgeAvailableInPublicProduct: false,
            contentScriptAttachmentAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            productExtensionUIAvailable: false,
            productNetworkEnforcementAvailable: false,
            productRuntimeExposed: false,
            nextRecommendedAction:
                viewModel?.nextRecommendedAction
                ?? "Install an internal MV3 extension and run diagnostics."
        )
    }
}

extension ChromeMV3CompatibilityReadinessSummary {
    static let requiredSyntheticReports = [
        "DNR/webRequest",
        "WebKitObject",
        "chrome.permissions",
        "chrome.runtime",
        "chrome.storage.local",
        "chrome.tabs/chrome.scripting",
        "contextCreationGate",
        "contextMenus/alarms/webNavigation",
        "controllerLoadGate",
        "runtimeBridgeReadiness",
        "serviceWorkerLifecycle",
        "sidePanel/offscreen/identity",
    ].sorted()

    static func make(
        report: ChromeMV3EndToEndInstallDiagnosticsReport,
        matrix: [ChromeMV3CompatibilityAPIMatrixRow]
    ) -> ChromeMV3CompatibilityReadinessSummary {
        let present = Set(
            report.internalSyntheticReadinessSummary.syntheticAPIReportsAvailable
        )
        let missing = requiredSyntheticReports.filter { !present.contains($0) }
        let blockers = report.blockerTaxonomy
        let fatalInstallCount = blockers.filter {
            $0.severity == .fatalInstall
        }.count
        let fatalRuntimeCount = blockers.filter {
            $0.severity == .fatalRuntime
        }.count
        let productBlockerCount = blockers.filter {
            $0.severity == .productBlocked
        }.count
        let unsupportedCount = matrix.filter {
            $0.statuses.contains(.unsupported)
        }.count
        let reportAvailable = report.lifecycleAvailability
            .compatibilityReportAvailable
        let generatedAvailable = report.lifecycleAvailability
            .generatedBundleAvailable
        let syntheticAvailable = report.lifecycleAvailability
            .internalSyntheticRuntimeDiagnosticsAvailable
        let ready = reportAvailable
            && generatedAvailable
            && syntheticAvailable
            && missing.isEmpty
            && fatalInstallCount == 0
            && fatalRuntimeCount == 0
        let level: ChromeMV3CompatibilityReadinessLevel
        if ready {
            level = .ready
        } else if fatalInstallCount > 0 || fatalRuntimeCount > 0 {
            level = .blocked
        } else {
            level = .partial
        }
        return ChromeMV3CompatibilityReadinessSummary(
            level: level,
            internalDeveloperPreviewReady: ready,
            reportAvailable: reportAvailable,
            generatedBundleAvailable: generatedAvailable,
            internalSyntheticRuntimeDiagnosticsAvailable: syntheticAvailable,
            requiredSyntheticReportsPresent:
                requiredSyntheticReports.filter { present.contains($0) },
            missingSyntheticReports: missing,
            fatalInstallBlockerCount: fatalInstallCount,
            fatalRuntimeBlockerCount: fatalRuntimeCount,
            productEnablementBlockerCount: productBlockerCount,
            unsupportedAPICount: unsupportedCount,
            nextRecommendedAction:
                report.aggregateAPICompatibility.nextRecommendedAction
        )
    }
}

private struct ChromeMV3CompatibilityAPIDefinition: Sendable {
    var id: String
    var group: String
    var displayName: String
    var api: ChromeMV3API?
    var documentationURL: String
    var diagnosticReportName: String?
    var webKitSyntheticReportName: String?
    var productRuntimeRequired: Bool
    var fixtureOnlyWhenCovered: Bool
    var defaultStatus: ChromeMV3CompatibilityMatrixStatus
    var isRequired: @Sendable (ChromeMV3EndToEndInstallDiagnosticsReport) -> Bool
}

enum ChromeMV3CompatibilityAPIMatrixBuilder {
    static func build(
        report: ChromeMV3EndToEndInstallDiagnosticsReport
    ) -> [ChromeMV3CompatibilityAPIMatrixRow] {
        definitions.map { definition in
            row(definition: definition, report: report)
        }
        .sorted {
            if $0.group != $1.group {
                return $0.group < $1.group
            }
            return $0.id < $1.id
        }
    }

    private static func row(
        definition: ChromeMV3CompatibilityAPIDefinition,
        report: ChromeMV3EndToEndInstallDiagnosticsReport
    ) -> ChromeMV3CompatibilityAPIMatrixRow {
        let required = definition.isRequired(report)
        let blockers = report.blockerTaxonomy.filter {
            guard let api = definition.api?.rawValue else {
                return false
            }
            return $0.apiNamespace == api
                || $0.manifestKey == definition.id
                || $0.manifestKey == definition.api?.rawValue
        }
        let reportNames = Set(
            report.internalSyntheticReadinessSummary.syntheticAPIReportsAvailable
        )
        let diagnosticCovered = definition.diagnosticReportName.map {
            reportNames.contains($0)
        } ?? false
        let webKitExecuted = definition.webKitSyntheticReportName.map {
            reportNames.contains($0)
        } ?? false
        var statuses: Set<ChromeMV3CompatibilityMatrixStatus> = []
        if required == false {
            statuses.insert(.notRequired)
        }
        if diagnosticCovered {
            statuses.insert(.internalSyntheticReady)
            if definition.fixtureOnlyWhenCovered {
                statuses.insert(.fixtureOnly)
            }
        }
        if webKitExecuted {
            statuses.insert(.webKitSyntheticExecuted)
        }
        if let api = definition.api {
            if report.aggregateAPICompatibility.partialAPIs.contains(api) {
                statuses.insert(.partial)
            }
            if report.aggregateAPICompatibility.deferredAPIs.contains(api) {
                statuses.insert(.deferred)
            }
            if report.aggregateAPICompatibility.unsupportedAPIs.contains(api) {
                statuses.insert(.unsupported)
            }
        }
        if blockers.contains(where: {
            $0.severity == .fatalInstall || $0.severity == .fatalRuntime
        }) {
            statuses.insert(.fatal)
        }
        if definition.defaultStatus == .deferred {
            statuses.insert(.deferred)
        }
        let productBlocked = required
            && (
                definition.productRuntimeRequired
                    || blockers.contains { $0.severity == .productBlocked }
                    || definition.api.map {
                        report.aggregateAPICompatibility.productBlockedAPIs
                            .contains($0)
                    } == true
            )
        if productBlocked {
            statuses.insert(.productBlocked)
        }
        if statuses.isEmpty {
            statuses.insert(definition.defaultStatus)
        }
        let missingDiagnostics = required
            && definition.diagnosticReportName != nil
            && diagnosticCovered == false
        return ChromeMV3CompatibilityAPIMatrixRow(
            id: definition.id,
            group: definition.group,
            apiNamespace: definition.api?.rawValue ?? definition.id,
            displayName: definition.displayName,
            chromeDocumentationURL: definition.documentationURL,
            statuses: statuses.sorted(),
            requiredByCurrentExtension: required,
            internalSyntheticCoverageAvailable: diagnosticCovered,
            webKitSyntheticExecutionAvailable: webKitExecuted,
            productBlocked: productBlocked,
            missingFromCurrentDiagnostics: missingDiagnostics,
            blockerIDs: blockers.map(\.id).sorted(),
            notes: notes(
                definition: definition,
                required: required,
                diagnosticCovered: diagnosticCovered,
                webKitExecuted: webKitExecuted,
                productBlocked: productBlocked
            )
        )
    }

    private static func notes(
        definition: ChromeMV3CompatibilityAPIDefinition,
        required: Bool,
        diagnosticCovered: Bool,
        webKitExecuted: Bool,
        productBlocked: Bool
    ) -> [String] {
        var notes: [String] = []
        if required == false {
            notes.append("Not required by the current extension manifest/report.")
        }
        if diagnosticCovered {
            notes.append("Covered by explicit internal synthetic diagnostics.")
        }
        if webKitExecuted {
            notes.append("Executed only in the WebKit synthetic harness.")
        }
        if productBlocked {
            notes.append("Product runtime remains unavailable for this API.")
        }
        return Array(Set(notes)).sorted()
    }

    private static let apiReference =
        "https://developer.chrome.com/docs/extensions/reference/api"
    private static let serviceWorkerLifecycle =
        "https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle"
    private static let activeTab =
        "https://developer.chrome.com/docs/extensions/develop/concepts/activeTab"
    private static let contentScripts =
        "https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts"
    private static let extensionPages =
        "https://developer.chrome.com/docs/extensions/develop/ui"

    private static let definitions: [ChromeMV3CompatibilityAPIDefinition] = [
        definition(
            id: "runtime",
            group: "core",
            displayName: "runtime",
            api: .runtime,
            documentationURL: "\(apiReference)/runtime",
            diagnosticReportName: "chrome.runtime",
            productRuntimeRequired: true,
            defaultStatus: .partial,
            isRequired: { _ in true }
        ),
        definition(
            id: "tabs",
            group: "core",
            displayName: "tabs",
            api: .tabs,
            documentationURL: "\(apiReference)/tabs",
            diagnosticReportName: "chrome.tabs/chrome.scripting",
            productRuntimeRequired: true,
            defaultStatus: .partial,
            isRequired: { $0.requiresPermission("tabs") }
        ),
        definition(
            id: "scripting",
            group: "core",
            displayName: "scripting",
            api: .scripting,
            documentationURL: "\(apiReference)/scripting",
            diagnosticReportName: "chrome.tabs/chrome.scripting",
            productRuntimeRequired: true,
            defaultStatus: .partial,
            isRequired: {
                $0.requiresPermission("scripting")
                    || ($0.activeManifestSummary?.contentScriptCount ?? 0) > 0
            }
        ),
        definition(
            id: "permissions",
            group: "core",
            displayName: "permissions",
            api: .permissions,
            documentationURL: "\(apiReference)/permissions",
            diagnosticReportName: "chrome.permissions",
            productRuntimeRequired: true,
            defaultStatus: .partial,
            isRequired: {
                $0.requiresPermission("permissions")
                    || ($0.activeManifestSummary?.optionalPermissions.isEmpty
                        == false)
                    || ($0.activeManifestSummary?.hostPermissions.isEmpty
                        == false)
            }
        ),
        definition(
            id: "i18n",
            group: "core",
            displayName: "i18n",
            api: .i18n,
            documentationURL: "\(apiReference)/i18n",
            diagnosticReportName: nil,
            productRuntimeRequired: true,
            defaultStatus: .partial,
            isRequired: {
                $0.blockerTaxonomy.contains {
                    $0.apiNamespace == ChromeMV3API.i18n.rawValue
                }
            }
        ),
        definition(
            id: "activeTab",
            group: "core",
            displayName: "activeTab",
            api: .activeTab,
            documentationURL: activeTab,
            diagnosticReportName: "chrome.permissions",
            productRuntimeRequired: true,
            defaultStatus: .partial,
            isRequired: { $0.requiresPermission("activeTab") }
        ),
        definition(
            id: "storage.local",
            group: "storage",
            displayName: "storage.local",
            api: .storage,
            documentationURL: "\(apiReference)/storage",
            diagnosticReportName: "chrome.storage.local",
            productRuntimeRequired: true,
            defaultStatus: .partial,
            isRequired: { $0.requiresPermission("storage") }
        ),
        definition(
            id: "storage.sync",
            group: "storage",
            displayName: "storage.sync",
            api: .storage,
            documentationURL: "\(apiReference)/storage",
            diagnosticReportName: nil,
            productRuntimeRequired: true,
            defaultStatus: .deferred,
            isRequired: { $0.requiresPermission("storage") }
        ),
        definition(
            id: "nativeMessaging",
            group: "native",
            displayName: "native messaging",
            api: .nativeMessaging,
            documentationURL:
                "https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging",
            diagnosticReportName: "chrome.runtime.nativeMessaging",
            productRuntimeRequired: true,
            fixtureOnlyWhenCovered: true,
            defaultStatus: .deferred,
            isRequired: { $0.requiresPermission("nativeMessaging") }
        ),
        definition(
            id: "serviceWorkerLifecycle",
            group: "lifecycle",
            displayName: "service worker lifecycle",
            api: .runtime,
            documentationURL: serviceWorkerLifecycle,
            diagnosticReportName: "serviceWorkerLifecycle",
            productRuntimeRequired: true,
            defaultStatus: .partial,
            isRequired: {
                $0.activeManifestSummary?.backgroundServiceWorker != nil
            }
        ),
        definition(
            id: "contextMenus",
            group: "events",
            displayName: "contextMenus",
            api: .contextMenus,
            documentationURL: "\(apiReference)/contextMenus",
            diagnosticReportName: "contextMenus/alarms/webNavigation",
            productRuntimeRequired: true,
            defaultStatus: .partial,
            isRequired: { $0.requiresPermission("contextMenus") }
        ),
        definition(
            id: "alarms",
            group: "events",
            displayName: "alarms",
            api: .alarms,
            documentationURL: "\(apiReference)/alarms",
            diagnosticReportName: "contextMenus/alarms/webNavigation",
            productRuntimeRequired: true,
            defaultStatus: .partial,
            isRequired: { $0.requiresPermission("alarms") }
        ),
        definition(
            id: "webNavigation",
            group: "events",
            displayName: "webNavigation",
            api: .webNavigation,
            documentationURL: "\(apiReference)/webNavigation",
            diagnosticReportName: "contextMenus/alarms/webNavigation",
            productRuntimeRequired: true,
            defaultStatus: .partial,
            isRequired: { $0.requiresPermission("webNavigation") }
        ),
        definition(
            id: "declarativeNetRequest",
            group: "network",
            displayName: "declarativeNetRequest",
            api: .declarativeNetRequest,
            documentationURL: "\(apiReference)/declarativeNetRequest",
            diagnosticReportName: "DNR/webRequest",
            productRuntimeRequired: true,
            fixtureOnlyWhenCovered: true,
            defaultStatus: .partial,
            isRequired: {
                $0.requiresPermission("declarativeNetRequest")
                    || ($0.activeManifestSummary?.hasDeclarativeNetRequest
                        == true)
            }
        ),
        definition(
            id: "webRequest",
            group: "network",
            displayName: "webRequest",
            api: .webRequest,
            documentationURL: "\(apiReference)/webRequest",
            diagnosticReportName: "DNR/webRequest",
            productRuntimeRequired: true,
            fixtureOnlyWhenCovered: true,
            defaultStatus: .partial,
            isRequired: {
                $0.requiresPermission("webRequest")
                    || $0.requiresPermission("webRequestBlocking")
            }
        ),
        definition(
            id: "sidePanel",
            group: "ui",
            displayName: "sidePanel",
            api: .sidePanel,
            documentationURL: "\(apiReference)/sidePanel",
            diagnosticReportName: "sidePanel/offscreen/identity",
            webKitSyntheticReportName: "sidePanel/offscreen/identity",
            productRuntimeRequired: true,
            defaultStatus: .deferred,
            isRequired: {
                $0.requiresPermission("sidePanel")
                    || ($0.activeManifestSummary?.hasSidePanel == true)
            }
        ),
        definition(
            id: "offscreen",
            group: "ui",
            displayName: "offscreen",
            api: .offscreen,
            documentationURL: "\(apiReference)/offscreen",
            diagnosticReportName: "sidePanel/offscreen/identity",
            webKitSyntheticReportName: "sidePanel/offscreen/identity",
            productRuntimeRequired: true,
            defaultStatus: .deferred,
            isRequired: { $0.requiresPermission("offscreen") }
        ),
        definition(
            id: "identity",
            group: "identity",
            displayName: "identity",
            api: .identity,
            documentationURL: "\(apiReference)/identity",
            diagnosticReportName: "sidePanel/offscreen/identity",
            webKitSyntheticReportName: "sidePanel/offscreen/identity",
            productRuntimeRequired: true,
            defaultStatus: .deferred,
            isRequired: {
                $0.requiresPermission("identity")
                    || $0.requiresPermission("identity.email")
                    || $0.blockerTaxonomy.contains {
                        $0.source == .identity
                    }
            }
        ),
        definition(
            id: "action popup/options",
            group: "extension pages",
            displayName: "action popup/options",
            api: .action,
            documentationURL: "\(apiReference)/action",
            diagnosticReportName: "chrome.runtime",
            productRuntimeRequired: true,
            defaultStatus: .partial,
            isRequired: {
                $0.activeManifestSummary?.hasAction == true
                    || $0.activeManifestSummary?.hasOptionsPage == true
            }
        ),
        definition(
            id: "content scripts",
            group: "extension pages",
            displayName: "content scripts",
            api: .scripting,
            documentationURL: contentScripts,
            diagnosticReportName: "chrome.tabs/chrome.scripting",
            productRuntimeRequired: true,
            defaultStatus: .partial,
            isRequired: {
                ($0.activeManifestSummary?.contentScriptCount ?? 0) > 0
            }
        ),
        definition(
            id: "extension pages",
            group: "extension pages",
            displayName: "extension pages",
            api: .runtime,
            documentationURL: extensionPages,
            diagnosticReportName: "chrome.runtime",
            productRuntimeRequired: true,
            defaultStatus: .partial,
            isRequired: {
                $0.activeManifestSummary?.hasAction == true
                    || $0.activeManifestSummary?.hasOptionsPage == true
                    || $0.activeManifestSummary?.hasSidePanel == true
            }
        ),
    ]

    private static func definition(
        id: String,
        group: String,
        displayName: String,
        api: ChromeMV3API?,
        documentationURL: String,
        diagnosticReportName: String?,
        webKitSyntheticReportName: String? = nil,
        productRuntimeRequired: Bool,
        fixtureOnlyWhenCovered: Bool = false,
        defaultStatus: ChromeMV3CompatibilityMatrixStatus,
        isRequired:
            @escaping @Sendable (ChromeMV3EndToEndInstallDiagnosticsReport)
            -> Bool
    ) -> ChromeMV3CompatibilityAPIDefinition {
        ChromeMV3CompatibilityAPIDefinition(
            id: id,
            group: group,
            displayName: displayName,
            api: api,
            documentationURL: documentationURL,
            diagnosticReportName: diagnosticReportName,
            webKitSyntheticReportName: webKitSyntheticReportName,
            productRuntimeRequired: productRuntimeRequired,
            fixtureOnlyWhenCovered: fixtureOnlyWhenCovered,
            defaultStatus: defaultStatus,
            isRequired: isRequired
        )
    }
}

private enum ChromeMV3CompatibilityBlockerGrouper {
    static func groups(
        _ blockers: [ChromeMV3APIBlockerRecord],
        kind: String,
        key: (ChromeMV3APIBlockerRecord) -> String,
        title: (String) -> String
    ) -> [ChromeMV3CompatibilityBlockerGroup] {
        Dictionary(grouping: blockers, by: key)
            .map { groupKey, values in
                ChromeMV3CompatibilityBlockerGroup(
                    id: "\(kind)-\(groupKey)",
                    groupKind: kind,
                    key: groupKey,
                    title: title(groupKey),
                    blockers: values.sorted {
                        if $0.severity != $1.severity {
                            return $0.severity < $1.severity
                        }
                        if $0.source != $1.source {
                            return $0.source < $1.source
                        }
                        return $0.id < $1.id
                    }
                )
            }
            .sorted {
                if $0.key != $1.key {
                    return $0.key < $1.key
                }
                return $0.id < $1.id
            }
    }
}

extension ChromeMV3InternalLifecycleActionDescriptor {
    static func all(
        for record: ChromeMV3ExtensionLifecycleRecord?,
        report: ChromeMV3EndToEndInstallDiagnosticsReport
    ) -> [ChromeMV3InternalLifecycleActionDescriptor] {
        let installed = record?.lifecycleState != .uninstalled
            && record != nil
            && report.lifecycleAvailability.extensionInstalledInInternalRegistry
        return ChromeMV3InternalLifecycleAction.allCases.sorted().map {
            descriptor(action: $0, installed: installed)
        }
    }

    private static func descriptor(
        action: ChromeMV3InternalLifecycleAction,
        installed: Bool
    ) -> ChromeMV3InternalLifecycleActionDescriptor {
        ChromeMV3InternalLifecycleActionDescriptor(
            action: action,
            title: title(for: action),
            internalOnly: true,
            mutatesLifecycle: mutates(action),
            requiresEnabledModule: true,
            enabledForCurrentRecord:
                action == .exportReportJSON
                || action == .runFinalReadiness
                || installed,
            note: "DEBUG/internal developer-preview action; product runtime remains unavailable."
        )
    }

    private static func title(for action: ChromeMV3InternalLifecycleAction)
        -> String
    {
        switch action {
        case .rebuild:
            return "Rebuild Generated Bundle"
        case .updateFromSource:
            return "Update From Source"
        case .uninstall:
            return "Uninstall Internal Record"
        case .reset:
            return "Reset Internal State"
        case .runDiagnostics:
            return "Run Diagnostics"
        case .recover:
            return "Run Recovery"
        case .runCleanup:
            return "Run Cleanup"
        case .runFinalReadiness:
            return "Run Final Readiness"
        case .exportReportJSON:
            return "Export Report JSON"
        }
    }

    private static func mutates(_ action: ChromeMV3InternalLifecycleAction)
        -> Bool
    {
        switch action {
        case .rebuild, .updateFromSource, .uninstall, .reset, .recover,
             .runCleanup, .runFinalReadiness, .runDiagnostics:
            return true
        case .exportReportJSON:
            return false
        }
    }
}

extension ChromeMV3EndToEndInstallDiagnosticsReport {
    fileprivate var activeManifestSummary: ChromeMV3ManifestSummary? {
        let active = generatedBundleVersionState.last {
            $0.state == .active || $0.state == .rollbackActive
        } ?? generatedBundleVersionState.last
        return active?.generatedBundleRecord.installReportSummary
            .manifestSummary
    }

    fileprivate func requiresPermission(_ permission: String) -> Bool {
        guard let summary = activeManifestSummary else { return false }
        return summary.permissions.contains(permission)
            || summary.optionalPermissions.contains(permission)
            || summary.hostPermissions.contains(permission)
    }
}

extension ChromeMV3ExtensionLifecycleRegistry {
    func listLifecycleRecords() -> [ChromeMV3ExtensionLifecycleRecord] {
        lifecycleRecordURLsForDiagnostics()
            .compactMap {
                try? decodeDiagnostics(
                    ChromeMV3ExtensionLifecycleRecord.self,
                    at: $0
                )
            }
            .sorted {
                if $0.profileID != $1.profileID {
                    return $0.profileID < $1.profileID
                }
                if $0.displayName != $1.displayName {
                    return $0.displayName < $1.displayName
                }
                return $0.extensionID < $1.extensionID
            }
    }

    func listInstalledExtensionStates()
        -> [ChromeMV3InstalledExtensionState]
    {
        listLifecycleRecords().compactMap { installedExtensionState(from: $0) }
    }

    func installedExtensionState(
        profileID: String,
        extensionID: String
    ) -> ChromeMV3InstalledExtensionState? {
        loadLifecycleRecord(
            profileID: profileID,
            extensionID: extensionID
        ).flatMap { installedExtensionState(from: $0) }
    }

    private func installedExtensionState(
        from record: ChromeMV3ExtensionLifecycleRecord
    ) -> ChromeMV3InstalledExtensionState? {
        guard record.lifecycleState != .uninstalled else {
            return nil
        }
        let active = activeGeneratedVersion(forInstalledState: record)
        let generatedRecord = active?.generatedBundleRecord
        let manifestSummary = generatedRecord?.installReportSummary
            .manifestSummary
        let generatedBundleHash = generatedRecord.flatMap {
            generatedBundleMetadataHash($0)
        }
        let generatedState =
            ChromeMV3InstalledExtensionGeneratedBundleState(
                activeVersionID: active?.id,
                generatedBundleRecordID: active?.generatedBundleRecordID,
                generatedBundleRootPath: active?.generatedBundleRootPath,
                generatedBundleHash: generatedBundleHash,
                generatedManifestHash:
                    generatedRecord?.generatedManifestSHA256
                        ?? active?.generatedManifestSHA256,
                manifestHash:
                    generatedRecord?.manifestSHA256
                        ?? active?.manifestSHA256,
                state: active?.state,
                generatedBundleAvailable: active != nil,
                runtimeLoadable: generatedRecord?.runtimeLoadable
                    ?? active?.runtimeLoadable
                    ?? false
            )
        let sourceType =
            installedSourceType(sourceKind: record.sourceKind)
        return ChromeMV3InstalledExtensionState(
            stableLocalExtensionID: record.extensionID,
            extensionID: record.extensionID,
            profileID: record.profileID,
            associatedProfileID: record.profileID,
            displayName:
                manifestSummary?.name.nilIfEmpty ?? record.displayName,
            displayVersion:
                manifestSummary?.version.nilIfEmpty ?? record.displayVersion,
            sourceType: sourceType,
            sourceKind: record.sourceKind,
            sourcePath: record.sourcePath,
            sourceDescriptor:
                installedSourceDescriptor(
                    sourceType: sourceType,
                    lastPathComponent: record.sourceLastPathComponent
                ),
            manifestSummary: manifestSummary,
            manifestHash:
                generatedRecord?.manifestSHA256
                    ?? active?.manifestSHA256,
            originalBundleContentHash:
                generatedRecord?.originalBundleContentSHA256,
            originalBundleRecordID: record.originalBundleRecordID,
            originalBundleRecordPath: record.originalBundleRecordPath,
            generatedBundleRecordID: active?.generatedBundleRecordID,
            generatedBundleHash: generatedBundleHash,
            generatedBundleRootPath: active?.generatedBundleRootPath,
            installed: true,
            installIntakeStatus: record.lifecycleState,
            enabled: record.runtimeState.internalRuntimeEnabled,
            lifecycleRecordPath: record.reportPaths.registryRecordPath,
            generatedBundleState: generatedState,
            localExperimentalLabel:
                "Local experimental developer preview",
            productSupportClaim: false,
            diagnostics:
                uniqueSortedCompatibilityDiagnostics(
                    record.diagnostics + [
                        "Installed extension state is derived from persisted lifecycle metadata only.",
                        "Installed extension state readout does not create ExtensionManager, WebKit extension, service-worker, content-script, native-host, timer, polling, or bridge objects.",
                        "Product/default runtime remains unavailable for installed extension state.",
                    ]
                )
        )
    }

    private func activeGeneratedVersion(
        forInstalledState record: ChromeMV3ExtensionLifecycleRecord
    ) -> ChromeMV3GeneratedBundleVersionRecord? {
        if let activeID = record.activeGeneratedVersionID,
           let active = record.generatedBundleVersions.first(where: {
            $0.id == activeID
           })
        {
            return active
        }
        return record.generatedBundleVersions.last {
            $0.state == .active || $0.state == .rollbackActive
        } ?? record.generatedBundleVersions.last
    }

    private func installedSourceType(
        sourceKind: ChromeMV3PackageSourceKind
    ) -> ChromeMV3InstalledExtensionSourceType {
        switch sourceKind {
        case .unpackedDirectory:
            return .localUnpacked
        case .zipArchive, .crxArchive:
            return .localArchive
        }
    }

    private func installedSourceDescriptor(
        sourceType: ChromeMV3InstalledExtensionSourceType,
        lastPathComponent: String
    ) -> String {
        "\(sourceType.rawValue):\(lastPathComponent)"
    }

    private func generatedBundleMetadataHash(
        _ record: ChromeMV3GeneratedBundleRecord
    ) -> String? {
        guard let data = try? ChromeMV3DeterministicJSON.encodedData(record)
        else { return nil }
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func listCompatibilityReportViewModels()
        -> [ChromeMV3CompatibilityReportViewModel]
    {
        listLifecycleRecords().compactMap {
            compatibilityReportViewModel(
                profileID: $0.profileID,
                extensionID: $0.extensionID
            )
        }
    }

    func compatibilityReportViewModel(
        profileID: String,
        extensionID: String
    ) -> ChromeMV3CompatibilityReportViewModel? {
        guard
            let record = loadLifecycleRecord(
                profileID: profileID,
                extensionID: extensionID
            ),
            let report = latestEndToEndDiagnosticsReport(
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        else {
            return nil
        }
        return ChromeMV3CompatibilityReportViewModel(
            report: report,
            lifecycleRecord: record
        )
    }

    func exportLatestEndToEndDiagnosticsJSON(
        profileID: String,
        extensionID: String
    ) -> String? {
        latestEndToEndDiagnosticsReport(
            profileID: profileID,
            extensionID: extensionID
        ).flatMap {
            try? ChromeMV3DeterministicJSON.encodedString($0)
        }
    }

    func runArtifactCleanup(
        profileID: String,
        extensionID: String
    ) -> ChromeMV3ArtifactCleanupReport? {
        guard
            var record = loadLifecycleRecord(
                profileID: profileID,
                extensionID: extensionID
            )
        else {
            return nil
        }
        var removedVersionIDs: [String] = []
        var preservedVersionIDs: [String] = []
        let activeIDs = Set(
            [
                record.activeGeneratedVersionID,
                record.previousWorkingGeneratedVersionID,
            ]
            .compactMap { $0 }
        )
        record.generatedBundleVersions = record.generatedBundleVersions.map {
            item in
            var updated = item
            if activeIDs.contains(item.id) {
                preservedVersionIDs.append(item.id)
                return updated
            }
            if item.state == .candidate || item.state == .failed {
                let root = URL(
                    fileURLWithPath: item.versionRootPath,
                    isDirectory: true
                )
                if fileManager.fileExists(atPath: root.path) {
                    try? fileManager.removeItem(at: root)
                }
                updated.state = .removed
                removedVersionIDs.append(item.id)
            }
            return updated
        }
        if record.candidateGeneratedVersionID.map({
            removedVersionIDs.contains($0)
        }) == true {
            record.candidateGeneratedVersionID = nil
        }
        let reportURL = diagnosticsReportURLForDiagnostics(
            profileID: record.profileID,
            extensionID: record.extensionID
        )
        let reportCorrupt = fileManager.fileExists(atPath: reportURL.path)
            && (
                try? decodeDiagnostics(
                    ChromeMV3EndToEndInstallDiagnosticsReport.self,
                    at: reportURL
                )
            ) == nil
        if reportCorrupt {
            try? fileManager.removeItem(at: reportURL)
            record.reportPaths.compatibilityReportPath = nil
        }
        let markerPath = record.reportPaths.crashMarkerPath
        let markerRemoved: Bool
        if let markerPath, fileManager.fileExists(atPath: markerPath) {
            try? fileManager.removeItem(atPath: markerPath)
            markerRemoved = true
        } else {
            markerRemoved = false
        }
        record.reportPaths.crashMarkerPath = nil
        let runtimeStateReset = record.runtimeState.internalRuntimeEnabled
            || record.runtimeState.syntheticHarnessStatePresent
            || record.runtimeState.sharedLifecycleSessionActive
            || record.runtimeState.nativeFixturePortOpen
            || record.runtimeState.storageStatePresent
            || record.runtimeState.permissionsStatePresent
        record.runtimeState.internalRuntimeEnabled = false
        record.runtimeState.syntheticHarnessStatePresent = false
        record.runtimeState.sharedLifecycleSessionActive = false
        record.runtimeState.nativeFixturePortOpen = false
        record.runtimeState.storageStatePresent = false
        record.runtimeState.permissionsStatePresent = false
        record.updatedAt = now()
        record.diagnostics = Array(
            Set(
                record.diagnostics + [
                    "Internal MV3 cleanup preserved active and previous working generated versions.",
                    "Product profile data was not deleted.",
                ]
            )
        ).sorted()
        try? ChromeMV3DeterministicJSON.write(
            record,
            to: URL(fileURLWithPath: record.reportPaths.registryRecordPath)
        )
        let report = ChromeMV3ArtifactCleanupReport(
            schemaVersion: 1,
            generatedAt: now(),
            profileID: record.profileID,
            extensionID: record.extensionID,
            removedGeneratedVersionIDs: removedVersionIDs.sorted(),
            preservedGeneratedVersionIDs:
                Array(Set(preservedVersionIDs)).sorted(),
            corruptReportRemoved: reportCorrupt,
            crashMarkerRemoved: markerRemoved,
            uninstalledTombstonePreserved:
                record.lifecycleState == .uninstalled,
            internalRuntimeStateReset: runtimeStateReset,
            productProfileDataDeleted: false,
            diagnostics: [
                "Failed and candidate generated versions are removable cleanup artifacts.",
                "Active and previous working generated versions are preserved.",
                "Product profile data is outside the MV3 internal cleanup boundary.",
            ]
        )
        try? writeDiagnosticsArtifact(
            report,
            fileName: ChromeMV3ArtifactCleanupReport.fileName,
            profileID: record.profileID,
            extensionID: record.extensionID
        )
        return report
    }

    func writeFoundationReadinessReport(
        profileID: String,
        extensionID: String,
        cleanupReport: ChromeMV3ArtifactCleanupReport? = nil
    ) -> ChromeMV3FoundationReadinessReport? {
        let record = loadLifecycleRecord(
            profileID: profileID,
            extensionID: extensionID
        )
        let report = latestEndToEndDiagnosticsReport(
            profileID: profileID,
            extensionID: extensionID
        )
        let viewModel = report.map {
            ChromeMV3CompatibilityReportViewModel(
                report: $0,
                lifecycleRecord: record
            )
        }
        let missing = viewModel?.readinessSummary.missingSyntheticReports
            ?? ChromeMV3CompatibilityReadinessSummary.requiredSyntheticReports
        let foundation = ChromeMV3FoundationReadinessReport(
            schemaVersion: 1,
            generatedAt: now(),
            viewModel: viewModel,
            apiMatrix: viewModel?.apiSupportMatrix ?? [],
            blockerSummary: viewModel?.blockersBySeverity ?? [],
            securityChecklist: .currentInternalDeveloperPreview(),
            performanceBudget: .currentInternalDeveloperPreview(),
            artifactCleanup: cleanupReport,
            productRuntimeGuard: .blocked,
            productEnablementPreflight:
                viewModel?.productEnablementPreflight,
            missingRequiredInternalReports: missing,
            finalPhaseStatus: .make(
                viewModel: viewModel,
                missingRequiredInternalReports: missing
            )
        )
        try? writeDiagnosticsArtifact(
            foundation,
            fileName: ChromeMV3FoundationReadinessReport.fileName,
            profileID: profileID,
            extensionID: extensionID
        )
        return foundation
    }

    private func lifecycleRecordURLsForDiagnostics() -> [URL] {
        let recordsRoot = rootURL
            .appendingPathComponent("lifecycle", isDirectory: true)
            .appendingPathComponent("records", isDirectory: true)
        guard
            let enumerator = fileManager.enumerator(
                at: recordsRoot,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
        else {
            return []
        }
        return enumerator.compactMap { item in
            guard let url = item as? URL else { return nil }
            return url.lastPathComponent == "lifecycle-record.json"
                ? url
                : nil
        }
    }

    private func diagnosticsReportURLForDiagnostics(
        profileID: String,
        extensionID: String
    ) -> URL {
        rootURL
            .appendingPathComponent("lifecycle", isDirectory: true)
            .appendingPathComponent("reports", isDirectory: true)
            .appendingPathComponent(
                safeDiagnosticsPathComponent(profileID),
                isDirectory: true
            )
            .appendingPathComponent(
                safeDiagnosticsPathComponent(extensionID),
                isDirectory: true
            )
            .appendingPathComponent(
                ChromeMV3ExtensionLifecycleRegistry.diagnosticsReportFileName
            )
    }

    private func diagnosticsArtifactURL(
        fileName: String,
        profileID: String,
        extensionID: String
    ) -> URL {
        rootURL
            .appendingPathComponent("lifecycle", isDirectory: true)
            .appendingPathComponent("reports", isDirectory: true)
            .appendingPathComponent(
                safeDiagnosticsPathComponent(profileID),
                isDirectory: true
            )
            .appendingPathComponent(
                safeDiagnosticsPathComponent(extensionID),
                isDirectory: true
            )
            .appendingPathComponent(fileName)
    }

    private func writeDiagnosticsArtifact<T: Encodable>(
        _ value: T,
        fileName: String,
        profileID: String,
        extensionID: String
    ) throws {
        let url = diagnosticsArtifactURL(
            fileName: fileName,
            profileID: profileID,
            extensionID: extensionID
        )
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try ChromeMV3DeterministicJSON.write(value, to: url)
    }

    private func decodeDiagnostics<T: Decodable>(
        _ type: T.Type,
        at url: URL
    ) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }
}

private func safeDiagnosticsPathComponent(_ raw: String) -> String {
    let allowed = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "-_"))
    let value = raw.unicodeScalars.map { scalar -> String in
        allowed.contains(scalar) ? String(scalar) : "-"
    }
    .joined()
    return value.isEmpty ? "value" : value
}

#if DEBUG
    import SwiftUI

    struct ChromeMV3InternalDiagnosticsReportView: View {
        let viewModel: ChromeMV3CompatibilityReportViewModel
        var onRunDiagnostics: (() -> Void)?
        var onRunCleanup: (() -> Void)?
        var onExportReportJSON: (() -> Void)?

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                header
                productFlags
                bundleSection
                apiMatrixSection
                blockerSection
                actionSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.extensionIdentity.displayName)
                    .font(.title2.weight(.semibold))
                Text(
                    "\(viewModel.extensionIdentity.extensionID) · \(viewModel.extensionIdentity.displayVersion)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(viewModel.readinessSummary.nextRecommendedAction)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var productFlags: some View {
            SettingsSection(
                title: "Developer Preview Flags",
                subtitle: "Internal diagnostics only; product runtime remains unavailable."
            ) {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 190), spacing: 10),
                    ],
                    alignment: .leading,
                    spacing: 10
                ) {
                    flagRow(
                        "internalDiagnosticsUIAvailable",
                        viewModel.productFlags.internalDiagnosticsUIAvailable
                    )
                    flagRow(
                        "developerPreviewLifecycleAvailable",
                        viewModel.productFlags.developerPreviewLifecycleAvailable
                    )
                    flagRow(
                        "internalSyntheticRuntimeDiagnosticsAvailable",
                        viewModel.productFlags
                            .internalSyntheticRuntimeDiagnosticsAvailable
                    )
                    flagRow(
                        "productRuntimeAvailable",
                        viewModel.productFlags.productRuntimeAvailable
                    )
                    flagRow(
                        "normalTabRuntimeBridgeAvailable",
                        viewModel.productFlags.normalTabRuntimeBridgeAvailable
                    )
                    flagRow(
                        "popupOptionsJSBridgeAvailableInDeveloperPreview",
                        viewModel.productFlags
                            .popupOptionsJSBridgeAvailableInDeveloperPreview
                    )
                    flagRow(
                        "popupOptionsJSBridgeAvailableInPublicProduct",
                        viewModel.productFlags
                            .popupOptionsJSBridgeAvailableInPublicProduct
                    )
                    flagRow(
                        "contentScriptAttachmentAvailableInProduct",
                        viewModel.productFlags
                            .contentScriptAttachmentAvailableInProduct
                    )
                    flagRow("runtimeLoadable", viewModel.productFlags.runtimeLoadable)
                    flagRow(
                        "productExtensionUIAvailable",
                        viewModel.productFlags.productExtensionUIAvailable
                    )
                    flagRow(
                        "productNetworkEnforcementAvailable",
                        viewModel.productFlags.productNetworkEnforcementAvailable
                    )
                }
            }
        }

        private var bundleSection: some View {
            SettingsSection(
                title: "Generated Bundle State",
                subtitle: viewModel.generatedBundleState.generatedBundleAvailable
                    ? "Generated diagnostics bundle is available."
                    : "No active generated diagnostics bundle is available."
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.generatedBundleState.versions) { version in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(version.id)
                                    .font(.callout.weight(.medium))
                                Text(version.state.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(version.runtimeLoadable ? "loadable" : "non-loadable")
                                .font(.caption)
                                .foregroundStyle(
                                    version.runtimeLoadable ? .red : .secondary
                                )
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }

        private var apiMatrixSection: some View {
            SettingsSection(
                title: "API Support Matrix",
                subtitle: "Internal support, synthetic coverage, product blockers, and missing diagnostics."
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.apiSupportMatrix) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(row.displayName)
                                    .font(.callout.weight(.medium))
                                Spacer()
                                Text(row.group)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(row.statuses.map(\.rawValue).joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }

        private var blockerSection: some View {
            SettingsSection(
                title: "Blockers",
                subtitle: "Grouped by severity for the current compatibility report."
            ) {
                if viewModel.blockersBySeverity.isEmpty {
                    Text("No blockers were reported.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.blockersBySeverity) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.title)
                                    .font(.callout.weight(.semibold))
                                ForEach(group.blockers, id: \.id) { blocker in
                                    Text(blocker.message)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }

        private var actionSection: some View {
            SettingsSection(
                title: "Internal Actions",
                subtitle: "Actions call existing internal lifecycle methods only."
            ) {
                HStack(spacing: 8) {
                    Button("Run Diagnostics") {
                        onRunDiagnostics?()
                    }
                    .disabled(onRunDiagnostics == nil)
                    Button("Cleanup") {
                        onRunCleanup?()
                    }
                    .disabled(onRunCleanup == nil)
                    Button("Export JSON") {
                        onExportReportJSON?()
                    }
                    .disabled(onExportReportJSON == nil)
                }
                Text(
                    viewModel.internalLifecycleActions
                        .map(\.title)
                        .joined(separator: ", ")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }

        private func flagRow(_ title: String, _ value: Bool) -> some View {
            HStack(spacing: 8) {
                Image(systemName: value ? "checkmark.circle" : "xmark.circle")
                    .foregroundStyle(value ? .green : .secondary)
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
#endif

private func uniqueSortedCompatibilityDiagnostics(
    _ values: [String]
) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
