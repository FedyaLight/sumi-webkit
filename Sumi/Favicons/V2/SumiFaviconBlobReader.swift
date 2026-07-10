import Foundation
import OSLog

final class SumiFaviconBlobReader: @unchecked Sendable {
    private static let log = Logger.sumi(category: "FaviconBlobReader")

    private let transaction: SumiFaviconBlobTransaction
    private let index: SumiFaviconBlobIndex

    init(
        transaction: SumiFaviconBlobTransaction,
        index: SumiFaviconBlobIndex
    ) {
        self.transaction = transaction
        self.index = index
    }

    func cachedSelection(
        for pageURL: URL,
        partition: SumiFaviconPartition,
        now: Date = Date()
    ) -> SumiStoredFaviconSelection? {
        transaction.read(partition: partition) { metadata, _, _ in
            index.selection(
                for: pageURL,
                partition: partition,
                metadata: metadata,
                now: now
            )
        }
    }

    func payloadData(
        blobID: String,
        partition: SumiFaviconPartition
    ) -> Data? {
        transaction.read(partition: partition) { metadata, cache, diskStorage in
            guard let blob = metadata.blobs[blobID] else { return nil }
            if partition.isPrivate {
                return cache.privatePayload(blobID: blobID, partition: partition)
            }
            do {
                return try diskStorage.readBlob(
                    fileName: blob.fileName,
                    partition: partition
                )
            } catch {
                Self.log.error(
                    "Failed to read favicon blob \(blob.blobID, privacy: .public) for \(partition.storageComponent, privacy: .public): \(String(describing: error), privacy: .public)"
                )
                return nil
            }
        }
    }

    func isPositiveCandidateFresh(
        _ candidateURL: URL,
        partition: SumiFaviconPartition,
        now: Date = Date()
    ) -> Bool {
        transaction.read(partition: partition) { metadata, _, _ in
            index.isPositiveCandidateFresh(candidateURL, metadata: metadata, now: now)
        }
    }

    func isNegativeCandidateFresh(
        _ candidateURL: URL,
        partition: SumiFaviconPartition,
        now: Date = Date()
    ) -> Bool {
        transaction.read(partition: partition) { metadata, _, _ in
            index.isNegativeCandidateFresh(candidateURL, metadata: metadata, now: now)
        }
    }

    func isNoIconFresh(
        for pageURL: URL,
        partition: SumiFaviconPartition,
        now: Date = Date()
    ) -> Bool {
        transaction.read(partition: partition) { metadata, _, _ in
            index.isNoIconFresh(for: pageURL, metadata: metadata, now: now)
        }
    }
}
