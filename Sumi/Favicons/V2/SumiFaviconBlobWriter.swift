import CryptoKit
import Foundation
import OSLog

final class SumiFaviconBlobWriter: @unchecked Sendable {
    private static let log = Logger.sumi(category: "FaviconBlobWriter")

    private let transaction: SumiFaviconBlobTransaction
    private let index: SumiFaviconBlobIndex

    init(
        transaction: SumiFaviconBlobTransaction,
        index: SumiFaviconBlobIndex
    ) {
        self.transaction = transaction
        self.index = index
    }

    @discardableResult
    func storeValidatedPayload(
        _ payload: SumiFaviconValidatedPayload,
        for candidate: SumiFaviconCandidate,
        aliasPageURLs: [URL] = [],
        now: Date = Date()
    ) throws -> SumiStoredFaviconSelection {
        let blobID = sha256Hex(payload.data)
        let identity = SumiFaviconBlobIdentity(
            blobID: blobID,
            fileName: "\(blobID).\(payload.payloadKind.preferredFileExtension)"
        )

        var newlyWrittenBlobFileName: String?
        var unreferencedBlobs = [SumiFaviconBlobRecord]()
        return try transaction.mutateImmediately(
            partition: candidate.partition,
            rollbackPhysicalMutation: { cache, diskStorage in
                if candidate.partition.isPrivate {
                    cache.removePrivatePayload(
                        blobID: identity.blobID,
                        partition: candidate.partition
                    )
                } else if let fileName = newlyWrittenBlobFileName {
                    do {
                        _ = try diskStorage.removeBlob(
                            fileName: fileName,
                            partition: candidate.partition
                        )
                    } catch {
                        Self.log.error(
                            "Failed to roll back favicon blob \(fileName, privacy: .public): \(String(describing: error), privacy: .public)"
                        )
                    }
                }
            },
            commitPhysicalMutation: { cache, diskStorage in
                self.removePhysicalBlobs(
                    unreferencedBlobs,
                    partition: candidate.partition,
                    cache: cache,
                    diskStorage: diskStorage
                )
            }
        ) { metadata, cache, diskStorage in
            if candidate.partition.isPrivate {
                cache.storePrivatePayload(
                    payload.data,
                    blobID: identity.blobID,
                    partition: candidate.partition
                )
            } else {
                let didWriteBlob = try diskStorage.writeBlobIfMissing(
                    payload.data,
                    fileName: identity.fileName,
                    partition: candidate.partition
                )
                if didWriteBlob {
                    newlyWrittenBlobFileName = identity.fileName
                }
            }

            let selection = index.indexPayload(
                payload,
                identity: identity,
                candidate: candidate,
                aliasPageURLs: aliasPageURLs,
                metadata: &metadata,
                now: now
            )
            unreferencedBlobs = removeUnreferencedBlobRecords(
                metadata: &metadata,
                excluding: Set(metadata.pageMappings.values.map(\.blobID))
            )
            return selection
        }
    }

    @discardableResult
    func associatePageAliases(
        _ aliasPageURLs: [URL],
        to selection: SumiStoredFaviconSelection,
        now: Date = Date()
    ) -> SumiFaviconAliasAssociationResult {
        guard !aliasPageURLs.isEmpty else { return .empty }

        return transaction.mutateCoalesced(
            partition: selection.partition,
            operation: "alias association"
        ) { metadata, _ in
            let result = index.associatePageAliases(
                aliasPageURLs,
                to: selection,
                metadata: &metadata,
                now: now
            )
            return (result, result.didChange)
        }
    }

    func recordFailure(
        candidateURL: URL,
        partition: SumiFaviconPartition,
        failureKind: SumiFaviconValidationFailureKind,
        ttl: TimeInterval,
        now: Date = Date()
    ) {
        transaction.mutateCoalesced(
            partition: partition,
            operation: "candidate failure"
        ) { metadata, _ in
            index.recordFailure(
                candidateURL: candidateURL,
                failureKind: failureKind,
                ttl: ttl,
                metadata: &metadata,
                now: now
            )
            return ((), true)
        }
    }

    func recordNoIconFound(
        for pageURL: URL,
        partition: SumiFaviconPartition,
        now: Date = Date()
    ) {
        transaction.mutateCoalesced(
            partition: partition,
            operation: "no-icon marker"
        ) { metadata, _ in
            let didChange = index.recordNoIconFound(
                for: pageURL,
                metadata: &metadata,
                now: now
            )
            return ((), didChange)
        }
    }

    private func removeUnreferencedBlobRecords(
        metadata: inout SumiFaviconBlobMetadata,
        excluding usedBlobIDs: Set<String>
    ) -> [SumiFaviconBlobRecord] {
        let removable = metadata.blobs.values.filter {
            !usedBlobIDs.contains($0.blobID)
        }
        for blob in removable {
            metadata.blobs[blob.blobID] = nil
        }

        let removedBlobIDs = Set(removable.map(\.blobID))
        metadata.candidateMappings = metadata.candidateMappings.filter { _, record in
            guard let blobID = record.blobID else { return true }
            return !removedBlobIDs.contains(blobID)
        }
        return removable
    }

    private func removePhysicalBlobs(
        _ blobs: [SumiFaviconBlobRecord],
        partition: SumiFaviconPartition,
        cache: SumiFaviconBlobCache,
        diskStorage: SumiFaviconBlobDiskStorage
    ) {
        for blob in blobs {
            if partition.isPrivate {
                cache.removePrivatePayload(
                    blobID: blob.blobID,
                    partition: partition
                )
                continue
            }
            do {
                _ = try diskStorage.removeBlob(
                    fileName: blob.fileName,
                    partition: partition
                )
            } catch {
                Self.log.error(
                    "Failed to remove unreferenced favicon blob for \(partition.storageComponent, privacy: .public): \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
