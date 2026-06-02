//
//  ChromeMV3ExtensionLifecycleRegistry.swift
//  Sumi
//
//  Internal/developer-preview Chrome MV3 lifecycle plumbing. This registry
//  stages, versions, diagnoses, rolls back, and removes deterministic records
//  only. It does not expose extension runtime to product tabs, install product
//  UI, enforce product network rules, or launch native hosts.
//

import CryptoKit
import Foundation

enum ChromeMV3LifecycleState: String, Codable, CaseIterable, Comparable, Sendable {
    case imported
    case validated
    case generated
    case diagnosticsReady
    case enabledInternal
    case disabledInternal
    case updatePending
    case updateFailed
    case uninstallPending
    case uninstalled
    case recoveryRequired
    case corrupt

    static func < (lhs: ChromeMV3LifecycleState, rhs: ChromeMV3LifecycleState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3GeneratedBundleVersionState:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case candidate
    case active
    case previousWorking
    case failed
    case rollbackActive
    case removed

    static func < (
        lhs: ChromeMV3GeneratedBundleVersionState,
        rhs: ChromeMV3GeneratedBundleVersionState
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3LifecycleOperationKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case installImport
    case update
    case rebuild
    case enable
    case disable
    case rollback
    case uninstall
    case reset
    case crashMarker
    case recoveryScan
    case diagnostics

    static func < (
        lhs: ChromeMV3LifecycleOperationKind,
        rhs: ChromeMV3LifecycleOperationKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3LifecycleFailureCode:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case compatibilityBlocker
    case corruptGeneratedArtifact
    case generatedBundleFailed
    case manifestInvalid
    case noActiveGeneratedVersion
    case noPreviousWorkingVersion
    case recordMissing
    case reportCorrupt
    case resourceMissing
    case runtimeObjectRejected
    case unsupportedSource
    case unknownInternalError

    static func < (
        lhs: ChromeMV3LifecycleFailureCode,
        rhs: ChromeMV3LifecycleFailureCode
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3APIBlockerSeverity:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case info
    case warning
    case productBlocked
    case unsupported
    case deferred
    case fatalInstall
    case fatalRuntime

    static func < (
        lhs: ChromeMV3APIBlockerSeverity,
        rhs: ChromeMV3APIBlockerSeverity
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3APIBlockerSource:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case manifest
    case resource
    case generatedBundle
    case WebKitObject
    case runtimeGate
    case JSBridge
    case permission
    case storage
    case nativeMessaging
    case serviceWorker
    case network
    case sidePanel
    case offscreen
    case identity
    case productUI
    case securityPolicy

    static func < (
        lhs: ChromeMV3APIBlockerSource,
        rhs: ChromeMV3APIBlockerSource
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3APIBlockerRecord: Codable, Equatable, Sendable {
    var id: String
    var severity: ChromeMV3APIBlockerSeverity
    var source: ChromeMV3APIBlockerSource
    var apiNamespace: String?
    var apiMethod: String?
    var manifestKey: String?
    var filePath: String?
    var message: String
    var remediation: String
    var roadmapOwner: String?
}

struct ChromeMV3LifecycleProductFlags: Codable, Equatable, Sendable {
    var productRuntimeAvailable: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var productUIAvailable: Bool
    var productNetworkEnforcementAvailable: Bool
    var productRuntimeExposed: Bool

    static let unavailable = ChromeMV3LifecycleProductFlags(
        productRuntimeAvailable: false,
        normalTabRuntimeBridgeAvailable: false,
        runtimeLoadable: false,
        productUIAvailable: false,
        productNetworkEnforcementAvailable: false,
        productRuntimeExposed: false
    )
}

struct ChromeMV3LifecycleCapabilityAvailability:
    Codable,
    Equatable,
    Sendable
{
    var extensionInstalledInInternalRegistry: Bool
    var generatedBundleAvailable: Bool
    var internalSyntheticRuntimeDiagnosticsAvailable: Bool
    var productRuntimeAvailable: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var compatibilityReportAvailable: Bool
}

struct ChromeMV3LifecycleRuntimeDiagnosticsSnapshot:
    Codable,
    Equatable,
    Sendable
{
    var WebKitObjectDiagnosticsAvailable: Bool
    var contextCreationGateDiagnosticsAvailable: Bool
    var controllerLoadGateDiagnosticsAvailable: Bool
    var runtimeBridgeReadinessDiagnosticsAvailable: Bool
    var runtimeJSMessagingDiagnosticsAvailable: Bool
    var tabsScriptingDiagnosticsAvailable: Bool
    var permissionsDiagnosticsAvailable: Bool
    var storageDiagnosticsAvailable: Bool
    var nativeMessagingDiagnosticsAvailable: Bool
    var serviceWorkerDiagnosticsAvailable: Bool
    var eventAPIDiagnosticsAvailable: Bool
    var networkDiagnosticsAvailable: Bool
    var sidePanelOffscreenIdentityDiagnosticsAvailable: Bool
    var passwordManagerDiagnosticsAvailable: Bool
    var diagnostics: [String]

    static let none = ChromeMV3LifecycleRuntimeDiagnosticsSnapshot(
        WebKitObjectDiagnosticsAvailable: false,
        contextCreationGateDiagnosticsAvailable: false,
        controllerLoadGateDiagnosticsAvailable: false,
        runtimeBridgeReadinessDiagnosticsAvailable: false,
        runtimeJSMessagingDiagnosticsAvailable: false,
        tabsScriptingDiagnosticsAvailable: false,
        permissionsDiagnosticsAvailable: false,
        storageDiagnosticsAvailable: false,
        nativeMessagingDiagnosticsAvailable: false,
        serviceWorkerDiagnosticsAvailable: false,
        eventAPIDiagnosticsAvailable: false,
        networkDiagnosticsAvailable: false,
        sidePanelOffscreenIdentityDiagnosticsAvailable: false,
        passwordManagerDiagnosticsAvailable: false,
        diagnostics: []
    )

    var anyDiagnosticsAvailable: Bool {
        WebKitObjectDiagnosticsAvailable
            || contextCreationGateDiagnosticsAvailable
            || controllerLoadGateDiagnosticsAvailable
            || runtimeBridgeReadinessDiagnosticsAvailable
            || runtimeJSMessagingDiagnosticsAvailable
            || tabsScriptingDiagnosticsAvailable
            || permissionsDiagnosticsAvailable
            || storageDiagnosticsAvailable
            || nativeMessagingDiagnosticsAvailable
            || serviceWorkerDiagnosticsAvailable
            || eventAPIDiagnosticsAvailable
            || networkDiagnosticsAvailable
            || sidePanelOffscreenIdentityDiagnosticsAvailable
            || passwordManagerDiagnosticsAvailable
    }
}

struct ChromeMV3LifecycleReportPaths: Codable, Equatable, Sendable {
    var registryRecordPath: String
    var compatibilityReportPath: String?
    var lastOperationReportPath: String?
    var crashMarkerPath: String?
}

struct ChromeMV3LifecycleRuntimeState: Codable, Equatable, Sendable {
    var internalRuntimeEnabled: Bool
    var syntheticHarnessStatePresent: Bool
    var sharedLifecycleSessionActive: Bool
    var nativeFixturePortOpen: Bool
    var storageStatePresent: Bool
    var permissionsStatePresent: Bool
    var resetSequence: Int

    static let empty = ChromeMV3LifecycleRuntimeState(
        internalRuntimeEnabled: false,
        syntheticHarnessStatePresent: false,
        sharedLifecycleSessionActive: false,
        nativeFixturePortOpen: false,
        storageStatePresent: false,
        permissionsStatePresent: false,
        resetSequence: 0
    )
}

enum ChromeMV3InstalledExtensionSourceType:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case localArchive
    case localUnpacked

    static func < (
        lhs: ChromeMV3InstalledExtensionSourceType,
        rhs: ChromeMV3InstalledExtensionSourceType
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3InstalledExtensionGeneratedBundleState:
    Codable,
    Equatable,
    Sendable
{
    var activeVersionID: String?
    var generatedBundleRecordID: String?
    var generatedBundleRootPath: String?
    var generatedBundleHash: String?
    var generatedManifestHash: String?
    var manifestHash: String?
    var state: ChromeMV3GeneratedBundleVersionState?
    var generatedBundleAvailable: Bool
    var runtimeLoadable: Bool
}

struct ChromeMV3InstalledExtensionState:
    Identifiable,
    Codable,
    Equatable,
    Sendable
{
    var id: String { "\(profileID):\(extensionID)" }
    var stableLocalExtensionID: String
    var extensionID: String
    var profileID: String
    var associatedProfileID: String
    var displayName: String
    var displayVersion: String
    var sourceType: ChromeMV3InstalledExtensionSourceType
    var sourceKind: ChromeMV3PackageSourceKind
    var sourcePath: String
    var sourceDescriptor: String
    var manifestSummary: ChromeMV3ManifestSummary?
    var manifestHash: String?
    var originalBundleContentHash: String?
    var originalBundleRecordID: String
    var originalBundleRecordPath: String
    var generatedBundleRecordID: String?
    var generatedBundleHash: String?
    var generatedBundleRootPath: String?
    var installed: Bool
    var installIntakeStatus: ChromeMV3LifecycleState
    var enabled: Bool
    var lifecycleRecordPath: String
    var generatedBundleState:
        ChromeMV3InstalledExtensionGeneratedBundleState
    var localExperimentalLabel: String
    var productSupportClaim: Bool
    var diagnostics: [String]
}

struct ChromeMV3GeneratedBundleVersionRecord:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var sequence: Int
    var createdAt: Date
    var state: ChromeMV3GeneratedBundleVersionState
    var versionRootPath: String
    var generatedBundleRootPath: String
    var rewrittenVariantRootPath: String?
    var runtimeLoadabilityReportPath: String?
    var originalBundleRecordID: String
    var generatedBundleRecordID: String
    var generatedManifestSHA256: String
    var manifestSHA256: String
    var runtimeLoadable: Bool
    var generatedBundleRecord: ChromeMV3GeneratedBundleRecord
    var rewriteApplicationReport: ChromeMV3GeneratedRewriteApplicationReport?
    var runtimeLoadabilityReport: ChromeMV3RuntimeLoadabilityReport?
    var diagnostics: [String]
}

struct ChromeMV3LifecycleCrashMarkerRecord: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var id: String
    var createdAt: Date
    var profileID: String
    var extensionID: String
    var activeGeneratedVersionID: String?
    var lifecycleSessionLeftActive: Bool
    var nativeFixturePortLeftOpen: Bool
    var reason: String
    var diagnostics: [String]
}

struct ChromeMV3LifecycleRecoveryStatus: Codable, Equatable, Sendable {
    var recoveryRequired: Bool
    var crashMarkerDetected: Bool
    var activeGeneratedBundleMissing: Bool
    var manifestSnapshotMissingOrCorrupt: Bool
    var generatedMetadataMissingOrCorrupt: Bool
    var reportMissingOrCorrupt: Bool
    var lifecycleSessionLeftActive: Bool
    var nativeFixturePortLeftOpen: Bool
    var rolledBackToPreviousWorkingVersionID: String?
    var internalRuntimeDisabled: Bool
    var rebuildRequired: Bool
    var diagnostics: [String]

    static let clean = ChromeMV3LifecycleRecoveryStatus(
        recoveryRequired: false,
        crashMarkerDetected: false,
        activeGeneratedBundleMissing: false,
        manifestSnapshotMissingOrCorrupt: false,
        generatedMetadataMissingOrCorrupt: false,
        reportMissingOrCorrupt: false,
        lifecycleSessionLeftActive: false,
        nativeFixturePortLeftOpen: false,
        rolledBackToPreviousWorkingVersionID: nil,
        internalRuntimeDisabled: false,
        rebuildRequired: false,
        diagnostics: []
    )
}

struct ChromeMV3LifecycleOperationSummary:
    Codable,
    Equatable,
    Sendable
{
    var operation: ChromeMV3LifecycleOperationKind
    var succeeded: Bool
    var failureCode: ChromeMV3LifecycleFailureCode?
    var message: String
    var lifecycleState: ChromeMV3LifecycleState?
    var activeGeneratedVersionID: String?
    var previousWorkingGeneratedVersionID: String?
    var generatedVersionID: String?
}

struct ChromeMV3AggregateAPICompatibility:
    Codable,
    Equatable,
    Sendable
{
    var supportedInternalAPIs: [ChromeMV3API]
    var supportedSyntheticAPIs: [ChromeMV3API]
    var partialAPIs: [ChromeMV3API]
    var productBlockedAPIs: [ChromeMV3API]
    var unsupportedAPIs: [ChromeMV3API]
    var deferredAPIs: [ChromeMV3API]
    var missingManifestResourceBlockers: [ChromeMV3APIBlockerRecord]
    var WebKitBlockers: [ChromeMV3APIBlockerRecord]
    var nativeHostBlockers: [ChromeMV3APIBlockerRecord]
    var serviceWorkerBlockers: [ChromeMV3APIBlockerRecord]
    var productUIBlockers: [ChromeMV3APIBlockerRecord]
    var securityPolicyBlockers: [ChromeMV3APIBlockerRecord]
    var allBlockers: [ChromeMV3APIBlockerRecord]
    var nextRecommendedAction: String
}

struct ChromeMV3LifecycleProductReadinessSummary:
    Codable,
    Equatable,
    Sendable
{
    var productRuntimeAvailable: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var productUIAvailable: Bool
    var productNetworkEnforcementAvailable: Bool
    var launchBlocked: Bool
    var blockers: [ChromeMV3APIBlockerRecord]
}

struct ChromeMV3LifecycleInternalSyntheticReadinessSummary:
    Codable,
    Equatable,
    Sendable
{
    var generatedBundleAvailable: Bool
    var generatedRewrittenVariantAvailable: Bool
    var staticRuntimeLoadabilityReportAvailable: Bool
    var runtimeCompatibilityDiagnosticsAvailable: Bool
    var syntheticAPIReportsAvailable: [String]
    var launchableInProduct: Bool
    var diagnostics: [String]
}

struct ChromeMV3EndToEndInstallDiagnosticsReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var generatedAt: Date
    var registryLifecycleState: ChromeMV3LifecycleState?
    var lifecycleAvailability: ChromeMV3LifecycleCapabilityAvailability
    var installImportResult: ChromeMV3LifecycleOperationSummary?
    var generatedBundleVersionState: [ChromeMV3GeneratedBundleVersionRecord]
    var updateRebuildResult: ChromeMV3LifecycleOperationSummary?
    var uninstallResetResult: ChromeMV3LifecycleOperationSummary?
    var crashRecoveryStatus: ChromeMV3LifecycleRecoveryStatus
    var aggregateAPICompatibility: ChromeMV3AggregateAPICompatibility
    var blockerTaxonomy: [ChromeMV3APIBlockerRecord]
    var productReadinessSummary: ChromeMV3LifecycleProductReadinessSummary
    var internalSyntheticReadinessSummary:
        ChromeMV3LifecycleInternalSyntheticReadinessSummary
    var passwordManagerReadinessSummary:
        ChromeMV3PasswordManagerRuntimeReadinessReport?
    var productFlags: ChromeMV3LifecycleProductFlags
}

struct ChromeMV3ExtensionLifecycleRecord: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var extensionID: String
    var profileID: String
    var installID: String
    var sequence: Int
    var displayName: String
    var displayVersion: String
    var sourceKind: ChromeMV3PackageSourceKind
    var sourcePath: String
    var sourceLastPathComponent: String
    var originalBundleRecordID: String
    var originalBundleRecordPath: String
    var originalBundleRootPath: String
    var manifestSnapshotPath: String
    var installReportPath: String
    var generatedBundlePlanPath: String
    var activeGeneratedVersionID: String?
    var candidateGeneratedVersionID: String?
    var previousWorkingGeneratedVersionID: String?
    var lifecycleState: ChromeMV3LifecycleState
    var installedAt: Date
    var updatedAt: Date
    var generatedBundleVersions: [ChromeMV3GeneratedBundleVersionRecord]
    var reportPaths: ChromeMV3LifecycleReportPaths
    var runtimeState: ChromeMV3LifecycleRuntimeState
    var productFlags: ChromeMV3LifecycleProductFlags
    var diagnostics: [String]
}

struct ChromeMV3LifecycleOperationResult:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var operation: ChromeMV3LifecycleOperationKind
    var succeeded: Bool
    var failureCode: ChromeMV3LifecycleFailureCode?
    var record: ChromeMV3ExtensionLifecycleRecord?
    var previousRecord: ChromeMV3ExtensionLifecycleRecord?
    var generatedVersion: ChromeMV3GeneratedBundleVersionRecord?
    var report: ChromeMV3EndToEndInstallDiagnosticsReport?
    var diagnostics: [String]
    var productFlags: ChromeMV3LifecycleProductFlags

    var summary: ChromeMV3LifecycleOperationSummary {
        ChromeMV3LifecycleOperationSummary(
            operation: operation,
            succeeded: succeeded,
            failureCode: failureCode,
            message: diagnostics.first ?? (succeeded ? "Operation succeeded." : "Operation failed."),
            lifecycleState: record?.lifecycleState,
            activeGeneratedVersionID: record?.activeGeneratedVersionID,
            previousWorkingGeneratedVersionID:
                record?.previousWorkingGeneratedVersionID,
            generatedVersionID: generatedVersion?.id
        )
    }
}

enum ChromeMV3ExtensionLifecycleRegistryError:
    LocalizedError,
    CustomStringConvertible
{
    case unsupportedSourceKind(ChromeMV3PackageSourceKind)
    case missingRecord(profileID: String, extensionID: String)
    case missingActiveGeneratedVersion(String)
    case missingPreviousWorkingGeneratedVersion(String)
    case corruptRecord(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSourceKind(let sourceKind):
            return "Unsupported internal MV3 lifecycle source kind: \(sourceKind.rawValue)"
        case .missingRecord(let profileID, let extensionID):
            return "Missing internal MV3 lifecycle record for profile \(profileID), extension \(extensionID)"
        case .missingActiveGeneratedVersion(let extensionID):
            return "Extension \(extensionID) has no active generated bundle version"
        case .missingPreviousWorkingGeneratedVersion(let extensionID):
            return "Extension \(extensionID) has no previous working generated bundle version"
        case .corruptRecord(let path):
            return "Internal MV3 lifecycle record is corrupt: \(path)"
        }
    }

    var description: String {
        errorDescription ?? String(describing: self)
    }
}

struct ChromeMV3ExtensionLifecycleRegistry {
    static let lifecycleSchemaVersion = 1
    static let diagnosticsReportFileName =
        "runtime-mv3-end-to-end-install-diagnostics-report.json"

    var rootURL: URL
    var now: () -> Date
    var fileManager: FileManager

    init(
        rootURL: URL,
        now: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.now = now
        self.fileManager = fileManager
    }

    func installUnpackedExtension(
        at sourceURL: URL,
        profileID: String,
        enableInternal: Bool = false,
        installedSourceKind: ChromeMV3PackageSourceKind = .unpackedDirectory,
        installedSourcePath: String? = nil,
        installedSourceLastPathComponent: String? = nil,
        runtimeDiagnostics:
            ChromeMV3LifecycleRuntimeDiagnosticsSnapshot = .none
    ) -> ChromeMV3LifecycleOperationResult {
        do {
            let stage = try ChromeMV3OriginalBundleStore(
                rootURL: rootURL,
                now: now
            ).stageSource(
                at: sourceURL.standardizedFileURL,
                sourceKind: .unpackedDirectory
            )
            let sequence = try nextSequence()
            let extensionID = stableID(
                prefix: "mv3-extension",
                parts: [
                    normalizedProfileID(profileID),
                    sourceURL.standardizedFileURL.path,
                ]
            )
            let installID = stableID(
                prefix: "mv3-install",
                parts: [extensionID, String(sequence)]
            )
            let generatedVersion = try writeGeneratedVersion(
                sequence: sequence,
                originalBundleRecord: stage.originalBundleRecord,
                manifestSnapshot: stage.manifestSnapshot,
                planningRecord: stage.generatedBundlePlan
            )
            let recordPath = registryRecordURL(
                profileID: profileID,
                extensionID: extensionID
            )
            let reportPath = diagnosticsReportURL(
                profileID: profileID,
                extensionID: extensionID
            )
            var record = ChromeMV3ExtensionLifecycleRecord(
                schemaVersion: Self.lifecycleSchemaVersion,
                extensionID: extensionID,
                profileID: normalizedProfileID(profileID),
                installID: installID,
                sequence: sequence,
                displayName: stage.originalBundleRecord.manifestName,
                displayVersion: stage.originalBundleRecord.manifestVersion,
                sourceKind: installedSourceKind,
                sourcePath: installedSourcePath
                    ?? sourceURL.standardizedFileURL.path,
                sourceLastPathComponent: installedSourceLastPathComponent
                    ?? sourceURL.lastPathComponent,
                originalBundleRecordID: stage.originalBundleRecord.id,
                originalBundleRecordPath:
                    URL(
                        fileURLWithPath:
                            stage.originalBundleRecord.storedPaths.recordRootPath,
                        isDirectory: true
                    )
                    .appendingPathComponent("record.json")
                    .path,
                originalBundleRootPath:
                    stage.originalBundleRecord.storedPaths.originalBundleRootPath,
                manifestSnapshotPath:
                    stage.originalBundleRecord.storedPaths.manifestSnapshotPath,
                installReportPath:
                    stage.originalBundleRecord.storedPaths.installReportPath,
                generatedBundlePlanPath:
                    stage.originalBundleRecord.storedPaths
                    .generatedBundlePlanPath,
                activeGeneratedVersionID: generatedVersion.id,
                candidateGeneratedVersionID: nil,
                previousWorkingGeneratedVersionID: nil,
                lifecycleState: enableInternal ? .enabledInternal : .diagnosticsReady,
                installedAt: now(),
                updatedAt: now(),
                generatedBundleVersions: [
                    version(generatedVersion, state: .active),
                ],
                reportPaths: ChromeMV3LifecycleReportPaths(
                    registryRecordPath: recordPath.path,
                    compatibilityReportPath: reportPath.path,
                    lastOperationReportPath: nil,
                    crashMarkerPath: nil
                ),
                runtimeState: ChromeMV3LifecycleRuntimeState(
                    internalRuntimeEnabled: enableInternal,
                    syntheticHarnessStatePresent: false,
                    sharedLifecycleSessionActive: false,
                    nativeFixturePortOpen: false,
                    storageStatePresent: false,
                    permissionsStatePresent: false,
                    resetSequence: 0
                ),
                productFlags: .unavailable,
                diagnostics: uniqueSortedLifecycle([
                    "Extension imported into the internal MV3 lifecycle registry.",
                    "Original unpacked bundle was staged read-only by convention.",
                    "Installed local source type is \(installedSourceKind.rawValue).",
                    "Generated bundle artifacts are internal diagnostics only.",
                    "Product runtime remains unavailable.",
                ])
            )
            try writeRecord(record)
            let report = try writeEndToEndDiagnosticsReport(
                for: record,
                installImportResult: ChromeMV3LifecycleOperationSummary(
                    operation: .installImport,
                    succeeded: true,
                    failureCode: nil,
                    message: "Internal MV3 import succeeded.",
                    lifecycleState: record.lifecycleState,
                    activeGeneratedVersionID: record.activeGeneratedVersionID,
                    previousWorkingGeneratedVersionID: nil,
                    generatedVersionID: generatedVersion.id
                ),
                runtimeDiagnostics: runtimeDiagnostics
            )
            record.reportPaths.compatibilityReportPath =
                diagnosticsReportURL(
                    profileID: profileID,
                    extensionID: extensionID
                ).path
            try writeRecord(record)
            return operationResult(
                operation: .installImport,
                succeeded: true,
                record: record,
                generatedVersion: generatedVersion,
                report: report,
                diagnostics: ["Internal MV3 import succeeded."]
            )
        } catch {
            return failureResult(
                operation: .installImport,
                error: error,
                sourceURL: sourceURL,
                profileID: profileID
            )
        }
    }

    func updateExtension(
        profileID: String,
        extensionID: String,
        from sourceURL: URL,
        runtimeDiagnostics:
            ChromeMV3LifecycleRuntimeDiagnosticsSnapshot = .none
    ) -> ChromeMV3LifecycleOperationResult {
        do {
            var record = try loadRecord(profileID: profileID, extensionID: extensionID)
            let previous = record
            let nextSequence = try nextSequence(after: record.sequence)
            let candidateVersionID = generatedVersionID(sequence: nextSequence)
            record.lifecycleState = .updatePending
            record.candidateGeneratedVersionID = candidateVersionID
            record.updatedAt = now()
            try writeRecord(record)

            let stage = try ChromeMV3OriginalBundleStore(
                rootURL: rootURL,
                now: now
            ).stageSource(
                at: sourceURL.standardizedFileURL,
                sourceKind: .unpackedDirectory
            )
            let generatedVersion = try writeGeneratedVersion(
                sequence: nextSequence,
                originalBundleRecord: stage.originalBundleRecord,
                manifestSnapshot: stage.manifestSnapshot,
                planningRecord: stage.generatedBundlePlan
            )

            record = promote(
                generatedVersion,
                in: record,
                stage: stage,
                sourceURL: sourceURL,
                sequence: nextSequence,
                enabledInternal: record.runtimeState.internalRuntimeEnabled
            )
            try writeRecord(record)
            let report = try writeEndToEndDiagnosticsReport(
                for: record,
                updateRebuildResult: ChromeMV3LifecycleOperationSummary(
                    operation: .update,
                    succeeded: true,
                    failureCode: nil,
                    message: "Internal MV3 update promoted a generated candidate.",
                    lifecycleState: record.lifecycleState,
                    activeGeneratedVersionID: record.activeGeneratedVersionID,
                    previousWorkingGeneratedVersionID:
                        record.previousWorkingGeneratedVersionID,
                    generatedVersionID: generatedVersion.id
                ),
                runtimeDiagnostics: runtimeDiagnostics
            )
            return operationResult(
                operation: .update,
                succeeded: true,
                record: record,
                previousRecord: previous,
                generatedVersion: generatedVersion,
                report: report,
                diagnostics: [
                    "Internal MV3 update promoted a generated candidate.",
                ]
            )
        } catch {
            return updateFailureResult(
                operation: .update,
                profileID: profileID,
                extensionID: extensionID,
                error: error,
                runtimeDiagnostics: runtimeDiagnostics
            )
        }
    }

    func rebuildExtension(
        profileID: String,
        extensionID: String,
        runtimeDiagnostics:
            ChromeMV3LifecycleRuntimeDiagnosticsSnapshot = .none
    ) -> ChromeMV3LifecycleOperationResult {
        do {
            var record = try loadRecord(profileID: profileID, extensionID: extensionID)
            let previous = record
            let nextSequence = try nextSequence(after: record.sequence)
            record.lifecycleState = .updatePending
            record.candidateGeneratedVersionID =
                generatedVersionID(sequence: nextSequence)
            record.updatedAt = now()
            try writeRecord(record)

            let original = try decode(
                ChromeMV3OriginalBundleRecord.self,
                at: URL(fileURLWithPath: record.originalBundleRecordPath)
            )
            let snapshot = try decode(
                ChromeMV3ManifestSnapshotRecord.self,
                at: URL(fileURLWithPath: record.manifestSnapshotPath)
            )
            let plan = try decode(
                ChromeMV3GeneratedBundlePlanningRecord.self,
                at: URL(fileURLWithPath: record.generatedBundlePlanPath)
            )
            let generatedVersion = try writeGeneratedVersion(
                sequence: nextSequence,
                originalBundleRecord: original,
                manifestSnapshot: snapshot,
                planningRecord: plan
            )
            record = promote(
                generatedVersion,
                in: record,
                stage: nil,
                sourceURL: URL(fileURLWithPath: record.sourcePath),
                sequence: nextSequence,
                enabledInternal: record.runtimeState.internalRuntimeEnabled
            )
            try writeRecord(record)
            let report = try writeEndToEndDiagnosticsReport(
                for: record,
                updateRebuildResult: ChromeMV3LifecycleOperationSummary(
                    operation: .rebuild,
                    succeeded: true,
                    failureCode: nil,
                    message: "Internal MV3 generated bundle rebuild succeeded.",
                    lifecycleState: record.lifecycleState,
                    activeGeneratedVersionID: record.activeGeneratedVersionID,
                    previousWorkingGeneratedVersionID:
                        record.previousWorkingGeneratedVersionID,
                    generatedVersionID: generatedVersion.id
                ),
                runtimeDiagnostics: runtimeDiagnostics
            )
            return operationResult(
                operation: .rebuild,
                succeeded: true,
                record: record,
                previousRecord: previous,
                generatedVersion: generatedVersion,
                report: report,
                diagnostics: [
                    "Internal MV3 generated bundle rebuild succeeded.",
                ]
            )
        } catch {
            return updateFailureResult(
                operation: .rebuild,
                profileID: profileID,
                extensionID: extensionID,
                error: error,
                runtimeDiagnostics: runtimeDiagnostics
            )
        }
    }

    func setInternalEnabled(
        _ enabled: Bool,
        profileID: String,
        extensionID: String
    ) -> ChromeMV3LifecycleOperationResult {
        do {
            var record = try loadRecord(profileID: profileID, extensionID: extensionID)
            record.lifecycleState = enabled ? .enabledInternal : .disabledInternal
            record.runtimeState.internalRuntimeEnabled = enabled
            if enabled == false {
                record.runtimeState.syntheticHarnessStatePresent = false
                record.runtimeState.sharedLifecycleSessionActive = false
                record.runtimeState.nativeFixturePortOpen = false
            }
            record.updatedAt = now()
            try writeRecord(record)
            let report = try writeEndToEndDiagnosticsReport(
                for: record,
                updateRebuildResult: ChromeMV3LifecycleOperationSummary(
                    operation: enabled ? .enable : .disable,
                    succeeded: true,
                    failureCode: nil,
                    message: enabled
                        ? "Internal extension record enabled."
                        : "Internal extension record disabled.",
                    lifecycleState: record.lifecycleState,
                    activeGeneratedVersionID: record.activeGeneratedVersionID,
                    previousWorkingGeneratedVersionID:
                        record.previousWorkingGeneratedVersionID,
                    generatedVersionID: record.activeGeneratedVersionID
                )
            )
            return operationResult(
                operation: enabled ? .enable : .disable,
                succeeded: true,
                record: record,
                report: report,
                diagnostics: [
                    enabled
                        ? "Internal extension record enabled."
                        : "Internal extension record disabled.",
                ]
            )
        } catch {
            return failureResult(operation: enabled ? .enable : .disable, error: error)
        }
    }

    func rollbackExtension(
        profileID: String,
        extensionID: String
    ) -> ChromeMV3LifecycleOperationResult {
        do {
            var record = try loadRecord(profileID: profileID, extensionID: extensionID)
            let previous = record
            guard let previousID = record.previousWorkingGeneratedVersionID else {
                throw ChromeMV3ExtensionLifecycleRegistryError
                    .missingPreviousWorkingGeneratedVersion(extensionID)
            }
            guard validGeneratedVersion(previousID, in: record) else {
                throw ChromeMV3ExtensionLifecycleRegistryError
                    .missingPreviousWorkingGeneratedVersion(extensionID)
            }
            let oldActiveID = record.activeGeneratedVersionID
            record.generatedBundleVersions = record.generatedBundleVersions.map { item in
                var updated = item
                if item.id == previousID {
                    updated.state = .rollbackActive
                } else if item.id == oldActiveID {
                    updated.state = .previousWorking
                }
                return updated
            }
            record.activeGeneratedVersionID = previousID
            record.previousWorkingGeneratedVersionID = oldActiveID
            record.candidateGeneratedVersionID = nil
            record.lifecycleState = .diagnosticsReady
            record.runtimeState.internalRuntimeEnabled = false
            record.updatedAt = now()
            try writeRecord(record)
            let report = try writeEndToEndDiagnosticsReport(
                for: record,
                updateRebuildResult: ChromeMV3LifecycleOperationSummary(
                    operation: .rollback,
                    succeeded: true,
                    failureCode: nil,
                    message: "Rolled back to previous working generated bundle.",
                    lifecycleState: record.lifecycleState,
                    activeGeneratedVersionID: record.activeGeneratedVersionID,
                    previousWorkingGeneratedVersionID:
                        record.previousWorkingGeneratedVersionID,
                    generatedVersionID: previousID
                )
            )
            return operationResult(
                operation: .rollback,
                succeeded: true,
                record: record,
                previousRecord: previous,
                generatedVersion:
                    record.generatedBundleVersions.first { $0.id == previousID },
                report: report,
                diagnostics: [
                    "Rolled back to previous working generated bundle.",
                ]
            )
        } catch {
            return failureResult(operation: .rollback, error: error)
        }
    }

    func uninstallExtension(
        profileID: String,
        extensionID: String,
        preserveTombstone: Bool = true
    ) -> ChromeMV3LifecycleOperationResult {
        do {
            var record = try loadRecord(profileID: profileID, extensionID: extensionID)
            let previous = record
            record.lifecycleState = .uninstallPending
            record.runtimeState.internalRuntimeEnabled = false
            record.runtimeState.syntheticHarnessStatePresent = false
            record.runtimeState.sharedLifecycleSessionActive = false
            record.runtimeState.nativeFixturePortOpen = false
            record.runtimeState.storageStatePresent = false
            record.runtimeState.permissionsStatePresent = false
            record.updatedAt = now()
            try writeRecord(record)

            for version in record.generatedBundleVersions {
                let root = URL(fileURLWithPath: version.versionRootPath, isDirectory: true)
                if fileManager.fileExists(atPath: root.path) {
                    try fileManager.removeItem(at: root)
                }
            }
            if let markerPath = record.reportPaths.crashMarkerPath,
               fileManager.fileExists(atPath: markerPath) {
                try fileManager.removeItem(atPath: markerPath)
            }
            record.generatedBundleVersions = record.generatedBundleVersions.map {
                version($0, state: .removed)
            }
            record.activeGeneratedVersionID = nil
            record.candidateGeneratedVersionID = nil
            record.previousWorkingGeneratedVersionID = nil
            record.lifecycleState = .uninstalled
            record.updatedAt = now()
            record.diagnostics = uniqueSortedLifecycle(
                record.diagnostics + [
                    "Internal runtime state was disabled before uninstall.",
                    "Generated bundle artifacts were removed by lifecycle policy.",
                    "Product profile data was not deleted.",
                ]
            )
            if preserveTombstone {
                try writeRecord(record)
                let report = try writeEndToEndDiagnosticsReport(
                    for: record,
                    uninstallResetResult: ChromeMV3LifecycleOperationSummary(
                        operation: .uninstall,
                        succeeded: true,
                        failureCode: nil,
                        message: "Internal MV3 extension state uninstalled.",
                        lifecycleState: record.lifecycleState,
                        activeGeneratedVersionID: nil,
                        previousWorkingGeneratedVersionID: nil,
                        generatedVersionID: nil
                    )
                )
                return operationResult(
                    operation: .uninstall,
                    succeeded: true,
                    record: record,
                    previousRecord: previous,
                    report: report,
                    diagnostics: [
                        "Internal MV3 extension state uninstalled.",
                    ]
                )
            } else {
                let path = registryRecordURL(
                    profileID: profileID,
                    extensionID: extensionID
                )
                if fileManager.fileExists(atPath: path.path) {
                    try fileManager.removeItem(at: path)
                }
                return operationResult(
                    operation: .uninstall,
                    succeeded: true,
                    previousRecord: previous,
                    diagnostics: [
                        "Internal MV3 extension record removed.",
                    ]
                )
            }
        } catch {
            return failureResult(operation: .uninstall, error: error)
        }
    }

    func resetExtensionState(
        profileID: String,
        extensionID: String
    ) -> ChromeMV3LifecycleOperationResult {
        do {
            var record = try loadRecord(profileID: profileID, extensionID: extensionID)
            let previous = record
            record.runtimeState = ChromeMV3LifecycleRuntimeState(
                internalRuntimeEnabled: false,
                syntheticHarnessStatePresent: false,
                sharedLifecycleSessionActive: false,
                nativeFixturePortOpen: false,
                storageStatePresent: false,
                permissionsStatePresent: false,
                resetSequence: record.runtimeState.resetSequence + 1
            )
            record.lifecycleState = .disabledInternal
            record.updatedAt = now()
            record.diagnostics = uniqueSortedLifecycle(
                record.diagnostics + [
                    "Internal storage, permissions, session, and fixture state were reset by policy.",
                ]
            )
            try writeRecord(record)
            let report = try writeEndToEndDiagnosticsReport(
                for: record,
                uninstallResetResult: ChromeMV3LifecycleOperationSummary(
                    operation: .reset,
                    succeeded: true,
                    failureCode: nil,
                    message: "Internal MV3 extension state reset.",
                    lifecycleState: record.lifecycleState,
                    activeGeneratedVersionID: record.activeGeneratedVersionID,
                    previousWorkingGeneratedVersionID:
                        record.previousWorkingGeneratedVersionID,
                    generatedVersionID: record.activeGeneratedVersionID
                )
            )
            return operationResult(
                operation: .reset,
                succeeded: true,
                record: record,
                previousRecord: previous,
                report: report,
                diagnostics: [
                    "Internal MV3 extension state reset.",
                ]
            )
        } catch {
            return failureResult(operation: .reset, error: error)
        }
    }

    @discardableResult
    func writeCrashMarker(
        profileID: String,
        extensionID: String,
        reason: String,
        lifecycleSessionLeftActive: Bool = true,
        nativeFixturePortLeftOpen: Bool = false
    ) -> ChromeMV3LifecycleOperationResult {
        do {
            var record = try loadRecord(profileID: profileID, extensionID: extensionID)
            let marker = ChromeMV3LifecycleCrashMarkerRecord(
                schemaVersion: Self.lifecycleSchemaVersion,
                id: stableID(
                    prefix: "mv3-crash-marker",
                    parts: [
                        normalizedProfileID(profileID),
                        extensionID,
                        String(record.sequence),
                        reason,
                    ]
                ),
                createdAt: now(),
                profileID: normalizedProfileID(profileID),
                extensionID: extensionID,
                activeGeneratedVersionID: record.activeGeneratedVersionID,
                lifecycleSessionLeftActive: lifecycleSessionLeftActive,
                nativeFixturePortLeftOpen: nativeFixturePortLeftOpen,
                reason: reason,
                diagnostics: uniqueSortedLifecycle([
                    "Crash marker is internal synthetic runtime state.",
                    reason,
                ])
            )
            let markerURL = crashMarkerURL(profileID: profileID, extensionID: extensionID)
            try ensureParentDirectory(for: markerURL)
            try ChromeMV3DeterministicJSON.write(marker, to: markerURL)
            record.reportPaths.crashMarkerPath = markerURL.path
            record.runtimeState.sharedLifecycleSessionActive =
                lifecycleSessionLeftActive
            record.runtimeState.nativeFixturePortOpen = nativeFixturePortLeftOpen
            record.runtimeState.syntheticHarnessStatePresent = true
            record.updatedAt = now()
            try writeRecord(record)
            return operationResult(
                operation: .crashMarker,
                succeeded: true,
                record: record,
                diagnostics: [
                    "Internal MV3 crash marker written.",
                ]
            )
        } catch {
            return failureResult(operation: .crashMarker, error: error)
        }
    }

    func runRecoveryScan(
        profileID: String,
        extensionID: String
    ) -> ChromeMV3LifecycleOperationResult {
        do {
            var record = try loadRecord(profileID: profileID, extensionID: extensionID)
            let previous = record
            let recovery = recoveryStatus(for: record)
            guard recovery.recoveryRequired else {
                let report = try writeEndToEndDiagnosticsReport(
                    for: record,
                    updateRebuildResult: ChromeMV3LifecycleOperationSummary(
                        operation: .recoveryScan,
                        succeeded: true,
                        failureCode: nil,
                        message: "Internal MV3 recovery scan found no action.",
                        lifecycleState: record.lifecycleState,
                        activeGeneratedVersionID: record.activeGeneratedVersionID,
                        previousWorkingGeneratedVersionID:
                            record.previousWorkingGeneratedVersionID,
                        generatedVersionID: record.activeGeneratedVersionID
                    ),
                    crashRecoveryStatus: recovery
                )
                return operationResult(
                    operation: .recoveryScan,
                    succeeded: true,
                    record: record,
                    previousRecord: previous,
                    report: report,
                    diagnostics: [
                        "Internal MV3 recovery scan found no action.",
                    ]
                )
            }

            record.runtimeState.internalRuntimeEnabled = false
            record.runtimeState.syntheticHarnessStatePresent = false
            record.runtimeState.sharedLifecycleSessionActive = false
            record.runtimeState.nativeFixturePortOpen = false
            record.lifecycleState = .recoveryRequired
            if let rollbackID = recovery.rolledBackToPreviousWorkingVersionID {
                let oldActiveID = record.activeGeneratedVersionID
                record.generatedBundleVersions = record.generatedBundleVersions.map {
                    item in
                    var updated = item
                    if item.id == rollbackID {
                        updated.state = .rollbackActive
                    } else if item.id == oldActiveID {
                        updated.state = .failed
                    }
                    return updated
                }
                record.activeGeneratedVersionID = rollbackID
                record.previousWorkingGeneratedVersionID = oldActiveID
            } else if recovery.rebuildRequired {
                record.activeGeneratedVersionID = nil
            }
            record.updatedAt = now()
            record.diagnostics = uniqueSortedLifecycle(
                record.diagnostics + recovery.diagnostics
            )
            if let markerPath = record.reportPaths.crashMarkerPath,
               fileManager.fileExists(atPath: markerPath) {
                try fileManager.removeItem(atPath: markerPath)
            }
            record.reportPaths.crashMarkerPath = nil
            try writeRecord(record)
            let report = try writeEndToEndDiagnosticsReport(
                for: record,
                updateRebuildResult: ChromeMV3LifecycleOperationSummary(
                    operation: .recoveryScan,
                    succeeded: true,
                    failureCode: nil,
                    message: "Internal MV3 recovery scan marked recoveryRequired.",
                    lifecycleState: record.lifecycleState,
                    activeGeneratedVersionID: record.activeGeneratedVersionID,
                    previousWorkingGeneratedVersionID:
                        record.previousWorkingGeneratedVersionID,
                    generatedVersionID: record.activeGeneratedVersionID
                ),
                crashRecoveryStatus: recovery
            )
            return operationResult(
                operation: .recoveryScan,
                succeeded: true,
                record: record,
                previousRecord: previous,
                report: report,
                diagnostics: [
                    "Internal MV3 recovery scan marked recoveryRequired.",
                ]
            )
        } catch {
            return failureResult(operation: .recoveryScan, error: error)
        }
    }

    func writeEndToEndDiagnostics(
        profileID: String,
        extensionID: String,
        runtimeDiagnostics:
            ChromeMV3LifecycleRuntimeDiagnosticsSnapshot = .none
    ) -> ChromeMV3EndToEndInstallDiagnosticsReport? {
        guard
            let record = try? loadRecord(profileID: profileID, extensionID: extensionID)
        else {
            return nil
        }
        return try? writeEndToEndDiagnosticsReport(
            for: record,
            updateRebuildResult: ChromeMV3LifecycleOperationSummary(
                operation: .diagnostics,
                succeeded: true,
                failureCode: nil,
                message: "End-to-end internal MV3 diagnostics refreshed.",
                lifecycleState: record.lifecycleState,
                activeGeneratedVersionID: record.activeGeneratedVersionID,
                previousWorkingGeneratedVersionID:
                    record.previousWorkingGeneratedVersionID,
                generatedVersionID: record.activeGeneratedVersionID
            ),
            runtimeDiagnostics: runtimeDiagnostics
        )
    }

    func latestEndToEndDiagnosticsReport(
        profileID: String,
        extensionID: String
    ) -> ChromeMV3EndToEndInstallDiagnosticsReport? {
        let url = diagnosticsReportURL(profileID: profileID, extensionID: extensionID)
        return try? decode(ChromeMV3EndToEndInstallDiagnosticsReport.self, at: url)
    }

    func loadLifecycleRecord(
        profileID: String,
        extensionID: String
    ) -> ChromeMV3ExtensionLifecycleRecord? {
        try? loadRecord(profileID: profileID, extensionID: extensionID)
    }

    private func writeGeneratedVersion(
        sequence: Int,
        originalBundleRecord: ChromeMV3OriginalBundleRecord,
        manifestSnapshot: ChromeMV3ManifestSnapshotRecord,
        planningRecord: ChromeMV3GeneratedBundlePlanningRecord
    ) throws -> ChromeMV3GeneratedBundleVersionRecord {
        let versionID = generatedVersionID(sequence: sequence)
        let versionRoot = generatedVersionRootURL(versionID: versionID)
        if fileManager.fileExists(atPath: versionRoot.path) {
            try fileManager.removeItem(at: versionRoot)
        }
        try fileManager.createDirectory(
            at: versionRoot,
            withIntermediateDirectories: true
        )
        let writeResult = try ChromeMV3GeneratedBundleWriter(rootURL: versionRoot)
            .writeGeneratedBundle(
                originalBundleRecord: originalBundleRecord,
                manifestSnapshot: manifestSnapshot,
                planningRecord: planningRecord
            )
        let runtimePlan = try decode(
            ChromeMV3RuntimeResourcePlan.self,
            at: writeResult.generatedBundleRootURL
                .appendingPathComponent(
                    ChromeMV3GeneratedBundleWriter.runtimeResourcePlanFileName
                )
        )
        let preview = try decode(
            ChromeMV3ManifestRewritePreview.self,
            at: writeResult.manifestRewritePreviewURL
        )
        let dryRunReport = try decode(
            ChromeMV3ManifestRewriteDryRunVerificationReport.self,
            at: writeResult.manifestRewriteDryRunReportURL
        )
        let rewriteResult = try ChromeMV3GeneratedRewriteVariantWriter()
            .writeRewrittenVariant(
                generatedBundleRecord: writeResult.record,
                generatedBundleRootURL: writeResult.generatedBundleRootURL,
                runtimeResourcePlan: runtimePlan,
                manifestRewritePreview: preview,
                dryRunReport: dryRunReport
            )
        let loadabilityReportURL = rewriteResult.variantRootURL
            .appendingPathComponent(ChromeMV3RuntimeLoadabilityVerifier.reportFileName)
        let loadabilityReport = try decode(
            ChromeMV3RuntimeLoadabilityReport.self,
            at: loadabilityReportURL
        )
        return ChromeMV3GeneratedBundleVersionRecord(
            schemaVersion: Self.lifecycleSchemaVersion,
            id: versionID,
            sequence: sequence,
            createdAt: now(),
            state: .candidate,
            versionRootPath: versionRoot.path,
            generatedBundleRootPath: writeResult.generatedBundleRootURL.path,
            rewrittenVariantRootPath: rewriteResult.variantRootURL.path,
            runtimeLoadabilityReportPath: loadabilityReportURL.path,
            originalBundleRecordID: originalBundleRecord.id,
            generatedBundleRecordID: writeResult.record.id,
            generatedManifestSHA256: writeResult.record.generatedManifestSHA256,
            manifestSHA256: writeResult.record.manifestSHA256,
            runtimeLoadable: false,
            generatedBundleRecord: writeResult.record,
            rewriteApplicationReport: rewriteResult.report,
            runtimeLoadabilityReport: loadabilityReport,
            diagnostics: uniqueSortedLifecycle([
                "Generated bundle version was written under an immutable lifecycle version root.",
                "Rewritten variant is fixture-only and remains non-loadable in product.",
            ])
        )
    }

    private func promote(
        _ generatedVersion: ChromeMV3GeneratedBundleVersionRecord,
        in record: ChromeMV3ExtensionLifecycleRecord,
        stage: ChromeMV3OriginalBundleStageResult?,
        sourceURL: URL,
        sequence: Int,
        enabledInternal: Bool
    ) -> ChromeMV3ExtensionLifecycleRecord {
        var updated = record
        let oldActiveID = updated.activeGeneratedVersionID
        updated.generatedBundleVersions = updated.generatedBundleVersions.map {
            item in
            var version = item
            if item.id == oldActiveID {
                version.state = .previousWorking
            }
            return version
        }
        updated.generatedBundleVersions.append(version(generatedVersion, state: .active))
        updated.activeGeneratedVersionID = generatedVersion.id
        updated.previousWorkingGeneratedVersionID = oldActiveID
        updated.candidateGeneratedVersionID = nil
        updated.lifecycleState = enabledInternal ? .enabledInternal : .diagnosticsReady
        updated.sequence = sequence
        updated.updatedAt = now()
        updated.sourcePath = sourceURL.standardizedFileURL.path
        updated.sourceLastPathComponent = sourceURL.lastPathComponent
        if let stage {
            updated.displayName = stage.originalBundleRecord.manifestName
            updated.displayVersion = stage.originalBundleRecord.manifestVersion
            updated.originalBundleRecordID = stage.originalBundleRecord.id
            updated.originalBundleRecordPath =
                URL(
                    fileURLWithPath:
                        stage.originalBundleRecord.storedPaths.recordRootPath,
                    isDirectory: true
                )
                .appendingPathComponent("record.json")
                .path
            updated.originalBundleRootPath =
                stage.originalBundleRecord.storedPaths.originalBundleRootPath
            updated.manifestSnapshotPath =
                stage.originalBundleRecord.storedPaths.manifestSnapshotPath
            updated.installReportPath =
                stage.originalBundleRecord.storedPaths.installReportPath
            updated.generatedBundlePlanPath =
                stage.originalBundleRecord.storedPaths.generatedBundlePlanPath
        }
        updated.diagnostics = uniqueSortedLifecycle(
            updated.diagnostics + [
                "Generated candidate promoted only after validation, generation, rewrite, and loadability report checks completed.",
            ]
        )
        return updated
    }

    private func updateFailureResult(
        operation: ChromeMV3LifecycleOperationKind,
        profileID: String,
        extensionID: String,
        error: Error,
        runtimeDiagnostics:
            ChromeMV3LifecycleRuntimeDiagnosticsSnapshot
    ) -> ChromeMV3LifecycleOperationResult {
        do {
            var record = try loadRecord(profileID: profileID, extensionID: extensionID)
            record.lifecycleState = .updateFailed
            record.candidateGeneratedVersionID = nil
            record.runtimeState.internalRuntimeEnabled = false
            record.updatedAt = now()
            record.diagnostics = uniqueSortedLifecycle(
                record.diagnostics + [
                    "Generated candidate failed and was not promoted.",
                    lifecycleErrorMessage(error),
                ]
            )
            try writeRecord(record)
            let report = try writeEndToEndDiagnosticsReport(
                for: record,
                updateRebuildResult: ChromeMV3LifecycleOperationSummary(
                    operation: operation,
                    succeeded: false,
                    failureCode: failureCode(for: error),
                    message: lifecycleErrorMessage(error),
                    lifecycleState: record.lifecycleState,
                    activeGeneratedVersionID: record.activeGeneratedVersionID,
                    previousWorkingGeneratedVersionID:
                        record.previousWorkingGeneratedVersionID,
                    generatedVersionID: nil
                ),
                runtimeDiagnostics: runtimeDiagnostics
            )
            return operationResult(
                operation: operation,
                succeeded: false,
                failureCode: failureCode(for: error),
                record: record,
                report: report,
                diagnostics: [
                    "Generated candidate failed and was not promoted.",
                    lifecycleErrorMessage(error),
                ]
            )
        } catch {
            return failureResult(operation: operation, error: error)
        }
    }

    private func failureResult(
        operation: ChromeMV3LifecycleOperationKind,
        error: Error,
        sourceURL: URL? = nil,
        profileID: String? = nil
    ) -> ChromeMV3LifecycleOperationResult {
        let diagnostics = [
            lifecycleErrorMessage(error),
            "No product runtime state was changed.",
        ]
        if let sourceURL, let profileID {
            let report = failureDiagnosticsReport(
                operation: operation,
                error: error,
                sourceURL: sourceURL,
                profileID: profileID
            )
            try? writeFailureReport(report)
            return ChromeMV3LifecycleOperationResult(
                schemaVersion: Self.lifecycleSchemaVersion,
                operation: operation,
                succeeded: false,
                failureCode: failureCode(for: error),
                record: nil,
                previousRecord: nil,
                generatedVersion: nil,
                report: report,
                diagnostics: diagnostics,
                productFlags: .unavailable
            )
        }
        return ChromeMV3LifecycleOperationResult(
            schemaVersion: Self.lifecycleSchemaVersion,
            operation: operation,
            succeeded: false,
            failureCode: failureCode(for: error),
            record: nil,
            previousRecord: nil,
            generatedVersion: nil,
            report: nil,
            diagnostics: diagnostics,
            productFlags: .unavailable
        )
    }

    private func operationResult(
        operation: ChromeMV3LifecycleOperationKind,
        succeeded: Bool,
        failureCode: ChromeMV3LifecycleFailureCode? = nil,
        record: ChromeMV3ExtensionLifecycleRecord? = nil,
        previousRecord: ChromeMV3ExtensionLifecycleRecord? = nil,
        generatedVersion: ChromeMV3GeneratedBundleVersionRecord? = nil,
        report: ChromeMV3EndToEndInstallDiagnosticsReport? = nil,
        diagnostics: [String]
    ) -> ChromeMV3LifecycleOperationResult {
        ChromeMV3LifecycleOperationResult(
            schemaVersion: Self.lifecycleSchemaVersion,
            operation: operation,
            succeeded: succeeded,
            failureCode: failureCode,
            record: record,
            previousRecord: previousRecord,
            generatedVersion: generatedVersion,
            report: report,
            diagnostics: uniqueSortedLifecycle(diagnostics),
            productFlags: .unavailable
        )
    }

    private func writeEndToEndDiagnosticsReport(
        for record: ChromeMV3ExtensionLifecycleRecord,
        installImportResult: ChromeMV3LifecycleOperationSummary? = nil,
        updateRebuildResult: ChromeMV3LifecycleOperationSummary? = nil,
        uninstallResetResult: ChromeMV3LifecycleOperationSummary? = nil,
        crashRecoveryStatus: ChromeMV3LifecycleRecoveryStatus = .clean,
        runtimeDiagnostics:
            ChromeMV3LifecycleRuntimeDiagnosticsSnapshot = .none
    ) throws -> ChromeMV3EndToEndInstallDiagnosticsReport {
        let installReport = try? decode(
            ChromeMV3InstallReport.self,
            at: URL(fileURLWithPath: record.installReportPath)
        )
        let compatibility = ChromeMV3EndToEndCompatibilityAggregator.aggregate(
            lifecycleRecord: record,
            installReport: installReport,
            runtimeDiagnostics: runtimeDiagnostics
        )
        let activeVersion = activeVersion(in: record)
        let staticReportAvailable = activeVersion?.runtimeLoadabilityReport != nil
        let syntheticReportNames = runtimeDiagnostics.reportNames
        let internalReadiness = ChromeMV3LifecycleInternalSyntheticReadinessSummary(
            generatedBundleAvailable: activeVersion != nil,
            generatedRewrittenVariantAvailable:
                activeVersion?.rewrittenVariantRootPath != nil,
            staticRuntimeLoadabilityReportAvailable: staticReportAvailable,
            runtimeCompatibilityDiagnosticsAvailable:
                runtimeDiagnostics.anyDiagnosticsAvailable
                    || staticReportAvailable,
            syntheticAPIReportsAvailable: syntheticReportNames,
            launchableInProduct: false,
            diagnostics: uniqueSortedLifecycle(
                runtimeDiagnostics.diagnostics + [
                    "Internal diagnostics are explicit and do not attach generated bundles to product normal tabs.",
                ]
            )
        )
        let productReadiness = ChromeMV3LifecycleProductReadinessSummary(
            productRuntimeAvailable: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            productUIAvailable: false,
            productNetworkEnforcementAvailable: false,
            launchBlocked: true,
            blockers: compatibility.allBlockers.filter {
                $0.severity == .productBlocked || $0.severity == .fatalRuntime
            }
        )
        let availability = ChromeMV3LifecycleCapabilityAvailability(
            extensionInstalledInInternalRegistry:
                record.lifecycleState != .uninstalled,
            generatedBundleAvailable: activeVersion != nil,
            internalSyntheticRuntimeDiagnosticsAvailable:
                internalReadiness.runtimeCompatibilityDiagnosticsAvailable,
            productRuntimeAvailable: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            compatibilityReportAvailable: true
        )
        let report = ChromeMV3EndToEndInstallDiagnosticsReport(
            schemaVersion: Self.lifecycleSchemaVersion,
            id: stableID(
                prefix: "mv3-e2e-report",
                parts: [
                    record.profileID,
                    record.extensionID,
                    record.activeGeneratedVersionID ?? "no-active-version",
                    record.lifecycleState.rawValue,
                ]
            ),
            reportFileName: Self.diagnosticsReportFileName,
            generatedAt: now(),
            registryLifecycleState: record.lifecycleState,
            lifecycleAvailability: availability,
            installImportResult: installImportResult,
            generatedBundleVersionState: record.generatedBundleVersions.sorted {
                $0.sequence < $1.sequence
            },
            updateRebuildResult: updateRebuildResult,
            uninstallResetResult: uninstallResetResult,
            crashRecoveryStatus: crashRecoveryStatus,
            aggregateAPICompatibility: compatibility,
            blockerTaxonomy: compatibility.allBlockers,
            productReadinessSummary: productReadiness,
            internalSyntheticReadinessSummary: internalReadiness,
            passwordManagerReadinessSummary:
                activeVersion?.runtimeLoadabilityReport?.passwordManagerReadiness,
            productFlags: .unavailable
        )
        let reportURL = diagnosticsReportURL(
            profileID: record.profileID,
            extensionID: record.extensionID
        )
        try ensureParentDirectory(for: reportURL)
        try ChromeMV3DeterministicJSON.write(report, to: reportURL)
        return report
    }

    private func failureDiagnosticsReport(
        operation: ChromeMV3LifecycleOperationKind,
        error: Error,
        sourceURL: URL,
        profileID: String
    ) -> ChromeMV3EndToEndInstallDiagnosticsReport {
        let fatalReport = ChromeMV3InstallReporter.fatalReport(error: error)
        let blocker = ChromeMV3EndToEndCompatibilityAggregator.blocker(
            severity: .fatalInstall,
            source: failureSource(for: error),
            api: nil,
            method: nil,
            manifestKey: nil,
            filePath: sourceURL.path,
            message: lifecycleErrorMessage(error),
            remediation:
                "Fix the unpacked MV3 source and retry internal import.",
            owner: "Prompt 55 lifecycle diagnostics"
        )
        let compatibility = ChromeMV3EndToEndCompatibilityAggregator.aggregate(
            lifecycleRecord: nil,
            installReport: fatalReport,
            extraBlockers: [blocker]
        )
        let operationSummary = ChromeMV3LifecycleOperationSummary(
            operation: operation,
            succeeded: false,
            failureCode: failureCode(for: error),
            message: lifecycleErrorMessage(error),
            lifecycleState: nil,
            activeGeneratedVersionID: nil,
            previousWorkingGeneratedVersionID: nil,
            generatedVersionID: nil
        )
        return ChromeMV3EndToEndInstallDiagnosticsReport(
            schemaVersion: Self.lifecycleSchemaVersion,
            id: stableID(
                prefix: "mv3-e2e-failure-report",
                parts: [
                    normalizedProfileID(profileID),
                    sourceURL.standardizedFileURL.path,
                    operation.rawValue,
                    lifecycleErrorMessage(error),
                ]
            ),
            reportFileName: Self.diagnosticsReportFileName,
            generatedAt: now(),
            registryLifecycleState: nil,
            lifecycleAvailability:
                ChromeMV3LifecycleCapabilityAvailability(
                    extensionInstalledInInternalRegistry: false,
                    generatedBundleAvailable: false,
                    internalSyntheticRuntimeDiagnosticsAvailable: false,
                    productRuntimeAvailable: false,
                    normalTabRuntimeBridgeAvailable: false,
                    runtimeLoadable: false,
                    compatibilityReportAvailable: true
                ),
            installImportResult: operation == .installImport
                ? operationSummary
                : nil,
            generatedBundleVersionState: [],
            updateRebuildResult: operation == .installImport
                ? nil
                : operationSummary,
            uninstallResetResult: nil,
            crashRecoveryStatus: .clean,
            aggregateAPICompatibility: compatibility,
            blockerTaxonomy: compatibility.allBlockers,
            productReadinessSummary:
                ChromeMV3LifecycleProductReadinessSummary(
                    productRuntimeAvailable: false,
                    normalTabRuntimeBridgeAvailable: false,
                    runtimeLoadable: false,
                    productUIAvailable: false,
                    productNetworkEnforcementAvailable: false,
                    launchBlocked: true,
                    blockers: compatibility.allBlockers
                ),
            internalSyntheticReadinessSummary:
                ChromeMV3LifecycleInternalSyntheticReadinessSummary(
                    generatedBundleAvailable: false,
                    generatedRewrittenVariantAvailable: false,
                    staticRuntimeLoadabilityReportAvailable: false,
                    runtimeCompatibilityDiagnosticsAvailable: false,
                    syntheticAPIReportsAvailable: [],
                    launchableInProduct: false,
                    diagnostics: [
                        "Import failed before internal synthetic diagnostics could run.",
                    ]
                ),
            passwordManagerReadinessSummary: nil,
            productFlags: .unavailable
        )
    }

    private func recoveryStatus(
        for record: ChromeMV3ExtensionLifecycleRecord
    ) -> ChromeMV3LifecycleRecoveryStatus {
        let marker = record.reportPaths.crashMarkerPath.flatMap {
            try? decode(
                ChromeMV3LifecycleCrashMarkerRecord.self,
                at: URL(fileURLWithPath: $0)
            )
        }
        let active = activeVersion(in: record)
        let activeGeneratedMissing = active.map {
            directoryExists(URL(fileURLWithPath: $0.generatedBundleRootPath, isDirectory: true)) == false
        } ?? (record.lifecycleState != .uninstalled)
        let manifestCorrupt =
            (try? decode(
                ChromeMV3ManifestSnapshotRecord.self,
                at: URL(fileURLWithPath: record.manifestSnapshotPath)
            )) == nil
        let metadataCorrupt: Bool
        if let active {
            metadataCorrupt =
                (try? decode(
                    ChromeMV3GeneratedBundleRecord.self,
                    at: URL(
                        fileURLWithPath:
                            active.generatedBundleRecord.generatedMetadataPath
                    )
                )) == nil
        } else {
            metadataCorrupt = record.lifecycleState != .uninstalled
        }
        let reportCorrupt =
            (try? decode(
                ChromeMV3EndToEndInstallDiagnosticsReport.self,
                at: diagnosticsReportURL(
                    profileID: record.profileID,
                    extensionID: record.extensionID
                )
            )) == nil
        let lifecycleSessionLeftActive =
            marker?.lifecycleSessionLeftActive
                ?? record.runtimeState.sharedLifecycleSessionActive
        let nativeFixturePortLeftOpen =
            marker?.nativeFixturePortLeftOpen
                ?? record.runtimeState.nativeFixturePortOpen
        let recoveryRequired = marker != nil
            || activeGeneratedMissing
            || manifestCorrupt
            || metadataCorrupt
            || reportCorrupt
            || lifecycleSessionLeftActive
            || nativeFixturePortLeftOpen
        let rollbackID = recoveryRequired
            ? validPreviousWorkingVersion(in: record)
            : nil
        var diagnostics: [String] = []
        if marker != nil {
            diagnostics.append("Crash marker was detected.")
        }
        if activeGeneratedMissing {
            diagnostics.append("Active generated bundle is missing.")
        }
        if manifestCorrupt {
            diagnostics.append("Manifest snapshot is missing or corrupt.")
        }
        if metadataCorrupt {
            diagnostics.append("Generated metadata is missing or corrupt.")
        }
        if reportCorrupt {
            diagnostics.append("End-to-end diagnostics report is missing or corrupt.")
        }
        if lifecycleSessionLeftActive {
            diagnostics.append("Internal lifecycle session was left active.")
        }
        if nativeFixturePortLeftOpen {
            diagnostics.append("Native messaging fixture port was left open.")
        }
        if let rollbackID {
            diagnostics.append(
                "Recovery can roll back to previous working generated version \(rollbackID)."
            )
        } else if recoveryRequired {
            diagnostics.append("No valid generated version is available; rebuild is required.")
        }
        return ChromeMV3LifecycleRecoveryStatus(
            recoveryRequired: recoveryRequired,
            crashMarkerDetected: marker != nil,
            activeGeneratedBundleMissing: activeGeneratedMissing,
            manifestSnapshotMissingOrCorrupt: manifestCorrupt,
            generatedMetadataMissingOrCorrupt: metadataCorrupt,
            reportMissingOrCorrupt: reportCorrupt,
            lifecycleSessionLeftActive: lifecycleSessionLeftActive,
            nativeFixturePortLeftOpen: nativeFixturePortLeftOpen,
            rolledBackToPreviousWorkingVersionID: rollbackID,
            internalRuntimeDisabled: recoveryRequired,
            rebuildRequired: recoveryRequired && rollbackID == nil,
            diagnostics: uniqueSortedLifecycle(diagnostics)
        )
    }

    private func validPreviousWorkingVersion(
        in record: ChromeMV3ExtensionLifecycleRecord
    ) -> String? {
        guard let previousID = record.previousWorkingGeneratedVersionID else {
            return nil
        }
        return validGeneratedVersion(previousID, in: record) ? previousID : nil
    }

    private func validGeneratedVersion(
        _ versionID: String,
        in record: ChromeMV3ExtensionLifecycleRecord
    ) -> Bool {
        guard
            let version = record.generatedBundleVersions.first(where: {
                $0.id == versionID
            })
        else {
            return false
        }
        return directoryExists(
            URL(fileURLWithPath: version.generatedBundleRootPath, isDirectory: true)
        )
        && fileManager.fileExists(
            atPath: version.generatedBundleRecord.generatedMetadataPath
        )
    }

    private func activeVersion(
        in record: ChromeMV3ExtensionLifecycleRecord
    ) -> ChromeMV3GeneratedBundleVersionRecord? {
        guard let activeID = record.activeGeneratedVersionID else { return nil }
        return record.generatedBundleVersions.first { $0.id == activeID }
    }

    private func version(
        _ version: ChromeMV3GeneratedBundleVersionRecord,
        state: ChromeMV3GeneratedBundleVersionState
    ) -> ChromeMV3GeneratedBundleVersionRecord {
        var updated = version
        updated.state = state
        return updated
    }

    private func writeFailureReport(
        _ report: ChromeMV3EndToEndInstallDiagnosticsReport
    ) throws {
        let url = failuresRootURL().appendingPathComponent("\(report.id).json")
        try ensureParentDirectory(for: url)
        try ChromeMV3DeterministicJSON.write(report, to: url)
    }

    private func writeRecord(_ record: ChromeMV3ExtensionLifecycleRecord) throws {
        let url = registryRecordURL(
            profileID: record.profileID,
            extensionID: record.extensionID
        )
        try ensureParentDirectory(for: url)
        try ChromeMV3DeterministicJSON.write(record, to: url)
    }

    private func loadRecord(
        profileID: String,
        extensionID: String
    ) throws -> ChromeMV3ExtensionLifecycleRecord {
        let url = registryRecordURL(profileID: profileID, extensionID: extensionID)
        guard fileManager.fileExists(atPath: url.path) else {
            throw ChromeMV3ExtensionLifecycleRegistryError.missingRecord(
                profileID: normalizedProfileID(profileID),
                extensionID: extensionID
            )
        }
        do {
            return try decode(ChromeMV3ExtensionLifecycleRecord.self, at: url)
        } catch {
            throw ChromeMV3ExtensionLifecycleRegistryError.corruptRecord(url.path)
        }
    }

    private func nextSequence(after current: Int? = nil) throws -> Int {
        let existing = lifecycleRecordURLs().compactMap {
            try? decode(ChromeMV3ExtensionLifecycleRecord.self, at: $0).sequence
        }
        return max(existing.max() ?? 0, current ?? 0) + 1
    }

    private func lifecycleRecordURLs() -> [URL] {
        let recordsRoot = lifecycleRootURL()
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
            guard url.lastPathComponent == "lifecycle-record.json" else {
                return nil
            }
            return url
        }
    }

    private func generatedVersionID(sequence: Int) -> String {
        "generated-version-\(String(format: "%04d", sequence))"
    }

    private func lifecycleRootURL() -> URL {
        rootURL.appendingPathComponent("lifecycle", isDirectory: true)
    }

    private func generatedVersionRootURL(versionID: String) -> URL {
        lifecycleRootURL()
            .appendingPathComponent("generated-versions", isDirectory: true)
            .appendingPathComponent(versionID, isDirectory: true)
    }

    private func registryRecordURL(profileID: String, extensionID: String) -> URL {
        lifecycleRootURL()
            .appendingPathComponent("records", isDirectory: true)
            .appendingPathComponent(safePathComponent(normalizedProfileID(profileID)), isDirectory: true)
            .appendingPathComponent(safePathComponent(extensionID), isDirectory: true)
            .appendingPathComponent("lifecycle-record.json")
    }

    private func diagnosticsReportURL(profileID: String, extensionID: String) -> URL {
        lifecycleRootURL()
            .appendingPathComponent("reports", isDirectory: true)
            .appendingPathComponent(safePathComponent(normalizedProfileID(profileID)), isDirectory: true)
            .appendingPathComponent(safePathComponent(extensionID), isDirectory: true)
            .appendingPathComponent(Self.diagnosticsReportFileName)
    }

    private func crashMarkerURL(profileID: String, extensionID: String) -> URL {
        lifecycleRootURL()
            .appendingPathComponent("crash-markers", isDirectory: true)
            .appendingPathComponent(safePathComponent(normalizedProfileID(profileID)), isDirectory: true)
            .appendingPathComponent("\(safePathComponent(extensionID)).json")
    }

    private func failuresRootURL() -> URL {
        lifecycleRootURL().appendingPathComponent("failures", isDirectory: true)
    }

    private func ensureParentDirectory(for url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func decode<T: Decodable>(_ type: T.Type, at url: URL) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: Data(contentsOf: url))
    }

