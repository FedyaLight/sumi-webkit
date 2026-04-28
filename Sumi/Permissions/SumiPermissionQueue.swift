import Foundation

struct SumiPermissionQueueEntry: Equatable, Sendable {
    var request: SumiPermissionRequest
    private(set) var coalescedRequestIds: [String]

    init(request: SumiPermissionRequest, coalescedRequestIds: [String] = []) {
        self.request = request
        self.coalescedRequestIds = coalescedRequestIds
    }

    var allRequestIds: [String] {
        [request.id] + coalescedRequestIds
    }

    mutating func coalesce(requestId: String) {
        guard requestId != request.id, !coalescedRequestIds.contains(requestId) else {
            return
        }
        coalescedRequestIds.append(requestId)
    }

    mutating func removeCoalesced(requestId: String) -> Bool {
        guard let index = coalescedRequestIds.firstIndex(of: requestId) else {
            return false
        }
        coalescedRequestIds.remove(at: index)
        return true
    }
}

enum SumiPermissionQueueEnqueueResult: Equatable, Sendable {
    case activated(SumiPermissionQueueEntry)
    case queued(SumiPermissionQueueEntry, position: Int)
    case coalesced(existing: SumiPermissionQueueEntry)
}

struct SumiPermissionQueueCancellation: Equatable, Sendable {
    let cancelledRequestIds: [String]
    let promotedActive: SumiPermissionQueueEntry?
}

struct SumiPermissionQueueAdvance: Equatable, Sendable {
    let completedRequestIds: [String]
    let nextActive: SumiPermissionQueueEntry?
}

struct SumiPermissionQueueSnapshot: Equatable, Sendable {
    let active: SumiPermissionQueueEntry?
    let queued: [SumiPermissionQueueEntry]
}

