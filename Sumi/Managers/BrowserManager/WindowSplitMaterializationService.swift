import Foundation
import SumiDomain

struct MaterializedWindowSplit {
    let presentation: WindowSplitPresentation
    let activeTab: Tab
}

/// Resolves one durable group into a complete window-local presentation after
/// every shortcut member has crossed exact window/Space admission.
@MainActor
struct WindowSplitMaterializationService {
    func withMaterialization(
        _ group: SumiDomain.SplitGroup,
        selection: WindowSplitSelection,
        in windowState: BrowserWindowState,
        tabManager: TabManager,
        finalizing: (MaterializedWindowSplit) -> Void
    ) -> Bool {
        guard tabManager.splitGroupStore.group(id: group.id) == group else {
            return false
        }
        let shortcutRequests = group.memberIDs.compactMap {
            memberID -> ShortcutPresentationActivationService.Request? in
            guard case .shortcutPin(let pinID) = memberID else { return nil }
            return .init(
                pinID: pinID,
                windowID: windowState.id,
                presentationSpaceID: group.container.spaceId
                    ?? windowState.currentSpaceId
            )
        }
        return tabManager.structuralLookupCoordinator.withTransaction {
            var result: MaterializedWindowSplit?
            guard tabManager.shortcutPresentationActivation
                .withActivation(shortcutRequests, applying: { _ in
                let projection = makeProjection(tabManager: tabManager)
                guard tabManager.splitGroupStore.group(id: group.id) == group,
                      case .ready(let presentation) = projection.resolve(
                          selection: selection,
                          in: windowState.id
                      ),
                      let activeTab = activeTab(
                          for: presentation.activeMemberID,
                          in: windowState.id,
                          tabManager: tabManager
                      ) else { return false }
                result = MaterializedWindowSplit(
                    presentation: presentation,
                    activeTab: activeTab
                )
                return true
            }), let result else { return false }
            finalizing(result)
            return true
        }
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
