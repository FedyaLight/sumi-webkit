import Foundation

struct SumiFaviconFetchRequest: Sendable {
    fileprivate enum Storage: Sendable {
        case immediate(SumiFaviconFetchResult)
        case scheduled(Task<SumiFaviconFetchResult, Never>)
    }

    fileprivate let storage: Storage

    var value: SumiFaviconFetchResult {
        get async {
            switch storage {
            case .immediate(let result):
                return result
            case .scheduled(let task):
                return await task.value
            }
        }
    }
}

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
        let task: Task<SumiFaviconFetchResult, Never>
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

    func request(
        candidate: SumiFaviconCandidate,
        context: SumiFaviconFetchContext,
        priority: SumiFaviconFetchPriority,
        now: Date = Date()
    ) -> SumiFaviconFetchRequest {
        let key = FetchKey(partition: candidate.partition, url: candidate.iconURL)
        if let cachedFailure = cachedFailureByKey[key],
           cachedFailure.expiresAt > now {
            return SumiFaviconFetchRequest(storage: .immediate(.failure(cachedFailure.kind)))
        }
        if let scheduledFetch = inFlight[key] {
            return SumiFaviconFetchRequest(storage: .scheduled(scheduledFetch.task))
        }

        let origin = originKey(for: candidate.iconURL)
        let token = UUID()
        let task = Task<SumiFaviconFetchResult, Never> { [weak self, fetcher, limiter] in
            let acquired = await limiter.acquire(
                partition: candidate.partition,
                origin: origin,
                priority: priority
            )
            let result: SumiFaviconFetchResult
            if !acquired {
                result = .cancelled
            } else if Task.isCancelled {
                await limiter.release(origin: origin)
                result = .cancelled
            } else {
                let fetched = await fetcher.fetch(url: candidate.iconURL, context: context)
                await limiter.release(origin: origin)
                result = Task.isCancelled ? .cancelled : fetched
            }
            await self?.completeFetch(key: key, token: token, result: result, now: now)
            return result
        }
        inFlight[key] = ScheduledFetch(token: token, task: task)
        return SumiFaviconFetchRequest(storage: .scheduled(task))
    }

    private func completeFetch(
        key: FetchKey,
        token: UUID,
        result: SumiFaviconFetchResult,
        now: Date
    ) {
        guard inFlight[key]?.token == token else { return }
        inFlight.removeValue(forKey: key)
        if case .failure(let failureKind) = result {
            cachedFailureByKey[key] = CachedFailure(
                kind: failureKind,
                expiresAt: now.addingTimeInterval(
                    SumiFaviconTTL.failureCacheDuration(for: failureKind)
                )
            )
        }
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
