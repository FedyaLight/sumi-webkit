import Foundation
import Observation
import SumiDomain

/// Owns window-local sidebar folder projection state and coalesces updates so
/// they never publish through shared models mid-view-update.
@MainActor
@Observable
final class SidebarFolderProjectionCoalescer {
    private(set) var store = SidebarFolderProjectionStore()

    @ObservationIgnored private var isFlushScheduled = false
    @ObservationIgnored private var pendingUpdates: [UUID: SidebarFolderProjectionState] = [:]

    func projection(for folderID: UUID) -> SidebarFolderProjectionState {
        store.projection(for: folderID)
    }

    func scheduleUpdate(
        for folderID: UUID,
        projectedChildIDs: [UUID],
        hasActiveProjection: Bool
    ) {
        let projection = SidebarFolderProjectionState(
            projectedChildIDs: projectedChildIDs,
            hasActiveProjection: hasActiveProjection
        )

        if store.projection(for: folderID) == projection,
           pendingUpdates[folderID] == nil {
            return
        }

        pendingUpdates[folderID] = projection
        guard !isFlushScheduled else { return }

        isFlushScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isFlushScheduled = false

            let updates = pendingUpdates
            pendingUpdates.removeAll()
            guard updates.isEmpty == false else { return }

            var nextStore = store
            var didChange = false

            for (folderID, projection) in updates {
                if nextStore.projection(for: folderID) == projection {
                    continue
                }
                nextStore.setProjection(projection, for: folderID)
                didChange = true
            }

            guard didChange else { return }
            store = nextStore
        }
    }
}
