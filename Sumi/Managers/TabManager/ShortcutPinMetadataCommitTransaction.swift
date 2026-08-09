import Foundation

@MainActor
final class ShortcutPinMetadataCommitTransaction {
    private let pins: ShortcutPinCollectionStateOwner
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let bindings: ShortcutTabBindingSynchronizer

    init(
        pins: ShortcutPinCollectionStateOwner,
        structuralMutations: TabStructuralCollectionMutationOwner,
        bindings: ShortcutTabBindingSynchronizer
    ) {
        self.pins = pins
        self.structuralMutations = structuralMutations
        self.bindings = bindings
    }

    @discardableResult
    func commit(
        replacing current: ShortcutPin,
        with target: ShortcutPin,
        presentation: LiveShortcutPresentationRefreshAdmission
    ) -> ShortcutPin? {
        var accepted: ShortcutPin?
        let committed = structuralMutations.withReversibleSideEffects {
            guard let latest = self.pins.shortcutPin(by: current.id),
                  latest === current,
                  self.replace(latest, with: target),
                  let inserted = self.pins.shortcutPin(by: current.id),
                  Self.hasSameValue(inserted, as: target)
            else { return false }

            guard presentation.changes.isEmpty
                    || self.bindings.refreshInstances(
                        for: inserted,
                        admission: presentation
                    )
            else { return false }
            accepted = inserted
            return true
        }
        return committed ? accepted : nil
    }

    private func replace(
        _ source: ShortcutPin,
        with target: ShortcutPin
    ) -> Bool {
        switch source.role {
        case .favorite:
            guard let profileID = source.profileId else { return false }
            var profilePins = pins.pinnedByProfileSnapshot()[profileID] ?? []
            guard let index = profilePins.firstIndex(where: {
                $0 === source
            }) else { return false }
            profilePins[index] = target.refreshed(index: source.index)
            structuralMutations.setPinnedTabs(
                profilePins,
                for: profileID
            )
            return true

        case .spacePinned:
            guard let spaceID = source.spaceId else { return false }
            var spacePins = pins.spacePinnedShortcutsSnapshot()[spaceID] ?? []
            guard let index = spacePins.firstIndex(where: {
                $0 === source
            }) else { return false }
            spacePins[index] = target.refreshed(index: source.index)
            structuralMutations.setSpacePinnedShortcuts(
                spacePins,
                for: spaceID
            )
            return true
        }
    }

    private static func hasSameValue(
        _ lhs: ShortcutPin,
        as rhs: ShortcutPin
    ) -> Bool {
        lhs.id == rhs.id
            && lhs.role == rhs.role
            && lhs.profileId == rhs.profileId
            && lhs.executionProfileId == rhs.executionProfileId
            && lhs.spaceId == rhs.spaceId
            && lhs.index == rhs.index
            && lhs.folderId == rhs.folderId
            && lhs.launchURL == rhs.launchURL
            && lhs.title == rhs.title
            && lhs.iconAsset == rhs.iconAsset
            && lhs.titleIsCustom == rhs.titleIsCustom
    }
}
