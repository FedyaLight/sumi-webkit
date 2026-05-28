//
//  ChromeMV3PermissionRuntimeImplementation.swift
//  Sumi
//
//  Internal Chrome MV3 permission and activeTab runtime implementation model.
//  This is restricted to deterministic internal/test runtime state. It does not
//  create product permission UI, expose runtime bridges to normal tabs, wake
//  service workers, launch native messaging, or schedule background work.
//

import CryptoKit
import Foundation

enum ChromeMV3ModeledPermissionPromptResult:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case accepted
    case denied
    case dismissed
    case notProvided

    static func < (
        lhs: ChromeMV3ModeledPermissionPromptResult,
        rhs: ChromeMV3ModeledPermissionPromptResult
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PermissionRuntimeOperationKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case activeTabGestureGrant
    case contains
    case getAll
    case lifecycleEvent
    case remove
    case request
    case resetActiveTab

    static func < (
        lhs: ChromeMV3PermissionRuntimeOperationKind,
        rhs: ChromeMV3PermissionRuntimeOperationKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3PermissionRuntimeEventKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case activeTabExpired
    case activeTabGranted
    case permissionAdded
    case permissionDenied
    case permissionDismissed
    case permissionRemoved
    case promptRequiredButProductUIUnavailable

    static func < (
        lhs: ChromeMV3PermissionRuntimeEventKind,
        rhs: ChromeMV3PermissionRuntimeEventKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3PermissionRuntimeNamespace:
    Codable,
    Equatable,
    Sendable
{
    var profileID: String
    var extensionID: String

    init(profileID: String, extensionID: String) {
        self.profileID = profileID.isEmpty ? "unknown-profile" : profileID
        self.extensionID = extensionID.isEmpty
            ? "unknown-extension"
            : extensionID
    }

    var stableParts: [String] {
        [profileID, extensionID]
    }
}

struct ChromeMV3PermissionRuntimeEventRecord:
    Codable,
    Equatable,
    Sendable
{
    var id: String
    var sequence: Int
    var eventKind: ChromeMV3PermissionRuntimeEventKind
    var source: String
    var profileID: String
    var extensionID: String
    var permissions: [String]
    var origins: [String]
    var tabID: Int?
    var activeTabGrantID: String?
    var activeTabExpiryCause: ChromeMV3ActiveTabExpiryTrigger?
    var chromePermissionsEventPayload:
        ChromeMV3PermissionsAPIEventPayload?
    var wouldDispatchToJSNow: Bool
    var serviceWorkerWakeRequired: Bool
    var serviceWorkerWakeBlocked: Bool
    var diagnostics: [String]

    init(
        sequence: Int,
        eventKind: ChromeMV3PermissionRuntimeEventKind,
        source: String,
        namespace: ChromeMV3PermissionRuntimeNamespace,
        permissions: [String] = [],
        origins: [String] = [],
        tabID: Int? = nil,
        activeTabGrantID: String? = nil,
        activeTabExpiryCause: ChromeMV3ActiveTabExpiryTrigger? = nil,
        chromePermissionsEventPayload:
            ChromeMV3PermissionsAPIEventPayload? = nil,
        wouldDispatchToJSNow: Bool = false,
        diagnostics: [String] = []
    ) {
        self.sequence = sequence
        self.eventKind = eventKind
        self.source = source
        self.profileID = namespace.profileID
        self.extensionID = namespace.extensionID
        self.permissions = Self.uniqueSorted(permissions)
        self.origins = Self.uniqueSorted(origins)
        self.tabID = tabID
        self.activeTabGrantID = activeTabGrantID
        self.activeTabExpiryCause = activeTabExpiryCause
        self.chromePermissionsEventPayload = chromePermissionsEventPayload
        self.wouldDispatchToJSNow = wouldDispatchToJSNow
        self.serviceWorkerWakeRequired = false
        self.serviceWorkerWakeBlocked = true
        self.diagnostics = Self.uniqueSorted(
            diagnostics
                + [
                    "Permission runtime event is internal/test scoped.",
                    "No product permission UI is displayed.",
                    "No service-worker wake is requested by this implementation layer.",
                ]
        )
        self.id = ChromeMV3PermissionRuntimeStableID.make(
            prefix: "permission-runtime-event",
            parts:
                namespace.stableParts
                + [
                    eventKind.rawValue,
                    source,
                    String(sequence),
                    self.permissions.joined(separator: ","),
                    self.origins.joined(separator: ","),
                    activeTabGrantID ?? "no-active-tab-grant",
                ]
        )
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { $0.isEmpty == false })).sorted()
    }
}

struct ChromeMV3PermissionRuntimeDiffRecord:
    Codable,
    Equatable,
    Sendable
{
    var id: String
    var sequence: Int
    var operation: ChromeMV3PermissionRuntimeOperationKind
    var addedOptionalPermissions: [String]
    var removedOptionalPermissions: [String]
    var addedOptionalOrigins: [String]
    var removedOptionalOrigins: [String]
    var addedDeniedPermissions: [String]
    var addedRevokedPermissions: [String]
    var activeGrantCountBefore: Int
    var activeGrantCountAfter: Int
    var diagnostics: [String]

    init(
        sequence: Int,
        operation: ChromeMV3PermissionRuntimeOperationKind,
        beforePermission:
            ChromeMV3PermissionDecisionStoreSnapshotSummary,
        afterPermission:
            ChromeMV3PermissionDecisionStoreSnapshotSummary,
        beforeActiveTab:
            ChromeMV3ActiveTabGrantStoreSnapshotSummary,
        afterActiveTab:
            ChromeMV3ActiveTabGrantStoreSnapshotSummary
    ) {
        self.sequence = sequence
        self.operation = operation
        self.addedOptionalPermissions = Self.added(
            beforePermission.grantedOptionalAPIPermissions,
            afterPermission.grantedOptionalAPIPermissions
        )
        self.removedOptionalPermissions = Self.removed(
            beforePermission.grantedOptionalAPIPermissions,
            afterPermission.grantedOptionalAPIPermissions
        )
        self.addedOptionalOrigins = Self.added(
            beforePermission.grantedOptionalHostPermissions,
            afterPermission.grantedOptionalHostPermissions
        )
        self.removedOptionalOrigins = Self.removed(
            beforePermission.grantedOptionalHostPermissions,
            afterPermission.grantedOptionalHostPermissions
        )
        self.addedDeniedPermissions = Self.added(
            beforePermission.deniedPermissions,
            afterPermission.deniedPermissions
        )
        self.addedRevokedPermissions = Self.added(
            beforePermission.revokedPermissions,
            afterPermission.revokedPermissions
        )
        self.activeGrantCountBefore = beforeActiveTab.activeGrantCount
        self.activeGrantCountAfter = afterActiveTab.activeGrantCount
        self.diagnostics = [
            "Permission runtime diff was computed from deterministic store summaries.",
        ]
        self.id = ChromeMV3PermissionRuntimeStableID.make(
            prefix: "permission-runtime-diff",
            parts: [
                beforePermission.profileID,
                beforePermission.extensionID,
                operation.rawValue,
                String(sequence),
                self.addedOptionalPermissions.joined(separator: ","),
                self.removedOptionalPermissions.joined(separator: ","),
                self.addedOptionalOrigins.joined(separator: ","),
                self.removedOptionalOrigins.joined(separator: ","),
                String(activeGrantCountBefore),
                String(activeGrantCountAfter),
            ]
        )
    }

    var changed: Bool {
        addedOptionalPermissions.isEmpty == false
            || removedOptionalPermissions.isEmpty == false
            || addedOptionalOrigins.isEmpty == false
            || removedOptionalOrigins.isEmpty == false
            || addedDeniedPermissions.isEmpty == false
            || addedRevokedPermissions.isEmpty == false
            || activeGrantCountBefore != activeGrantCountAfter
    }

    private static func added(_ before: [String], _ after: [String])
        -> [String]
    {
        Array(Set(after).subtracting(Set(before))).sorted()
    }

    private static func removed(_ before: [String], _ after: [String])
        -> [String]
    {
        Array(Set(before).subtracting(Set(after))).sorted()
    }
}

struct ChromeMV3PermissionRuntimeTransactionRecord:
    Codable,
    Equatable,
    Sendable
{
    var id: String
    var sequence: Int
    var operation: ChromeMV3PermissionRuntimeOperationKind
    var profileID: String
    var extensionID: String
    var permissions: [String]
    var origins: [String]
    var returnedBoolean: Bool?
    var modeledPromptResult: ChromeMV3ModeledPermissionPromptResult?
    var productPromptResult:
        ChromeMV3PermissionPromptResultDisposition?
    var eventRecordIDs: [String]
    var diffRecordID: String?
    var diagnostics: [String]

    init(
        sequence: Int,
        operation: ChromeMV3PermissionRuntimeOperationKind,
        namespace: ChromeMV3PermissionRuntimeNamespace,
        permissions: [String] = [],
        origins: [String] = [],
        returnedBoolean: Bool? = nil,
        modeledPromptResult: ChromeMV3ModeledPermissionPromptResult? = nil,
        productPromptResult:
            ChromeMV3PermissionPromptResultDisposition? = nil,
        eventRecordIDs: [String] = [],
        diffRecordID: String? = nil,
        diagnostics: [String] = []
    ) {
        self.sequence = sequence
        self.operation = operation
        self.profileID = namespace.profileID
        self.extensionID = namespace.extensionID
        self.permissions = Self.uniqueSorted(permissions)
        self.origins = Self.uniqueSorted(origins)
        self.returnedBoolean = returnedBoolean
        self.modeledPromptResult = modeledPromptResult
        self.productPromptResult = productPromptResult
        self.eventRecordIDs = Self.uniqueSorted(eventRecordIDs)
        self.diffRecordID = diffRecordID
        self.diagnostics = Self.uniqueSorted(
            diagnostics
                + [
                    "Permission runtime transaction executed in internal/test state only.",
                ]
        )
        self.id = ChromeMV3PermissionRuntimeStableID.make(
            prefix: "permission-runtime-transaction",
            parts:
                namespace.stableParts
                + [
                    operation.rawValue,
                    String(sequence),
                    self.permissions.joined(separator: ","),
                    self.origins.joined(separator: ","),
                    returnedBoolean.map(String.init) ?? "no-bool",
                    modeledPromptResult?.rawValue ?? "no-modeled-result",
                    productPromptResult?.rawValue ?? "no-product-result",
                ]
        )
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { $0.isEmpty == false })).sorted()
    }
}

