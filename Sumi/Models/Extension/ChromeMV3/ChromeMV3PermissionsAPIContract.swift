//
//  ChromeMV3PermissionsAPIContract.swift
//  Sumi
//
//  Pure Chrome MV3 chrome.permissions API contract models. This file records
//  future contains, getAll, request, remove, onAdded, onRemoved, and report
//  semantics only. It does not import WebKit, create or load contexts, prompt
//  users, register JavaScript listeners, dispatch events, wake service workers,
//  inject scripts, open ports, launch native messaging, or schedule work.
//

import CryptoKit
import Foundation

enum ChromeMV3PermissionsAPIRequestSourceContext:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case actionPopup
    case extensionPage
    case optionsPage
    case serviceWorker
    case testFixture

    static func < (
        lhs: ChromeMV3PermissionsAPIRequestSourceContext,
        rhs: ChromeMV3PermissionsAPIRequestSourceContext
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PermissionsAPIRequestedItemKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case apiPermission
    case origin

    static func < (
        lhs: ChromeMV3PermissionsAPIRequestedItemKind,
        rhs: ChromeMV3PermissionsAPIRequestedItemKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PermissionsAPIInputIssueKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case emptyOrigin
    case emptyPermission
    case invalidOriginPattern
    case originPatternInPermissionsArray
    case unsupportedOriginPattern

    static func < (
        lhs: ChromeMV3PermissionsAPIInputIssueKind,
        rhs: ChromeMV3PermissionsAPIInputIssueKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3PermissionsAPIInputIssue:
    Codable,
    Equatable,
    Sendable
{
    var kind: ChromeMV3PermissionsAPIInputIssueKind
    var value: String
    var diagnostics: [String]
}

struct ChromeMV3PermissionsAPIRequestInput:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var sourceContext: ChromeMV3PermissionsAPIRequestSourceContext
    var userGestureModeled: Bool
    var extensionModuleEnabled: Bool
    var permissions: [String]
    var origins: [String]

    init(
        extensionID: String,
        profileID: String,
        sourceContext: ChromeMV3PermissionsAPIRequestSourceContext,
        userGestureModeled: Bool = false,
        extensionModuleEnabled: Bool = true,
        permissions: [String] = [],
        origins: [String] = []
    ) {
        self.extensionID = extensionID.isEmpty
            ? "unknown-extension"
            : extensionID
        self.profileID = profileID.isEmpty ? "unknown-profile" : profileID
        self.sourceContext = sourceContext
        self.userGestureModeled = userGestureModeled
        self.extensionModuleEnabled = extensionModuleEnabled
        self.permissions = Self.uniqueSortedTrimmed(permissions)
        self.origins = Self.uniqueSortedTrimmed(origins)
    }

    var normalized: ChromeMV3PermissionsAPINormalizedRequest {
        ChromeMV3PermissionsAPINormalizedRequest(input: self)
    }

    private static func uniqueSortedTrimmed(_ values: [String]) -> [String] {
        Array(Set(values.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        })).sorted()
    }
}

struct ChromeMV3PermissionsAPINormalizedRequest:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var sourceContext: ChromeMV3PermissionsAPIRequestSourceContext
    var userGestureModeled: Bool
    var extensionModuleEnabled: Bool
    var permissions: [String]
    var origins: [String]
    var inputIssues: [ChromeMV3PermissionsAPIInputIssue]
    var diagnostics: [String]

    init(input: ChromeMV3PermissionsAPIRequestInput) {
        var permissions: [String] = []
        var origins: [String] = []
        var issues: [ChromeMV3PermissionsAPIInputIssue] = []

        for permission in input.permissions {
            guard permission.isEmpty == false else {
                issues.append(
                    ChromeMV3PermissionsAPIInputIssue(
                        kind: .emptyPermission,
                        value: permission,
                        diagnostics: ["Empty API permission was ignored."]
                    )
                )
                continue
            }
            if Self.looksLikeOrigin(permission) {
                issues.append(
                    ChromeMV3PermissionsAPIInputIssue(
                        kind: .originPatternInPermissionsArray,
                        value: permission,
                        diagnostics: [
                            "Host permissions must be supplied in origins, not permissions.",
                        ]
                    )
                )
            } else {
                permissions.append(permission)
            }
        }

        for origin in input.origins {
            guard origin.isEmpty == false else {
                issues.append(
                    ChromeMV3PermissionsAPIInputIssue(
                        kind: .emptyOrigin,
                        value: origin,
                        diagnostics: ["Empty origin was ignored."]
                    )
                )
                continue
            }
            let pattern = ChromeMV3HostMatchPattern(origin)
            switch pattern.status {
            case .valid:
                origins.append(origin)
            case .invalid:
                issues.append(
                    ChromeMV3PermissionsAPIInputIssue(
                        kind: .invalidOriginPattern,
                        value: origin,
                        diagnostics: pattern.diagnostics
                    )
                )
                origins.append(origin)
            case .unsupportedNeedsVerification:
                issues.append(
                    ChromeMV3PermissionsAPIInputIssue(
                        kind: .unsupportedOriginPattern,
                        value: origin,
                        diagnostics: pattern.diagnostics
                    )
                )
                origins.append(origin)
            }
        }

        self.extensionID = input.extensionID
        self.profileID = input.profileID
        self.sourceContext = input.sourceContext
        self.userGestureModeled = input.userGestureModeled
        self.extensionModuleEnabled = input.extensionModuleEnabled
        self.permissions = Self.uniqueSorted(permissions)
        self.origins = Self.uniqueSorted(origins)
        self.inputIssues = issues.sorted {
            if $0.kind != $1.kind {
                return $0.kind < $1.kind
            }
            return $0.value < $1.value
        }
        self.diagnostics = Self.uniqueSorted(
            issues.flatMap(\.diagnostics)
                + [
                    "chrome.permissions input normalized for a non-executing API contract.",
                    "Host permission paths are recorded but ignored for permission decisions.",
                ]
        )
    }

    private static func looksLikeOrigin(_ value: String) -> Bool {
        value == "<all_urls>" || value.contains("://")
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { $0.isEmpty == false })).sorted()
    }
}

struct ChromeMV3PermissionsAPIContainsResult:
    Codable,
    Equatable,
    Sendable
{
    var input: ChromeMV3PermissionsAPINormalizedRequest
    var wouldReturn: Bool
    var runtimeImplementedNow: Bool
    var permissionDecisions: [ChromeMV3APIPermissionDecision]
    var originDecisions: [ChromeMV3HostAccessDecision]
    var unsupportedPermissions: [String]
    var deferredPermissions: [String]
    var blockedDiagnostics: [String]
    var diagnostics: [String]
}

struct ChromeMV3PermissionsAPIGetAllResult:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var permissions: [String]
    var origins: [String]
    var excludedDeniedOrRevokedPermissions: [String]
    var excludedUnsupportedPermissions: [String]
    var excludedDeferredPermissions: [String]
    var optionalGrantedPermissions: [String]
    var optionalGrantedOrigins: [String]
    var runtimeImplementedNow: Bool
    var diagnostics: [String]
}

