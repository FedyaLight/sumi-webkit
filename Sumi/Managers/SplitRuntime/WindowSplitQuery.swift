import Foundation
import SumiDomain

/// Read-only window projection used by tab suspension, WebKit ownership and
/// split chrome. No query mutates durable or window-local state.
@MainActor
final class WindowSplitQuery {
    private let tabManager: @MainActor () -> TabManager?
    private let windowState: @MainActor (UUID) -> BrowserWindowState?
    private let previewIsActive: @MainActor (UUID) -> Bool

    init(
        tabManager: @escaping @MainActor () -> TabManager?,
        windowState: @escaping @MainActor (UUID) -> BrowserWindowState?,
        previewIsActive: @escaping @MainActor (UUID) -> Bool
    ) {
        self.tabManager = tabManager
        self.windowState = windowState
        self.previewIsActive = previewIsActive
    }

    func group(in windowID: UUID) -> SumiDomain.SplitGroup? {
        guard let selection = windowState(windowID)?.splitSelection else {
            return nil
        }
        guard let group = tabManager()?.splitGroupStore.group(
            id: selection.groupID
        ), group.contains(selection.activeMemberID) else {
            return nil
        }
        return group
    }

    func resolution(in windowID: UUID) -> WindowSplitResolution {
        guard let windowState = windowState(windowID),
              let tabManager = tabManager() else {
            return .inactive
        }
        return WindowSplitProjection(
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
        ).resolve(
            selection: windowState.splitSelection,
            in: windowID
        )
    }

    func visibleTabIDs(in windowID: UUID) -> [UUID] {
        if previewIsActive(windowID) {
            return windowState(windowID)?.currentTabId.map { [$0] } ?? []
        }
        return resolution(in: windowID).presentation?.visibleTabIDs ?? []
    }

    func contains(tabID: UUID, in windowID: UUID) -> Bool {
        resolution(in: windowID).presentation?.contains(tabID: tabID) == true
    }

    func isActive(tabID: UUID, in windowID: UUID) -> Bool {
        resolution(in: windowID).presentation?.activeTabID == tabID
    }

    func memberID(for tabID: UUID, in windowID: UUID) -> SplitMemberID? {
        resolution(in: windowID).presentation?.memberID(for: tabID)
    }
}