struct ChromeMV3PermissionRuntimeStateOwnerSnapshot:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var namespace: ChromeMV3PermissionRuntimeNamespace
    var permissionStore:
        ChromeMV3PermissionDecisionStoreSnapshot
    var activeTabStore:
        ChromeMV3ActiveTabGrantStoreSnapshot
    var transactionRecords:
        [ChromeMV3PermissionRuntimeTransactionRecord]
    var eventRecords: [ChromeMV3PermissionRuntimeEventRecord]
    var permissionDiffs: [ChromeMV3PermissionRuntimeDiffRecord]
    var nextSequence: Int
    var permissionImplementationAvailableInInternalRuntime: Bool
    var permissionUIAvailableInProduct: Bool
    var activeTabAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]
}

struct ChromeMV3PermissionRuntimeRequestApplication:
    Codable,
    Equatable,
    Sendable
{
    var result: ChromeMV3PermissionsAPIRequestResult
    var returnedBoolean: Bool
    var permissionStore:
        ChromeMV3PermissionDecisionStore
    var activeTabStore: ChromeMV3ActiveTabGrantStore
    var eventRecords: [ChromeMV3PermissionRuntimeEventRecord]
    var diffRecord: ChromeMV3PermissionRuntimeDiffRecord?
    var diagnostics: [String]
}

struct ChromeMV3PermissionRuntimeRemoveApplication:
    Codable,
    Equatable,
    Sendable
{
    var result: ChromeMV3PermissionsAPIRemoveResult
    var returnedBoolean: Bool
    var permissionStore:
        ChromeMV3PermissionDecisionStore
    var activeTabStore: ChromeMV3ActiveTabGrantStore
    var eventRecords: [ChromeMV3PermissionRuntimeEventRecord]
    var diffRecord: ChromeMV3PermissionRuntimeDiffRecord?
    var diagnostics: [String]
}

struct ChromeMV3ActiveTabRuntimeGrantResult:
    Codable,
    Equatable,
    Sendable
{
    var gestureEvent: ChromeMV3ActiveTabGestureEvent
    var granted: Bool
    var grantRecord: ChromeMV3ActiveTabGrantRecord?
    var activeTabStoreSummary:
        ChromeMV3ActiveTabGrantStoreSnapshotSummary
    var eventRecord: ChromeMV3PermissionRuntimeEventRecord?
    var diagnostics: [String]
}

struct ChromeMV3PermissionRuntimeLifecycleApplication:
    Codable,
    Equatable,
    Sendable
{
    var lifecycleResult: ChromeMV3PermissionLifecycleEventResult
    var permissionStore:
        ChromeMV3PermissionDecisionStore
    var activeTabStore: ChromeMV3ActiveTabGrantStore
    var eventRecords: [ChromeMV3PermissionRuntimeEventRecord]
    var diffRecord: ChromeMV3PermissionRuntimeDiffRecord?
    var diagnostics: [String]
}