enum ChromeMV3PermissionsAPIRequestClassification:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case alreadyGranted
    case deferredPermission
    case deniedByPolicy
    case disabledModule
    case invalidInput
    case missingUserGesture
    case notDeclaredOptional
    case requestableOptionalOrigin
    case requestableOptionalPermission
    case unsupportedPermission

    static func < (
        lhs: ChromeMV3PermissionsAPIRequestClassification,
        rhs: ChromeMV3PermissionsAPIRequestClassification
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3PermissionsAPIRequestItemDecision:
    Codable,
    Equatable,
    Sendable
{
    var kind: ChromeMV3PermissionsAPIRequestedItemKind
    var value: String
    var classification: ChromeMV3PermissionsAPIRequestClassification
    var alreadyGranted: Bool
    var declaredOptional: Bool
    var optionalDeclarationMatched: [String]
    var unsupported: Bool
    var deferred: Bool
    var deniedByPolicy: Bool
    var revokedInStore: Bool
    var missingUserGesture: Bool
    var wouldRequireProductUI: Bool
    var wouldGrantIfUserAccepted: Bool
    var diagnostics: [String]
}

struct ChromeMV3PermissionsAPIRequestResult:
    Codable,
    Equatable,
    Sendable
{
    var input: ChromeMV3PermissionsAPINormalizedRequest
    var itemDecisions: [ChromeMV3PermissionsAPIRequestItemDecision]
    var wouldRequirePrompt: Bool
    var wouldBeAllowedByModel: Bool
    var wouldBeDeniedByModel: Bool
    var wouldGrantIfUserAccepted: Bool
    var canPromptUserNow: Bool
    var canDispatchPermissionEventNow: Bool
    var runtimeImplementedNow: Bool
    var eventPayloadIfAccepted: ChromeMV3PermissionsAPIEventPayload?
    var diagnostics: [String]
}

enum ChromeMV3PermissionsAPIRemoveClassification:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case disabledModule
    case invalidInput
    case notGranted
    case removedOptionalOrigin
    case removedOptionalPermission
    case requiredManifestPermission
    case unsupportedOrDeferred

    static func < (
        lhs: ChromeMV3PermissionsAPIRemoveClassification,
        rhs: ChromeMV3PermissionsAPIRemoveClassification
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3PermissionsAPIRemoveItemDecision:
    Codable,
    Equatable,
    Sendable
{
    var kind: ChromeMV3PermissionsAPIRequestedItemKind
    var value: String
    var classification: ChromeMV3PermissionsAPIRemoveClassification
    var removable: Bool
    var requiredManifestPermission: Bool
    var grantedOptional: Bool
    var diagnostics: [String]
}

struct ChromeMV3PermissionsAPIRemoveResult:
    Codable,
    Equatable,
    Sendable
{
    var input: ChromeMV3PermissionsAPINormalizedRequest
    var itemDecisions: [ChromeMV3PermissionsAPIRemoveItemDecision]
    var wouldReturn: Bool
    var wouldRevokeModeledPermissions: Bool
    var wouldExpireActiveTabGrants: Bool
    var expiredActiveTabGrantIDs: [String]
    var updatedPermissionStoreSummary:
        ChromeMV3PermissionDecisionStoreSnapshotSummary?
    var updatedActiveTabStoreSummary:
        ChromeMV3ActiveTabGrantStoreSnapshotSummary?
    var canDispatchPermissionEventNow: Bool
    var runtimeImplementedNow: Bool
    var eventPayloadIfApplied: ChromeMV3PermissionsAPIEventPayload?
    var diagnostics: [String]
}

struct ChromeMV3PermissionsAPIRemoveApplication:
    Codable,
    Equatable,
    Sendable
{
    var result: ChromeMV3PermissionsAPIRemoveResult
    var permissionStore: ChromeMV3PermissionDecisionStore
    var activeTabStore: ChromeMV3ActiveTabGrantStore
}

enum ChromeMV3PermissionsAPIEventKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case onAdded
    case onRemoved

    static func < (
        lhs: ChromeMV3PermissionsAPIEventKind,
        rhs: ChromeMV3PermissionsAPIEventKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PermissionsAPIEventSource:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case extensionDisable
    case profileClose
    case removeCall
    case requestAccepted
    case testFixture

    static func < (
        lhs: ChromeMV3PermissionsAPIEventSource,
        rhs: ChromeMV3PermissionsAPIEventSource
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3PermissionsAPIEventPayload:
    Codable,
    Equatable,
    Sendable
{
    var eventKind: ChromeMV3PermissionsAPIEventKind
    var source: ChromeMV3PermissionsAPIEventSource
    var extensionID: String
    var profileID: String
    var permissions: [String]
    var origins: [String]
    var wouldDispatchNow: Bool
    var listenerRegistrationRequired: Bool
    var serviceWorkerWakeRequired: Bool
    var canRegisterListenersNow: Bool
    var canWakeServiceWorkerNow: Bool
    var runtimeImplementedNow: Bool
    var blockers: [String]
    var serviceWorkerWakePreflight:
        ChromeMV3ServiceWorkerWakePreflight? = nil
}

struct ChromeMV3PermissionsAPIContractSummary:
    Codable,
    Equatable,
    Sendable
{
    var containsModeled: Bool
    var getAllModeled: Bool
    var requestModeled: Bool
    var removeModeled: Bool
    var onAddedModeled: Bool
    var onRemovedModeled: Bool
    var optionalPermissions: [String]
    var optionalOrigins: [String]
    var grantedOptionalPermissions: [String]
    var grantedOptionalOrigins: [String]
    var canPromptUserNow: Bool
    var canDispatchPermissionEventNow: Bool
    var canRegisterListenersNow: Bool
    var canWakeServiceWorkerNow: Bool
    var canDispatchMessagesNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var serviceWorkerLifecycleReportSummary:
        ChromeMV3ServiceWorkerLifecycleReportSummary? = nil
}

struct ChromeMV3PasswordManagerPermissionAPIReadiness:
    Codable,
    Equatable,
    Sendable
{
    var hostPermissionsAlreadyDeclaredOrOptional: [String]
    var containsWouldReturnForLoginOrigin: Bool
    var requestWouldRequireProductUI: Bool
    var actionPopupUserGestureCouldRequestPermissionInFuture: Bool
    var removeWouldRevokeAccessAndExpireActiveTabGrants: Bool
    var onAddedEventNotDispatchable: Bool
    var onRemovedEventNotDispatchable: Bool
    var storageRuntimeBlockerRemains: Bool
    var runtimeMessagingBlockerRemains: Bool
    var nativeMessagingBlockerRemains: Bool
    var passwordManagerPermissionAPIReady: Bool
    var blockers: [String]
}

struct ChromeMV3PermissionsAPIContractReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var containsModeled: Bool
    var getAllModeled: Bool
    var requestModeled: Bool
    var removeModeled: Bool
    var onAddedModeled: Bool
    var onRemovedModeled: Bool
    var canPromptUserNow: Bool
    var canDispatchPermissionEventNow: Bool
    var canRegisterListenersNow: Bool
    var canWakeServiceWorkerNow: Bool
    var canDispatchMessagesNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var passwordManagerPermissionAPIReady: Bool
    var serviceWorkerLifecycleReportSummary:
        ChromeMV3ServiceWorkerLifecycleReportSummary? = nil
}

struct ChromeMV3PermissionsAPIContractReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var candidateID: String
    var extensionID: String
    var profileID: String
    var permissionStoreSummary:
        ChromeMV3PermissionDecisionStoreSnapshotSummary
    var activeTabStoreSummary:
        ChromeMV3ActiveTabGrantStoreSnapshotSummary
    var contractSummary: ChromeMV3PermissionsAPIContractSummary
    var containsContractCoverage: [ChromeMV3PermissionsAPIContainsResult]
    var getAllContractCoverage: ChromeMV3PermissionsAPIGetAllResult
    var requestContractCoverage: [ChromeMV3PermissionsAPIRequestResult]
    var removeContractCoverage: [ChromeMV3PermissionsAPIRemoveResult]
    var onAddedEventContractCoverage: [ChromeMV3PermissionsAPIEventPayload]
    var onRemovedEventContractCoverage: [ChromeMV3PermissionsAPIEventPayload]
    var optionalPermissionState:
        ChromeMV3PermissionDecisionStoreSnapshotSummary
    var activeTabSideEffectDiagnostics: [String]
    var routeListenerReadinessImpact: [String]
    var passwordManagerPermissionAPIReadiness:
        ChromeMV3PasswordManagerPermissionAPIReadiness
    var canPromptUserNow: Bool
    var canDispatchPermissionEventNow: Bool
    var canRegisterListenersNow: Bool
    var canWakeServiceWorkerNow: Bool
    var canDispatchMessagesNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var serviceWorkerLifecycleReportSummary:
        ChromeMV3ServiceWorkerLifecycleReportSummary? = nil
    var documentationSources: [ChromeMV3ManifestRewritePreviewSource]
    var diagnostics: [String]

    var summary: ChromeMV3PermissionsAPIContractReportSummary {
        ChromeMV3PermissionsAPIContractReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            containsModeled: true,
            getAllModeled: true,
            requestModeled: true,
            removeModeled: true,
            onAddedModeled: true,
            onRemovedModeled: true,
            canPromptUserNow: false,
            canDispatchPermissionEventNow: false,
            canRegisterListenersNow: false,
            canWakeServiceWorkerNow: false,
            canDispatchMessagesNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            passwordManagerPermissionAPIReady: false,
            serviceWorkerLifecycleReportSummary:
                serviceWorkerLifecycleReportSummary
        )
    }
}

enum ChromeMV3PermissionsAPIContractEvaluator {
    static func contains(
        input: ChromeMV3PermissionsAPIRequestInput,
        permissionStore: ChromeMV3PermissionDecisionStore,
        activeTabStore: ChromeMV3ActiveTabGrantStore? = nil
    ) -> ChromeMV3PermissionsAPIContainsResult {
        let normalized = input.normalized
        let broker = permissionStore.permissionBroker(
            activeTabStore: activeTabStore
        )
        let permissionDecisions = normalized.permissions.map {
            broker.apiPermissionDecision($0)
        }.sorted { $0.permission < $1.permission }
        let originDecisions = normalized.origins.map {
            broker.hostAccessDecision(origin: $0, tabID: nil)
        }.sorted { ($0.origin ?? $0.url ?? "") < ($1.origin ?? $1.url ?? "") }
        let issueBlocked = normalized.inputIssues.isEmpty == false
        let storeBlocked = permissionDecisions.contains {
            $0.hasPermission == false
        } || originDecisions.contains { $0.hasHostAccess == false }
        let disabled = normalized.extensionModuleEnabled == false
        let wouldReturn = disabled == false
            && issueBlocked == false
            && storeBlocked == false
        let unsupported = permissionDecisions
            .filter(\.unsupported)
            .map(\.permission)
        let deferred = permissionDecisions
            .filter(\.deferred)
            .map(\.permission)
        let blocked = permissionDecisions
            .filter { $0.hasPermission == false }
            .flatMap(\.diagnostics)
            + originDecisions
            .filter { $0.hasHostAccess == false }
            .flatMap(\.diagnostics)
            + normalized.inputIssues.flatMap(\.diagnostics)
            + (disabled ? ["Extension module is disabled."] : [])

        return ChromeMV3PermissionsAPIContainsResult(
            input: normalized,
            wouldReturn: wouldReturn,
            runtimeImplementedNow: false,
            permissionDecisions: permissionDecisions,
            originDecisions: originDecisions,
            unsupportedPermissions: Array(Set(unsupported)).sorted(),
            deferredPermissions: Array(Set(deferred)).sorted(),
            blockedDiagnostics: Array(Set(blocked)).sorted(),
            diagnostics: Array(Set(
                normalized.diagnostics
                    + [
                        "chrome.permissions.contains is modeled only; no callback or Promise is executed.",
                        "runtimeImplementedNow remains false.",
                    ]
                    + blocked
            )).sorted()
        )
    }

    static func getAll(
        permissionStore: ChromeMV3PermissionDecisionStore
    ) -> ChromeMV3PermissionsAPIGetAllResult {
        let snapshot = permissionStore.exportSnapshot()
        let deniedRevoked = Set(
            snapshot.deniedPermissions + snapshot.revokedPermissions
        )
        let unsupported = Set(snapshot.unsupportedPermissions)
        let deferred = Set(snapshot.deferredPermissions)
        let excluded = deniedRevoked.union(unsupported).union(deferred)
        let permissions = Array(Set(
            snapshot.declaredAPIPermissions
                + snapshot.grantedOptionalAPIPermissions
        )).filter { excluded.contains($0) == false }.sorted()
        let origins = Array(Set(
            snapshot.declaredHostPermissions
                + snapshot.grantedOptionalHostPermissions
        )).filter { excluded.contains($0) == false }.sorted()

        return ChromeMV3PermissionsAPIGetAllResult(
            extensionID: snapshot.extensionID,
            profileID: snapshot.profileID,
            permissions: permissions,
            origins: origins,
            excludedDeniedOrRevokedPermissions:
                Array(deniedRevoked).sorted(),
            excludedUnsupportedPermissions:
                Array(unsupported).sorted(),
            excludedDeferredPermissions:
                Array(deferred).sorted(),
            optionalGrantedPermissions:
                snapshot.grantedOptionalAPIPermissions,
            optionalGrantedOrigins:
                snapshot.grantedOptionalHostPermissions,
            runtimeImplementedNow: false,
            diagnostics: [
                "chrome.permissions.getAll is modeled from the permission decision store.",
                "Denied, revoked, unsupported, and deferred entries are excluded from the modeled current grant set.",
                "runtimeImplementedNow remains false.",
            ]
        )
    }

    static func request(
        input: ChromeMV3PermissionsAPIRequestInput,
        permissionStore: ChromeMV3PermissionDecisionStore,
        activeTabStore: ChromeMV3ActiveTabGrantStore? = nil
    ) -> ChromeMV3PermissionsAPIRequestResult {
        let normalized = input.normalized
        let broker = permissionStore.permissionBroker(
            activeTabStore: activeTabStore
        )
        let permissionItems = normalized.permissions.map {
            requestDecision(
                permission: $0,
                normalized: normalized,
                broker: broker,
                snapshot: permissionStore.snapshot
            )
        }
        let originItems = normalized.origins.map {
            requestDecision(
                origin: $0,
                normalized: normalized,
                broker: broker,
                snapshot: permissionStore.snapshot
            )
        }
        let invalidItems = normalized.inputIssues.map {
            ChromeMV3PermissionsAPIRequestItemDecision(
                kind: issueKind($0),
                value: $0.value,
                classification: .invalidInput,
                alreadyGranted: false,
                declaredOptional: false,
                optionalDeclarationMatched: [],
                unsupported: $0.kind == .unsupportedOriginPattern,
                deferred: false,
                deniedByPolicy: false,
                revokedInStore: false,
                missingUserGesture: false,
                wouldRequireProductUI: false,
                wouldGrantIfUserAccepted: false,
                diagnostics: $0.diagnostics
            )
        }
        let decisions = (permissionItems + originItems + invalidItems)
            .sorted(by: itemSort)
        let wouldRequirePrompt = decisions.contains {
            $0.wouldRequireProductUI
        }
        let denied = decisions.contains {
            switch $0.classification {
            case .alreadyGranted, .requestableOptionalOrigin,
                 .requestableOptionalPermission:
                return false
            case .deferredPermission, .deniedByPolicy, .disabledModule,
                 .invalidInput, .missingUserGesture, .notDeclaredOptional,
                 .unsupportedPermission:
                return true
            }
        }
        let grantable = decisions.isEmpty == false
            && decisions.allSatisfy {
                $0.alreadyGranted || $0.wouldGrantIfUserAccepted
            }
        let event = addedEventPayload(
            requestInput: normalized,
            itemDecisions: decisions,
            source: .requestAccepted
        )

        return ChromeMV3PermissionsAPIRequestResult(
            input: normalized,
            itemDecisions: decisions,
            wouldRequirePrompt: wouldRequirePrompt,
            wouldBeAllowedByModel:
                decisions.isEmpty == false
                    && decisions.allSatisfy(\.alreadyGranted),
            wouldBeDeniedByModel: denied,
            wouldGrantIfUserAccepted: grantable,
            canPromptUserNow: false,
            canDispatchPermissionEventNow: false,
            runtimeImplementedNow: false,
            eventPayloadIfAccepted: event,
            diagnostics: Array(Set(
                normalized.diagnostics
                    + decisions.flatMap(\.diagnostics)
                    + [
                        "chrome.permissions.request is modeled only; no product permission UI is shown.",
                        "A real user gesture is required by Chrome before future prompting.",
                        "canPromptUserNow remains false.",
                        "canDispatchPermissionEventNow remains false.",
                        "runtimeImplementedNow remains false.",
                    ]
            )).sorted()
        )
    }

    static func remove(
        input: ChromeMV3PermissionsAPIRequestInput,
        permissionStore: ChromeMV3PermissionDecisionStore,
        activeTabStore: ChromeMV3ActiveTabGrantStore? = nil
    ) -> ChromeMV3PermissionsAPIRemoveResult {
        applyingRemove(
            input: input,
            permissionStore: permissionStore,
            activeTabStore: activeTabStore
                ?? ChromeMV3ActiveTabGrantStore.empty(
                    extensionID: permissionStore.snapshot.extensionID,
                    profileID: permissionStore.snapshot.profileID
                ),
            apply: false,
            sequence: 1
        ).result
    }

    static func applyingRemove(
        input: ChromeMV3PermissionsAPIRequestInput,
        permissionStore: ChromeMV3PermissionDecisionStore,
        activeTabStore: ChromeMV3ActiveTabGrantStore,
        apply: Bool = true,
        sequence: Int
    ) -> ChromeMV3PermissionsAPIRemoveApplication {
        let normalized = input.normalized
        let broker = permissionStore.permissionBroker(
            activeTabStore: activeTabStore
        )
        let permissionItems = normalized.permissions.map {
            removeDecision(
                permission: $0,
                normalized: normalized,
                broker: broker,
                snapshot: permissionStore.snapshot
            )
        }
        let originItems = normalized.origins.map {
            removeDecision(
                origin: $0,
                normalized: normalized,
                broker: broker,
                snapshot: permissionStore.snapshot
            )
        }
        let invalidItems = normalized.inputIssues.map {
            ChromeMV3PermissionsAPIRemoveItemDecision(
                kind: issueKind($0),
                value: $0.value,
                classification: .invalidInput,
                removable: false,
                requiredManifestPermission: false,
                grantedOptional: false,
                diagnostics: $0.diagnostics
            )
        }
        let decisions = (permissionItems + originItems + invalidItems)
            .sorted(by: removeItemSort)
        let removableValues = decisions.filter(\.removable).map(\.value)
        let nextPermissionStore = apply
            ? removableValues.enumerated().reduce(permissionStore) {
                store, element in
                store.applyingPermissionsAPIRemove(
                    element.element,
                    sequence: sequence + element.offset
                )
            }
            : permissionStore
        let expiry: (
            store: ChromeMV3ActiveTabGrantStore,
            expired: [ChromeMV3ActiveTabGrantRecord],
            retained: [ChromeMV3ActiveTabGrantRecord]
        )
        if apply && removableValues.isEmpty == false {
            expiry = activeTabStore.expiringForPermissionRevoke(
                extensionID: normalized.extensionID,
                profileID: normalized.profileID,
                permission: removableValues.sorted().joined(separator: ","),
                sequence: sequence + removableValues.count
            )
        } else {
            expiry = (
                store: activeTabStore,
                expired: [],
                retained:
                    activeTabStore.snapshot.grantRecords.filter {
                        $0.grant.active
                    }
            )
        }
        let event = removedEventPayload(
            requestInput: normalized,
            itemDecisions: decisions,
            source: .removeCall
        )
        let wouldReturn = decisions.isEmpty == false
            && decisions.allSatisfy(\.removable)
        let expiredIDs = expiry.expired.map(\.id).sorted()
        let updatedPermissionSummary = apply
            ? nextPermissionStore.exportSnapshot().summary
            : nil
        let updatedActiveTabSummary = apply
            ? expiry.store.exportSnapshot().summary
            : nil
        let removeDiagnostics = Array(Set(
            normalized.diagnostics
                + decisions.flatMap(\.diagnostics)
                + expiry.expired.flatMap(\.grant.diagnostics)
                + [
                    "chrome.permissions.remove is modeled only; no callback or Promise is executed.",
                    "Required manifest permissions are not removable by this contract.",
                    "canDispatchPermissionEventNow remains false.",
                    "runtimeImplementedNow remains false.",
                ]
        )).sorted()
        let result = ChromeMV3PermissionsAPIRemoveResult(
            input: normalized,
            itemDecisions: decisions,
            wouldReturn: wouldReturn,
            wouldRevokeModeledPermissions: removableValues.isEmpty == false,
            wouldExpireActiveTabGrants: expiry.expired.isEmpty == false,
            expiredActiveTabGrantIDs: expiredIDs,
            updatedPermissionStoreSummary: updatedPermissionSummary,
            updatedActiveTabStoreSummary: updatedActiveTabSummary,
            canDispatchPermissionEventNow: false,
            runtimeImplementedNow: false,
            eventPayloadIfApplied: event,
            diagnostics: removeDiagnostics
        )
        return ChromeMV3PermissionsAPIRemoveApplication(
            result: result,
            permissionStore: nextPermissionStore,
            activeTabStore: apply ? expiry.store : activeTabStore
        )
    }

    static func addedEventPayload(
        requestInput input: ChromeMV3PermissionsAPINormalizedRequest,
        itemDecisions: [ChromeMV3PermissionsAPIRequestItemDecision],
        source: ChromeMV3PermissionsAPIEventSource
    ) -> ChromeMV3PermissionsAPIEventPayload {
        eventPayload(
            kind: .onAdded,
            source: source,
            extensionID: input.extensionID,
            profileID: input.profileID,
            permissions: itemDecisions.filter {
                $0.kind == .apiPermission && $0.wouldGrantIfUserAccepted
            }.map(\.value),
            origins: itemDecisions.filter {
                $0.kind == .origin && $0.wouldGrantIfUserAccepted
            }.map(\.value)
        )
    }

    static func removedEventPayload(
        requestInput input: ChromeMV3PermissionsAPINormalizedRequest,
        itemDecisions: [ChromeMV3PermissionsAPIRemoveItemDecision],
        source: ChromeMV3PermissionsAPIEventSource
    ) -> ChromeMV3PermissionsAPIEventPayload {
        eventPayload(
            kind: .onRemoved,
            source: source,
            extensionID: input.extensionID,
            profileID: input.profileID,
            permissions: itemDecisions.filter {
                $0.kind == .apiPermission && $0.removable
            }.map(\.value),
            origins: itemDecisions.filter {
                $0.kind == .origin && $0.removable
            }.map(\.value)
        )
    }

    static func eventPayload(
        kind: ChromeMV3PermissionsAPIEventKind,
        source: ChromeMV3PermissionsAPIEventSource,
        extensionID: String,
        profileID: String,
        permissions: [String],
        origins: [String]
    ) -> ChromeMV3PermissionsAPIEventPayload {
        ChromeMV3PermissionsAPIEventPayload(
            eventKind: kind,
            source: source,
            extensionID: extensionID.isEmpty
                ? "unknown-extension"
                : extensionID,
            profileID: profileID.isEmpty ? "unknown-profile" : profileID,
            permissions: uniqueSorted(permissions),
            origins: uniqueSorted(origins),
            wouldDispatchNow: false,
            listenerRegistrationRequired: true,
            serviceWorkerWakeRequired: false,
            canRegisterListenersNow: false,
            canWakeServiceWorkerNow: false,
            runtimeImplementedNow: false,
            blockers: [
                "Permission event payload is modeled only.",
                "No chrome.permissions listener is registered.",
                "No permission event is dispatched.",
                "Service-worker wake is not requested by this permission implementation layer.",
                "No extension context is created or loaded.",
            ],
            serviceWorkerWakePreflight:
                ChromeMV3ServiceWorkerWakePreflight.evaluate(
                    request:
                        ChromeMV3ServiceWorkerWakeRequest
                        .permissionsChanged(
                            extensionID: extensionID,
                            profileID: profileID,
                            eventKind: kind
                        )
                )
        )
    }

    private static func requestDecision(
        permission: String,
        normalized: ChromeMV3PermissionsAPINormalizedRequest,
        broker: ChromeMV3PermissionBroker,
        snapshot: ChromeMV3PermissionDecisionStoreSnapshot
    ) -> ChromeMV3PermissionsAPIRequestItemDecision {
        let decision = broker.apiPermissionDecision(permission)
        let disabled = normalized.extensionModuleEnabled == false
        let denied = snapshot.deniedPermissions.contains(permission)
        let revoked = snapshot.revokedPermissions.contains(permission)
        let optional = snapshot.optionalAPIPermissions.contains(permission)
        let classification: ChromeMV3PermissionsAPIRequestClassification
        let missingGesture: Bool
        let requiresUI: Bool
        let wouldGrant: Bool

        if disabled {
            classification = .disabledModule
            missingGesture = false
            requiresUI = false
            wouldGrant = false
        } else if decision.unsupported {
            classification = .unsupportedPermission
            missingGesture = false
            requiresUI = false
            wouldGrant = false
        } else if decision.deferred {
            classification = .deferredPermission
            missingGesture = false
            requiresUI = false
            wouldGrant = false
        } else if denied {
            classification = .deniedByPolicy
            missingGesture = false
            requiresUI = false
            wouldGrant = false
        } else if decision.hasPermission {
            classification = .alreadyGranted
            missingGesture = false
            requiresUI = false
            wouldGrant = false
        } else if optional {
            missingGesture = normalized.userGestureModeled == false
            classification = missingGesture
                ? .missingUserGesture
                : .requestableOptionalPermission
            requiresUI = missingGesture == false
            wouldGrant = missingGesture == false
        } else {
            classification = .notDeclaredOptional
            missingGesture = false
            requiresUI = false
            wouldGrant = false
        }

        return ChromeMV3PermissionsAPIRequestItemDecision(
            kind: .apiPermission,
            value: permission,
            classification: classification,
            alreadyGranted: decision.hasPermission,
            declaredOptional: optional,
            optionalDeclarationMatched: optional ? [permission] : [],
            unsupported: decision.unsupported,
            deferred: decision.deferred,
            deniedByPolicy: denied,
            revokedInStore: revoked,
            missingUserGesture: missingGesture,
            wouldRequireProductUI: requiresUI,
            wouldGrantIfUserAccepted: wouldGrant,
            diagnostics: Array(Set(
                decision.diagnostics
                    + [
                        "chrome.permissions.request item classified as \(classification.rawValue).",
                    ]
                    + (revoked
                        ? [
                            "Permission is revoked in the modeled store and would need an explicit future grant operation.",
                        ]
                        : [])
                    + (requiresUI
                        ? [
                            "Product permission UI would be required before a real grant.",
                        ]
                        : [])
            )).sorted()
        )
    }

    private static func requestDecision(
        origin: String,
        normalized: ChromeMV3PermissionsAPINormalizedRequest,
        broker: ChromeMV3PermissionBroker,
        snapshot: ChromeMV3PermissionDecisionStoreSnapshot
    ) -> ChromeMV3PermissionsAPIRequestItemDecision {
        let decision = broker.hostAccessDecision(origin: origin, tabID: nil)
        let disabled = normalized.extensionModuleEnabled == false
        let unsupported = ChromeMV3HostMatchPattern(origin).isUnsupported
        let denied = permissionList(snapshot.deniedPermissions, covers: origin)
        let revoked = permissionList(snapshot.revokedPermissions, covers: origin)
        let optionalMatches = optionalHostDeclarations(
            in: snapshot,
            covering: origin
        )
        let classification: ChromeMV3PermissionsAPIRequestClassification
        let missingGesture: Bool
        let requiresUI: Bool
        let wouldGrant: Bool

        if disabled {
            classification = .disabledModule
            missingGesture = false
            requiresUI = false
            wouldGrant = false
        } else if unsupported {
            classification = .unsupportedPermission
            missingGesture = false
            requiresUI = false
            wouldGrant = false
        } else if denied {
            classification = .deniedByPolicy
            missingGesture = false
            requiresUI = false
            wouldGrant = false
        } else if decision.hasHostAccess {
            classification = .alreadyGranted
            missingGesture = false
            requiresUI = false
            wouldGrant = false
        } else if optionalMatches.isEmpty == false {
            missingGesture = normalized.userGestureModeled == false
            classification = missingGesture
                ? .missingUserGesture
                : .requestableOptionalOrigin
            requiresUI = missingGesture == false
            wouldGrant = missingGesture == false
        } else {
            classification = .notDeclaredOptional
            missingGesture = false
            requiresUI = false
            wouldGrant = false
        }

        return ChromeMV3PermissionsAPIRequestItemDecision(
            kind: .origin,
            value: origin,
            classification: classification,
            alreadyGranted: decision.hasHostAccess,
            declaredOptional: optionalMatches.isEmpty == false,
            optionalDeclarationMatched: optionalMatches,
            unsupported: unsupported,
            deferred: false,
            deniedByPolicy: denied,
            revokedInStore: revoked,
            missingUserGesture: missingGesture,
            wouldRequireProductUI: requiresUI,
            wouldGrantIfUserAccepted: wouldGrant,
            diagnostics: Array(Set(
                decision.diagnostics
                    + [
                        "chrome.permissions.request origin classified as \(classification.rawValue).",
                    ]
                    + (requiresUI
                        ? [
                            "Product permission UI would be required before a real optional origin grant.",
                        ]
                        : [])
            )).sorted()
        )
    }

    private static func removeDecision(
        permission: String,
        normalized: ChromeMV3PermissionsAPINormalizedRequest,
        broker: ChromeMV3PermissionBroker,
        snapshot: ChromeMV3PermissionDecisionStoreSnapshot
    ) -> ChromeMV3PermissionsAPIRemoveItemDecision {
        let decision = broker.apiPermissionDecision(permission)
        let required = snapshot.declaredAPIPermissions.contains(permission)
        let grantedOptional =
            snapshot.grantedOptionalAPIPermissions.contains(permission)
        let classification: ChromeMV3PermissionsAPIRemoveClassification
        let removable: Bool
        if normalized.extensionModuleEnabled == false {
            classification = .disabledModule
            removable = false
        } else if required {
            classification = .requiredManifestPermission
            removable = false
        } else if decision.unsupported || decision.deferred {
            classification = .unsupportedOrDeferred
            removable = false
        } else if grantedOptional {
            classification = .removedOptionalPermission
            removable = true
        } else {
            classification = .notGranted
            removable = false
        }

        return ChromeMV3PermissionsAPIRemoveItemDecision(
            kind: .apiPermission,
            value: permission,
            classification: classification,
            removable: removable,
            requiredManifestPermission: required,
            grantedOptional: grantedOptional,
            diagnostics: Array(Set(
                decision.diagnostics
                    + [
                        "chrome.permissions.remove item classified as \(classification.rawValue).",
                    ]
            )).sorted()
        )
    }

    private static func removeDecision(
        origin: String,
        normalized: ChromeMV3PermissionsAPINormalizedRequest,
        broker: ChromeMV3PermissionBroker,
        snapshot: ChromeMV3PermissionDecisionStoreSnapshot
    ) -> ChromeMV3PermissionsAPIRemoveItemDecision {
        let decision = broker.hostAccessDecision(origin: origin, tabID: nil)
        let required = hostDeclarations(
            snapshot.declaredHostPermissions,
            covering: origin
        ).isEmpty == false
        let grantedOptional = hostDeclarations(
            snapshot.grantedOptionalHostPermissions,
            covering: origin
        ).isEmpty == false
        let classification: ChromeMV3PermissionsAPIRemoveClassification
        let removable: Bool
        if normalized.extensionModuleEnabled == false {
            classification = .disabledModule
            removable = false
        } else if required {
            classification = .requiredManifestPermission
            removable = false
        } else if ChromeMV3HostMatchPattern(origin).isUnsupported {
            classification = .unsupportedOrDeferred
            removable = false
        } else if grantedOptional {
            classification = .removedOptionalOrigin
            removable = true
        } else {
            classification = .notGranted
            removable = false
        }

        return ChromeMV3PermissionsAPIRemoveItemDecision(
            kind: .origin,
            value: origin,
            classification: classification,
            removable: removable,
            requiredManifestPermission: required,
            grantedOptional: grantedOptional,
            diagnostics: Array(Set(
                decision.diagnostics
                    + [
                        "chrome.permissions.remove origin classified as \(classification.rawValue).",
                    ]
            )).sorted()
        )
    }

    private static func optionalHostDeclarations(
        in snapshot: ChromeMV3PermissionDecisionStoreSnapshot,
        covering origin: String
    ) -> [String] {
        hostDeclarations(snapshot.optionalHostPermissions, covering: origin)
    }

    private static func hostDeclarations(
        _ declarations: [String],
        covering origin: String
    ) -> [String] {
        declarations.filter {
            $0 == origin || ChromeMV3HostMatchPattern($0).matches(url: origin)
        }.sorted()
    }

    private static func permissionList(
        _ permissions: [String],
        covers origin: String
    ) -> Bool {
        permissions.contains {
            $0 == origin || ChromeMV3HostMatchPattern($0).matches(url: origin)
        }
    }

    private static func issueKind(
        _ issue: ChromeMV3PermissionsAPIInputIssue
    ) -> ChromeMV3PermissionsAPIRequestedItemKind {
        switch issue.kind {
        case .emptyPermission, .originPatternInPermissionsArray:
            return .apiPermission
        case .emptyOrigin, .invalidOriginPattern, .unsupportedOriginPattern:
            return .origin
        }
    }

    private static func itemSort(
        lhs: ChromeMV3PermissionsAPIRequestItemDecision,
        rhs: ChromeMV3PermissionsAPIRequestItemDecision
    ) -> Bool {
        if lhs.kind != rhs.kind {
            return lhs.kind < rhs.kind
        }
        return lhs.value < rhs.value
    }

    private static func removeItemSort(
        lhs: ChromeMV3PermissionsAPIRemoveItemDecision,
        rhs: ChromeMV3PermissionsAPIRemoveItemDecision
    ) -> Bool {
        if lhs.kind != rhs.kind {
            return lhs.kind < rhs.kind
        }
        return lhs.value < rhs.value
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { $0.isEmpty == false })).sorted()
    }
}

