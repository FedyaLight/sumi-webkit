import Foundation
import SumiDomain

struct MaterializedWindowSplit {
    let presentation: WindowSplitPresentation
    let activeTab: Tab
}

/// Resolves one durable group into a complete window-local presentation,
/// materializing only shortcut members missing from that window.
@MainActor
struct WindowSplitMaterializationService {
    func materialize(
        _ group: SumiDomain.SplitGroup,
        selection: WindowSplitSelection,
        in windowState: BrowserWindowState,
        tabManager: TabManager
    ) -> MaterializedWindowSplit? {
        guard tabManager.splitGroupStore.group(id: group.id) == group else {
            return nil
        }
        let projection = makeProjection(tabManager: tabManager)
        let initialResolution = projection.resolve(
            selection: selection,
            in: windowState.id
        )
        switch initialResolution {
        case .needsMaterialization(
            let resolvedGroup,
            let resolvedSelection,
            let shortcutPinIDs
        ):
            guard resolvedGroup == group, resolvedSelection == selection else {
                return nil
            }
            for pinID in shortcutPinIDs {
                guard let pin = tabManager.shortcutPinCollectionStateOwner
                    .shortcutPin(by: pinID) else {
                    return nil
                }
                _ = tabManager.shortcutTabMaterializer.materialize(
                    pin,
                    in: windowState.id,
                    currentSpaceId: group.container.spaceId
                        ?? pin.spaceId
                        ?? windowState.currentSpaceId
                )
            }
        case .ready:
            break
        case .inactive, .invalid:
            return nil
        }

        guard tabManager.splitGroupStore.group(id: group.id) == group,
              case .ready(let presentation) = projection.resolve(
                  selection: selection,
                  in: windowState.id
              ),
              let activeTab = activeTab(
                  for: presentation.activeMemberID,
                  in: windowState.id,
                  tabManager: tabManager
              ) else {
            return nil
        }
        return MaterializedWindowSplit(
            presentation: presentation,
            activeTab: activeTab
        )
    }

    private func makeProjection(
        tabManager: TabManager
    ) -> WindowSplitProjection {
        WindowSplitProjection(
            group: { tabManager.splitGroupStore.group(id: $0) },
            regularTabExists: {
                tabManager.regularTabCollectionOwner.tab(for: $0) != nil
            },
            shortcutPinExists: {
                tabManager.shortcutPinCollectionStateOwner
                    .shortcutPin(by: $0) != nil
            },
            shortcutLiveTabID: { pinID, windowID in
                tabManager.liveShortcutTabs.tab(
                    for: pinID,
                    in: windowID
                )?.id
            }
        )
    }

    private func activeTab(
        for memberID: SplitMemberID,
        in windowID: UUID,
        tabManager: TabManager
    ) -> Tab? {
        switch memberID {
        case .regularTab(let tabID):
            return tabManager.regularTabCollectionOwner.tab(for: tabID)
        case .shortcutPin(let pinID):
            return tabManager.liveShortcutTabs.tab(for: pinID, in: windowID)
        }
    }
}
