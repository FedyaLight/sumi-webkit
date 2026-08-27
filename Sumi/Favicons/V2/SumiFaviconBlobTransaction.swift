import Foundation
import OSLog

enum SumiFaviconPartitionMutationScope {
    case partition(SumiFaviconPartition)
    case allKnown
}

/// The single synchronization and durability boundary for favicon metadata.
/// Domain rules live in the index; physical I/O lives in disk storage.
final class SumiFaviconBlobTransaction: @unchecked Sendable {
    private static let log = Logger.sumi(category: "FaviconBlobTransaction")

    private let queue = DispatchQueue(label: "SumiFaviconBlobTransaction", qos: .utility)
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let cache: SumiFaviconBlobCache
    private let database: SumiDatabase
    private let diskStorage: SumiFaviconBlobDiskStorage
    private let codec: SumiFaviconMetadataCodec
    private let persistCoalesceInterval: TimeInterval

    private var pendingPersistPartitions: Set<SumiFaviconPartition> = []
    private var scheduledFlushGeneration: UInt64?
    private var nextFlushGeneration: UInt64 = 0

    init(
        cache: SumiFaviconBlobCache,
        database: SumiDatabase,
        diskStorage: SumiFaviconBlobDiskStorage,
        codec: SumiFaviconMetadataCodec,
        persistCoalesceInterval: TimeInterval
    ) {
        self.cache = cache
        self.database = database
        self.diskStorage = diskStorage
        self.codec = codec
        self.persistCoalesceInterval = max(0, persistCoalesceInterval)
        queue.setSpecific(key: queueKey, value: 1)
    }

