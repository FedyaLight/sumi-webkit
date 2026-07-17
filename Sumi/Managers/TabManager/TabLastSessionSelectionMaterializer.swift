import Foundation

@MainActor
final class TabLastSessionSelectionMaterializer {
    private let spaces: TabSpaceCollectionStateOwner
    private let selection: TabSelectionStateOwner

    init(
        spaces: TabSpaceCollectionStateOwner,
        selection: TabSelectionStateOwner
    ) {
        self.spaces = spaces
        self.selection = selection
    }

    func materialize(
        _ plan: TabLastSessionMergePlan,
        spacesByID: [UUID: Space],
        regularTabsByID: [UUID: Tab]
    ) {
        switch plan.spaceSelection {
        case .keepCurrent:
            break
        case .select(let spaceID):
            spaces.replaceCurrentSpace(spaceID.flatMap { spacesByID[$0] })
        }
        if let tabID = plan.requestedCurrentTabId,
           let tab = regularTabsByID[tabID] {
            selection.replaceCurrentTab(tab)
        }
    }
}
