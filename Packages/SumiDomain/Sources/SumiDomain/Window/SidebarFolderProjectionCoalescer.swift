import Foundation
import Observation

public struct SidebarFolderProjectionState: Equatable {
    public var projectedChildIDs: [UUID] = []
    public var hasActiveProjection: Bool = false

    public init(
        projectedChildIDs: [UUID] = [],
        hasActiveProjection: Bool = false
    ) {
        self.projectedChildIDs = projectedChildIDs
        self.hasActiveProjection = hasActiveProjection
    }

    public static let empty = SidebarFolderProjectionState()
}

public struct SidebarFolderProjectionStore: Equatable {
    fileprivate var projectionsByFolderID: [UUID: SidebarFolderProjectionState] = [:]

    public init() {}

    public func projection(for folderID: UUID) -> SidebarFolderProjectionState {
        projectionsByFolderID[folderID] ?? .empty
    }

    public mutating func setProjection(
        _ projection: SidebarFolderProjectionState,
        for folderID: UUID
    ) {
        if projection == .empty {
            projectionsByFolderID.removeValue(forKey: folderID)
            return
        }
        projectionsByFolderID[folderID] = projection
    }
}

/// Owns window-local sidebar folder projection state and coalesces updates so
/// they never publish through shared models mid-view-update.
@MainActor
@Observable
public final class SidebarFolderProjectionCoalescer {
    public init() {}
    public private(set) var store: SidebarFolderProjectionStore = .init()

    @ObservationIgnored private var isFlushScheduled: Bool = false
    @ObservationIgnored private var pendingUpdates: [UUID: SidebarFolderProjectionState] = [:]

    public func projection(for folderID: UUID) -> SidebarFolderProjectionState {
        store.projection(for: folderID)
    }

    public func scheduleUpdate(
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
            self.isFlushScheduled = false

            let updates = self.pendingUpdates
            self.pendingUpdates.removeAll()

            guard updates.isEmpty == false else { return }

            var nextStore = self.store
            var didChange = false

            for (folderID, projection) in updates {
                if nextStore.projection(for: folderID) == projection {
                    continue
                }
                nextStore.setProjection(projection, for: folderID)
                didChange = true
            }

            guard didChange else { return }
            self.store = nextStore
        }
    }
}
