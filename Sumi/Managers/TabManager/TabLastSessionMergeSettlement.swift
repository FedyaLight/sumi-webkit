import Foundation

@MainActor
final class TabLastSessionMergeSettlement {
    private let persistence: TabStructuralPersistenceService

    init(persistence: TabStructuralPersistenceService) {
        self.persistence = persistence
    }

    func settle(_: TabLastSessionMergePlan) {
        persistence.scheduleStructuralPersistence()
    }
}
