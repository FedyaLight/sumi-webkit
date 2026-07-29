import Foundation

@MainActor
final class TabLastSessionMergeSettlement {
    private let lazyRestore: TabLazyRestoreCoordinator
    private let persistence: TabStructuralPersistenceService

    init(
        lazyRestore: TabLazyRestoreCoordinator,
        persistence: TabStructuralPersistenceService
    ) {
        self.lazyRestore = lazyRestore
        self.persistence = persistence
    }

    func settle(_ plan: TabLastSessionMergePlan) {
        lazyRestore.reset(restoredTabIDs: plan.lazyRestoredTabIds)
        persistence.scheduleStructuralPersistence()
    }
}