struct ChromeMV3PermissionRuntimeStateOwner:
    Codable,
    Equatable,
    Sendable
{
    private(set) var permissionStore:
        ChromeMV3PermissionDecisionStore
    private(set) var activeTabStore:
        ChromeMV3ActiveTabGrantStore
    private(set) var transactionRecords:
        [ChromeMV3PermissionRuntimeTransactionRecord]
    private(set) var eventRecords: [ChromeMV3PermissionRuntimeEventRecord]
    private(set) var permissionDiffs:
        [ChromeMV3PermissionRuntimeDiffRecord]
    private(set) var nextSequence: Int
    var internalRuntimeMutationAllowed: Bool

    init(
        permissionStore: ChromeMV3PermissionDecisionStore,
        activeTabStore: ChromeMV3ActiveTabGrantStore? = nil,
        transactionRecords:
            [ChromeMV3PermissionRuntimeTransactionRecord] = [],
        eventRecords: [ChromeMV3PermissionRuntimeEventRecord] = [],
        permissionDiffs:
            [ChromeMV3PermissionRuntimeDiffRecord] = [],
        nextSequence: Int = 1,
        internalRuntimeMutationAllowed: Bool = true
    ) {
        let snapshot = permissionStore.exportSnapshot()
        self.permissionStore = permissionStore
        self.activeTabStore = activeTabStore
            ?? ChromeMV3ActiveTabGrantStore.empty(
                extensionID: snapshot.extensionID,
                profileID: snapshot.profileID
            )
        self.transactionRecords = transactionRecords.sorted {
            if $0.sequence != $1.sequence {
                return $0.sequence < $1.sequence
            }
            return $0.id < $1.id
        }
        self.eventRecords = eventRecords.sorted {
            if $0.sequence != $1.sequence {
                return $0.sequence < $1.sequence
            }
            return $0.id < $1.id
        }
        self.permissionDiffs = permissionDiffs.sorted {
            if $0.sequence != $1.sequence {
                return $0.sequence < $1.sequence
            }
            return $0.id < $1.id
        }
        self.nextSequence = max(
            nextSequence,
            (
                self.transactionRecords.map(\.sequence)
                    + self.eventRecords.map(\.sequence)
                    + self.permissionDiffs.map(\.sequence)
            ).max().map { $0 + 1 } ?? 1
        )
        self.internalRuntimeMutationAllowed = internalRuntimeMutationAllowed
    }

    init(
        permissionBroker broker: ChromeMV3PermissionBroker,
        internalRuntimeMutationAllowed: Bool = true
    ) {
        let state = broker.state
        let permissionStore = ChromeMV3PermissionDecisionStore(
            snapshot: ChromeMV3PermissionDecisionStoreSnapshot(
                extensionID: state.extensionID,
                profileID: state.profileID,
                declaredAPIPermissions: state.requiredPermissions,
                declaredHostPermissions: state.hostPermissions,
                optionalAPIPermissions: state.optionalPermissions,
                optionalHostPermissions: state.optionalHostPermissions,
                grantedOptionalAPIPermissions:
                    state.grantedOptionalPermissions,
                grantedOptionalHostPermissions:
                    state.grantedOptionalHostPermissions,
                deniedPermissions: state.deniedPermissions,
                revokedPermissions: state.revokedPermissions,
                deferredPermissions: state.unavailablePermissions,
                unsupportedPermissions: state.unsupportedPermissions,
                diagnostics: state.diagnostics
            )
        )
        let activeTabStore = ChromeMV3ActiveTabGrantStore.from(
            extensionID: state.extensionID,
            profileID: state.profileID,
            grants: state.activeTabGrants
        )
        self.init(
            permissionStore: permissionStore,
            activeTabStore: activeTabStore,
            internalRuntimeMutationAllowed: internalRuntimeMutationAllowed
        )
    }

    init(snapshot: ChromeMV3PermissionRuntimeStateOwnerSnapshot) {
        self.init(
            permissionStore:
                ChromeMV3PermissionDecisionStore(
                    snapshot: snapshot.permissionStore
                ),
            activeTabStore:
                ChromeMV3ActiveTabGrantStore(
                    snapshot: snapshot.activeTabStore
                ),
            transactionRecords: snapshot.transactionRecords,
            eventRecords: snapshot.eventRecords,
            permissionDiffs: snapshot.permissionDiffs,
            nextSequence: snapshot.nextSequence,
            internalRuntimeMutationAllowed:
                snapshot
                .permissionImplementationAvailableInInternalRuntime
        )
    }

    var namespace: ChromeMV3PermissionRuntimeNamespace {
        ChromeMV3PermissionRuntimeNamespace(
            profileID: permissionStore.snapshot.profileID,
            extensionID: permissionStore.snapshot.extensionID
        )
    }

    var permissionBroker: ChromeMV3PermissionBroker {
        permissionStore.permissionBroker(activeTabStore: activeTabStore)
    }

    var snapshot: ChromeMV3PermissionRuntimeStateOwnerSnapshot {
        ChromeMV3PermissionRuntimeStateOwnerSnapshot(
            schemaVersion: 1,
            namespace: namespace,
            permissionStore: permissionStore.exportSnapshot(),
            activeTabStore: activeTabStore.exportSnapshot(),
            transactionRecords: transactionRecords,
            eventRecords: eventRecords,
            permissionDiffs: permissionDiffs,
            nextSequence: nextSequence,
            permissionImplementationAvailableInInternalRuntime:
                internalRuntimeMutationAllowed,
            permissionUIAvailableInProduct: false,
            activeTabAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            diagnostics: [
                "Permission runtime state is namespaced by profile id and extension id.",
                "Internal runtime permission state is deterministic and exportable.",
                "Product permission UI, product activeTab, normal-tab runtime bridge, and runtime loadability remain unavailable.",
            ]
        )
    }

    func contains(
        input: ChromeMV3PermissionsAPIRequestInput
    ) -> ChromeMV3PermissionsAPIContainsResult {
        var result = ChromeMV3PermissionsAPIContractEvaluator.contains(
            input: input,
            permissionStore: permissionStore,
            activeTabStore: activeTabStore
        )
        result.runtimeImplementedNow = true
        result.diagnostics = Self.uniqueSorted(
            result.diagnostics
                + [
                    "chrome.permissions.contains executed against internal runtime permission state.",
                ]
        )
        return result
    }

    func getAll() -> ChromeMV3PermissionsAPIGetAllResult {
        var result = ChromeMV3PermissionsAPIContractEvaluator.getAll(
            permissionStore: permissionStore
        )
        result.runtimeImplementedNow = true
        result.diagnostics = Self.uniqueSorted(
            result.diagnostics
                + [
                    "chrome.permissions.getAll executed against internal runtime permission state.",
                ]
        )
        return result
    }

    mutating func request(
        input: ChromeMV3PermissionsAPIRequestInput,
        modeledPromptResult:
            ChromeMV3ModeledPermissionPromptResult = .notProvided,
        productPromptResult:
            ChromeMV3PermissionPromptResultRecord? = nil
    ) -> ChromeMV3PermissionRuntimeRequestApplication {
        let beforePermission = permissionStore.exportSnapshot().summary
        let beforeActiveTab = activeTabStore.exportSnapshot().summary
        let sequence = takeSequence()
        var result = ChromeMV3PermissionsAPIContractEvaluator.request(
            input: input,
            permissionStore: permissionStore,
            activeTabStore: activeTabStore
        )
        result.runtimeImplementedNow = true
        result.canPromptUserNow = false
        result.canDispatchPermissionEventNow = false

        var returned = result.wouldBeAllowedByModel
        var newEvents: [ChromeMV3PermissionRuntimeEventRecord] = []

        if result.wouldBeAllowedByModel {
            returned = true
        } else if result.wouldGrantIfUserAccepted,
                  modeledPromptResult == .accepted,
                  internalRuntimeMutationAllowed
        {
            for item in result.itemDecisions
                where item.wouldGrantIfUserAccepted
            {
                permissionStore =
                    permissionStore.applyingPermissionsAPIModeledGrant(
                        item.value,
                        kind: item.kind,
                        sequence: takeSequence()
                    )
            }
            returned = true
            let payload = result.eventPayloadIfAccepted
            let event = makeEvent(
                sequence: sequence,
                eventKind: .permissionAdded,
                source: "chrome.permissions.request.accepted",
                permissions:
                    result.itemDecisions
                    .filter {
                        $0.kind == .apiPermission
                            && $0.wouldGrantIfUserAccepted
                    }
                    .map(\.value),
                origins:
                    result.itemDecisions
                    .filter {
                        $0.kind == .origin
                            && $0.wouldGrantIfUserAccepted
                    }
                    .map(\.value),
                chromePermissionsEventPayload: payload,
                diagnostics: [
                    productPromptResult == nil
                        ? "Modeled prompt result accepted optional permission request."
                        : "Developer-preview product prompt accepted optional permission request.",
                ]
            )
            newEvents.append(event)
        } else if result.wouldGrantIfUserAccepted,
                  modeledPromptResult == .denied,
                  internalRuntimeMutationAllowed
        {
            for item in result.itemDecisions
                where item.wouldGrantIfUserAccepted
            {
                permissionStore = permissionStore.applyingModeledDenial(
                    item.value,
                    sequence: takeSequence()
                )
            }
            returned = false
            let event = makeEvent(
                sequence: sequence,
                eventKind: .permissionDenied,
                source: "chrome.permissions.request.denied",
                permissions:
                    result.itemDecisions
                    .filter { $0.kind == .apiPermission }
                    .map(\.value),
                origins:
                    result.itemDecisions
                    .filter { $0.kind == .origin }
                    .map(\.value),
                diagnostics: [
                    "Modeled prompt result denied optional permission request.",
                ]
            )
            newEvents.append(event)
        } else if result.wouldGrantIfUserAccepted,
                  modeledPromptResult == .dismissed,
                  internalRuntimeMutationAllowed
        {
            returned = false
            let event = makeEvent(
                sequence: sequence,
                eventKind: .permissionDismissed,
                source: "chrome.permissions.request.dismissed",
                permissions:
                    result.itemDecisions
                    .filter { $0.kind == .apiPermission }
                    .map(\.value),
                origins:
                    result.itemDecisions
                    .filter { $0.kind == .origin }
                    .map(\.value),
                diagnostics: [
                    productPromptResult == nil
                        ? "Modeled prompt result dismissed optional permission request."
                        : "Developer-preview product prompt dismissed optional permission request.",
                ]
            )
            newEvents.append(event)
        } else if result.wouldRequirePrompt {
            returned = false
            let event = makeEvent(
                sequence: sequence,
                eventKind: .promptRequiredButProductUIUnavailable,
                source: "chrome.permissions.request.promptUnavailable",
                permissions:
                    result.itemDecisions
                    .filter { $0.kind == .apiPermission }
                    .map(\.value),
                origins:
                    result.itemDecisions
                    .filter { $0.kind == .origin }
                    .map(\.value),
                diagnostics: [
                    "Permission prompt was required but product permission UI is unavailable.",
                ]
            )
            newEvents.append(event)
        } else {
            returned = false
            let event = makeEvent(
                sequence: sequence,
                eventKind: .permissionDenied,
                source: "chrome.permissions.request.blocked",
                permissions:
                    result.itemDecisions
                    .filter { $0.kind == .apiPermission }
                    .map(\.value),
                origins:
                    result.itemDecisions
                    .filter { $0.kind == .origin }
                    .map(\.value),
                diagnostics: [
                    "Permission request was blocked by internal runtime state.",
                ]
            )
            newEvents.append(event)
        }

        result.diagnostics = Self.uniqueSorted(
            result.diagnostics
                + [
                    "chrome.permissions.request executed in internal runtime state.",
                    "Product permission UI remains unavailable.",
                    "Returned \(returned) for the modeled request.",
                ]
        )
        let diff = appendDiffIfChanged(
            sequence: sequence,
            operation: .request,
            beforePermission: beforePermission,
            beforeActiveTab: beforeActiveTab
        )
        appendEvents(newEvents)
        appendTransaction(
            sequence: sequence,
            operation: .request,
            permissions: input.normalized.permissions,
            origins: input.normalized.origins,
            returnedBoolean: returned,
            modeledPromptResult: modeledPromptResult,
            productPromptResult: productPromptResult?.disposition,
            eventRecordIDs: newEvents.map(\.id),
            diffRecordID: diff?.id,
            diagnostics: result.diagnostics
        )

        return ChromeMV3PermissionRuntimeRequestApplication(
            result: result,
            returnedBoolean: returned,
            permissionStore: permissionStore,
            activeTabStore: activeTabStore,
            eventRecords: newEvents,
            diffRecord: diff,
            diagnostics: result.diagnostics
        )
    }

    mutating func remove(
        input: ChromeMV3PermissionsAPIRequestInput
    ) -> ChromeMV3PermissionRuntimeRemoveApplication {
        let beforePermission = permissionStore.exportSnapshot().summary
        let beforeActiveTab = activeTabStore.exportSnapshot().summary
        let sequence = takeSequence()
        let applied = ChromeMV3PermissionsAPIContractEvaluator
            .applyingRemove(
                input: input,
                permissionStore: permissionStore,
                activeTabStore: activeTabStore,
                apply: internalRuntimeMutationAllowed,
                sequence: takeSequence()
            )
        permissionStore = applied.permissionStore
        activeTabStore = applied.activeTabStore

        var result = applied.result
        result.runtimeImplementedNow = true
        result.canDispatchPermissionEventNow = false
        result.diagnostics = Self.uniqueSorted(
            result.diagnostics
                + [
                    "chrome.permissions.remove executed against internal runtime permission state.",
                ]
        )

        var newEvents: [ChromeMV3PermissionRuntimeEventRecord] = []
        if result.wouldReturn {
            newEvents.append(
                makeEvent(
                    sequence: sequence,
                    eventKind: .permissionRemoved,
                    source: "chrome.permissions.remove",
                    permissions:
                        result.itemDecisions
                        .filter {
                            $0.kind == .apiPermission && $0.removable
                        }
                        .map(\.value),
                    origins:
                        result.itemDecisions
                        .filter {
                            $0.kind == .origin && $0.removable
                        }
                        .map(\.value),
                    chromePermissionsEventPayload:
                        result.eventPayloadIfApplied,
                    diagnostics: [
                        "Optional permission/origin was revoked from internal runtime state.",
                    ]
                )
            )
        } else {
            newEvents.append(
                makeEvent(
                    sequence: sequence,
                    eventKind: .permissionDenied,
                    source: "chrome.permissions.remove.blocked",
                    permissions: input.normalized.permissions,
                    origins: input.normalized.origins,
                    diagnostics: [
                        "Permission remove was rejected by internal runtime state.",
                    ]
                )
            )
        }
        let expired = activeTabStore.snapshot.grantRecords.filter {
            $0.grant.expiryRecord?.trigger == .permissionRevoke
                && $0.grant.expiryRecord?.sequence
                    == sequence + result.itemDecisions.count
        }
        for record in expired {
            newEvents.append(
                makeEvent(
                    sequence: record.grant.expiryRecord?.sequence
                        ?? sequence,
                    eventKind: .activeTabExpired,
                    source: "chrome.permissions.remove",
                    tabID: record.grant.tabID,
                    activeTabGrantID: record.id,
                    activeTabExpiryCause:
                        record.grant.expiryRecord?.trigger,
                    diagnostics: record.grant.diagnostics
                )
            )
        }
        let diff = appendDiffIfChanged(
            sequence: sequence,
            operation: .remove,
            beforePermission: beforePermission,
            beforeActiveTab: beforeActiveTab
        )
        appendEvents(newEvents)
        appendTransaction(
            sequence: sequence,
            operation: .remove,
            permissions: input.normalized.permissions,
            origins: input.normalized.origins,
            returnedBoolean: result.wouldReturn,
            eventRecordIDs: newEvents.map(\.id),
            diffRecordID: diff?.id,
            diagnostics: result.diagnostics
        )

        return ChromeMV3PermissionRuntimeRemoveApplication(
            result: result,
            returnedBoolean: result.wouldReturn,
            permissionStore: permissionStore,
            activeTabStore: activeTabStore,
            eventRecords: newEvents,
            diffRecord: diff,
            diagnostics: result.diagnostics
        )
    }

    mutating func grantActiveTabFromGesture(
        _ event: ChromeMV3ActiveTabGestureEvent
    ) -> ChromeMV3ActiveTabRuntimeGrantResult {
        let beforePermission = permissionStore.exportSnapshot().summary
        let beforeActiveTab = activeTabStore.exportSnapshot().summary
        let sequence = event.sequence > 0 ? event.sequence : takeSequence()
        let broker = permissionBroker
        guard internalRuntimeMutationAllowed,
              broker.wouldGrantFromGesture(event)
        else {
            let diagnostics = [
                "activeTab grant was blocked because permission, modeled user gesture, or internal mutation gate was missing.",
            ]
            let result = ChromeMV3ActiveTabRuntimeGrantResult(
                gestureEvent: event,
                granted: false,
                grantRecord: nil,
                activeTabStoreSummary:
                    activeTabStore.exportSnapshot().summary,
                eventRecord:
                    makeEvent(
                        sequence: sequence,
                        eventKind: .permissionDenied,
                        source: "activeTab.\(event.reason.rawValue)",
                        tabID: event.tabID,
                        diagnostics: diagnostics
                    ),
                diagnostics: diagnostics
            )
            if let eventRecord = result.eventRecord {
                appendEvents([eventRecord])
            }
            appendTransaction(
                sequence: sequence,
                operation: .activeTabGestureGrant,
                returnedBoolean: false,
                eventRecordIDs: result.eventRecord.map { [$0.id] } ?? [],
                diagnostics: diagnostics
            )
            return result
        }

        activeTabStore = activeTabStore.addingModeledGrant(
            tabID: event.tabID,
            url: event.url,
            reason: event.reason,
            sequence: sequence
        )
        let grantRecord = activeTabStore.snapshot.grantRecords.first {
            $0.grant.createdSequence == sequence
                && $0.grant.tabID == event.tabID
        }
        let eventRecord = makeEvent(
            sequence: sequence,
            eventKind: .activeTabGranted,
            source: "activeTab.\(event.reason.rawValue)",
            tabID: event.tabID,
            activeTabGrantID: grantRecord?.id,
            diagnostics:
                grantRecord?.grant.diagnostics
                ?? ["activeTab grant was recorded."]
        )
        let diff = appendDiffIfChanged(
            sequence: sequence,
            operation: .activeTabGestureGrant,
            beforePermission: beforePermission,
            beforeActiveTab: beforeActiveTab
        )
        appendEvents([eventRecord])
        appendTransaction(
            sequence: sequence,
            operation: .activeTabGestureGrant,
            returnedBoolean: grantRecord != nil,
            eventRecordIDs: [eventRecord.id],
            diffRecordID: diff?.id,
            diagnostics: eventRecord.diagnostics
        )
        return ChromeMV3ActiveTabRuntimeGrantResult(
            gestureEvent: event,
            granted: grantRecord != nil,
            grantRecord: grantRecord,
            activeTabStoreSummary:
                activeTabStore.exportSnapshot().summary,
            eventRecord: eventRecord,
            diagnostics: eventRecord.diagnostics
        )
    }

    mutating func applyLifecycleEvent(
        _ event: ChromeMV3PermissionLifecycleEvent
    ) -> ChromeMV3PermissionRuntimeLifecycleApplication {
        let beforePermission = permissionStore.exportSnapshot().summary
        let beforeActiveTab = activeTabStore.exportSnapshot().summary
        let sequence = event.sequence > 0 ? event.sequence : takeSequence()
        let adapter = ChromeMV3PermissionLifecycleAdapter(
            permissionStore: permissionStore,
            activeTabStore: activeTabStore
        )
        .applying(event)
        permissionStore = adapter.permissionStore
        activeTabStore = adapter.activeTabStore
        let lifecycleResult = adapter.eventResults.last
            ?? ChromeMV3PermissionLifecycleEventResult(
                event: event,
                grantsExpired: [],
                grantsRetained:
                    activeTabStore.snapshot.grantRecords.filter {
                        $0.grant.active
                    },
                permissionStoreSummary:
                    permissionStore.exportSnapshot().summary,
                activeTabStoreSummary:
                    activeTabStore.exportSnapshot().summary,
                readinessImpact: [],
                diagnostics: [
                    "Lifecycle event produced no adapter result.",
                ]
            )
        let newEvents = lifecycleResult.grantsExpired.map { record in
            makeEvent(
                sequence: record.grant.expiryRecord?.sequence ?? sequence,
                eventKind: .activeTabExpired,
                source: "lifecycle.\(event.kind.rawValue)",
                tabID: record.grant.tabID,
                activeTabGrantID: record.id,
                activeTabExpiryCause: record.grant.expiryRecord?.trigger,
                diagnostics: record.grant.diagnostics
            )
        }
        let diff = appendDiffIfChanged(
            sequence: sequence,
            operation: .lifecycleEvent,
            beforePermission: beforePermission,
            beforeActiveTab: beforeActiveTab
        )
        appendEvents(newEvents)
        appendTransaction(
            sequence: sequence,
            operation: .lifecycleEvent,
            returnedBoolean: lifecycleResult.grantsExpired.isEmpty == false,
            eventRecordIDs: newEvents.map(\.id),
            diffRecordID: diff?.id,
            diagnostics: lifecycleResult.diagnostics
        )
        return ChromeMV3PermissionRuntimeLifecycleApplication(
            lifecycleResult: lifecycleResult,
            permissionStore: permissionStore,
            activeTabStore: activeTabStore,
            eventRecords: newEvents,
            diffRecord: diff,
            diagnostics: lifecycleResult.diagnostics
        )
    }

    mutating func resetActiveTabGrants(
        sequence explicitSequence: Int? = nil
    ) -> ChromeMV3PermissionRuntimeLifecycleApplication {
        let sequence = explicitSequence ?? takeSequence()
        let beforePermission = permissionStore.exportSnapshot().summary
        let beforeActiveTab = activeTabStore.exportSnapshot().summary
        let expiry = activeTabStore.expiringForExplicitReset(
            sequence: sequence
        )
        activeTabStore = expiry.store
        let event = ChromeMV3PermissionLifecycleEvent(
            kind: .permissionRevoked,
            extensionID: namespace.extensionID,
            profileID: namespace.profileID,
            permission: "activeTab",
            sequence: sequence
        )
        let lifecycleResult = ChromeMV3PermissionLifecycleEventResult(
            event: event,
            grantsExpired: expiry.expired,
            grantsRetained: expiry.retained,
            permissionStoreSummary:
                permissionStore.exportSnapshot().summary,
            activeTabStoreSummary:
                activeTabStore.exportSnapshot().summary,
            readinessImpact: [
                "activeTab grants were explicitly reset in internal runtime state.",
                "runtimeLoadable remains false.",
            ],
            diagnostics: [
                "Explicit activeTab reset expired matching internal grants.",
            ]
        )
        let newEvents = expiry.expired.map { record in
            makeEvent(
                sequence: record.grant.expiryRecord?.sequence ?? sequence,
                eventKind: .activeTabExpired,
                source: "activeTab.explicitReset",
                tabID: record.grant.tabID,
                activeTabGrantID: record.id,
                activeTabExpiryCause: record.grant.expiryRecord?.trigger,
                diagnostics: record.grant.diagnostics
            )
        }
        let diff = appendDiffIfChanged(
            sequence: sequence,
            operation: .resetActiveTab,
            beforePermission: beforePermission,
            beforeActiveTab: beforeActiveTab
        )
        appendEvents(newEvents)
        appendTransaction(
            sequence: sequence,
            operation: .resetActiveTab,
            returnedBoolean: expiry.expired.isEmpty == false,
            eventRecordIDs: newEvents.map(\.id),
            diffRecordID: diff?.id,
            diagnostics: lifecycleResult.diagnostics
        )
        return ChromeMV3PermissionRuntimeLifecycleApplication(
            lifecycleResult: lifecycleResult,
            permissionStore: permissionStore,
            activeTabStore: activeTabStore,
            eventRecords: newEvents,
            diffRecord: diff,
            diagnostics: lifecycleResult.diagnostics
        )
    }

    private mutating func takeSequence() -> Int {
        let value = nextSequence
        nextSequence += 1
        return value
    }

    private func makeEvent(
        sequence: Int,
        eventKind: ChromeMV3PermissionRuntimeEventKind,
        source: String,
        permissions: [String] = [],
        origins: [String] = [],
        tabID: Int? = nil,
        activeTabGrantID: String? = nil,
        activeTabExpiryCause: ChromeMV3ActiveTabExpiryTrigger? = nil,
        chromePermissionsEventPayload:
            ChromeMV3PermissionsAPIEventPayload? = nil,
        diagnostics: [String] = []
    ) -> ChromeMV3PermissionRuntimeEventRecord {
        ChromeMV3PermissionRuntimeEventRecord(
            sequence: sequence,
            eventKind: eventKind,
            source: source,
            namespace: namespace,
            permissions: permissions,
            origins: origins,
            tabID: tabID,
            activeTabGrantID: activeTabGrantID,
            activeTabExpiryCause: activeTabExpiryCause,
            chromePermissionsEventPayload: chromePermissionsEventPayload,
            wouldDispatchToJSNow: false,
            diagnostics: diagnostics
        )
    }

    private mutating func appendEvents(
        _ records: [ChromeMV3PermissionRuntimeEventRecord]
    ) {
        eventRecords = (eventRecords + records).sorted {
            if $0.sequence != $1.sequence {
                return $0.sequence < $1.sequence
            }
            return $0.id < $1.id
        }
    }

    private mutating func appendTransaction(
        sequence: Int,
        operation: ChromeMV3PermissionRuntimeOperationKind,
        permissions: [String] = [],
        origins: [String] = [],
        returnedBoolean: Bool? = nil,
        modeledPromptResult:
            ChromeMV3ModeledPermissionPromptResult? = nil,
        productPromptResult:
            ChromeMV3PermissionPromptResultDisposition? = nil,
        eventRecordIDs: [String] = [],
        diffRecordID: String? = nil,
        diagnostics: [String] = []
    ) {
        transactionRecords.append(
            ChromeMV3PermissionRuntimeTransactionRecord(
                sequence: sequence,
                operation: operation,
                namespace: namespace,
                permissions: permissions,
                origins: origins,
                returnedBoolean: returnedBoolean,
                modeledPromptResult: modeledPromptResult,
                productPromptResult: productPromptResult,
                eventRecordIDs: eventRecordIDs,
                diffRecordID: diffRecordID,
                diagnostics: diagnostics
            )
        )
        transactionRecords.sort {
            if $0.sequence != $1.sequence {
                return $0.sequence < $1.sequence
            }
            return $0.id < $1.id
        }
    }

    private mutating func appendDiffIfChanged(
        sequence: Int,
        operation: ChromeMV3PermissionRuntimeOperationKind,
        beforePermission:
            ChromeMV3PermissionDecisionStoreSnapshotSummary,
        beforeActiveTab:
            ChromeMV3ActiveTabGrantStoreSnapshotSummary
    ) -> ChromeMV3PermissionRuntimeDiffRecord? {
        let diff = ChromeMV3PermissionRuntimeDiffRecord(
            sequence: sequence,
            operation: operation,
            beforePermission: beforePermission,
            afterPermission: permissionStore.exportSnapshot().summary,
            beforeActiveTab: beforeActiveTab,
            afterActiveTab: activeTabStore.exportSnapshot().summary
        )
        guard diff.changed else { return nil }
        permissionDiffs.append(diff)
        permissionDiffs.sort {
            if $0.sequence != $1.sequence {
                return $0.sequence < $1.sequence
            }
            return $0.id < $1.id
        }
        return diff
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { $0.isEmpty == false })).sorted()
    }
}