    private func failureCode(for error: Error) -> ChromeMV3LifecycleFailureCode {
        if let sourceError = error as? ChromeMV3ExtensionLifecycleRegistryError {
            switch sourceError {
            case .unsupportedSourceKind:
                return .unsupportedSource
            case .missingRecord:
                return .recordMissing
            case .missingActiveGeneratedVersion,
                 .missingPreviousWorkingGeneratedVersion:
                return .noPreviousWorkingVersion
            case .corruptRecord:
                return .reportCorrupt
            }
        }
        if let validationError = error as? ChromeMV3ManifestValidationError {
            switch validationError {
            case .unsupportedManifestVersion,
                 .missingManifestVersion,
                 .invalidManifestVersion,
                 .missingName,
                 .missingVersion,
                 .backgroundPageUnsupported,
                 .backgroundScriptsUnsupported,
                 .backgroundPersistenceUnsupported,
                 .invalidJSON,
                 .invalidJSONStructure,
                 .missingManifest,
                 .unsupportedSafariPackageInput,
                 .unsupportedArchiveInspection,
                 .unsafeResourcePath:
                return .manifestInvalid
            }
        }
        if let writerError = error as? ChromeMV3GeneratedBundleWriterError {
            switch writerError {
            case .missingReferencedResource,
                 .missingOriginalBundle,
                 .nonRegularReferencedResource,
                 .symbolicLinkReferencedResource,
                 .sourceEscapedOriginalRoot,
                 .unsafeResourcePath:
                return .resourceMissing
            case .recordMismatch,
                 .invalidManifestJSON:
                return .generatedBundleFailed
            }
        }
        if error is ChromeMV3GeneratedRewriteVariantWriterError {
            return .generatedBundleFailed
        }
        return .unknownInternalError
    }

