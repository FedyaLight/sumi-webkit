import Combine
import Foundation

@MainActor
final class TabStructuralMutationPublisher {
    private let persistence: TabStructuralPersistenceService
    private let faviconService: any BrowserFaviconServicing
    private let lookup: TabStructuralLookupCoordinator
    private let changes: ObservableObjectPublisher
    private let regularTabs: RegularTabCollectionStateOwner

    init(
        persistence: TabStructuralPersistenceService,
        faviconService: any BrowserFaviconServicing,
        lookup: TabStructuralLookupCoordinator,
        changes: ObservableObjectPublisher,
        regularTabs: RegularTabCollectionStateOwner
    ) {
        self.persistence = persistence
        self.faviconService = faviconService
        self.lookup = lookup
        self.changes = changes
        self.regularTabs = regularTabs
    }

    func announceStateChange() {
        lookup.runBeforeCurrentBatchPublication { [changes] in changes.send() }
    }

    func publishTabsSnapshot() {
        lookup.runBeforeCurrentBatchPublication { [regularTabs] in
            regularTabs.publishTabsBySpaceSnapshot()
        }
    }

    @discardableResult
    func withTransaction<T>(_ operation: () throws -> T) rethrows -> T {
        try lookup.withTransaction(operation)
    }

    func publish(_ settlement: TabStructuralMutationTransaction.Settlement) {
        guard case .committed(let effects, let announce, let publishTabs) = settlement else {
            preconditionFailure("A rolled-back settlement belongs to the collection store")
        }
        withTransaction {
            effects.forEach(publish)
            if announce { announceStateChange() }
            if publishTabs { publishTabsSnapshot() }
        }
    }

    func publish(_ effect: TabStructuralMutationTransaction.Effect) {
        switch effect {
        case .regularTabs(let spaceID, let previous, let current):
            persistence.markRegularTabsSnapshotDirty(for: spaceID)
            persistence.recordRegularTabsStructuralChange(
                previous: previous,
                current: current
            )
            lookup.queueEntries(removing: previous, with: current)
            lookup.requestPublish(scope: .space(spaceID))
        case .folders(let spaceID, let previous, let current):
            persistence.markFoldersSnapshotDirty(for: spaceID)
            persistence.recordFoldersStructuralChange(
                previous: previous,
                current: current
            )
            lookup.requestPublish(scope: .space(spaceID))
        case .profilePins(let profileID, let previous, let current, let allPins):
            faviconService.syncShortcutPins(allPins)
            persistence.markPinnedSnapshotDirty(for: profileID)
            persistence.recordShortcutPinsStructuralChange(
                previous: previous,
                current: current
            )
            lookup.requestPublish(scope: .profile(profileID))
        case .spacePins(let spaceID, let previous, let current, let allPins):
            faviconService.syncShortcutPins(allPins)
            persistence.markSpacePinnedSnapshotDirty(for: spaceID)
            persistence.recordShortcutPinsStructuralChange(
                previous: previous,
                current: current
            )
            lookup.requestPublish(scope: .space(spaceID))
        }
    }
}