extension ChromeMV3ActiveTabGrantStore {
    func expiringForExplicitReset(
        sequence: Int
    ) -> (
        store: ChromeMV3ActiveTabGrantStore,
        expired: [ChromeMV3ActiveTabGrantRecord],
        retained: [ChromeMV3ActiveTabGrantRecord]
    ) {
        expiringForRuntimeImplementation(
            trigger: .explicitReset,
            sequence: sequence,
            reason: "activeTab grants were explicitly reset.",
            shouldExpire: { $0.profileID == snapshot.profileID }
        )
    }

    private func expiringForRuntimeImplementation(
        trigger: ChromeMV3ActiveTabExpiryTrigger,
        sequence: Int,
        reason: String,
        shouldExpire: (ChromeMV3ActiveTabGrant) -> Bool
    ) -> (
        store: ChromeMV3ActiveTabGrantStore,
        expired: [ChromeMV3ActiveTabGrantRecord],
        retained: [ChromeMV3ActiveTabGrantRecord]
    ) {
        let before = snapshot.grantRecords
        let after = before.map { record -> ChromeMV3ActiveTabGrantRecord in
            guard record.grant.active,
                  record.grant.expiryTriggers.contains(trigger),
                  shouldExpire(record.grant)
            else { return record }
            return ChromeMV3ActiveTabGrantRecord(
                grant: record.grant.expiring(
                    trigger: trigger,
                    sequence: sequence,
                    reason: reason
                )
            )
        }
        let expired = zip(before, after).compactMap { old, new in
            old.grant.active && new.grant.active == false ? new : nil
        }
        let retained = after.filter { $0.grant.active }
        let diagnostics = expired.isEmpty
            ? ["No activeTab grants expired for \(trigger.rawValue)."]
            : expired.flatMap(\.grant.diagnostics)
        let store = ChromeMV3ActiveTabGrantStore(
            snapshot: ChromeMV3ActiveTabGrantStoreSnapshot(
                extensionID: snapshot.extensionID,
                profileID: snapshot.profileID,
                grantRecords: after,
                nextSequence: max(snapshot.nextSequence, sequence + 1),
                diagnostics: snapshot.diagnostics + diagnostics
            )
        )
        return (
            store,
            expired.sorted { $0.id < $1.id },
            retained.sorted { $0.id < $1.id }
        )
    }
}

