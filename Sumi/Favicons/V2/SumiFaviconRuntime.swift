import Foundation

/// Favicon composition root. It exposes independent capabilities and has no
/// forwarding API or mutable scheduling/storage state of its own.
final class SumiFaviconRuntime: @unchecked Sendable {
    let images: SumiFaviconImageRepository
    let liveDiscovery: SumiFaviconLiveDiscoveryPipeline
    let payloadIngestion: SumiFaviconPayloadIngestion
    let coldFetches: SumiFaviconColdFetchService
    let maintenance: SumiFaviconCacheMaintenance

    private let persistenceLifecycle: SumiFaviconPersistenceLifecycle

    init(
        rootDirectory: URL,
        fetcher: any SumiFaviconNetworkFetching,
        notificationCenter: NotificationCenter = .default
    ) {
        let blobStorage = SumiFaviconBlobStorage(rootDirectory: rootDirectory)
        let preparedPipeline = SumiPreparedFaviconPipeline(
            blobReader: blobStorage.reader,
            preparedCache: SumiPreparedFaviconCache()
        )
        let updatePublisher = SumiFaviconUpdatePublisher(
            notificationCenter: notificationCenter
        )
        let mutationGate = SumiFaviconMutationGate()
        let fetchScheduler = SumiFaviconFetchScheduler(fetcher: fetcher)
        let payloadCommitter = SumiFaviconStoredPayloadCommitter(
            blobReader: blobStorage.reader,
            blobWriter: blobStorage.writer,
            preparedPipeline: preparedPipeline,
            updatePublisher: updatePublisher,
            mutationGate: mutationGate
        )
        let resolutionPipeline = SumiFaviconCandidateResolutionPipeline(
            blobReader: blobStorage.reader,
            blobWriter: blobStorage.writer,
            payloadFetcher: SumiFaviconPayloadFetcher(fetchScheduler: fetchScheduler),
            payloadCommitter: payloadCommitter,
            mutationGate: mutationGate
        )
        let coldFetches = SumiFaviconColdFetchService(
            blobReader: blobStorage.reader,
            resolutionPipeline: resolutionPipeline,
            fetchScheduler: fetchScheduler
        )

        self.coldFetches = coldFetches
        images = SumiFaviconImageRepository(
            blobReader: blobStorage.reader,
            preparedPipeline: preparedPipeline,
            coldFetches: coldFetches
        )
        liveDiscovery = SumiFaviconLiveDiscoveryPipeline(
            resolutionPipeline: resolutionPipeline,
            fetchScheduler: fetchScheduler,
            preparedPipeline: preparedPipeline
        )
        payloadIngestion = SumiFaviconPayloadIngestion(
            payloadCommitter: payloadCommitter,
            preparedPipeline: preparedPipeline
        )
        maintenance = SumiFaviconCacheMaintenance(
            blobMaintenance: blobStorage.maintenance,
            preparedPipeline: preparedPipeline,
            updatePublisher: updatePublisher,
            mutationGate: mutationGate,
            coldFetches: coldFetches
        )
        persistenceLifecycle = SumiFaviconPersistenceLifecycle(
            blobMaintenance: blobStorage.maintenance,
            notificationCenter: notificationCenter
        )
    }
}
