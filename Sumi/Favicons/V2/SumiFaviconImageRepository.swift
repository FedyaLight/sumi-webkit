import AppKit
import Foundation

final class SumiFaviconImageRepository: @unchecked Sendable {
    private let blobReader: SumiFaviconBlobReader
    private let preparedPipeline: SumiPreparedFaviconPipeline
    private let coldFetches: SumiFaviconColdFetchService

    init(
        blobReader: SumiFaviconBlobReader,
        preparedPipeline: SumiPreparedFaviconPipeline,
        coldFetches: SumiFaviconColdFetchService
    ) {
        self.blobReader = blobReader
        self.preparedPipeline = preparedPipeline
        self.coldFetches = coldFetches
    }

    func cachedPreparedImage(for request: SumiPreparedFaviconRequest) -> NSImage? {
        guard let selection = blobReader.cachedSelection(
            for: request.pageURL,
            partition: request.partition
        ) else {
            return nil
        }
        return preparedPipeline.cachedImage(for: selection, request: request)
    }

    func cachedSelection(
        for pageURL: URL,
        partition: SumiFaviconPartition
    ) -> SumiStoredFaviconSelection? {
        blobReader.cachedSelection(for: pageURL, partition: partition)
    }

    func preparedImage(
        for request: SumiPreparedFaviconRequest,
        priority: SumiFaviconFetchPriority,
        scheduleFetchOnMiss: Bool = true
    ) async -> NSImage? {
        if let selection = blobReader.cachedSelection(
            for: request.pageURL,
            partition: request.partition
        ), let prepared = await preparedPipeline.preparedImage(
            for: selection,
            request: request
        ) {
            return prepared
        }

        if scheduleFetchOnMiss {
            coldFetches.schedule(
                pageURL: request.pageURL,
                partition: request.partition,
                priority: priority
            )
        }
        return nil
    }

    func hasFavicon(
        for pageURL: URL,
        partition: SumiFaviconPartition
    ) -> Bool {
        blobReader.cachedSelection(for: pageURL, partition: partition) != nil
    }
}
