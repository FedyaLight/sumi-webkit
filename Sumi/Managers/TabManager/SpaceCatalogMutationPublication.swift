import Combine
import Foundation

@MainActor
final class SpaceCatalogMutationPublication {
    private let persistence: TabStructuralPersistenceService
    private let changes: ObservableObjectPublisher

    init(
        persistence: TabStructuralPersistenceService,
        changes: ObservableObjectPublisher
    ) {
        self.persistence = persistence
        self.changes = changes
    }

    func willMutate() {
        changes.send()
    }

    func didMutate(
        spaceID: UUID,
        in transactions: TabStructuralLookupCoordinator
    ) {
        persistence.markAllSpacesStructurallyDirty()
        transactions.requestPublish(scope: .space(spaceID, catalog: true))
        persistence.scheduleStructuralPersistence()
    }
}
