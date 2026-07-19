import Foundation
import Observation
import SumiDomain

/// Window-local expansion and sticky-row state for each Space pinned section.
@MainActor
@Observable
final class SidebarSpacePinnedCollapseState {
    private(set) var collapsedSpaceIDs: Set<UUID> = []
    private(set) var projectionStore = SidebarFolderProjectionStore()

    @ObservationIgnored private var isFlushScheduled = false
    @ObservationIgnored private var pendingUpdates: [UUID: SidebarFolderProjectionState] = [:]

    var persistedCollapsedSpaceIDs: [UUID] {
        collapsedSpaceIDs.sorted { $0.uuidString < $1.uuidString }
    }

    func isCollapsed(_ spaceID: UUID) -> Bool {
        collapsedSpaceIDs.contains(spaceID)
    }

    @discardableResult
    func setCollapsed(_ isCollapsed: Bool, for spaceID: UUID) -> Bool {
        let changed: Bool
        if isCollapsed {
            changed = collapsedSpaceIDs.insert(spaceID).inserted
        } else {
            changed = collapsedSpaceIDs.remove(spaceID) != nil
            clearProjection(for: spaceID)
        }
        return changed
    }

    func restoreCollapsedSpaceIDs(_ spaceIDs: [UUID]) {
        collapsedSpaceIDs = Set(spaceIDs)
        projectionStore = SidebarFolderProjectionStore()
        pendingUpdates.removeAll()
    }

    @discardableResult
    func removeSpace(_ spaceID: UUID) -> Bool {
        let changed = collapsedSpaceIDs.remove(spaceID) != nil
        clearProjection(for: spaceID)
        return changed
    }

    func projection(for spaceID: UUID) -> SidebarFolderProjectionState {
        projectionStore.projection(for: spaceID)
    }

    func pendingOrCurrentProjection(for spaceID: UUID) -> SidebarFolderProjectionState {
        let current = projectionStore.projection(for: spaceID)
        return pendingUpdates[spaceID] ?? current
    }

    func scheduleMutation(
        for spaceID: UUID,
        _ transform: (SidebarFolderProjectionState) -> SidebarFolderProjectionState
    ) {
        let base = pendingUpdates[spaceID] ?? projectionStore.projection(for: spaceID)
        let projection = transform(base)
        guard projection != base || pendingUpdates[spaceID] != nil else { return }

        pendingUpdates[spaceID] = projection
        scheduleFlushIfNeeded()
    }

    private func clearProjection(for spaceID: UUID) {
        pendingUpdates.removeValue(forKey: spaceID)
        var nextStore = projectionStore
        nextStore.setProjection(.empty, for: spaceID)
        if nextStore != projectionStore {
            projectionStore = nextStore
        }
    }

    private func scheduleFlushIfNeeded() {
        guard !isFlushScheduled else { return }
        isFlushScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isFlushScheduled = false

            let updates = pendingUpdates
            pendingUpdates.removeAll()
            guard !updates.isEmpty else { return }

            var nextStore = projectionStore
            for (spaceID, projection) in updates {
                nextStore.setProjection(projection, for: spaceID)
            }
            if nextStore != projectionStore {
                projectionStore = nextStore
            }
        }
    }
}
