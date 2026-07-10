import Foundation

/// Coalesces identical fetches and owns their short-lived failure cache. The
/// limiter and network transports are separate capabilities.
actor SumiFaviconFetchScheduler {
    struct Configuration: Sendable {
        var globalConcurrencyLimit = 6
        var perOriginConcurrencyLimit = 2
    }

    private struct FetchKey: Hashable, Sendable {
        let partition: SumiFaviconPartition
        let url: URL
    }

    private struct ScheduledFetch {
        let token: UUID
        let task: Task<SumiFaviconFetchResult?, Never>
    }

    private struct CachedFailure {
        let kind: SumiFaviconValidationFailureKind
        let expiresAt: Date
    }

    private let fetcher: any SumiFaviconNetworkFetching
    private let limiter: SumiFaviconFetchLimiter
    private var inFlight: [FetchKey: ScheduledFetch] = [:]
    private var cachedFailureByKey: [FetchKey: CachedFailure] = [:]

    init(
        fetcher: any SumiFaviconNetworkFetching,
        configuration: Configuration = Configuration()
    ) {
        self.fetcher = fetcher
        limiter = SumiFaviconFetchLimiter(
            globalLimit: configuration.globalConcurrencyLimit,
            perOriginLimit: configuration.perOriginConcurrencyLimit
        )
    }

    func fetch(
        candidate: SumiFaviconCandidate,
        context: SumiFaviconFetchContext,
        priority: SumiFaviconFetchPriority,
        now: Date = Date()
    ) async -> SumiFaviconFetchResult {
        let key = FetchKey(partition: candidate.partition, url: candidate.iconURL)
        if let cachedFailure = cachedFailureByKey[key],
           cachedFailure.expiresAt > now {
            return .failure(cachedFailure.kind)
        }
        if let scheduledFetch = inFlight[key] {
            return await scheduledFetch.task.value ?? .cancelled
        }

        let origin = originKey(for: candidate.iconURL)
        let token = UUID()
        let task = Task<SumiFaviconFetchResult?, Never> { [fetcher, limiter] in
            let acquired = await limiter.acquire(
                partition: candidate.partition,
                origin: origin,
                priority: priority
            )
            guard acquired else { return nil }
            guard !Task.isCancelled else {
                await limiter.release(origin: origin)
                return nil
            }
            let result = await fetcher.fetch(url: candidate.iconURL, context: context)
            await limiter.release(origin: origin)
            return Task.isCancelled ? nil : result
        }
        inFlight[key] = ScheduledFetch(token: token, task: task)
        let result = await task.value
        if inFlight[key]?.token == token {
            inFlight.removeValue(forKey: key)
        }

        if let result, case .failure(let failureKind) = result {
            cachedFailureByKey[key] = CachedFailure(
                kind: failureKind,
                expiresAt: now.addingTimeInterval(
                    SumiFaviconTTL.failureCacheDuration(for: failureKind)
                )
            )
        }
        return result ?? .cancelled
    }

    func cancel(partition: SumiFaviconPartition) async {
        let matchingKeys = inFlight.keys.filter { $0.partition == partition }
        for key in matchingKeys {
            inFlight.removeValue(forKey: key)?.task.cancel()
        }
        cachedFailureByKey = cachedFailureByKey.filter {
            $0.key.partition != partition
        }
        await limiter.cancelQueuedFetches(partition: partition)
    }

    func cancelAll() async {
        for scheduledFetch in inFlight.values {
            scheduledFetch.task.cancel()
        }
        inFlight.removeAll()
        cachedFailureByKey.removeAll()
        await limiter.cancelQueuedFetches()
    }

    #if DEBUG
        func drainForTests(cancel: Bool = true) async {
            while !inFlight.isEmpty {
                let scheduledFetches = Array(inFlight.map { ($0.key, $0.value) })
                if cancel {
                    for (_, scheduledFetch) in scheduledFetches {
                        scheduledFetch.task.cancel()
                    }
                    await limiter.cancelQueuedFetches()
                }
                for (key, scheduledFetch) in scheduledFetches {
                    _ = await scheduledFetch.task.value
                    if inFlight[key]?.token == scheduledFetch.token {
                        inFlight.removeValue(forKey: key)
                    }
                }
            }
        }
    #endif

    private func originKey(for url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? url.absoluteString.lowercased()
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }
}
