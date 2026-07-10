import Foundation

/// Page-level cold-fetch coalescing. Tasks capture only the resolution
/// pipeline, never this service or the runtime composition root strongly.
final class SumiFaviconColdFetchService: @unchecked Sendable {
    private struct ScheduledFetch {
        let token: UUID
        let partition: SumiFaviconPartition
        var task: Task<Void, Never>?
    }

    private let blobReader: SumiFaviconBlobReader
    private let resolutionPipeline: SumiFaviconCandidateResolutionPipeline
    private let fetchScheduler: SumiFaviconFetchScheduler
    private let queue = DispatchQueue(label: "SumiFaviconColdFetchService")
    private var scheduledByPageKey: [String: ScheduledFetch] = [:]

    init(
        blobReader: SumiFaviconBlobReader,
        resolutionPipeline: SumiFaviconCandidateResolutionPipeline,
        fetchScheduler: SumiFaviconFetchScheduler
    ) {
        self.blobReader = blobReader
        self.resolutionPipeline = resolutionPipeline
        self.fetchScheduler = fetchScheduler
    }

    deinit {
        cancelAll()
    }

    func schedule(
        pageURL: URL,
        partition: SumiFaviconPartition,
        priority: SumiFaviconFetchPriority
    ) {
        guard pageURL.sumiIsHTTPOrHTTPS else { return }
        guard !blobReader.isNoIconFresh(for: pageURL, partition: partition) else {
            return
        }

        let key = "\(partition.storageComponent)|\(pageURL.sumiFaviconPageKey)"
        let token = UUID()
        let shouldSchedule = queue.sync { () -> Bool in
            guard scheduledByPageKey[key] == nil else { return false }
            scheduledByPageKey[key] = ScheduledFetch(
                token: token,
                partition: partition,
                task: nil
            )
            return true
        }
        guard shouldSchedule else { return }

        let pipeline = resolutionPipeline
        let task = Task(priority: Self.taskPriority(for: priority)) { [weak self] in
            defer {
                self?.finish(pageKey: key, token: token)
            }
            guard !Task.isCancelled else { return }
            _ = await pipeline.resolve(
                SumiFaviconDiscovery.rootFallbackCandidates(
                    for: pageURL,
                    partition: partition
                ),
                pageURL: pageURL,
                fetchContext: .publicRootFallback,
                priority: priority
            )
        }

        let shouldCancel = queue.sync { () -> Bool in
            guard var scheduled = scheduledByPageKey[key],
                  scheduled.token == token
            else {
                return true
            }
            scheduled.task = task
            scheduledByPageKey[key] = scheduled
            return false
        }
        if shouldCancel {
            task.cancel()
        }
    }

    func cancel(partition: SumiFaviconPartition) {
        let tasks = queue.sync { () -> [Task<Void, Never>] in
            scheduledByPageKey.values
                .filter { $0.partition == partition }
                .compactMap(\.task)
        }
        tasks.forEach { $0.cancel() }
        let fetchScheduler = fetchScheduler
        Task {
            await fetchScheduler.cancel(partition: partition)
        }
    }

    func cancelAll() {
        let tasks = queue.sync { () -> [Task<Void, Never>] in
            scheduledByPageKey.values.compactMap(\.task)
        }
        tasks.forEach { $0.cancel() }
        let fetchScheduler = fetchScheduler
        Task {
            await fetchScheduler.cancelAll()
        }
    }

    #if DEBUG
        func drainForTests(cancel: Bool = true) async {
            while true {
                let tasks = queue.sync { () -> [Task<Void, Never>] in
                    let tasks = scheduledByPageKey.values.compactMap(\.task)
                    if cancel {
                        scheduledByPageKey.removeAll()
                    }
                    return tasks
                }
                if cancel {
                    tasks.forEach { $0.cancel() }
                    await fetchScheduler.cancelAll()
                }
                guard !tasks.isEmpty else { break }
                for task in tasks {
                    await task.value
                }
            }
            await fetchScheduler.drainForTests(cancel: cancel)
        }
    #endif

    private func finish(pageKey: String, token: UUID) {
        queue.sync {
            guard scheduledByPageKey[pageKey]?.token == token else { return }
            scheduledByPageKey.removeValue(forKey: pageKey)
        }
    }

    private static func taskPriority(
        for priority: SumiFaviconFetchPriority
    ) -> TaskPriority {
        switch priority {
        case .visibleActiveTab:
            return .userInitiated
        case .visibleSidebarOrTabStrip, .pinnedLauncher, .historyBookmarkVisibleRow:
            return .utility
        case .backgroundPrefetch, .staleRefresh:
            return .background
        }
    }
}

private extension URL {
    var sumiIsHTTPOrHTTPS: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    var sumiFaviconPageKey: String {
        SumiFaviconCanonicalURL.pageKey(for: self)
    }
}
