import Foundation

/// The persistence authority required by a tab-closing transaction.
@MainActor
protocol TabClosurePersistence: AnyObject {
    func cancelRuntimeStatePersistence(for tabId: UUID)
    func scheduleStructuralPersistence()
}

extension TabStructuralPersistenceService: TabClosurePersistence {}