extension ChromeMV3PermissionDecisionStore {
    func applyingPermissionsAPIModeledGrant(
        _ value: String,
        kind: ChromeMV3PermissionsAPIRequestedItemKind,
        sequence: Int
    ) -> ChromeMV3PermissionDecisionStore {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { return self }
        var apiGrants = snapshot.grantedOptionalAPIPermissions
        var originGrants = snapshot.grantedOptionalHostPermissions
        let status: ChromeMV3PermissionBrokerDecisionStatus
        let source: ChromeMV3PermissionBrokerGrantSource
        let diagnostics: [String]

        switch kind {
        case .apiPermission:
            if snapshot.optionalAPIPermissions.contains(normalized) {
                apiGrants.append(normalized)
                status = .allowed
                source = .optionalPermissionModeledGrant
                diagnostics = [
                    "chrome.permissions.request modeled API grant was recorded.",
                ]
            } else {
                status = .blocked
                source = .none
                diagnostics = [
                    "chrome.permissions.request grant was not declared optional.",
                ]
            }
        case .origin:
            let optionalMatches = snapshot.optionalHostPermissions.filter {
                $0 == normalized
                    || ChromeMV3HostMatchPattern($0)
                    .matches(url: normalized)
            }
            if optionalMatches.isEmpty == false {
                originGrants.append(normalized)
                status = .allowed
                source = .optionalHostPermissionModeledGrant
                diagnostics = [
                    "chrome.permissions.request modeled optional origin grant was recorded.",
                ]
            } else {
                status = .blocked
                source = .none
                diagnostics = [
                    "chrome.permissions.request origin grant was not declared optional.",
                ]
            }
        }

        return replacingSnapshot(
            grantedOptionalAPIPermissions: apiGrants,
            grantedOptionalHostPermissions: originGrants,
            deniedPermissions:
                snapshot.deniedPermissions.filter { $0 != normalized },
            revokedPermissions:
                snapshot.revokedPermissions.filter { $0 != normalized },
            record: ChromeMV3ModeledPermissionDecisionRecord(
                extensionID: snapshot.extensionID,
                profileID: snapshot.profileID,
                subjectKind: subjectKind(for: kind),
                value: normalized,
                status: status,
                grantSource: source,
                sequence: sequence,
                diagnostics: diagnostics
            ),
            diagnostics: diagnostics
        )
    }

