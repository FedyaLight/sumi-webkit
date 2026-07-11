import Foundation
import SumiDomain

/// Stops presenting a shortcut-sidebar split in one window. The durable group
/// is already canonical and is therefore never rewritten during unload.
@MainActor
final class ShortcutHostedSplitUnloadService {
    private let runtimeLease: () -> SplitShortcutRuntimeLease?
    private let selectTabWithoutPersistence: (Tab, BrowserWindowState) -> Void
    private let showEmptyStateWithoutPersistence: (BrowserWindowState) -> Void
    private let performImmediateVisualHandoff: (BrowserWindowState) -> Void
    private let refreshCompositor: (BrowserWindowState) -> Void
    private let persistWindowSession: (BrowserWindowState) -> Void

    init(
        runtimeLease: @escaping () -> SplitShortcutRuntimeLease?,
        selectTabWithoutPersistence: @escaping (Tab, BrowserWindowState) -> Void,
        showEmptyStateWithoutPersistence: @escaping (BrowserWindowState) -> Void,
        performImmediateVisualHandoff: @escaping (BrowserWindowState) -> Void,
        refreshCompositor: @escaping (BrowserWindowState) -> Void,
        persistWindowSession: @escaping (BrowserWindowState) -> Void
    ) {
        self.runtimeLease = runtimeLease
        self.selectTabWithoutPersistence = selectTabWithoutPersistence
        self.showEmptyStateWithoutPersistence = showEmptyStateWithoutPersistence
        self.performImmediateVisualHandoff = performImmediateVisualHandoff
        self.refreshCompositor = refreshCompositor
        self.persistWindowSession = persistWindowSession
    }

    @discardableResult
    func unloadShortcutHostedSplitGroup(
        _ group: SumiDomain.SplitGroup,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard let runtime = runtimeLease(),
              group.container.isShortcutSidebar,
              runtime.tabManager.splitGroupStore.group(id: group.id) == group
        else {
            return false
        }

        let pinIDs = Set(group.memberIDs.compactMap { memberID -> UUID? in
            guard case .shortcutPin(let pinID) = memberID else { return nil }
            return pinID
        })
        guard pinIDs.count == group.memberIDs.count,
              let retirement = runtime.tabManager.shortcutLiveTabRetirement
                .prepareRetirements(pinIds: pinIDs, in: windowState.id) else {
            return false
        }

        windowState.splitSelection = nil
        if let fallback = fallbackVisibleRegularTab(
            in: windowState,
            tabManager: runtime.tabManager
        ) {
            selectTabWithoutPersistence(fallback, windowState)
        } else {
            showEmptyStateWithoutPersistence(windowState)
        }
        performImmediateVisualHandoff(windowState)

        _ = runtime.tabManager.shortcutLiveTabRetirement.finish(retirement)
        refreshCompositor(windowState)
        persistWindowSession(windowState)
        return true
    }

    private func fallbackVisibleRegularTab(
        in windowState: BrowserWindowState,
        tabManager: TabManager
    ) -> Tab? {
        guard let spaceID = windowState.currentSpaceId,
              let space = tabManager.spaceStateOwner.space(with: spaceID) else {
            return nil
        }
        return tabManager.regularTabCollectionOwner.tabs(in: space).first
    }
}