    deinit {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            flushPendingPersistsLocked()
        } else {
            queue.sync { flushPendingPersistsLocked() }
        }
    }

    func read<Result>(
        partition: SumiFaviconPartition,
        _ body: (
            SumiFaviconBlobMetadata,
            SumiFaviconBlobCache,
            SumiFaviconBlobDiskStorage
        ) throws -> Result
    ) rethrows -> Result {
        try sync {
            let metadata = loadMetadataIfNeeded(for: partition)
            return try body(metadata, cache, diskStorage)
        }
    }

    func cachedMetadata(
        for partition: SumiFaviconPartition
    ) -> SumiFaviconBlobMetadata? {
        cache.metadata(for: partition)
    }

    func mutateImmediately<Result>(
        partition: SumiFaviconPartition,
        rollbackPhysicalMutation: (
            (SumiFaviconBlobCache, SumiFaviconBlobDiskStorage) -> Void
        )? = nil,
        commitPhysicalMutation: (
            (SumiFaviconBlobCache, SumiFaviconBlobDiskStorage) -> Void
        )? = nil,
        _ mutation: (
            inout SumiFaviconBlobMetadata,
            SumiFaviconBlobCache,
            SumiFaviconBlobDiskStorage
        ) throws -> Result
    ) throws -> Result {
        try sync {
            var metadata = loadMetadataIfNeeded(for: partition)
            do {
                let result = try mutation(&metadata, cache, diskStorage)
                guard !partition.isPrivate else {
                    cache.storeMetadata(metadata, for: partition)
                    commitPhysicalMutation?(cache, diskStorage)
                    return result
                }

                // The in-memory index is committed only after the durable write.
                // A failed metadata write must not expose a selection that will
                // disappear after restart.
                try persist(metadata: metadata, partition: partition)
                cache.storeMetadata(metadata, for: partition)
                pendingPersistPartitions.remove(partition)
                commitPhysicalMutation?(cache, diskStorage)
                return result
            } catch {
                rollbackPhysicalMutation?(cache, diskStorage)
                throw error
            }
        }
    }

    func mutateCoalesced<Result>(
        partition: SumiFaviconPartition,
        operation: String,
        _ mutation: (
            inout SumiFaviconBlobMetadata,
            SumiFaviconBlobCache
        ) -> (result: Result, didChange: Bool)
    ) -> Result {
        sync {
            var metadata = loadMetadataIfNeeded(for: partition)
            let outcome = mutation(&metadata, cache)
            guard outcome.didChange else { return outcome.result }

            cache.storeMetadata(metadata, for: partition)
            schedulePersistLocked(partition: partition, operation: operation)
            return outcome.result
        }
    }

    func mutateEachCoalesced<Result>(
        scope: SumiFaviconPartitionMutationScope,
        operation: String,
        _ mutation: (
            SumiFaviconPartition,
            inout SumiFaviconBlobMetadata
        ) -> Result
    ) -> [Result] {
        sync {
            partitions(for: scope).map { partition in
                var metadata = loadMetadataIfNeeded(for: partition)
                let result = mutation(partition, &metadata)
                cache.storeMetadata(metadata, for: partition)
                schedulePersistLocked(partition: partition, operation: operation)
                return result
            }
        }
    }

    func clearPartition(_ partition: SumiFaviconPartition) throws {
        try sync {
            if !partition.isPrivate {
                try diskStorage.removePartition(partition)
                try database.transaction {
                    try $0.documents.delete(
                        key: metadataKey(for: partition)
                    )
                }
            }
            cache.clear(partition)
            pendingPersistPartitions.remove(partition)
        }
    }

    func flushPendingPersists() {
        sync { flushPendingPersistsLocked() }
    }

    private func sync<Result>(_ body: () throws -> Result) rethrows -> Result {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try body()
        }
        return try queue.sync(execute: body)
    }

    private func loadMetadataIfNeeded(
        for partition: SumiFaviconPartition
    ) -> SumiFaviconBlobMetadata {
        if let metadata = cache.metadata(for: partition) {
            return metadata
        }

        guard !partition.isPrivate else {
            let metadata = SumiFaviconBlobMetadata()
            cache.storeMetadata(metadata, for: partition)
            return metadata
        }

        let loadedData: Data
        do {
            guard let data = try database.read({
                try $0.documents.data(forKey: metadataKey(for: partition))
            }) else {
                let metadata = SumiFaviconBlobMetadata()
                cache.storeMetadata(metadata, for: partition)
                return metadata
            }
            loadedData = data
        } catch {
            Self.log.error(
                "Failed to read favicon metadata for partition \(partition.storageComponent, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            let metadata = SumiFaviconBlobMetadata()
            cache.storeMetadata(metadata, for: partition)
            return metadata
        }

        do {
            let metadata = try codec.decode(loadedData)
            cache.storeMetadata(metadata, for: partition)
            return metadata
        } catch let error as SumiFaviconMetadataCodec.DecodingError {
            switch error {
            case .unsupportedSchemaVersion(let version):
                Self.log.error(
                    "Favicon metadata for partition \(partition.storageComponent, privacy: .public) has unsupported schemaVersion \(version, privacy: .public); starting fresh."
                )
            }
        } catch {
            Self.log.error(
                "Failed to decode favicon metadata for partition \(partition.storageComponent, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }

        let metadata = SumiFaviconBlobMetadata()
        cache.storeMetadata(metadata, for: partition)
        return metadata
    }

    private func persist(
        metadata: SumiFaviconBlobMetadata,
        partition: SumiFaviconPartition
    ) throws {
        guard !partition.isPrivate else { return }
        let data = try codec.encode(metadata)
        try database.transaction {
            try $0.documents.save(data, forKey: metadataKey(for: partition))
        }
    }

    private func schedulePersistLocked(
        partition: SumiFaviconPartition,
        operation: String
    ) {
        guard !partition.isPrivate else { return }

        guard persistCoalesceInterval > 0 else {
            writeMetadataOrLog(partition: partition, operation: operation)
            return
        }

        pendingPersistPartitions.insert(partition)
        guard scheduledFlushGeneration == nil else { return }

        nextFlushGeneration &+= 1
        let generation = nextFlushGeneration
        scheduledFlushGeneration = generation
        queue.asyncAfter(deadline: .now() + persistCoalesceInterval) { [weak self] in
            self?.flushPendingPersistsLocked(expectedGeneration: generation)
        }
    }

    private func flushPendingPersistsLocked(expectedGeneration: UInt64? = nil) {
        if let expectedGeneration,
           scheduledFlushGeneration != expectedGeneration {
            return
        }

        scheduledFlushGeneration = nil
        let partitions = pendingPersistPartitions
        pendingPersistPartitions.removeAll()
        for partition in partitions {
            writeMetadataOrLog(partition: partition, operation: "coalesced flush")
        }
    }

    private func writeMetadataOrLog(
        partition: SumiFaviconPartition,
        operation: String
    ) {
        guard let metadata = cache.metadata(for: partition) else { return }
        do {
            try persist(metadata: metadata, partition: partition)
        } catch {
            Self.log.error(
                "Failed to persist favicon metadata after \(operation, privacy: .public) for \(partition.storageComponent, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func partitions(
        for scope: SumiFaviconPartitionMutationScope
    ) -> Set<SumiFaviconPartition> {
        switch scope {
        case .partition(let partition):
            return [partition]
        case .allKnown:
            do {
                let persisted = try database.read {
                    try $0.documents.keys(withPrefix: "favicon.metadata.")
                }.compactMap { key -> SumiFaviconPartition? in
                    let component = String(
                        key.dropFirst("favicon.metadata.".count)
                    )
                    guard component.hasPrefix("profile-") else { return nil }
                    return SumiFaviconPartition(
                        profileIdentifier: String(
                            component.dropFirst("profile-".count)
                        ),
                        isPrivate: false
                    )
                }
                return cache.loadedPartitions
                    .union(persisted)
                    .union(try diskStorage.discoverRegularPartitions())
            } catch {
                Self.log.error(
                    "Failed to discover favicon partitions under \(self.diskStorage.rootDirectory.path, privacy: .public): \(String(describing: error), privacy: .public)"
                )
                return cache.loadedPartitions
            }
        }
    }

    private func metadataKey(for partition: SumiFaviconPartition) -> String {
        "favicon.metadata.\(partition.storageComponent)"
    }
}
