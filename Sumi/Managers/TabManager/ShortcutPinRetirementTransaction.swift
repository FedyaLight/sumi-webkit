import Foundation
import SumiDomain

@MainActor
final class ShortcutPinRetirementTransaction {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let pins: ShortcutPinCollectionStateOwner
    private let committer: ShortcutPinRetirementCommitter

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        pins: ShortcutPinCollectionStateOwner,
        committer: ShortcutPinRetirementCommitter
    ) {
        self.structuralLookup = structuralLookup
        self.pins = pins
        self.committer = committer
    }

    func remove(_ pin: ShortcutPin) {
        structuralLookup.withTransaction {
            guard self.pins.shortcutPin(by: pin.id) === pin else { return }
            committer.commit(pin)
        }
    }
}
