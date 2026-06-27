import Foundation

struct SumiPendingAuthorizationQuery: Sendable {
    let query: SumiPermissionAuthorizationQuery
    let primaryRequestId: String
    let tabId: String?
    var requestIds: Set<String>
    let keys: [SumiPermissionKey]
}

struct SumiPendingAuthorizationQueryIndex {
    typealias DecisionContinuation = CheckedContinuation<SumiPermissionCoordinatorDecision, Never>

    private var continuationByRequestId: [String: DecisionContinuation] = [:]
    private var queryById: [String: SumiPendingAuthorizationQuery] = [:]
    private var queryIdByRequestId: [String: String] = [:]
    private(set) var activeQueriesByPageId: [String: SumiPermissionAuthorizationQuery] = [:]

    func pending(queryId: String) -> SumiPendingAuthorizationQuery? {
        queryById[queryId]
    }

    func activeQuery(forPageId pageId: String) -> SumiPermissionAuthorizationQuery? {
        activeQueriesByPageId[Self.normalizedPageId(pageId)]
    }

    func isActive(queryId: String, pageId: String) -> Bool {
        activeQueriesByPageId[Self.normalizedPageId(pageId)]?.id == queryId
    }

    func query(forRequestId requestId: String) -> SumiPermissionAuthorizationQuery? {
        guard let queryId = queryIdByRequestId[requestId] else { return nil }
        return queryById[queryId]?.query
    }

    func pendingQueries(forRequestIds requestIds: [String]) -> [SumiPendingAuthorizationQuery] {
        let queryIds = Set(requestIds.compactMap { queryIdByRequestId[$0] })
        return queryIds.compactMap { queryById[$0] }
    }

    func primaryRequestIds(matching isIncluded: (SumiPendingAuthorizationQuery) -> Bool) -> [String] {
        queryById.values
            .filter(isIncluded)
            .map(\.primaryRequestId)
    }

    func pageIds(forRequestIds requestIds: [String]) -> Set<String> {
        var pageIds: Set<String> = []
        for requestId in requestIds {
            guard let queryId = queryIdByRequestId[requestId],
                  let query = queryById[queryId]?.query
            else {
                continue
            }
            pageIds.insert(query.pageId)
        }
        return pageIds
    }

    mutating func storeNewPendingQuery(
        query: SumiPermissionAuthorizationQuery,
        entry: SumiPermissionQueueEntry,
        request: SumiPermissionRequest,
        continuation: DecisionContinuation,
        keys: [SumiPermissionKey]
    ) {
        let requestIds = Set(entry.allRequestIds)
        queryById[query.id] = SumiPendingAuthorizationQuery(
            query: query,
            primaryRequestId: entry.request.id,
            tabId: request.tabId,
            requestIds: requestIds,
            keys: keys
        )
        for requestId in requestIds {
            queryIdByRequestId[requestId] = query.id
        }
        continuationByRequestId[request.id] = continuation
    }

    mutating func activate(_ query: SumiPermissionAuthorizationQuery) {
        activeQueriesByPageId[Self.normalizedPageId(query.pageId)] = query
    }

    mutating func registerCoalesced(
        existing: SumiPermissionQueueEntry,
        requestId: String,
        continuation: DecisionContinuation
    ) -> String? {
        guard let existingQueryId = queryIdByRequestId[existing.request.id],
              var pending = queryById[existingQueryId]
        else {
            return nil
        }

        pending.requestIds.insert(requestId)
        queryById[existingQueryId] = pending
        queryIdByRequestId[requestId] = existingQueryId
        continuationByRequestId[requestId] = continuation
        return existingQueryId
    }

    mutating func resolveCancelledRequestIds(_ requestIds: [String]) -> [DecisionContinuation] {
        var continuations: [DecisionContinuation] = []
        var touchedQueryIds: Set<String> = []

        for requestId in requestIds {
            if let continuation = continuationByRequestId.removeValue(forKey: requestId) {
                continuations.append(continuation)
            }
            guard let queryId = queryIdByRequestId.removeValue(forKey: requestId),
                  var pending = queryById[queryId]
            else {
                continue
            }
            pending.requestIds.remove(requestId)
            touchedQueryIds.insert(queryId)
            if pending.requestIds.isEmpty {
                queryById.removeValue(forKey: queryId)
            } else {
                queryById[queryId] = pending
            }
        }

        for queryId in touchedQueryIds {
            guard queryById[queryId] == nil else { continue }
            if let pageId = activeQueriesByPageId.first(where: { $0.value.id == queryId })?.key {
                activeQueriesByPageId.removeValue(forKey: pageId)
            }
        }

        return continuations
    }

    mutating func takeContinuations(for requestIds: Set<String>) -> [DecisionContinuation] {
        var continuations: [DecisionContinuation] = []
        for requestId in requestIds {
            if let continuation = continuationByRequestId.removeValue(forKey: requestId) {
                continuations.append(continuation)
            }
        }
        return continuations
    }

    mutating func remove(_ pending: SumiPendingAuthorizationQuery) {
        queryById.removeValue(forKey: pending.query.id)
        for requestId in pending.requestIds {
            queryIdByRequestId.removeValue(forKey: requestId)
        }
        activeQueriesByPageId.removeValue(forKey: Self.normalizedPageId(pending.query.pageId))
    }

    mutating func refreshActiveQuery(
        pageId: String,
        snapshot: SumiPermissionQueueSnapshot
    ) {
        let normalizedPageId = Self.normalizedPageId(pageId)
        if let active = snapshot.active,
           let queryId = queryIdByRequestId[active.request.id],
           let query = queryById[queryId]?.query
        {
            activeQueriesByPageId[normalizedPageId] = query
        } else {
            activeQueriesByPageId.removeValue(forKey: normalizedPageId)
        }
    }

    private static func normalizedPageId(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "global" : trimmed
    }
}