    private func failureSource(for error: Error) -> ChromeMV3APIBlockerSource {
        if error is ChromeMV3GeneratedBundleWriterError {
            return .generatedBundle
        }
        return .manifest
    }

    private func lifecycleErrorMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}

enum ChromeMV3EndToEndCompatibilityAggregator {
    static func aggregate(
        lifecycleRecord: ChromeMV3ExtensionLifecycleRecord?,
        installReport: ChromeMV3InstallReport?,
        runtimeDiagnostics:
            ChromeMV3LifecycleRuntimeDiagnosticsSnapshot = .none,
        extraBlockers: [ChromeMV3APIBlockerRecord] = []
    ) -> ChromeMV3AggregateAPICompatibility {
        var blockers: [ChromeMV3APIBlockerRecord] = extraBlockers
        if let installReport {
            blockers.append(contentsOf: installReport.fatalValidationErrors.map {
                blocker(
                    severity: .fatalInstall,
                    source: .manifest,
                    api: nil,
                    method: nil,
                    manifestKey: $0.field,
                    filePath: installReport.packageMetadata?.originalBundlePath,
                    message: $0.message,
                    remediation: "Fix manifest validation error and retry internal import.",
                    owner: "Prompt 55 lifecycle diagnostics"
                )
            })
            blockers.append(contentsOf: installReport.warnings.map {
                blocker(
                    severity: severity(for: $0),
                    source: source(for: $0),
                    api: api(from: $0.field),
                    method: nil,
                    manifestKey: $0.field,
                    filePath: nil,
                    message: $0.message,
                    remediation: remediation(for: $0),
                    owner: owner(for: $0)
                )
            })
            blockers.append(contentsOf: installReport.unsupportedAPIs.map {
                blocker(
                    severity: .unsupported,
                    source: .securityPolicy,
                    api: $0,
                    method: nil,
                    manifestKey: $0.rawValue,
                    filePath: nil,
                    message: "\($0.rawValue) is not supported by the internal MV3 foundation.",
                    remediation: "Remove this API dependency or wait for an explicit compatibility task.",
                    owner: "Chrome MV3 API compatibility roadmap"
                )
            })
            blockers.append(contentsOf: installReport.deferredAPIs.map {
                blocker(
                    severity: .deferred,
                    source: source(for: $0),
                    api: $0,
                    method: nil,
                    manifestKey: $0.rawValue,
                    filePath: nil,
                    message: "\($0.rawValue) is deferred or synthetic-only in this lifecycle.",
                    remediation: "Use internal diagnostics only; do not claim product runtime support.",
                    owner: "Chrome MV3 API compatibility roadmap"
                )
            })
            blockers.append(contentsOf: productBlockers(from: installReport))
        }
        if let record = lifecycleRecord {
            for version in record.generatedBundleVersions {
                blockers.append(contentsOf: version.generatedBundleRecord.resourceWarnings.map {
                    blocker(
                        severity: .warning,
                        source: .resource,
                        api: nil,
                        method: nil,
                        manifestKey: $0.field,
                        filePath: $0.path,
                        message: $0.message,
                        remediation: "Fix or remove the manifest resource reference.",
                        owner: "Prompt 55 lifecycle diagnostics"
                    )
                })
            }
            if record.productFlags.runtimeLoadable == false {
                blockers.append(
                    blocker(
                        severity: .productBlocked,
                        source: .runtimeGate,
                        api: .runtime,
                        method: nil,
                        manifestKey: nil,
                        filePath: nil,
                        message: "runtimeLoadable remains false for product runtime.",
                        remediation: "Keep this extension in internal diagnostics until a later product runtime prompt changes the gate.",
                        owner: "Prompt 56+ product hardening"
                    )
                )
            }
        }
        if runtimeDiagnostics.WebKitObjectDiagnosticsAvailable == false {
            blockers.append(
                blocker(
                    severity: .info,
                    source: .WebKitObject,
                    api: .runtime,
                    method: nil,
                    manifestKey: nil,
                    filePath: nil,
                    message: "WebKit object acceptance diagnostics are not attached to this aggregate report.",
                    remediation: "Run the explicit DEBUG/internal WebKit object diagnostics gate when needed.",
                    owner: "Prompt 37-45 diagnostics"
                )
            )
        }
        blockers = uniqueBlockers(blockers)
        let productBlocked = blockers.compactMap { blocker -> ChromeMV3API? in
            guard blocker.severity == .productBlocked else { return nil }
            return blocker.apiNamespace.flatMap(ChromeMV3API.init(rawValue:))
        }
        let supportedInternal = uniqueAPIs(
            (installReport?.supportedAPIs ?? [])
                + (installReport?.nativeHostAPIs ?? [])
        )
        let supportedSynthetic = uniqueAPIs(
            (installReport?.shimmedAPIs ?? [])
                + (runtimeDiagnostics.anyDiagnosticsAvailable
                    ? [.runtime]
                    : [])
        )
        let partial = uniqueAPIs(installReport?.needsVerificationAPIs ?? [])
        let unsupported = uniqueAPIs(installReport?.unsupportedAPIs ?? [])
        let deferred = uniqueAPIs(installReport?.deferredAPIs ?? [])
        return ChromeMV3AggregateAPICompatibility(
            supportedInternalAPIs: supportedInternal,
            supportedSyntheticAPIs: supportedSynthetic,
            partialAPIs: partial,
            productBlockedAPIs: uniqueAPIs(productBlocked),
            unsupportedAPIs: unsupported,
            deferredAPIs: deferred,
            missingManifestResourceBlockers: blockers.filter {
                $0.source == .manifest || $0.source == .resource
            },
            WebKitBlockers: blockers.filter { $0.source == .WebKitObject },
            nativeHostBlockers: blockers.filter {
                $0.source == .nativeMessaging
            },
            serviceWorkerBlockers: blockers.filter {
                $0.source == .serviceWorker
            },
            productUIBlockers: blockers.filter {
                $0.source == .productUI || $0.source == .sidePanel
            },
            securityPolicyBlockers: blockers.filter {
                $0.source == .securityPolicy
            },
            allBlockers: blockers,
            nextRecommendedAction: nextAction(blockers: blockers)
        )
    }