    func applyingPermissionsAPIRemove(
        _ value: String,
        sequence: Int
    ) -> ChromeMV3PermissionDecisionStore {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { return self }
        let kind = normalized == "<all_urls>" || normalized.contains("://")
            ? ChromeMV3PermissionsAPIRequestedItemKind.origin
            : .apiPermission
        let diagnostics = [
            "chrome.permissions.remove modeled revoke was recorded.",
        ]
        return replacingSnapshot(
            grantedOptionalAPIPermissions:
                snapshot.grantedOptionalAPIPermissions
                .filter { $0 != normalized },
            grantedOptionalHostPermissions:
                snapshot.grantedOptionalHostPermissions
                .filter { $0 != normalized },
            deniedPermissions:
                snapshot.deniedPermissions.filter { $0 != normalized },
            revokedPermissions: snapshot.revokedPermissions + [normalized],
            record: ChromeMV3ModeledPermissionDecisionRecord(
                extensionID: snapshot.extensionID,
                profileID: snapshot.profileID,
                subjectKind: subjectKind(for: kind),
                value: normalized,
                status: .revoked,
                grantSource: .none,
                sequence: sequence,
                diagnostics: diagnostics
            ),
            diagnostics: diagnostics
        )
    }

    private func replacingSnapshot(
        grantedOptionalAPIPermissions: [String],
        grantedOptionalHostPermissions: [String],
        deniedPermissions: [String],
        revokedPermissions: [String],
        record: ChromeMV3ModeledPermissionDecisionRecord,
        diagnostics: [String]
    ) -> ChromeMV3PermissionDecisionStore {
        ChromeMV3PermissionDecisionStore(
            snapshot: ChromeMV3PermissionDecisionStoreSnapshot(
                schemaVersion: snapshot.schemaVersion,
                extensionID: snapshot.extensionID,
                profileID: snapshot.profileID,
                declaredAPIPermissions: snapshot.declaredAPIPermissions,
                declaredHostPermissions: snapshot.declaredHostPermissions,
                optionalAPIPermissions: snapshot.optionalAPIPermissions,
                optionalHostPermissions: snapshot.optionalHostPermissions,
                grantedOptionalAPIPermissions:
                    grantedOptionalAPIPermissions,
                grantedOptionalHostPermissions:
                    grantedOptionalHostPermissions,
                deniedPermissions: deniedPermissions,
                revokedPermissions: revokedPermissions,
                deferredPermissions: snapshot.deferredPermissions,
                unsupportedPermissions: snapshot.unsupportedPermissions,
                decisionRecords: snapshot.decisionRecords + [record],
                diagnostics: snapshot.diagnostics + diagnostics
            )
        )
    }

