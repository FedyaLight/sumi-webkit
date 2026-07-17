import Foundation
import SwiftData

/// SwiftData adapter for the pure restore planner.
struct TabRestoreLoader: TabRestorePayloadLoading {
    private let reader: TabRestoreStoreReader
    private let planner: TabRestorePlanner
    private let blockedProfileIDs: Set<UUID>

    init(
        container: ModelContainer,
        blockedProfileIDs: Set<UUID> = [],
        planner: TabRestorePlanner = TabRestorePlanner()
    ) {
        self.reader = TabRestoreStoreReader(container: container)
        self.blockedProfileIDs = blockedProfileIDs
        self.planner = planner
    }

    func load(defaultProfileId: UUID?) async throws -> TabRestorePayload {
        let signpostState = PerformanceTrace.beginInterval("TabRestoreLoader.load")
        defer {
            PerformanceTrace.endInterval("TabRestoreLoader.load", signpostState)
        }
        let records = try await reader.read()
        return planner.makePayload(
            from: records,
            defaultProfileId: defaultProfileId,
            blockedProfileIDs: blockedProfileIDs
        )
    }
}