    static func blocker(
        severity: ChromeMV3APIBlockerSeverity,
        source: ChromeMV3APIBlockerSource,
        api: ChromeMV3API?,
        method: String?,
        manifestKey: String?,
        filePath: String?,
        message: String,
        remediation: String,
        owner: String?
    ) -> ChromeMV3APIBlockerRecord {
        let id = stableID(
            prefix: "mv3-blocker",
            parts: [
                severity.rawValue,
                source.rawValue,
                api?.rawValue ?? "",
                method ?? "",
                manifestKey ?? "",
                filePath ?? "",
                message,
            ]
        )
        return ChromeMV3APIBlockerRecord(
            id: id,
            severity: severity,
            source: source,
            apiNamespace: api?.rawValue,
            apiMethod: method,
            manifestKey: manifestKey,
            filePath: filePath,
            message: message,
            remediation: remediation,
            roadmapOwner: owner
        )
    }

    private static func productBlockers(
        from report: ChromeMV3InstallReport
    ) -> [ChromeMV3APIBlockerRecord] {
        var blockers: [ChromeMV3APIBlockerRecord] = []
        let network = report.networkCompatibilitySummary
        if network.declaresDeclarativeNetRequest {
            blockers.append(
                blocker(
                    severity: .productBlocked,
                    source: .network,
                    api: .declarativeNetRequest,
                    method: nil,
                    manifestKey: "declarative_net_request",
                    filePath: nil,
                    message: "declarativeNetRequest is available only in internal evaluator diagnostics; product network enforcement is unavailable.",
                    remediation: "Keep DNR usage diagnostic-only until product network policy is explicitly designed.",
                    owner: "Prompt 53/56 network compatibility"
                )
            )
        }
        if network.declaresWebRequest || network.declaresWebRequestBlocking {
            blockers.append(
                blocker(
                    severity: .productBlocked,
                    source: .network,
                    api: .webRequest,
                    method: network.declaresWebRequestBlocking
                        ? "blocking"
                        : nil,
                    manifestKey: network.declaresWebRequestBlocking
                        ? "permissions.webRequestBlocking"
                        : "permissions.webRequest",
                    filePath: nil,
                    message: "webRequest is synthetic-only; product request observation and blocking are unavailable.",
                    remediation: "Do not subscribe to product network events in this lifecycle.",
                    owner: "Prompt 53/56 network compatibility"
                )
            )
        }
        let side = report.sidePanelOffscreenIdentitySummary
        if side.declaresSidePanelManifestKey || side.declaresSidePanelPermission {
            blockers.append(
                blocker(
                    severity: .productBlocked,
                    source: .sidePanel,
                    api: .sidePanel,
                    method: nil,
                    manifestKey: side.declaresSidePanelManifestKey
                        ? "side_panel"
                        : "permissions.sidePanel",
                    filePath: side.sidePanelDefaultPath,
                    message: "sidePanel is internal/synthetic diagnostics only; product side-panel UI is unavailable.",
                    remediation: "Keep sidePanel blocked until a product UI prompt explicitly adds it.",
                    owner: "Prompt 54/56 product UI"
                )
            )
        }
        if side.declaresOffscreenPermission {
            blockers.append(
                blocker(
                    severity: .productBlocked,
                    source: .offscreen,
                    api: .offscreen,
                    method: "createDocument",
                    manifestKey: "permissions.offscreen",
                    filePath: nil,
                    message: "offscreen documents are model-only diagnostics; product hidden offscreen runtime is unavailable.",
                    remediation: "Do not create product hidden offscreen WebViews in this lifecycle.",
                    owner: "Prompt 54/56 runtime policy"
                )
            )
        }
        if side.declaresIdentityPermission
            || side.declaresIdentityEmailPermission
            || side.oauth2Scopes.isEmpty == false
        {
            blockers.append(
                blocker(
                    severity: .productBlocked,
                    source: .identity,
                    api: .identity,
                    method: "launchWebAuthFlow",
                    manifestKey:
                        side.oauth2Scopes.isEmpty ? "permissions.identity" : "oauth2",
                    filePath: nil,
                    message: "identity OAuth and external auth network flows are product-blocked.",
                    remediation: "Use deterministic synthetic identity fixtures only.",
                    owner: "Prompt 54/56 identity policy"
                )
            )
        }
        if report.detectedAPIs.contains(.nativeMessaging) {
            blockers.append(
                blocker(
                    severity: .productBlocked,
                    source: .nativeMessaging,
                    api: .nativeMessaging,
                    method: "connect" + "Native",
                    manifestKey: "permissions.nativeMessaging",
                    filePath: nil,
                    message: "Native messaging is limited to explicit fixture hosts; arbitrary product native host launch is unavailable.",
                    remediation: "Keep native messaging under the fixture gate.",
                    owner: "Prompt 50/56 native messaging policy"
                )
            )
        }
        if report.manifestSummary?.backgroundServiceWorker != nil {
            blockers.append(
                blocker(
                    severity: .productBlocked,
                    source: .serviceWorker,
                    api: .runtime,
                    method: "serviceWorkerWake",
                    manifestKey: "background.service_worker",
                    filePath: report.manifestSummary?.backgroundServiceWorker,
                    message: "Service-worker wake is internal/shared fixture state only; product wake remains unavailable.",
                    remediation: "Do not create permanent background behavior or product wake paths.",
                    owner: "Prompt 51/56 service-worker lifecycle"
                )
            )
        }
        return blockers
    }

