import Foundation
import SumiChromeContracts

/// App-target adapter: sidebar chrome packages command through
/// `SidebarChromeCommanding` instead of importing `BrowserManager` / `TabManager`.
@MainActor
final class BrowserSidebarChromeCommandingAdapter: SidebarChromeCommanding {
    private let selectSpaceAction: @MainActor (UUID) -> Void
    private let createTabInSelectedSpaceAction: @MainActor () -> Void

    init(
        selectSpace: @escaping @MainActor (UUID) -> Void,
        createTabInSelectedSpace: @escaping @MainActor () -> Void
    ) {
        self.selectSpaceAction = selectSpace
        self.createTabInSelectedSpaceAction = createTabInSelectedSpace
    }

    convenience init(browserManager: BrowserManager) {
        self.init(
            selectSpace: { [weak browserManager] spaceID in
                guard let browserManager else { return }
                guard let space = browserManager.windowSessionBundle.spaceStateOwner.space(for: spaceID) else {
                    return
                }
                guard let windowState = browserManager.windowRegistry?.activeWindow else { return }
                browserManager.windowSessionBundle.spaceStateOwner.setActiveSpace(space, in: windowState)
            },
            createTabInSelectedSpace: { [weak browserManager] in
                guard let browserManager else { return }
                guard let windowState = browserManager.windowRegistry?.activeWindow else { return }
                let space = browserManager.windowSessionBundle.spaceStateOwner.space(
                    for: windowState.currentSpaceId
                )
                _ = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
                    in: space,
                    activate: true
                )
            }
        )
    }

    func selectSpace(id spaceID: UUID) {
        selectSpaceAction(spaceID)
    }

    func createTabInSelectedSpace() {
        createTabInSelectedSpaceAction()
    }
}
