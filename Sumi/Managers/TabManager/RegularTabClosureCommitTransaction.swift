import Foundation

@MainActor
final class RegularTabClosureCommitTransaction {
    private let regularTabs: RegularTabCollectionOwner
    private let spaces: TabSpaceCollectionStateOwner
    private let runtimeCleanup: RegularTabClosureRuntimeCleanup
    private let persistence: any TabClosurePersistence
    private let runtimePorts: TabRuntimePortConnection

    init(
        regularTabs: RegularTabCollectionOwner,
        spaces: TabSpaceCollectionStateOwner,
        runtimeCleanup: RegularTabClosureRuntimeCleanup,
        persistence: any TabClosurePersistence,
        runtimePorts: TabRuntimePortConnection
    ) {
        self.regularTabs = regularTabs
        self.spaces = spaces
        self.runtimeCleanup = runtimeCleanup
        self.persistence = persistence
        self.runtimePorts = runtimePorts
    }

    func commit(_ candidates: Set<UUID>) -> CommittedRegularTabClosures? {
        let removals = regularTabs.remove(
            candidates,
            in: spaces.spaces,
            currentSpaceId: spaces.currentSpace?.id
        )
        guard removals.isEmpty == false else { return nil }
        let runtime = runtimePorts.requireLease()
        runtimeCleanup.releaseConfirmedRemovals(removals, runtime: runtime)
        persistence.scheduleStructuralPersistence()
        return CommittedRegularTabClosures(
            removals: removals,
            runtime: runtime
        )
    }

    func commitExact(
        _ tab: Tab,
        in spaceID: UUID
    ) -> CommittedRegularTabClosures? {
        guard tab.spaceId == spaceID,
              let removal = regularTabs.remove(
                  ifIdentical: tab,
                  from: spaceID,
                  currentSpaceId: spaces.currentSpace?.id
              )
        else {
            return nil
        }
        persistence.cancelRuntimeStatePersistence(for: tab.id)
        let runtime = runtimePorts.requireLease()
        runtimeCleanup.releaseConfirmedRemovals(
            [removal],
            runtime: runtime
        )
        persistence.scheduleStructuralPersistence()
        return CommittedRegularTabClosures(
            removals: [removal],
            runtime: runtime
        )
    }

    func publish(_ committed: CommittedRegularTabClosures) {
        for removal in committed.removals {
            committed.runtime.captureClosedTab(
                removal.tab,
                sourceSpaceId: removal.spaceId
            )
        }
        committed.runtime.notifications()?.presentTabClosureNotification(
            tabCount: committed.removals.count
        )
        _ = committed.runtime.validateWindowStates()
    }
}
