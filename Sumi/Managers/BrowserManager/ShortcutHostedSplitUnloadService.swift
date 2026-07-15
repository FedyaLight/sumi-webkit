import Foundation
import SumiDomain

/// Stops presenting a shortcut-sidebar split in one window. The durable group
/// is already canonical and is therefore never rewritten during unload.
@MainActor
final class ShortcutHostedSplitUnloadService {
    private let runtimeLease: () -> SplitShortcutRuntimeLease?
    private let performImmediateVisualHandoff: (BrowserWindowState) -> Void
    private let refreshCompositor: (BrowserWindowState) -> Void

    init(
        runtimeLease: @escaping () -> SplitShortcutRuntimeLease?,
        performImmediateVisualHandoff: @escaping (BrowserWindowState) -> Void,
        refreshCompositor: @escaping (BrowserWindowState) -> Void
    ) {
        self.runtimeLease = runtimeLease
        self.performImmediateVisualHandoff = performImmediateVisualHandoff
        self.refreshCompositor = refreshCompositor
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
        guard pinIDs.count == group.memberIDs.count else {
            return false
        }
        var target = windowState.unpublishedShortcutMutationState
        target.splitSelection = nil
        if let fallback = fallbackVisibleRegularTab(
            in: windowState,
            tabManager: runtime.tabManager
        ) {
            _ = WindowTabSelectionStateApplicator.apply(
                fallback,
                to: &target,
                updateSpaceFromTab: true,
                rememberSelection: true
            )
        } else {
            target.currentTabId = nil
            target.currentShortcutPinId = nil
            target.currentShortcutPinRole = nil
            target.isShowingEmptyState = true
        }
        guard let retirement = runtime.tabManager.structuralLookupCoordinator
            .withTransaction({
                runtime.tabManager.shortcutLiveTabRetirement
                    .prepareRetirements(
                        pinIds: pinIDs,
                        in: windowState.id,
                        targetWindowState: target
                    )
            }), retirement.result.didRetire else { return false }
        performImmediateVisualHandoff(windowState)

        _ = runtime.tabManager.shortcutLiveTabRetirement.finish(retirement)
        refreshCompositor(windowState)
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
