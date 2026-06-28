import Foundation

enum SumiPermissionSiteDecisionError: Error, Equatable, LocalizedError {
    case unavailable
    case unsupportedPermission(String)
    case persistentStoreUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Site permission decisions are unavailable."
        case .unsupportedPermission(let permissionIdentity):
            return "Site permission decisions are unsupported for \(permissionIdentity)."
        case .persistentStoreUnavailable:
            return "Persistent site permission storage is unavailable."
        }
    }
}

protocol SumiPermissionCoordinating: Sendable {
    func requestPermission(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision

    func queryPermissionState(
        _ context: SumiPermissionSecurityContext
    ) async -> SumiPermissionCoordinatorDecision

    func siteDecisionRecords(
        profilePartitionId: String,
        isEphemeralProfile: Bool
    ) async throws -> [SumiPermissionStoreRecord]

    func transientDecisionRecords(
        profilePartitionId: String,
        pageId: String
    ) async throws -> [SumiPermissionStoreRecord]

    func setSiteDecision(
        for key: SumiPermissionKey,
        state: SumiPermissionState,
        source: SumiPermissionDecisionSource,
        reason: String?
    ) async throws

    func resetSiteDecision(
        for key: SumiPermissionKey
    ) async throws

    func resetSiteDecisions(
        for keys: [SumiPermissionKey]
    ) async throws

    @discardableResult
    func resetTransientDecisions(
        profilePartitionId: String,
        pageId: String?,
        requestingOrigin: SumiPermissionOrigin,
        topOrigin: SumiPermissionOrigin,
        reason: String
    ) async -> Int

    func activeQuery(forPageId pageId: String) async -> SumiPermissionAuthorizationQuery?

    func recordPromptShown(queryId: String) async

    func stateSnapshot() async -> SumiPermissionCoordinatorState

    func events() async -> AsyncStream<SumiPermissionCoordinatorEvent>

    @discardableResult
    func approveCurrentAttempt(_ queryId: String) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func approveOnce(_ queryId: String) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func approveForSession(_ queryId: String) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func approvePersistently(_ queryId: String) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func denyForSession(_ queryId: String) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func dismiss(_ queryId: String) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func denyPersistently(_ queryId: String) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func systemBlock(
        queryId: String,
        snapshots: [SumiSystemPermissionSnapshot],
        reason: String
    ) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func cancel(
        queryId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func cancel(
        requestId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func cancel(
        pageId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func cancelNavigation(
        pageId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func cancelTab(
        tabId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func cancelProfile(
        profilePartitionId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision

    @discardableResult
    func cancelSession(
        ownerId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision
}

extension SumiPermissionCoordinator: SumiPermissionCoordinating {}

extension SumiPermissionCoordinating {
    func siteDecisionRecords(
        profilePartitionId: String,
        isEphemeralProfile: Bool
    ) async throws -> [SumiPermissionStoreRecord] {
        _ = profilePartitionId
        _ = isEphemeralProfile
        throw SumiPermissionSiteDecisionError.unavailable
    }

    func transientDecisionRecords(
        profilePartitionId: String,
        pageId: String
    ) async throws -> [SumiPermissionStoreRecord] {
        _ = profilePartitionId
        _ = pageId
        return []
    }

    func setSiteDecision(
        for key: SumiPermissionKey,
        state: SumiPermissionState,
        source: SumiPermissionDecisionSource,
        reason: String?
    ) async throws {
        _ = key
        _ = state
        _ = source
        _ = reason
        throw SumiPermissionSiteDecisionError.unavailable
    }

    func resetSiteDecision(
        for key: SumiPermissionKey
    ) async throws {
        _ = key
        throw SumiPermissionSiteDecisionError.unavailable
    }

    func resetSiteDecisions(
        for keys: [SumiPermissionKey]
    ) async throws {
        for key in keys {
            try await resetSiteDecision(for: key)
        }
    }

    @discardableResult
    func resetTransientDecisions(
        profilePartitionId: String,
        pageId: String?,
        requestingOrigin: SumiPermissionOrigin,
        topOrigin: SumiPermissionOrigin,
        reason: String
    ) async -> Int {
        _ = profilePartitionId
        _ = pageId
        _ = requestingOrigin
        _ = topOrigin
        _ = reason
        return 0
    }

    func recordPromptShown(queryId: String) async {
        _ = queryId
    }

    @discardableResult
    func approveCurrentAttempt(_ queryId: String) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: "approve-current-attempt-unavailable")
    }

    @discardableResult
    func approveOnce(_ queryId: String) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: "approve-once-unavailable")
    }

    @discardableResult
    func approveForSession(_ queryId: String) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: "approve-for-session-unavailable")
    }

    @discardableResult
    func approvePersistently(_ queryId: String) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: "approve-persistently-unavailable")
    }

    @discardableResult
    func denyForSession(_ queryId: String) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: "deny-for-session-unavailable")
    }

    @discardableResult
    func dismiss(_ queryId: String) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: "dismiss-unavailable")
    }

    @discardableResult
    func denyPersistently(_ queryId: String) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: "deny-persistently-unavailable")
    }

    @discardableResult
    func systemBlock(
        queryId: String,
        snapshots: [SumiSystemPermissionSnapshot],
        reason: String
    ) async -> SumiPermissionCoordinatorDecision {
        _ = queryId
        _ = snapshots
        return ignoredSettlementDecision(reason: reason)
    }

    @discardableResult
    func cancel(
        queryId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: reason)
    }

    @discardableResult
    func cancel(
        requestId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: reason)
    }

    @discardableResult
    func cancel(
        pageId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: reason)
    }

    @discardableResult
    func cancelNavigation(
        pageId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: reason)
    }

    @discardableResult
    func cancelTab(
        tabId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: reason)
    }

    @discardableResult
    func cancelProfile(
        profilePartitionId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: reason)
    }

    @discardableResult
    func cancelSession(
        ownerId: String,
        reason: String
    ) async -> SumiPermissionCoordinatorDecision {
        ignoredSettlementDecision(reason: reason)
    }

    private func ignoredSettlementDecision(reason: String) -> SumiPermissionCoordinatorDecision {
        SumiPermissionCoordinatorDecision(
            outcome: .ignored,
            state: nil,
            persistence: nil,
            source: .runtime,
            reason: reason,
            permissionTypes: []
        )
    }
}
