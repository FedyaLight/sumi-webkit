import Foundation

enum SumiPermissionPendingQueryRegistrationResult {
    case activated(SumiPermissionAuthorizationQuery)
    case queued(SumiPermissionAuthorizationQuery, position: Int)
    case coalesced(queryId: String, requestId: String)
    case coalescedQueryMissing(
        continuation: SumiPermissionPendingQueryOwner.DecisionContinuation,
        permissionTypes: [SumiPermissionType]
    )
}

struct SumiPermissionPendingQueryOwner {
    typealias DecisionContinuation = SumiPendingAuthorizationQueryIndex.DecisionContinuation

    private var index = SumiPendingAuthorizationQueryIndex()
    private var queueCountByPageId: [String: Int] = [:]

    var activeQueriesByPageId: [String: SumiPermissionAuthorizationQuery] {
        index.activeQueriesByPageId
    }

    var queueCountsByPageId: [String: Int] {
        queueCountByPageId
    }

    func activeQuery(forPageId pageId: String) -> SumiPermissionAuthorizationQuery? {
        index.activeQuery(forPageId: pageId)
    }

    func pending(queryId: String) -> SumiPendingAuthorizationQuery? {
        index.pending(queryId: queryId)
    }

    func isActive(queryId: String, pageId: String) -> Bool {
        index.isActive(queryId: queryId, pageId: pageId)
    }

    func promotedQuery(from entry: SumiPermissionQueueEntry?) -> SumiPermissionAuthorizationQuery? {
        guard let entry else { return nil }
        return index.query(forRequestId: entry.request.id)
    }

    func primaryRequestIds(
        matching isIncluded: (SumiPendingAuthorizationQuery) -> Bool
    ) -> [String] {
        index.primaryRequestIds(matching: isIncluded)
    }

    func pageIds(forRequestIds requestIds: [String]) -> Set<String> {
        index.pageIds(forRequestIds: requestIds)
    }

    func pendingQueries(forRequestIds requestIds: [String]) -> [SumiPendingAuthorizationQuery] {
        index.pendingQueries(forRequestIds: requestIds)
    }

    mutating func register(
        _ continuation: DecisionContinuation,
        enqueueResult: SumiPermissionQueueEnqueueResult,
        query: SumiPermissionAuthorizationQuery,
        request: SumiPermissionRequest,
        keys: [SumiPermissionKey]
    ) -> SumiPermissionPendingQueryRegistrationResult {
        switch enqueueResult {
        case .activated(let entry):
            storeNewPendingQuery(
                query: query,
                entry: entry,
                request: request,
                continuation: continuation,
                keys: keys
            )
            index.activate(query)
            queueCountByPageId[normalizedPageId(query.pageId)] = 0
            return .activated(query)
        case .queued(let entry, let position):
            storeNewPendingQuery(
                query: query,
                entry: entry,
                request: request,
                continuation: continuation,
                keys: keys
            )
            queueCountByPageId[normalizedPageId(query.pageId)] = position
            return .queued(query, position: position)
        case .coalesced(let existing):
            guard let existingQueryId = index.registerCoalesced(
                existing: existing,
                requestId: request.id,
                continuation: continuation
            ) else {
                return .coalescedQueryMissing(
                    continuation: continuation,
                    permissionTypes: request.permissionTypes
                )
            }
            return .coalesced(queryId: existingQueryId, requestId: request.id)
        }
    }

    mutating func resolveCompletedActiveQuery(
        _ pending: SumiPendingAuthorizationQuery
    ) -> [DecisionContinuation] {
        let continuations = index.takeContinuations(for: pending.requestIds)
        index.remove(pending)
        return continuations
    }

    mutating func resolveCancelledRequestIds(_ requestIds: [String]) -> [DecisionContinuation] {
        index.resolveCancelledRequestIds(requestIds)
    }

    mutating func refreshActiveQuery(
        pageId: String,
        snapshot: SumiPermissionQueueSnapshot
    ) {
        let normalizedPageId = normalizedPageId(pageId)
        index.refreshActiveQuery(pageId: normalizedPageId, snapshot: snapshot)

        if snapshot.queued.isEmpty {
            queueCountByPageId.removeValue(forKey: normalizedPageId)
        } else {
            queueCountByPageId[normalizedPageId] = snapshot.queued.count
        }
    }

    private mutating func storeNewPendingQuery(
        query: SumiPermissionAuthorizationQuery,
        entry: SumiPermissionQueueEntry,
        request: SumiPermissionRequest,
        continuation: DecisionContinuation,
        keys: [SumiPermissionKey]
    ) {
        index.storeNewPendingQuery(
            query: query,
            entry: entry,
            request: request,
            continuation: continuation,
            keys: keys
        )
    }

    private func normalizedPageId(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "global" : trimmed
    }
}