private enum ChromeMV3PermissionRuntimeStableID {
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

struct ChromeMV3PermissionImplementationReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var permissionImplementationAvailableInInternalRuntime: Bool
    var permissionUIAvailableInProduct: Bool
    var activeTabAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var permissionRuntimeStateAvailable: Bool
    var permissionsModelHandlersAvailable: Bool
    var permissionsJSBridgeAvailableInSyntheticHarness: Bool
    var permissionsJSExecutedInWebKitSyntheticHarness: Bool
    var chromePermissionsRuntimeMutationsCovered: Bool
    var activeTabLifecycleCovered: Bool
    var tabsQueryPermissionCovered: Bool
    var tabsMessagingPermissionCovered: Bool
    var scriptingPermissionCovered: Bool
    var webKitSyntheticPermissionVerificationStatus: String
}

struct ChromeMV3PermissionImplementationReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var extensionID: String
    var profileID: String
    var permissionRuntimeSnapshot:
        ChromeMV3PermissionRuntimeStateOwnerSnapshot
    var permissionStateSummary:
        ChromeMV3PermissionDecisionStoreSnapshotSummary
    var activeTabStoreSummary:
        ChromeMV3ActiveTabGrantStoreSnapshotSummary
    var grantDenyRevokeTransactions:
        [ChromeMV3PermissionRuntimeTransactionRecord]
    var activeTabGrantResults: [ChromeMV3ActiveTabRuntimeGrantResult]
    var activeTabLifecycleResults:
        [ChromeMV3PermissionRuntimeLifecycleApplication]
    var permissionDiffs: [ChromeMV3PermissionRuntimeDiffRecord]
    var chromePermissionsContainsResults:
        [ChromeMV3PermissionsAPIContainsResult]
    var chromePermissionsGetAllResults:
        [ChromeMV3PermissionsAPIGetAllResult]
    var chromePermissionsRequestResults:
        [ChromeMV3PermissionRuntimeRequestApplication]
    var chromePermissionsRemoveResults:
        [ChromeMV3PermissionRuntimeRemoveApplication]
    var permissionsJSShimCoverage: ChromeMV3PermissionsJSShimCoverage
    var permissionsWebKitExecutionSummary:
        ChromeMV3PermissionsWebKitExecutionSummary
    var tabsQueryRedactionResults:
        [ChromeMV3SyntheticTabRedactionDecision]
    var tabsSendMessagePermissionResults:
        [ChromeMV3TabsScriptingJSBridgeHostResponse]
    var tabsConnectPermissionResults:
        [ChromeMV3TabsScriptingJSBridgeHostResponse]
    var scriptingExecuteScriptPermissionResults:
        [ChromeMV3TabsScriptingJSBridgeHostResponse]
    var webKitSyntheticTabsScriptingPermissionVerificationStatus: String
    var eventDiagnostics: [ChromeMV3PermissionRuntimeEventRecord]
    var permissionImplementationAvailableInInternalRuntime: Bool
    var permissionRuntimeStateAvailable: Bool
    var permissionsModelHandlersAvailable: Bool
    var permissionsJSBridgeAvailableInSyntheticHarness: Bool
    var permissionsJSExecutedInWebKitSyntheticHarness: Bool
    var permissionUIAvailableInProduct: Bool
    var activeTabAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var serviceWorkerWakeAvailable: Bool
    var nativeMessagingAvailable: Bool
    var productRuntimeExposed: Bool
    var documentationSources: [ChromeMV3ManifestRewritePreviewSource]
    var diagnostics: [String]

    var summary: ChromeMV3PermissionImplementationReportSummary {
        ChromeMV3PermissionImplementationReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            permissionImplementationAvailableInInternalRuntime:
                permissionImplementationAvailableInInternalRuntime,
            permissionUIAvailableInProduct: false,
            activeTabAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            permissionRuntimeStateAvailable: true,
            permissionsModelHandlersAvailable: true,
            permissionsJSBridgeAvailableInSyntheticHarness:
                permissionsJSBridgeAvailableInSyntheticHarness,
            permissionsJSExecutedInWebKitSyntheticHarness:
                permissionsWebKitExecutionSummary
                .permissionsJSExecutedInWebKitSyntheticHarness,
            chromePermissionsRuntimeMutationsCovered:
                chromePermissionsRequestResults.contains {
                    $0.returnedBoolean
                        && $0.permissionStore.exportSnapshot().summary
                        .grantedOptionalHostPermissions.isEmpty == false
                }
                && chromePermissionsRemoveResults.contains {
                    $0.returnedBoolean
                },
            activeTabLifecycleCovered:
                activeTabGrantResults.contains { $0.granted }
                    && activeTabLifecycleResults.contains {
                        $0.eventRecords.isEmpty == false
                    },
            tabsQueryPermissionCovered:
                tabsQueryRedactionResults.contains {
                    $0.status == .redactedNoPermission
                }
                && tabsQueryRedactionResults.contains {
                    $0.status == .exposedByHostPermission
                        || $0.status == .exposedByActiveTab
                },
            tabsMessagingPermissionCovered:
                tabsSendMessagePermissionResults.contains { $0.succeeded }
                    && tabsSendMessagePermissionResults.contains {
                        $0.lastErrorCode
                            == ChromeMV3RuntimeLastErrorCase
                            .activeTabMissing.rawValue
                            || $0.lastErrorCode
                            == ChromeMV3RuntimeLastErrorCase
                            .hostPermissionMissing.rawValue
                    },
            scriptingPermissionCovered:
                scriptingExecuteScriptPermissionResults.contains {
                    $0.succeeded
                }
                    && scriptingExecuteScriptPermissionResults.contains {
                        $0.lastErrorCode
                            == ChromeMV3RuntimeLastErrorCase
                            .permissionDenied.rawValue
                            || $0.lastErrorCode
                            == ChromeMV3RuntimeLastErrorCase
                            .activeTabMissing.rawValue
                    },
            webKitSyntheticPermissionVerificationStatus:
                webKitSyntheticTabsScriptingPermissionVerificationStatus
        )
    }
}