actor SumiPermissionQueue {
    private struct PageQueue: Sendable {
        var active: SumiPermissionQueueEntry?
        var queued: [SumiPermissionQueueEntry] = []
    }

    private var queuesByPageId: [String: PageQueue] = [:]

    @discardableResult
    func enqueue(_ request: SumiPermissionRequest) -> SumiPermissionQueueEnqueueResult {
        let pageId = request.pageBucketId
        var pageQueue = queuesByPageId[pageId] ?? PageQueue()

        if var active = pageQueue.active,
           isDuplicate(request, of: active.request)
        {
            active.coalesce(requestId: request.id)
            pageQueue.active = active
            queuesByPageId[pageId] = pageQueue
            return .coalesced(existing: active)
        }

        if let queuedIndex = pageQueue.queued.firstIndex(where: { isDuplicate(request, of: $0.request) }) {
            var queuedEntry = pageQueue.queued[queuedIndex]
            queuedEntry.coalesce(requestId: request.id)
            pageQueue.queued[queuedIndex] = queuedEntry
            queuesByPageId[pageId] = pageQueue
            return .coalesced(existing: queuedEntry)
        }

        let entry = SumiPermissionQueueEntry(request: request)
        if pageQueue.active == nil {
            pageQueue.active = entry
            queuesByPageId[pageId] = pageQueue
            return .activated(entry)
        }

        pageQueue.queued.append(entry)
        queuesByPageId[pageId] = pageQueue
        return .queued(entry, position: pageQueue.queued.count)
    }

    func activeRequest(forPageId pageId: String) -> SumiPermissionQueueEntry? {
        queuesByPageId[normalizedPageId(pageId)]?.active
    }

    func queuedRequests(forPageId pageId: String) -> [SumiPermissionQueueEntry] {
        queuesByPageId[normalizedPageId(pageId)]?.queued ?? []
    }

    func snapshot(forPageId pageId: String) -> SumiPermissionQueueSnapshot {
        let pageQueue = queuesByPageId[normalizedPageId(pageId)] ?? PageQueue()
        return SumiPermissionQueueSnapshot(active: pageQueue.active, queued: pageQueue.queued)
    }

    @discardableResult
    func finishActiveRequest(pageId: String) -> SumiPermissionQueueAdvance {
        let pageId = normalizedPageId(pageId)
        guard var pageQueue = queuesByPageId[pageId],
              let active = pageQueue.active
        else {
            return SumiPermissionQueueAdvance(completedRequestIds: [], nextActive: nil)
        }

        let next = pageQueue.queued.isEmpty ? nil : pageQueue.queued.removeFirst()
        pageQueue.active = next
        store(pageQueue, forPageId: pageId)
        return SumiPermissionQueueAdvance(
            completedRequestIds: active.allRequestIds,
            nextActive: next
        )
    }

    @discardableResult
    func cancel(requestId: String) -> SumiPermissionQueueCancellation {
        let normalizedRequestId = requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRequestId.isEmpty else {
            return SumiPermissionQueueCancellation(cancelledRequestIds: [], promotedActive: nil)
        }

        for pageId in queuesByPageId.keys.sorted() {
            guard var pageQueue = queuesByPageId[pageId] else { continue }

            if var active = pageQueue.active {
                if active.request.id == normalizedRequestId {
                    let cancelledIds = active.allRequestIds
                    let promoted = pageQueue.queued.isEmpty ? nil : pageQueue.queued.removeFirst()
                    pageQueue.active = promoted
                    store(pageQueue, forPageId: pageId)
                    return SumiPermissionQueueCancellation(
                        cancelledRequestIds: cancelledIds,
                        promotedActive: promoted
                    )
                }
                if active.removeCoalesced(requestId: normalizedRequestId) {
                    pageQueue.active = active
                    store(pageQueue, forPageId: pageId)
                    return SumiPermissionQueueCancellation(
                        cancelledRequestIds: [normalizedRequestId],
                        promotedActive: nil
                    )
                }
            }

            for index in pageQueue.queued.indices {
                var entry = pageQueue.queued[index]
                if entry.request.id == normalizedRequestId {
                    let cancelledIds = entry.allRequestIds
                    pageQueue.queued.remove(at: index)
                    store(pageQueue, forPageId: pageId)
                    return SumiPermissionQueueCancellation(
                        cancelledRequestIds: cancelledIds,
                        promotedActive: nil
                    )
                }
                if entry.removeCoalesced(requestId: normalizedRequestId) {
                    pageQueue.queued[index] = entry
                    store(pageQueue, forPageId: pageId)
                    return SumiPermissionQueueCancellation(
                        cancelledRequestIds: [normalizedRequestId],
                        promotedActive: nil
                    )
                }
            }
        }

        return SumiPermissionQueueCancellation(cancelledRequestIds: [], promotedActive: nil)
    }

    @discardableResult
    func cancel(pageId: String) -> SumiPermissionQueueCancellation {
        let pageId = normalizedPageId(pageId)
        guard let pageQueue = queuesByPageId.removeValue(forKey: pageId) else {
            return SumiPermissionQueueCancellation(cancelledRequestIds: [], promotedActive: nil)
        }
        return SumiPermissionQueueCancellation(
            cancelledRequestIds: requestIds(in: pageQueue),
            promotedActive: nil
        )
    }

    @discardableResult
    func cancelNavigation(pageId: String) -> SumiPermissionQueueCancellation {
        cancel(pageId: pageId)
    }

    private func isDuplicate(
        _ request: SumiPermissionRequest,
        of existingRequest: SumiPermissionRequest
    ) -> Bool {
        request.pageBucketId == existingRequest.pageBucketId
            && request.queuePersistentIdentity == existingRequest.queuePersistentIdentity
    }

    private func requestIds(in pageQueue: PageQueue) -> [String] {
        var ids = pageQueue.active?.allRequestIds ?? []
        for entry in pageQueue.queued {
            ids.append(contentsOf: entry.allRequestIds)
        }
        return ids
    }

    private func store(_ pageQueue: PageQueue, forPageId pageId: String) {
        if pageQueue.active == nil && pageQueue.queued.isEmpty {
            queuesByPageId.removeValue(forKey: pageId)
        } else {
            queuesByPageId[pageId] = pageQueue
        }
    }

    private func normalizedPageId(_ pageId: String) -> String {
        let trimmed = pageId.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "global" : trimmed
    }
}
