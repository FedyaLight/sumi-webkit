import Foundation
import SumiDomain

struct TabShortcutPinDestination {
    let role: ShortcutPinRole
    let profileId: UUID?
    let spaceId: UUID?
    let folderId: UUID?
    let index: Int
    let opensFolder: Bool
}

/// Atomically turns a regular tab into a shortcut. Planning and authorization
/// are read-only; insertion and the authorized commit share one batch.
@MainActor
final class RegularTabShortcutConversionService {
    private let scheduleStructuralPersistence: () -> Void
    private let makeShortcutPin: (
        Tab,
        ShortcutPinRole,
        UUID?,
        UUID?,
        UUID?,
        Int
    ) -> ShortcutPin
    private let insertShortcutPin: (ShortcutPin, Int, Bool) -> ShortcutPin?
    private let planner: RegularTabShortcutConversionPlanner
    private let authorizer: TabShortcutConversionAuthorizer
    private let displayedCommitter: DisplayedTabShortcutConversionCommitter
    private let detachedConverter: DetachedTabShortcutConverter
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        scheduleStructuralPersistence: @escaping () -> Void,
        makeShortcutPin: @escaping (
            Tab,
            ShortcutPinRole,
            UUID?,
            UUID?,
            UUID?,
            Int
        ) -> ShortcutPin,
        insertShortcutPin: @escaping (
            ShortcutPin,
            Int,
            Bool
        ) -> ShortcutPin?,
        planner: RegularTabShortcutConversionPlanner,
        authorizer: TabShortcutConversionAuthorizer,
        displayedCommitter: DisplayedTabShortcutConversionCommitter,
        detachedConverter: DetachedTabShortcutConverter,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.scheduleStructuralPersistence = scheduleStructuralPersistence
        self.makeShortcutPin = makeShortcutPin
        self.insertShortcutPin = insertShortcutPin
        self.planner = planner
        self.authorizer = authorizer
        self.displayedCommitter = displayedCommitter
        self.detachedConverter = detachedConverter
        self.structuralLookup = structuralLookup
    }

    func prepare(
        _ tab: Tab,
        preferredWindowId: UUID? = nil
    ) -> TabShortcutConversionPreparation {
        planner.prepareConversion(tab, preferredWindowId: preferredWindowId)
    }

    @discardableResult
    func convert(
        _ tab: Tab,
        destination: TabShortcutPinDestination,
        preferredWindowId: UUID? = nil
    ) -> ShortcutPin? {
        commit(
            tab,
            preparation: prepare(
                tab,
                preferredWindowId: preferredWindowId
            ),
            destination: destination
        )
    }

    @discardableResult
    func commit(
        _ tab: Tab,
        preparation: TabShortcutConversionPreparation,
        destination: TabShortcutPinDestination
    ) -> ShortcutPin? {
        let pin = makeShortcutPin(
            tab,
            destination.role,
            destination.profileId,
            destination.spaceId,
            destination.folderId,
            destination.index
        )
        guard let authorization = authorizer.authorize(
            preparation,
            for: tab,
            candidatePin: pin
        ) else { return nil }
        let insertedPin: ShortcutPin? = structuralLookup.withTransaction {
            guard let inserted = insertShortcutPin(
                pin,
                destination.index,
                destination.opensFolder
            ) else { return nil }
            switch authorization {
            case .displayed(let authorized):
                displayedCommitter.commit(to: inserted, using: authorized)
            case .detached(let authorized):
                detachedConverter.commit(using: authorized)
            }
            return inserted
        }
        guard let insertedPin else { return nil }
        scheduleStructuralPersistence()
        return insertedPin
    }
}