enum ChromeMV3PermissionImplementationReportWriter {
    static let reportFileName =
        "runtime-permission-implementation-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3PermissionImplementationReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3PermissionImplementationReport {
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

enum ChromeMV3PermissionImplementationReportGenerator {
    static func makeReport(
        extensionID: String = "permission-runtime-fixture-extension",
        profileID: String = "permission-runtime-fixture-profile",
        webKitSyntheticPermissionVerificationStatus: String =
            "notRunBySynchronousPermissionImplementationReport",
        permissionsWebKitExecutionSummary:
            ChromeMV3PermissionsWebKitExecutionSummary? = nil
    ) -> ChromeMV3PermissionImplementationReport {
        let configuration =
            ChromeMV3TabsScriptingJSBridgeConfiguration.syntheticHarness(
                extensionID: extensionID,
                profileID: profileID
            )
        let permissionsConfiguration =
            ChromeMV3PermissionsJSBridgeConfiguration.syntheticHarness(
                extensionID: extensionID,
                profileID: profileID
            )
        var owner = ChromeMV3PermissionRuntimeStateOwner(
            permissionStore:
                ChromeMV3PermissionDecisionStore(
                    snapshot:
                        ChromeMV3PermissionDecisionStoreSnapshot(
                            extensionID: extensionID,
                            profileID: profileID,
                            declaredAPIPermissions: [
                                "activeTab",
                                "scripting",
                                "tabs",
                            ],
                            declaredHostPermissions: [],
                            optionalAPIPermissions: ["history"],
                            optionalHostPermissions: [
                                "https://example.com/*",
                            ]
                        )
                )
        )
        let originInput = ChromeMV3PermissionsAPIRequestInput(
            extensionID: extensionID,
            profileID: profileID,
            sourceContext: .actionPopup,
            userGestureModeled: true,
            origins: ["https://example.com/"]
        )
        let containsBefore = owner.contains(input: originInput)
        let promptUnavailable = owner.request(
            input: originInput,
            modeledPromptResult: .notProvided
        )
        let accepted = owner.request(
            input: originInput,
            modeledPromptResult: .accepted
        )
        let getAllAfterGrant = owner.getAll()
        let registryAfterGrant =
            ChromeMV3SyntheticTabRegistry.passwordManagerFixture(
                extensionID: extensionID,
                profileID: profileID,
                includeProductNormalTab: true
            )
        let handlerAfterGrant = ChromeMV3TabsScriptingJSBridgeHandler(
            configuration: configuration,
            tabRegistry: registryAfterGrant,
            permissionRuntimeOwner: owner
        )
        let queryAfterGrant = handlerAfterGrant.handle(
            request(
                namespace: "tabs",
                methodName: "query",
                invocationMode: .promise,
                arguments: [.object(["active": .bool(true)])]
            )
        )
        let sendAfterGrant = handlerAfterGrant.handle(
            request(
                namespace: "tabs",
                methodName: "sendMessage",
                invocationMode: .promise,
                arguments: [
                    .number(1),
                    .object(["type": .string("permission-report")]),
                    .object(["frameId": .number(0)]),
                ]
            )
        )
        let connectAfterGrant = handlerAfterGrant.handle(
            request(
                namespace: "tabs",
                methodName: "connect",
                invocationMode: .fireAndForget,
                arguments: [
                    .number(1),
                    .object(["name": .string("permission-report")]),
                ]
            )
        )
        let executeAfterGrant = handlerAfterGrant.handle(
            executeScriptRequest(tabID: 1, invocationMode: .promise)
        )
        let productBlocked = handlerAfterGrant.handle(
            executeScriptRequest(tabID: 99, invocationMode: .promise)
        )

        let removed = owner.remove(input: originInput)
        let registryAfterRemove =
            ChromeMV3SyntheticTabRegistry.passwordManagerFixture(
                extensionID: extensionID,
                profileID: profileID
            )
        let handlerAfterRemove = ChromeMV3TabsScriptingJSBridgeHandler(
            configuration: configuration,
            tabRegistry: registryAfterRemove,
            permissionRuntimeOwner: owner
        )
        let queryAfterRemove = handlerAfterRemove.handle(
            request(
                namespace: "tabs",
                methodName: "query",
                invocationMode: .promise,
                arguments: [.object(["active": .bool(true)])]
            )
        )
        let sendAfterRemove = handlerAfterRemove.handle(
            request(
                namespace: "tabs",
                methodName: "sendMessage",
                invocationMode: .promise,
                arguments: [
                    .number(1),
                    .object(["type": .string("after-remove")]),
                ]
            )
        )
        let executeAfterRemove = handlerAfterRemove.handle(
            executeScriptRequest(tabID: 1, invocationMode: .promise)
        )

        var activeTabOwner = ChromeMV3PermissionRuntimeStateOwner(
            permissionStore:
                ChromeMV3PermissionDecisionStore(
                    snapshot:
                        ChromeMV3PermissionDecisionStoreSnapshot(
                            extensionID: extensionID,
                            profileID: profileID,
                            declaredAPIPermissions: [
                                "activeTab",
                                "scripting",
                            ],
                            declaredHostPermissions: []
                        )
                )
        )
        let activeGrant = activeTabOwner.grantActiveTabFromGesture(
            ChromeMV3ActiveTabGestureEvent(
                extensionID: extensionID,
                profileID: profileID,
                tabID: 1,
                url: "https://example.com/login",
                reason: .testFixture,
                userGestureModeled: true,
                sequence: 20
            )
        )
        let activeHandler = ChromeMV3TabsScriptingJSBridgeHandler(
            configuration: configuration,
            tabRegistry:
                ChromeMV3SyntheticTabRegistry.passwordManagerFixture(
                    extensionID: extensionID,
                    profileID: profileID
                ),
            permissionRuntimeOwner: activeTabOwner
        )
        let queryActiveTab = activeHandler.handle(
            request(
                namespace: "tabs",
                methodName: "query",
                invocationMode: .promise,
                arguments: [.object(["active": .bool(true)])]
            )
        )
        let sendActiveTab = activeHandler.handle(
            request(
                namespace: "tabs",
                methodName: "sendMessage",
                invocationMode: .promise,
                arguments: [
                    .number(1),
                    .object(["type": .string("active-tab")]),
                ]
            )
        )
        let connectActiveTab = activeHandler.handle(
            request(
                namespace: "tabs",
                methodName: "connect",
                invocationMode: .fireAndForget,
                arguments: [.number(1), .object([:])]
            )
        )
        let executeActiveTab = activeHandler.handle(
            executeScriptRequest(tabID: 1, invocationMode: .promise)
        )
        let expired = activeTabOwner.applyLifecycleEvent(
            ChromeMV3PermissionLifecycleEvent(
                kind: .tabNavigated,
                extensionID: extensionID,
                profileID: profileID,
                tabID: 1,
                oldURL: "https://example.com/login",
                newURL: "https://chromium.org/",
                sequence: 21
            )
        )
        let expiredHandler = ChromeMV3TabsScriptingJSBridgeHandler(
            configuration: configuration,
            tabRegistry:
                ChromeMV3SyntheticTabRegistry.passwordManagerFixture(
                    extensionID: extensionID,
                    profileID: profileID
                ),
            permissionRuntimeOwner: activeTabOwner
        )
        let sendExpiredActiveTab = expiredHandler.handle(
            request(
                namespace: "tabs",
                methodName: "sendMessage",
                invocationMode: .promise,
                arguments: [
                    .number(1),
                    .object(["type": .string("expired")]),
                ]
            )
        )

        var deniedOwner = ChromeMV3PermissionRuntimeStateOwner(
            permissionStore:
                ChromeMV3PermissionDecisionStore(
                    snapshot:
                        ChromeMV3PermissionDecisionStoreSnapshot(
                            extensionID: extensionID,
                            profileID: profileID,
                            declaredAPIPermissions: ["activeTab"],
                            optionalAPIPermissions: ["history"]
                        )
                )
        )
        let denied = deniedOwner.request(
            input:
                ChromeMV3PermissionsAPIRequestInput(
                    extensionID: extensionID,
                    profileID: profileID,
                    sourceContext: .actionPopup,
                    userGestureModeled: true,
                    permissions: ["history"]
                ),
            modeledPromptResult: .denied
        )
        let missingScriptingHandler = ChromeMV3TabsScriptingJSBridgeHandler(
            configuration: configuration,
            permissionBroker:
                ChromeMV3TabsScriptingPermissionFixtures.hostOnly(
                    extensionID: extensionID,
                    profileID: profileID
                )
        )
        let missingScripting = missingScriptingHandler.handle(
            executeScriptRequest(tabID: 1, invocationMode: .promise)
        )

        let redactions =
            redactionDecisions(from: [
                queryAfterGrant,
                queryAfterRemove,
                queryActiveTab,
            ])
        let finalSnapshot = owner.snapshot
        let chromeRequests = [promptUnavailable, accepted, denied]
        let chromeRemoves = [removed]
        let allEvents = owner.eventRecords + activeTabOwner.eventRecords
            + deniedOwner.eventRecords
        let allTransactions = owner.transactionRecords
            + activeTabOwner.transactionRecords
            + deniedOwner.transactionRecords
        let allDiffs = owner.permissionDiffs + activeTabOwner.permissionDiffs
            + deniedOwner.permissionDiffs
        let resolvedPermissionsWebKitExecutionSummary =
            permissionsWebKitExecutionSummary
            ?? ChromeMV3PermissionsWebKitExecutionSummary.notAttempted(
                permissionRuntimeStateAvailable: true,
                permissionsModelHandlersAvailable: true,
                permissionsJSBridgeAvailableInSyntheticHarness:
                    permissionsConfiguration
                    .permissionsJSBridgeAvailableInSyntheticHarness
            )
        let reportID = ChromeMV3PermissionRuntimeStableID.make(
            prefix: "runtime-permission-implementation",
            parts: [
                extensionID,
                profileID,
                finalSnapshot.permissionStore.storeID,
                finalSnapshot.activeTabStore.storeID,
                allTransactions.map(\.id).joined(separator: ","),
                webKitSyntheticPermissionVerificationStatus,
                resolvedPermissionsWebKitExecutionSummary.status,
            ]
        )

        return ChromeMV3PermissionImplementationReport(
            schemaVersion: 1,
            id: reportID,
            reportFileName:
                ChromeMV3PermissionImplementationReportWriter.reportFileName,
            extensionID: extensionID,
            profileID: profileID,
            permissionRuntimeSnapshot: finalSnapshot,
            permissionStateSummary: finalSnapshot.permissionStore.summary,
            activeTabStoreSummary: finalSnapshot.activeTabStore.summary,
            grantDenyRevokeTransactions:
                allTransactions.sorted {
                    if $0.sequence != $1.sequence {
                        return $0.sequence < $1.sequence
                    }
                    return $0.id < $1.id
                },
            activeTabGrantResults: [activeGrant],
            activeTabLifecycleResults: [expired],
            permissionDiffs:
                allDiffs.sorted {
                    if $0.sequence != $1.sequence {
                        return $0.sequence < $1.sequence
                    }
                    return $0.id < $1.id
                },
            chromePermissionsContainsResults: [containsBefore],
            chromePermissionsGetAllResults: [getAllAfterGrant],
            chromePermissionsRequestResults: chromeRequests,
            chromePermissionsRemoveResults: chromeRemoves,
            permissionsJSShimCoverage:
                ChromeMV3PermissionsJSShimSource.coverage,
            permissionsWebKitExecutionSummary:
                resolvedPermissionsWebKitExecutionSummary,
            tabsQueryRedactionResults: redactions,
            tabsSendMessagePermissionResults: [
                sendAfterGrant,
                sendAfterRemove,
                sendActiveTab,
                sendExpiredActiveTab,
            ],
            tabsConnectPermissionResults: [
                connectAfterGrant,
                connectActiveTab,
            ],
            scriptingExecuteScriptPermissionResults: [
                executeAfterGrant,
                executeAfterRemove,
                executeActiveTab,
                missingScripting,
                productBlocked,
            ],
            webKitSyntheticTabsScriptingPermissionVerificationStatus:
                webKitSyntheticPermissionVerificationStatus,
            eventDiagnostics:
                allEvents.sorted {
                    if $0.sequence != $1.sequence {
                        return $0.sequence < $1.sequence
                    }
                    return $0.id < $1.id
                },
            permissionImplementationAvailableInInternalRuntime: true,
            permissionRuntimeStateAvailable: true,
            permissionsModelHandlersAvailable: true,
            permissionsJSBridgeAvailableInSyntheticHarness:
                permissionsConfiguration
                .permissionsJSBridgeAvailableInSyntheticHarness,
            permissionsJSExecutedInWebKitSyntheticHarness:
                resolvedPermissionsWebKitExecutionSummary
                .permissionsJSExecutedInWebKitSyntheticHarness,
            permissionUIAvailableInProduct: false,
            activeTabAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            serviceWorkerWakeAvailable: false,
            nativeMessagingAvailable: false,
            productRuntimeExposed: false,
            documentationSources: documentationSources(),
            diagnostics: [
                "Internal permission runtime state owner executed contains/getAll/request/remove against deterministic state.",
                "permissionsJSExecutedInWebKitSyntheticHarness is tracked separately from model handler coverage.",
                "tabs.query, tabs.sendMessage, tabs.connect, and scripting.executeScript were evaluated against updated permission state.",
                "activeTab grants were created from a modeled user gesture and expired through lifecycle state.",
                "Product permission UI, product activeTab, product normal-tab runtime, service-worker wake, native messaging, and runtime loadability remain unavailable.",
            ]
        )
    }

