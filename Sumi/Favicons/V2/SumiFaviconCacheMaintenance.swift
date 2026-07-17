import Foundation

final class SumiFaviconCacheMaintenance: @unchecked Sendable {
    private let blobMaintenance: SumiFaviconBlobMaintenance
    private let preparedPipeline: SumiPreparedFaviconPipeline
    private let updatePublisher: SumiFaviconUpdatePublisher
    private let mutationGate: SumiFaviconMutationGate
    private let coldFetches: SumiFaviconColdFetchService

    init(
        blobMaintenance: SumiFaviconBlobMaintenance,
        preparedPipeline: SumiPreparedFaviconPipeline,
        updatePublisher: SumiFaviconUpdatePublisher,
        mutationGate: SumiFaviconMutationGate,
        coldFetches: SumiFaviconColdFetchService
    ) {
        self.blobMaintenance = blobMaintenance
        self.preparedPipeline = preparedPipeline
        self.updatePublisher = updatePublisher
        self.mutationGate = mutationGate
        self.coldFetches = coldFetches
    }

    func invalidateSite(
        domain: String,
        partition: SumiFaviconPartition? = nil
    ) {
        mutationGate.performGlobalCleanup {
            let invalidations = blobMaintenance.invalidateSite(
                domain: domain,
                partition: partition
            )
            invalidatePreparedVariants(invalidations)
        }
        coldFetches.cancelAll()
        updatePublisher.publish(domain: domain, partition: partition, revision: nil)
    }

    func clearPartition(_ partition: SumiFaviconPartition) throws {
        defer { coldFetches.cancel(partition: partition) }
        try mutationGate.performPartitionCleanup(partition) {
            try blobMaintenance.clearPartition(partition)
            preparedPipeline.invalidate(partition: partition)
        }
    }

    func burnAfterHistoryClear(
        savedLogins: Set<String>,
        bookmarkHosts: Set<String>
    ) {
        mutationGate.performGlobalCleanup {
            invalidatePreparedVariants(
                blobMaintenance.burnAfterHistoryClear(
                    savedLogins: savedLogins,
                    bookmarkHosts: bookmarkHosts
                )
            )
        }
        coldFetches.cancelAll()
    }

    func burnDomains(
        _ domains: Set<String>,
        remainingHistoryHosts: Set<String>,
        savedLogins: Set<String>,
        bookmarkHosts: Set<String>
    ) {
        mutationGate.performGlobalCleanup {
            invalidatePreparedVariants(
                blobMaintenance.burnDomains(
                    domains,
                    remainingHistoryHosts: remainingHistoryHosts,
                    savedLogins: savedLogins,
                    bookmarkHosts: bookmarkHosts
                )
            )
        }
        coldFetches.cancelAll()
        for domain in domains {
            updatePublisher.publish(domain: domain, partition: nil, revision: nil)
        }
    }

    private func invalidatePreparedVariants(
        _ invalidations: [SumiFaviconInvalidation]
    ) {
        for invalidation in Set(invalidations) {
            preparedPipeline.invalidate(
                partition: invalidation.partition,
                revision: invalidation.revision
            )
        }
    }
}
