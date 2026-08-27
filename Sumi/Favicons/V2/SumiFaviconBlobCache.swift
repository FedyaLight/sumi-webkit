import Foundation

/// Session cache for decoded partition indexes and ephemeral private payloads.
/// Mutations remain transaction-owned; memory-only UI reads take atomic snapshots.
final class SumiFaviconBlobCache: @unchecked Sendable {
    private let lock = NSLock()
    private var metadataByPartition: [SumiFaviconPartition: SumiFaviconBlobMetadata] = [:]
    private var privatePayloadsByPartition: [SumiFaviconPartition: [String: Data]] = [:]

    var loadedPartitions: Set<SumiFaviconPartition> {
        lock.withLock { Set(metadataByPartition.keys) }
    }

    func metadata(for partition: SumiFaviconPartition) -> SumiFaviconBlobMetadata? {
        lock.withLock { metadataByPartition[partition] }
    }

    func storeMetadata(
        _ metadata: SumiFaviconBlobMetadata,
        for partition: SumiFaviconPartition
    ) {
        lock.withLock {
            metadataByPartition[partition] = metadata
        }
    }

    func storePrivatePayload(
        _ data: Data,
        blobID: String,
        partition: SumiFaviconPartition
    ) {
        precondition(partition.isPrivate)
        lock.withLock {
            var payloads = privatePayloadsByPartition[partition] ?? [:]
            payloads[blobID] = data
            privatePayloadsByPartition[partition] = payloads
        }
    }

    func privatePayload(
        blobID: String,
        partition: SumiFaviconPartition
    ) -> Data? {
        precondition(partition.isPrivate)
        return lock.withLock {
            privatePayloadsByPartition[partition]?[blobID]
        }
    }

    func clear(_ partition: SumiFaviconPartition) {
        lock.withLock {
            metadataByPartition[partition] = SumiFaviconBlobMetadata()
            privatePayloadsByPartition[partition] = nil
        }
    }

    func removePrivatePayload(
        blobID: String,
        partition: SumiFaviconPartition
    ) {
        lock.withLock {
            privatePayloadsByPartition[partition]?[blobID] = nil
            if privatePayloadsByPartition[partition]?.isEmpty == true {
                privatePayloadsByPartition[partition] = nil
            }
        }
    }
}