    private static func severity(
        for issue: ChromeMV3InstallIssue
    ) -> ChromeMV3APIBlockerSeverity {
        switch issue.code {
        case "unsupportedAPI":
            return .unsupported
        case "deferredAPI":
            return .deferred
        case _ where issue.code.contains("ProductBlocked"):
            return .productBlocked
        case _ where issue.code.contains("SyntheticOnly"):
            return .productBlocked
        default:
            return issue.severity == .fatal ? .fatalInstall : .warning
        }
    }

    private static func source(
        for issue: ChromeMV3InstallIssue
    ) -> ChromeMV3APIBlockerSource {
        guard let field = issue.field else { return .manifest }
        if field.contains("webRequest")
            || field.contains("declarative_net_request")
        {
            return .network
        }
        if field.contains("side") {
            return .sidePanel
        }
        if field.contains("offscreen") {
            return .offscreen
        }
        if field.contains("identity") || field.contains("oauth2") {
            return .identity
        }
        if field.contains("nativeMessaging") {
            return .nativeMessaging
        }
        return .manifest
    }

    private static func source(
        for api: ChromeMV3API
    ) -> ChromeMV3APIBlockerSource {
        switch api {
        case .webRequest, .declarativeNetRequest:
            return .network
        case .sidePanel:
            return .sidePanel
        case .offscreen:
            return .offscreen
        case .identity:
            return .identity
        case .nativeMessaging:
            return .nativeMessaging
        case .permissions:
            return .permission
        case .storage:
            return .storage
        default:
            return .runtimeGate
        }
    }