    static func makeReport(
        loadingPrerequisitesReportFrom rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> ChromeMV3PermissionImplementationReport {
        let rootURL = rootURL.standardizedFileURL
        let prerequisitesURL = rootURL.appendingPathComponent(
            ChromeMV3RuntimeBridgePrerequisitesReportWriter.reportFileName
        )
        let extensionID: String
        if fileManager.fileExists(atPath: prerequisitesURL.path),
           let data = try? Data(contentsOf: prerequisitesURL),
           let prerequisites = try? JSONDecoder().decode(
            ChromeMV3RuntimeBridgePrerequisitesReport.self,
            from: data
           )
        {
            extensionID = prerequisites.candidateID
        } else {
            extensionID = "permission-runtime-fixture-extension"
        }
        return makeReport(extensionID: extensionID)
    }

    private static func request(
        namespace: String,
        methodName: String,
        invocationMode: ChromeMV3JSBridgeInvocationMode,
        arguments: [ChromeMV3StorageValue] = []
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID:
                ChromeMV3PermissionRuntimeStableID.make(
                    prefix: "permission-runtime-report-call",
                    parts: [
                        namespace,
                        methodName,
                        invocationMode.rawValue,
                        arguments.map {
                            (try? $0.canonicalJSONString()) ?? "argument"
                        }.joined(separator: "|"),
                    ]
                ),
            namespace: namespace,
            methodName: methodName,
            invocationMode: invocationMode,
            arguments: arguments,
            listenerID: nil,
            eventName: nil,
            portID: nil,
            diagnostics: []
        )
    }

