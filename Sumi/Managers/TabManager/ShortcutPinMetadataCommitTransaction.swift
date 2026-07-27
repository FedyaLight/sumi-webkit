import Foundation

@MainActor
final class ShortcutPinMetadataCommitTransaction {
    private let pins: ShortcutPinCollectionStateOwner
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let spacePinnedStructure: SpacePinnedStructureOwner
    private let bindings: ShortcutTabBindingSynchronizer

    init(
        pins: ShortcutPinCollectionStateOwner,
        structuralMutations: TabStructuralCollectionMutationOwner,
        spacePinnedStructure: SpacePinnedStructureOwner,
        bindings: ShortcutTabBindingSynchronizer
    ) {
        self.pins = pins
        self.structuralMutations = structuralMutations
        self.spacePinnedStructure = spacePinnedStructure
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
        case .essential:
            guard let profileID = source.profileId else { return false }
            var profilePins = pins.essentialPins(for: profileID)
            guard let index = profilePins.firstIndex(where: {
                $0 === source
            }) else { return false }
            profilePins[index] = target.refreshed(index: source.index)
            structuralMutations.setPinnedTabs(
                ShortcutPin.reindexed(profilePins),
                for: profileID
            )
            return true

        case .spacePinned:
            guard let spaceID = source.spaceId else { return false }
            if source.folderId == nil {
                var replaced = false
                let items = spacePinnedStructure
                    .topLevelSpacePinnedItems(for: spaceID)
                    .map { item in
                        guard case .shortcut(let candidate) = item,
                              candidate === source
                        else { return item }
                        replaced = true
                        return SpacePinnedStructureOwner.SpacePinnedTopLevelItem
                            .shortcut(target.refreshed(index: source.index))
                    }
                guard replaced else { return false }
                spacePinnedStructure.applyTopLevelSpacePinnedOrder(
                    items,
                    for: spaceID
                )
                return true
            }

            var replaced = false
            spacePinnedStructure.withSpacePinnedShortcutGroup(
                for: spaceID,
                folderId: source.folderId
            ) { folderPins in
                guard let index = folderPins.firstIndex(where: {
                    $0 === source
                }) else { return }
                folderPins[index] = target.refreshed(index: source.index)
                replaced = true
            }
            return replaced
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
