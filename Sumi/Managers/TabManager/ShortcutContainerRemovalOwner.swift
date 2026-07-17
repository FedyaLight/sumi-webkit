import Foundation

/// Removes a tab from whichever structural container currently holds it: an
/// essentials/space-pinned shortcut array or a space's regular-tab list.
@MainActor
final class ShortcutContainerRemovalOwner {
    private let pins: ShortcutPinCollectionStateOwner
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let regularTabs: RegularTabCollectionOwner
    private let spaces: TabSpaceCollectionStateOwner

    init(
        pins: ShortcutPinCollectionStateOwner,
        structuralMutations: TabStructuralCollectionMutationOwner,
        regularTabs: RegularTabCollectionOwner,
        spaces: TabSpaceCollectionStateOwner
    ) {
        self.pins = pins
        self.structuralMutations = structuralMutations
        self.regularTabs = regularTabs
        self.spaces = spaces
    }

    @discardableResult
    func removeFromCurrentContainer(_ tab: Tab) -> Bool {
        for (profileId, profilePins) in pins.pinnedByProfileSnapshot() {
            if let index = profilePins.firstIndex(where: { $0.id == tab.id }) {
                var copy = profilePins
                if index < copy.count { copy.remove(at: index) }
                structuralMutations.setPinnedTabs(copy, for: profileId)
                return true
            }
        }

        if let spaceId = tab.spaceId {
            return regularTabs.remove(
                ifIdentical: tab,
                from: spaceId,
                currentSpaceId: spaces.currentSpace?.id
            ) != nil
        }
        return false
    }

    func containsIdenticalRegularTab(_ tab: Tab, in spaceID: UUID) -> Bool {
        regularTabs.containsIdentical(tab, in: spaceID)
    }
}