    private static func executeScriptRequest(
        tabID: Int,
        invocationMode: ChromeMV3JSBridgeInvocationMode
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        request(
            namespace: "scripting",
            methodName: "executeScript",
            invocationMode: invocationMode,
            arguments: [
                .object([
                    "target": .object([
                        "tabId": .number(Double(tabID)),
                        "frameIds": .array([.number(0)]),
                    ]),
                    "functionSource": .string(
                        "function getTitle() { return document.title; }"
                    ),
                    "args": .array([]),
                ]),
            ]
        )
    }

    private static func redactionDecisions(
        from responses: [ChromeMV3TabsScriptingJSBridgeHostResponse]
    ) -> [ChromeMV3SyntheticTabRedactionDecision] {
        responses.compactMap { response in
            guard case .array(let values)? = response.resultPayload,
                  let first = values.first,
                  let tabID = first.objectValue?["id"]?.intValue
            else { return nil }
            let urlVisible = first.objectValue?["url"]?.stringValue != nil
            let titleVisible = first.objectValue?["title"]?.stringValue != nil
            let status: ChromeMV3SyntheticTabRedactionStatus =
                urlVisible || titleVisible
                    ? response.diagnostics.contains {
                        $0.contains("exposedByActiveTab")
                    } ? .exposedByActiveTab : .exposedByHostPermission
                    : .redactedNoPermission
            return ChromeMV3SyntheticTabRedactionDecision(
                tabID: tabID,
                status: status,
                urlVisible: urlVisible,
                titleVisible: titleVisible,
                hostAccessDecision:
                    ChromeMV3HostAccessDecision(
                        url: first.objectValue?["url"]?.stringValue,
                        origin:
                            ChromeMV3PermissionBrokerURL.origin(
                                from: first.objectValue?["url"]?.stringValue
                            ),
                        status:
                            urlVisible ? .allowed : .blocked,
                        grantSource:
                            status == .exposedByActiveTab
                                ? .activeTabGrant
                                : status == .exposedByHostPermission
                                    ? .optionalHostPermissionModeledGrant
                                    : .none,
                        hasHostAccess: urlVisible || titleVisible,
                        allowedByHostPermission:
                            status == .exposedByHostPermission,
                        allowedByOptionalHostPermission:
                            status == .exposedByHostPermission,
                        allowedByActiveTab:
                            status == .exposedByActiveTab,
                        matchingHostPatterns: [],
                        optionalHostPatternsThatCouldPrompt: [],
                        invalidHostPatterns: [],
                        unsupportedHostPatterns: [],
                        deniedByPattern: false,
                        revokedByPattern: false,
                        wouldNeedPrompt: false,
                        missingReason:
                            urlVisible ? .none : .hostPermissionMissing,
                        diagnostics: response.diagnostics
                    ),
                diagnostics: response.diagnostics
            )
        }
        .sorted {
            if $0.tabID != $1.tabID {
                return $0.tabID < $1.tabID
            }
            return $0.status < $1.status
        }
    }

    private static func documentationSources()
        -> [ChromeMV3ManifestRewritePreviewSource]
    {
        [
            source(
                title: "Chrome permissions API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/permissions",
                note: "Defines contains, getAll, request, remove, and onAdded/onRemoved."
            ),
            source(
                title: "Chrome runtime API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/runtime",
                note: "Defines runtime.lastError and callback/Promise runtime API behavior used by the synthetic permissions shim."
            ),
            source(
                title: "Chrome declare permissions",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/declare-permissions",
                note: "Defines required, optional, host, and optional host permission declarations."
            ),
            source(
                title: "Chrome tabs API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/tabs",
                note: "Defines tab URL/title sensitivity, tabs permission, host permission, and activeTab relationships."
            ),
            source(
                title: "Chrome scripting API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/scripting",
                note: "Defines scripting permission plus host permission or activeTab for executeScript."
            ),
            source(
                title: "Chrome activeTab",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/activeTab",
                note: "Defines user-gesture temporary host access and revocation on navigation or tab close."
            ),
            ChromeMV3ManifestRewritePreviewSource(
                kind: .currentSumiCode,
                title: "Local WebKit SDK headers",
                url: nil,
                note: "MacOSX WebKit headers document WKUserScript, WKScriptMessageHandlerWithReply, WKContentWorld, WKWebViewConfiguration, and callAsyncJavaScript usage confined to the controlled synthetic harness."
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
}

private extension ChromeMV3StorageValue {
    var objectValue: [String: ChromeMV3StorageValue]? {
        guard case .object(let object) = self else { return nil }
        return object
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case .number(let value) = self else { return nil }
        return Int(value)
    }
}
