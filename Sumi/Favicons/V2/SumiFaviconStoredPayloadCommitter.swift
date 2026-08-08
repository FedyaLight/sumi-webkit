import Foundation

/// Commits a validated payload and its presentation invalidation as one
/// cleanup-generation-aware operation.
final class SumiFaviconStoredPayloadCommitter: @unchecked Sendable {
    private let blobReader: SumiFaviconBlobReader
    private let blobWriter: SumiFaviconBlobWriter
    private let preparedPipeline: SumiPreparedFaviconPipeline
    private let updatePublisher: SumiFaviconUpdatePublisher
    private let mutationGate: SumiFaviconMutationGate

    init(
        blobReader: SumiFaviconBlobReader,
        blobWriter: SumiFaviconBlobWriter,
        preparedPipeline: SumiPreparedFaviconPipeline,
        updatePublisher: SumiFaviconUpdatePublisher,
        mutationGate: SumiFaviconMutationGate
    ) {
        self.blobReader = blobReader
        self.blobWriter = blobWriter
        self.preparedPipeline = preparedPipeline
        self.updatePublisher = updatePublisher
        self.mutationGate = mutationGate
    }

    func lease(for partition: SumiFaviconPartition) -> SumiFaviconMutationGate.Lease {
        mutationGate.lease(for: partition)
    }

    func store(
        _ payload: SumiFaviconValidatedPayload,
        for candidate: SumiFaviconCandidate,
        aliasPageURLs: [URL] = [],
        lease: SumiFaviconMutationGate.Lease
    ) throws -> SumiStoredFaviconSelection? {
        try mutationGate.performIfCurrent(lease) {
            let oldSelection = blobReader.cachedSelection(
                for: candidate.pageURL,
                partition: candidate.partition
            )
            let selection = try blobWriter.storeValidatedPayload(
                payload,
                for: candidate,
                aliasPageURLs: aliasPageURLs
            )
            if let oldSelection,
               oldSelection.revision != selection.revision {
                preparedPipeline.invalidate(
                    partition: oldSelection.partition,
                    blobID: oldSelection.blobID,
                    revision: oldSelection.revision
                )
            }
            publishUpdates(
                for: [candidate.pageURL] + aliasPageURLs,
                partition: candidate.partition,
                revision: selection.revision
            )
            return selection
        }
    }

    func associateAliases(
        _ aliasPageURLs: [URL],
        to selection: SumiStoredFaviconSelection,
        lease: SumiFaviconMutationGate.Lease
    ) {
        guard !aliasPageURLs.isEmpty else { return }
        _ = mutationGate.performIfCurrent(lease) {
            let result = blobWriter.associatePageAliases(aliasPageURLs, to: selection)
            guard result.didChange else { return }
            for invalidation in Set(result.invalidations) {
                preparedPipeline.invalidate(
                    partition: invalidation.partition,
                    revision: invalidation.revision
                )
            }
            publishUpdates(
                for: [selection.pageURL] + aliasPageURLs,
                partition: selection.partition,
                revision: selection.revision
            )
        }
    }

    private func publishUpdates(
        for pageURLs: [URL],
        partition: SumiFaviconPartition,
        revision: String
    ) {
        let domains = Set(pageURLs.compactMap { $0.host?.lowercased() })
        guard !domains.isEmpty else {
            updatePublisher.publish(
                domain: nil,
                partition: partition,
                revision: revision
            )
            return
        }
        for domain in domains.sorted() {
            updatePublisher.publish(
                domain: domain,
                partition: partition,
                revision: revision
            )
        }
    }
}
