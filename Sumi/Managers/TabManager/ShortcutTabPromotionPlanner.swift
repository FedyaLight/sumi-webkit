import Foundation
import SumiDomain

/// Joins source admission with the durable regular-tab placement plan.
@MainActor
final class ShortcutTabPromotionPlanner {
    private let spaces: TabSpaceCollectionStateOwner
    private let splitGroups: SplitGroupStore
    private let regularTabs: RegularTabCollectionOwner
    private let sources: ShortcutTabPromotionSourcePlanner

    init(
        spaces: TabSpaceCollectionStateOwner,
        splitGroups: SplitGroupStore,
        regularTabs: RegularTabCollectionOwner,
        sources: ShortcutTabPromotionSourcePlanner
    ) {
        self.spaces = spaces
        self.splitGroups = splitGroups
        self.regularTabs = regularTabs
        self.sources = sources
    }

    func prepare(
        _ pin: ShortcutPin,
        targetSpaceID: UUID,
        targetIndex: Int?,
        preferredWindowID: UUID?,
        allowsGroupedPin: Bool
    ) -> ShortcutTabPromotionPlan? {
        guard spaces.contains(spaceId: targetSpaceID),
              allowsGroupedPin || splitGroups.group(
                  containing: .shortcutPin(pin.id)
              ) == nil,
              let source = sources.prepareSource(
                  pin,
                  targetSpaceID: targetSpaceID,
                  preferredWindowID: preferredWindowID
              ), let placement = regularTabs.preparePlacement(
                  source.tab,
                  in: targetSpaceID,
                  at: targetIndex
              ) else { return nil }
        return ShortcutTabPromotionPlan(
            pinID: pin.id,
            tab: source.tab,
            chosenEntry: source.chosenEntry,
            selectedWindowStates: source.selectedWindowStates,
            targetSpaceID: targetSpaceID,
            targetIndex: targetIndex,
            runtime: source.runtime,
            placement: placement
        )
    }
}