    private func subjectKind(
        for kind: ChromeMV3PermissionsAPIRequestedItemKind
    ) -> ChromeMV3PermissionDecisionSubjectKind {
        switch kind {
        case .apiPermission:
            return .apiPermission
        case .origin:
            return .hostPermission
        }
    }
}

enum ChromeMV3PermissionsAPIContractReportWriter {
    static let reportFileName = "runtime-permissions-api-contract-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3PermissionsAPIContractReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3PermissionsAPIContractReport {
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

enum ChromeMV3PermissionsAPIContractReportGenerator {
    static func makeSummary(
        prerequisitesReport prerequisites:
            ChromeMV3RuntimeBridgePrerequisitesReport,
        profileID: String = "diagnostic-profile",
        modeledActiveTabGrants: [ChromeMV3ActiveTabGrant] = []
    ) -> ChromeMV3PermissionsAPIContractReportSummary {
        makeReport(
            prerequisitesReport: prerequisites,
            profileID: profileID,
            modeledActiveTabGrants: modeledActiveTabGrants
        ).summary
    }

    static func makeReport(
        prerequisitesReport prerequisites:
            ChromeMV3RuntimeBridgePrerequisitesReport,
        profileID: String = "diagnostic-profile",
        modeledActiveTabGrants: [ChromeMV3ActiveTabGrant] = []
    ) -> ChromeMV3PermissionsAPIContractReport {
        let extensionID = prerequisites.candidateID
        let permissionStore = ChromeMV3PermissionLifecycleReportGenerator
            .permissionStore(
                prerequisites: prerequisites,
                extensionID: extensionID,
                profileID: profileID
            )
        let activeTabStore = ChromeMV3ActiveTabGrantStore.from(
            extensionID: extensionID,
            profileID: profileID,
            grants: modeledActiveTabGrants
        )
        let snapshot = permissionStore.exportSnapshot()
        let activeSnapshot = activeTabStore.exportSnapshot()
        let containsInput = ChromeMV3PermissionsAPIRequestInput(
            extensionID: extensionID,
            profileID: profileID,
            sourceContext: .testFixture,
            userGestureModeled: false,
            permissions: snapshot.declaredAPIPermissions.prefix(1).map { $0 },
            origins:
                (snapshot.declaredHostPermissions.prefix(1).map { $0 }
                    + snapshot.grantedOptionalHostPermissions.prefix(1).map { $0 })
        )
        let optionalPermission = snapshot.optionalAPIPermissions.first
            ?? "tabs"
        let optionalOrigin = snapshot.optionalHostPermissions.first
            ?? "https://optional.example/*"
        let requestInputs = [
            ChromeMV3PermissionsAPIRequestInput(
                extensionID: extensionID,
                profileID: profileID,
                sourceContext: .testFixture,
                userGestureModeled: true,
                permissions:
                    snapshot.declaredAPIPermissions.prefix(1).map { $0 }
            ),
            ChromeMV3PermissionsAPIRequestInput(
                extensionID: extensionID,
                profileID: profileID,
                sourceContext: .actionPopup,
                userGestureModeled: true,
                permissions: [optionalPermission],
                origins: [optionalOrigin]
            ),
            ChromeMV3PermissionsAPIRequestInput(
                extensionID: extensionID,
                profileID: profileID,
                sourceContext: .actionPopup,
                userGestureModeled: false,
                permissions: [optionalPermission]
            ),
            ChromeMV3PermissionsAPIRequestInput(
                extensionID: extensionID,
                profileID: profileID,
                sourceContext: .testFixture,
                userGestureModeled: true,
                permissions:
                    snapshot.unsupportedPermissions
                    + snapshot.deferredPermissions
            ),
        ]
        let removeInputs = [
            ChromeMV3PermissionsAPIRequestInput(
                extensionID: extensionID,
                profileID: profileID,
                sourceContext: .testFixture,
                permissions:
                    snapshot.declaredAPIPermissions.prefix(1).map { $0 }
            ),
            ChromeMV3PermissionsAPIRequestInput(
                extensionID: extensionID,
                profileID: profileID,
                sourceContext: .testFixture,
                permissions:
                    snapshot.grantedOptionalAPIPermissions.prefix(1).map { $0 },
                origins:
                    snapshot.grantedOptionalHostPermissions.prefix(1).map { $0 }
            ),
        ]
        let contains = ChromeMV3PermissionsAPIContractEvaluator.contains(
            input: containsInput,
            permissionStore: permissionStore,
            activeTabStore: activeTabStore
        )
        let getAll = ChromeMV3PermissionsAPIContractEvaluator.getAll(
            permissionStore: permissionStore
        )
        let requests = requestInputs.map {
            ChromeMV3PermissionsAPIContractEvaluator.request(
                input: $0,
                permissionStore: permissionStore,
                activeTabStore: activeTabStore
            )
        }
        let removes = removeInputs.map {
            ChromeMV3PermissionsAPIContractEvaluator.remove(
                input: $0,
                permissionStore: permissionStore,
                activeTabStore: activeTabStore
            )
        }
        let addedEvents = requests.compactMap(\.eventPayloadIfAccepted)
        let removedEvents = removes.compactMap(\.eventPayloadIfApplied)
            + [
                ChromeMV3PermissionsAPIContractEvaluator.eventPayload(
                    kind: .onRemoved,
                    source: .extensionDisable,
                    extensionID: extensionID,
                    profileID: profileID,
                    permissions: [],
                    origins: []
                ),
                ChromeMV3PermissionsAPIContractEvaluator.eventPayload(
                    kind: .onRemoved,
                    source: .profileClose,
                    extensionID: extensionID,
                    profileID: profileID,
                    permissions: [],
                    origins: []
                ),
            ]
        let password = passwordManagerPermissionAPIReadiness(
            prerequisites: prerequisites,
            permissionStore: permissionStore,
            activeTabStore: activeTabStore
        )
        let lifecycleSummary =
            ChromeMV3ServiceWorkerLifecycleReportGenerator.makeReport(
                prerequisitesReport: prerequisites,
                profileID: profileID
            ).summary
        let summary = ChromeMV3PermissionsAPIContractSummary(
            containsModeled: true,
            getAllModeled: true,
            requestModeled: true,
            removeModeled: true,
            onAddedModeled: true,
            onRemovedModeled: true,
            optionalPermissions: snapshot.optionalAPIPermissions,
            optionalOrigins: snapshot.optionalHostPermissions,
            grantedOptionalPermissions:
                snapshot.grantedOptionalAPIPermissions,
            grantedOptionalOrigins:
                snapshot.grantedOptionalHostPermissions,
            canPromptUserNow: false,
            canDispatchPermissionEventNow: false,
            canRegisterListenersNow: false,
            canWakeServiceWorkerNow: false,
            canDispatchMessagesNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            serviceWorkerLifecycleReportSummary:
                lifecycleSummary
        )
        let routeListenerImpact = [
            "Messaging route diagnostics can reference chrome.permissions.request when optional host grants are missing.",
            "Listener readiness includes chrome.permissions.onAdded/onRemoved as modeled event payloads only.",
            "No listener registration, service-worker wake, or message dispatch is enabled by this report.",
        ]
        return ChromeMV3PermissionsAPIContractReport(
            schemaVersion: 1,
            id: id(
                candidateID: prerequisites.candidateID,
                prerequisiteReportID: prerequisites.id,
                permissionStoreID: snapshot.storeID,
                activeTabStoreID: activeSnapshot.storeID
            ),
            reportFileName:
                ChromeMV3PermissionsAPIContractReportWriter.reportFileName,
            candidateID: prerequisites.candidateID,
            extensionID: extensionID,
            profileID: profileID,
            permissionStoreSummary: snapshot.summary,
            activeTabStoreSummary: activeSnapshot.summary,
            contractSummary: summary,
            containsContractCoverage: [contains],
            getAllContractCoverage: getAll,
            requestContractCoverage: requests,
            removeContractCoverage: removes,
            onAddedEventContractCoverage: addedEvents,
            onRemovedEventContractCoverage: removedEvents,
            optionalPermissionState: snapshot.summary,
            activeTabSideEffectDiagnostics:
                removes.flatMap(\.diagnostics).sorted(),
            routeListenerReadinessImpact: routeListenerImpact,
            passwordManagerPermissionAPIReadiness: password,
            canPromptUserNow: false,
            canDispatchPermissionEventNow: false,
            canRegisterListenersNow: false,
            canWakeServiceWorkerNow: false,
            canDispatchMessagesNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            serviceWorkerLifecycleReportSummary:
                lifecycleSummary,
            documentationSources: documentationSources(),
            diagnostics: [
                "chrome.permissions API contract is deterministic and non-executing.",
                "contains/getAll/request/remove are modeled without callbacks, Promises, or JavaScript execution.",
                "onAdded/onRemoved payloads are modeled but not dispatched.",
                "Product permission UI is required for future optional grants and is not implemented here.",
                "Context loading, service-worker wake, listener registration, message dispatch, and native messaging remain blocked.",
                "Sumi does not claim Chrome MV3 runtime support.",
            ]
        )
    }

