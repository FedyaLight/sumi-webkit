import Foundation

@MainActor
final class TabLastSessionRegularTabMaterializer {
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let membership: TabCollectionMembershipOwner
    private let tabFactory: TabFactory

    init(
        structuralMutations: TabStructuralCollectionMutationOwner,
        membership: TabCollectionMembershipOwner,
        tabFactory: TabFactory
    ) {
        self.structuralMutations = structuralMutations
        self.membership = membership
        self.tabFactory = tabFactory
    }

    func materialize(
        _ plan: TabLastSessionMergePlan,
        existing: [TabLastSessionRegularTabKey: Tab]
    ) -> [UUID: Tab] {
        var tabsByID: [UUID: Tab] = [:]
        for spaceID in plan.orderedSpaceIds {
            let tabs = (plan.regularTabsBySpace[spaceID] ?? [])
                .enumerated().map { offset, placement -> Tab in
                    let tab: Tab
                    switch placement {
                    case .existing(let id, let sourceSpaceID, _):
                        guard let liveTab = existing[
                            TabLastSessionRegularTabKey(
                                spaceID: sourceSpaceID,
                                tabID: id
                            )
                        ] else {
                            preconditionFailure(
                                "Last-session plan referenced a missing live tab"
                            )
                        }
                        tab = liveTab
                    case .restored(let restored):
                        let restoredTab = tabFactory.makeTab(
                            id: restored.id,
                            url: restored.url,
                            name: restored.name,
                            favicon: "globe",
                            spaceId: restored.spaceId,
                            index: offset,
                            loadsCachedFaviconOnInit: false
                        )
                        restoredTab.profileId = restored.profileId
                        restoredTab.canGoBack = restored.canGoBack
                        restoredTab.canGoForward = restored.canGoForward
                        membership.attach(restoredTab)
                        tab = restoredTab
                    }
                    tab.spaceId = spaceID
                    tab.index = offset
                    tabsByID[tab.id] = tab
                    return tab
                }
            structuralMutations.setTabs(tabs, for: spaceID)
        }
        return tabsByID
    }
}
