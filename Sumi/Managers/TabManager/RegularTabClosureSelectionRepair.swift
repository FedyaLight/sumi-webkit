import Foundation

@MainActor
final class RegularTabClosureSelectionRepair {
    private let selection: TabSelectionStateOwner
    private let spaces: TabSpaceCollectionStateOwner
    private let regularTabs: RegularTabCollectionOwner
    private let shortcutPresentation: TabShortcutPresentationOwner

    init(
        selection: TabSelectionStateOwner,
        spaces: TabSpaceCollectionStateOwner,
        regularTabs: RegularTabCollectionOwner,
        shortcutPresentation: TabShortcutPresentationOwner
    ) {
        self.selection = selection
        self.spaces = spaces
        self.regularTabs = regularTabs
        self.shortcutPresentation = shortcutPresentation
    }

    var currentTab: Tab? { selection.currentTab }

    func repair(
        after removals: [RegularTabCollectionOwner.Removal],
        removedCurrentTab: Tab?,
        profileID: UUID?
    ) {
        guard let removedCurrentTab,
              let currentRemoval = removals.first(where: {
                  $0.tab.id == removedCurrentTab.id
              }) else { return }
        let snapshot = makeSnapshot(
            forRemovedCurrent: currentRemoval.tab,
            removedIndexInCurrentSpace: currentRemoval.indexInCurrentSpace,
            profileID: profileID
        )
        switch SelectionAfterClosurePolicy.decision(from: snapshot) {
        case .keepCurrent:
            break
        case .replaceCurrent(let tab):
            selection.replaceCurrentTab(tab)
        }
    }

    private func makeSnapshot(
        forRemovedCurrent tab: Tab,
        removedIndexInCurrentSpace: Int?,
        profileID: UUID?
    ) -> SelectionAfterClosurePolicy.Snapshot {
        let currentSpace = spaces.currentSpace
        let spacePinnedTabs: [Tab]
        let spaceRegularTabs: [Tab]
        if let currentSpace {
            spacePinnedTabs = shortcutPresentation.liveSpacePinnedTabs(
                for: currentSpace.id
            )
            spaceRegularTabs = regularTabs.tabs(in: currentSpace.id)
        } else {
            spacePinnedTabs = []
            spaceRegularTabs = []
        }
        return SelectionAfterClosurePolicy.Snapshot(
            removedWasGlobalPinned: tab.spaceId == nil,
            hasCurrentSpace: currentSpace != nil,
            essentialTabs: shortcutPresentation.activeEssentialTabs(
                for: profileID
            ),
            spacePinnedTabs: spacePinnedTabs,
            regularTabs: spaceRegularTabs,
            removedIndexInCurrentSpace: removedIndexInCurrentSpace
        )
    }
}