    static func makeReport(
        loadingPrerequisitesReportFrom rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> ChromeMV3PermissionsAPIContractReport {
        let rootURL = rootURL.standardizedFileURL
        let prerequisitesURL = rootURL.appendingPathComponent(
            ChromeMV3RuntimeBridgePrerequisitesReportWriter.reportFileName
        )
        let data = try Data(contentsOf: prerequisitesURL)
        let prerequisites = try JSONDecoder().decode(
            ChromeMV3RuntimeBridgePrerequisitesReport.self,
            from: data
        )
        return makeReport(prerequisitesReport: prerequisites)
    }

    private static func passwordManagerPermissionAPIReadiness(
        prerequisites: ChromeMV3RuntimeBridgePrerequisitesReport,
        permissionStore: ChromeMV3PermissionDecisionStore,
        activeTabStore: ChromeMV3ActiveTabGrantStore
    ) -> ChromeMV3PasswordManagerPermissionAPIReadiness {
        let loginURL = "https://example.com/login"
        let contains = ChromeMV3PermissionsAPIContractEvaluator.contains(
            input: ChromeMV3PermissionsAPIRequestInput(
                extensionID: prerequisites.candidateID,
                profileID: activeTabStore.snapshot.profileID,
                sourceContext: .testFixture,
                origins: [loginURL]
            ),
            permissionStore: permissionStore,
            activeTabStore: activeTabStore
        )
        let request = ChromeMV3PermissionsAPIContractEvaluator.request(
            input: ChromeMV3PermissionsAPIRequestInput(
                extensionID: prerequisites.candidateID,
                profileID: activeTabStore.snapshot.profileID,
                sourceContext: .actionPopup,
                userGestureModeled: true,
                origins: [loginURL]
            ),
            permissionStore: permissionStore,
            activeTabStore: activeTabStore
        )
        let remove = ChromeMV3PermissionsAPIContractEvaluator.applyingRemove(
            input: ChromeMV3PermissionsAPIRequestInput(
                extensionID: prerequisites.candidateID,
                profileID: activeTabStore.snapshot.profileID,
                sourceContext: .testFixture,
                origins: [loginURL]
            ),
            permissionStore: permissionStore,
            activeTabStore: activeTabStore,
            apply: false,
            sequence: 1
        ).result
        let summary = prerequisites.passwordManagerPrerequisiteSummary
        let hostDeclarations = Array(Set(
            prerequisites.manifestFacts.hostPermissions
                + prerequisites.manifestFacts.optionalHostPermissions
        )).sorted()
        return ChromeMV3PasswordManagerPermissionAPIReadiness(
            hostPermissionsAlreadyDeclaredOrOptional: hostDeclarations,
            containsWouldReturnForLoginOrigin: contains.wouldReturn,
            requestWouldRequireProductUI: request.wouldRequirePrompt,
            actionPopupUserGestureCouldRequestPermissionInFuture:
                prerequisites.manifestFacts.actionPopupPresent
                    || summary.actionPopupPresent,
            removeWouldRevokeAccessAndExpireActiveTabGrants:
                remove.wouldRevokeModeledPermissions
                    && remove.wouldExpireActiveTabGrants,
            onAddedEventNotDispatchable: true,
            onRemovedEventNotDispatchable: true,
            storageRuntimeBlockerRemains:
                prerequisites.manifestFacts.storagePermissionPresent
                    || summary.storagePermissionPresent,
            runtimeMessagingBlockerRemains: true,
            nativeMessagingBlockerRemains:
                prerequisites.manifestFacts.nativeMessagingPermissionPresent
                    || summary.nativeMessagingPermissionPresent,
            passwordManagerPermissionAPIReady: false,
            blockers: Array(Set(
                summary.blockers
                    + contains.blockedDiagnostics
                    + request.diagnostics
                    + remove.diagnostics
                    + [
                        "Password-manager permission API readiness is false because product permission UI is not implemented.",
                        "Permission events are not dispatchable.",
                        "Storage, runtime messaging, native messaging, content-script injection, and service-worker wake blockers remain.",
                    ]
            )).sorted()
        )
    }

    private static func documentationSources()
        -> [ChromeMV3ManifestRewritePreviewSource]
    {
        [
            source(
                title: "Chrome permissions API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/permissions",
                note: "Defines chrome.permissions.contains, getAll, request, remove, onAdded, onRemoved, optional permissions, and user-gesture request behavior."
            ),
            source(
                title: "Chrome declare permissions",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/declare-permissions",
                note: "Defines permissions, optional_permissions, host_permissions, and optional_host_permissions manifest keys."
            ),
            source(
                title: "Chrome match patterns",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/match-patterns",
                note: "Defines match pattern syntax and host-permission path behavior."
            ),
            source(
                title: "Chrome activeTab",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/activeTab",
                note: "Defines temporary user-gesture-bound host access and revocation on navigation or tab close."
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
        prerequisiteReportID: String,
        permissionStoreID: String,
        activeTabStoreID: String
    ) -> String {
        ChromeMV3PermissionsAPIStableID.make(
            prefix: "runtime-permissions-api-contract",
            parts: [
                candidateID,
                prerequisiteReportID,
                permissionStoreID,
                activeTabStoreID,
            ]
        )
    }
}

private enum ChromeMV3PermissionsAPIStableID {
    static func make(prefix: String, parts: [String]) -> String {
        let seed = parts.joined(separator: "|")
        return "\(prefix)-\(sha256Hex(Data(seed.utf8)).prefix(32))"
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