    private static func remediation(for issue: ChromeMV3InstallIssue) -> String {
        switch severity(for: issue) {
        case .unsupported:
            return "Remove the unsupported API dependency or wait for an explicit compatibility task."
        case .deferred:
            return "Keep this API in diagnostics until a future implementation prompt owns it."
        case .productBlocked:
            return "Do not expose this API in product runtime in this lifecycle."
        case .fatalInstall:
            return "Fix the manifest or resource error and retry import."
        default:
            return "Review the internal compatibility report before enabling diagnostics."
        }
    }

    private static func owner(for issue: ChromeMV3InstallIssue) -> String? {
        switch source(for: issue) {
        case .network:
            return "Prompt 53/56 network compatibility"
        case .sidePanel, .offscreen, .identity, .productUI:
            return "Prompt 54/56 product hardening"
        case .nativeMessaging:
            return "Prompt 50/56 native messaging policy"
        default:
            return "Chrome MV3 lifecycle diagnostics"
        }
    }

    private static func api(from field: String?) -> ChromeMV3API? {
        guard let field else { return nil }
        let normalized = field
            .replacingOccurrences(of: "permissions.", with: "")
            .replacingOccurrences(of: "declarative_net_request", with: "declarativeNetRequest")
        return ChromeMV3API(rawValue: normalized)
    }

