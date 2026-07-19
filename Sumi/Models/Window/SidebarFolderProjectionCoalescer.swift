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

    /// The projection a same-tick mutation would base itself on: any pending
    /// write wins over the flushed store. Always touches `store` so SwiftUI
    /// observation keeps tracking flushes even while a pending value wins.
    func pendingOrCurrentProjection(for folderID: UUID) -> SidebarFolderProjectionState {
        let current = store.projection(for: folderID)
        return pendingUpdates[folderID] ?? current
    }

    func scheduleUpdate(
        for folderID: UUID,
        stickyItemIDs: [UUID],
        hasActiveProjection: Bool
    ) {
        let projection = SidebarFolderProjectionState(
            stickyItemIDs: stickyItemIDs,
            hasActiveProjection: hasActiveProjection
        )
        scheduleMutation(for: folderID) { _ in projection }
    }

    /// Transforms the folder's projection on top of any same-tick pending
    /// write, so appends from one folder's handler survive prunes scheduled
    /// by another view in the same tick.
    func scheduleMutation(
        for folderID: UUID,
        _ transform: (SidebarFolderProjectionState) -> SidebarFolderProjectionState
    ) {
        let base = pendingUpdates[folderID] ?? store.projection(for: folderID)
        let projection = transform(base)

        if projection == base, pendingUpdates[folderID] == nil {
            return
        }

        pendingUpdates[folderID] = projection
        scheduleFlushIfNeeded()
    }

    private func scheduleFlushIfNeeded() {
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
