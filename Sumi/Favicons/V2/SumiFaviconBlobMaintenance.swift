import Foundation

final class SumiFaviconBlobMaintenance: @unchecked Sendable {
    private let transaction: SumiFaviconBlobTransaction
    private let index: SumiFaviconBlobIndex

    init(
        transaction: SumiFaviconBlobTransaction,
        index: SumiFaviconBlobIndex
    ) {
        self.transaction = transaction
        self.index = index
    }

    func flushPendingPersists() {
        transaction.flushPendingPersists()
    }

    func invalidateSite(
        domain: String,
        partition: SumiFaviconPartition? = nil
    ) -> [SumiFaviconInvalidation] {
        guard let normalizedDomain = index.normalizedSiteDomain(domain) else { return [] }
        let scope = partition.map(SumiFaviconPartitionMutationScope.partition) ?? .allKnown
        return transaction.mutateEachCoalesced(
            scope: scope,
            operation: "site invalidation"
        ) { partition, metadata in
            index.invalidateSite(
                normalizedDomain: normalizedDomain,
                partition: partition,
                metadata: &metadata
            )
        }.flatMap(\.self)
    }

    func clearPartition(_ partition: SumiFaviconPartition) {
        transaction.clearPartition(partition)
    }

    func burnAfterHistoryClear(
        savedLogins: Set<String>,
        bookmarkHosts: Set<String>
    ) -> [SumiFaviconInvalidation] {
        let preservedHosts = index.normalizedHosts(savedLogins)
            .union(index.normalizedHosts(bookmarkHosts))
        return transaction.mutateEachCoalesced(
            scope: .allKnown,
            operation: "history clear burn"
        ) { partition, metadata in
            index.burnAfterHistoryClear(
                preservedHosts: preservedHosts,
                partition: partition,
                metadata: &metadata
            )
        }.flatMap(\.self)
    }

    func burnDomains(
        _ domains: Set<String>,
        remainingHistoryHosts: Set<String>,
        savedLogins: Set<String>,
        bookmarkHosts: Set<String>
    ) -> [SumiFaviconInvalidation] {
        let normalizedDomains = Set(domains.compactMap(index.normalizedSiteDomain))
        guard !normalizedDomains.isEmpty else { return [] }
        let preservedHosts = index.normalizedHosts(remainingHistoryHosts)
            .union(index.normalizedHosts(savedLogins))
            .union(index.normalizedHosts(bookmarkHosts))

        return transaction.mutateEachCoalesced(
            scope: .allKnown,
            operation: "domain burn"
        ) { partition, metadata in
            index.burnDomains(
                normalizedDomains: normalizedDomains,
                preservedHosts: preservedHosts,
                partition: partition,
                metadata: &metadata
            )
        }.flatMap(\.self)
    }
}