    private static func uniqueBlockers(
        _ blockers: [ChromeMV3APIBlockerRecord]
    ) -> [ChromeMV3APIBlockerRecord] {
        var seen: Set<String> = []
        return blockers.filter { blocker in
            if seen.contains(blocker.id) { return false }
            seen.insert(blocker.id)
            return true
        }
        .sorted {
            if $0.severity != $1.severity {
                return $0.severity < $1.severity
            }
            if $0.source != $1.source {
                return $0.source < $1.source
            }
            return $0.id < $1.id
        }
    }

    private static func uniqueAPIs(_ apis: [ChromeMV3API]) -> [ChromeMV3API] {
        Array(Set(apis)).sorted()
    }

    private static func nextAction(
        blockers: [ChromeMV3APIBlockerRecord]
    ) -> String {
        if blockers.contains(where: { $0.severity == .fatalInstall }) {
            return "Fix fatal manifest/resource errors and retry internal import."
        }
        if blockers.contains(where: { $0.severity == .fatalRuntime }) {
            return "Rebuild or recover generated artifacts before running diagnostics."
        }
        if blockers.contains(where: { $0.severity == .productBlocked }) {
            return "Use internal diagnostics only; product runtime remains unavailable."
        }
        if blockers.contains(where: { $0.severity == .unsupported }) {
            return "Remove unsupported API dependencies or keep the extension disabled internally."
        }
        return "Internal diagnostics can be refreshed or the generated bundle can be rebuilt."
    }
}

