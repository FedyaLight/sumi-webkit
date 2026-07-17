import Foundation

@MainActor
final class TabLastSessionMergePlanningService {
    private let planner: TabLastSessionMergePlanner
    private let snapshotter: TabLastSessionLiveStateSnapshotter

    init(
        planner: TabLastSessionMergePlanner,
        snapshotter: TabLastSessionLiveStateSnapshotter
    ) {
        self.planner = planner
        self.snapshotter = snapshotter
    }

    func prepare(_ snapshot: TabPersistenceSnapshot) -> PreparedTabLastSessionMerge {
        let current = snapshotter.prepare()
        return PreparedTabLastSessionMerge(
            plan: planner.makePlan(snapshot: snapshot, live: current.live),
            existingSpaces: current.spaces,
            existingFolders: current.folders,
            existingTabs: current.tabs
        )
    }
}
