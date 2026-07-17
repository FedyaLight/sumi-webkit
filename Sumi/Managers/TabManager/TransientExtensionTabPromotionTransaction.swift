import Foundation

@MainActor
final class TransientExtensionTabPromotionTransaction {
    private let spaces: TabSpaceCollectionStateOwner
    private let membership: TabCollectionMembershipOwner
    private let regularTabs: RegularTabCollectionOwner
    private let persistence: TabStructuralPersistenceService
    private let selection: TabActiveSelectionOwner

    init(
        spaces: TabSpaceCollectionStateOwner,
        membership: TabCollectionMembershipOwner,
        regularTabs: RegularTabCollectionOwner,
        persistence: TabStructuralPersistenceService,
        selection: TabActiveSelectionOwner
    ) {
        self.spaces = spaces
        self.membership = membership
        self.regularTabs = regularTabs
        self.persistence = persistence
        self.selection = selection
    }

    func promote(_ tab: Tab, in requestedSpace: Space?, activate: Bool) -> Bool {
        guard membership.isTransientExtensionTab(tab),
              membership.tab(for: tab.id) === tab else {
            return false
        }
        guard let targetSpace = requestedSpace
            ?? tab.spaceId.flatMap(spaces.space(with:)),
              spaces.space(with: targetSpace.id) === targetSpace else {
            RuntimeDiagnostics.debug(
                "Skipping transient extension tab promotion for '\(tab.name)' because no exact target space was resolved.",
                category: "TabManager"
            )
            return false
        }
        guard let placement = regularTabs.preparePlacement(
            tab,
            in: targetSpace.id,
            at: nil
        ) else { return false }
        guard membership.promoteTransientExtensionTab(tab) else {
            precondition(placement.cancel())
            return false
        }
        guard placement.commit() else {
            precondition(
                !regularTabs.containsIdentical(tab, in: targetSpace.id),
                "Failed promotion left the Tab in regular membership"
            )
            membership.registerTransientExtensionTab(tab)
            precondition(
                membership.tab(for: tab.id) === tab,
                "Failed promotion must restore the exact transient Tab"
            )
            return false
        }

        persistence.scheduleStructuralPersistence()
        if activate {
            selection.setActiveTab(tab)
        }
        return true
    }
}
