import Foundation

/// Session cache for decoded partition indexes and ephemeral private payloads.
/// The transaction executor is its sole caller and provides synchronization.
final class SumiFaviconBlobCache {
    private var metadataByPartition: [SumiFaviconPartition: SumiFaviconBlobMetadata] = [:]
    private var privatePayloadsByPartition: [SumiFaviconPartition: [String: Data]] = [:]

    var loadedPartitions: Set<SumiFaviconPartition> {
        Set(metadataByPartition.keys)
    }

    func metadata(for partition: SumiFaviconPartition) -> SumiFaviconBlobMetadata? {
        metadataByPartition[partition]
    }

    func storeMetadata(
        _ metadata: SumiFaviconBlobMetadata,
        for partition: SumiFaviconPartition
    ) {
        metadataByPartition[partition] = metadata
    }

    func storePrivatePayload(
        _ data: Data,
        blobID: String,
        partition: SumiFaviconPartition
    ) {
        precondition(partition.isPrivate)
        var payloads = privatePayloadsByPartition[partition] ?? [:]
        payloads[blobID] = data
        privatePayloadsByPartition[partition] = payloads
    }

    func privatePayload(
        blobID: String,
        partition: SumiFaviconPartition
    ) -> Data? {
        precondition(partition.isPrivate)
        return privatePayloadsByPartition[partition]?[blobID]
    }

    func clear(_ partition: SumiFaviconPartition) {
        metadataByPartition[partition] = SumiFaviconBlobMetadata()
        privatePayloadsByPartition[partition] = nil
    }

    func removePrivatePayload(
        blobID: String,
        partition: SumiFaviconPartition
    ) {
        privatePayloadsByPartition[partition]?[blobID] = nil
        if privatePayloadsByPartition[partition]?.isEmpty == true {
            privatePayloadsByPartition[partition] = nil
        }
    }
}
