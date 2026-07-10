import Foundation

/// Serializes destructive cache mutations with late fetch commits. A lease is
/// invalidated before cleanup begins, so a request started against older state
/// cannot recreate data after a partition/site clear.
final class SumiFaviconMutationGate: @unchecked Sendable {
    struct Lease: Sendable {
        fileprivate let partition: SumiFaviconPartition
        fileprivate let partitionGeneration: UInt64
        fileprivate let globalCleanupGeneration: UInt64
    }

    private let queue = DispatchQueue(label: "SumiFaviconMutationGate")
    private var partitionGenerations: [SumiFaviconPartition: UInt64] = [:]
    private var globalCleanupGeneration: UInt64 = 0

    func lease(for partition: SumiFaviconPartition) -> Lease {
        queue.sync {
            Lease(
                partition: partition,
                partitionGeneration: partitionGenerations[partition, default: 0],
                globalCleanupGeneration: globalCleanupGeneration
            )
        }
    }

    func performIfCurrent<Result>(
        _ lease: Lease,
        _ body: () throws -> Result
    ) rethrows -> Result? {
        try queue.sync {
            guard isCurrentLocked(lease) else { return nil }
            return try body()
        }
    }

    func isCurrent(_ lease: Lease) -> Bool {
        queue.sync { isCurrentLocked(lease) }
    }

    func performPartitionCleanup(
        _ partition: SumiFaviconPartition,
        _ body: () -> Void
    ) {
        queue.sync {
            partitionGenerations[partition, default: 0] &+= 1
            body()
        }
    }

    func performGlobalCleanup(_ body: () -> Void) {
        queue.sync {
            globalCleanupGeneration &+= 1
            body()
        }
    }

    private func isCurrentLocked(_ lease: Lease) -> Bool {
        partitionGenerations[lease.partition, default: 0] == lease.partitionGeneration
            && globalCleanupGeneration == lease.globalCleanupGeneration
    }
}