private extension ChromeMV3LifecycleRuntimeDiagnosticsSnapshot {
    var reportNames: [String] {
        var names: [String] = []
        if WebKitObjectDiagnosticsAvailable {
            names.append("WebKitObject")
        }
        if contextCreationGateDiagnosticsAvailable {
            names.append("contextCreationGate")
        }
        if controllerLoadGateDiagnosticsAvailable {
            names.append("controllerLoadGate")
        }
        if runtimeBridgeReadinessDiagnosticsAvailable {
            names.append("runtimeBridgeReadiness")
        }
        if runtimeJSMessagingDiagnosticsAvailable {
            names.append("chrome.runtime")
        }
        if tabsScriptingDiagnosticsAvailable {
            names.append("chrome.tabs/chrome.scripting")
        }
        if permissionsDiagnosticsAvailable {
            names.append("chrome.permissions")
        }
        if storageDiagnosticsAvailable {
            names.append("chrome.storage.local")
        }
        if nativeMessagingDiagnosticsAvailable {
            names.append("chrome.runtime.nativeMessaging")
        }
        if serviceWorkerDiagnosticsAvailable {
            names.append("serviceWorkerLifecycle")
        }
        if eventAPIDiagnosticsAvailable {
            names.append("contextMenus/alarms/webNavigation")
        }
        if networkDiagnosticsAvailable {
            names.append("DNR/webRequest")
        }
        if sidePanelOffscreenIdentityDiagnosticsAvailable {
            names.append("sidePanel/offscreen/identity")
        }
        if passwordManagerDiagnosticsAvailable {
            names.append("passwordManagerFixture")
        }
        return names.sorted()
    }
}

private func stableID(prefix: String, parts: [String]) -> String {
    let data = parts.joined(separator: "\u{1f}").data(using: .utf8) ?? Data()
    let digest = SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
    return "\(prefix)-\(digest.prefix(24))"
}

private func normalizedProfileID(_ profileID: String) -> String {
    let trimmed = profileID.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "internal-debug-profile" : trimmed
}

private func safePathComponent(_ raw: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let value = raw.unicodeScalars.map { scalar -> String in
        allowed.contains(scalar) ? String(scalar) : "-"
    }
    .joined()
    return value.isEmpty ? "value" : value
}

private func lifecycleErrorMessage(_ error: Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? String(describing: error)
}

private func uniqueSortedLifecycle(_ values: [String]) -> [String] {
    Array(Set(values)).sorted()
}
