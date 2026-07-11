import Foundation

/// Restores one shortcut member from a split to its launcher position. Split,
/// launcher, and registry mutations publish atomically; runtime teardown occurs
/// postcommit and the window session is written exactly once.
@MainActor
final class SplitShortcutMemberRestoreService {
    private struct CommitResult {
        let retirement: PreparedShortcutLiveTabRetirement?
        let needsEmptyState: Bool
    }

    private struct Restoration {
        let resolution: SplitShortcutMemberResolution
        let splitGroupId: UUID
        let remainingGroup: SplitGroup?
        let retiresLiveInstance: Bool
        let preparesVisualReplacement: Bool
    }

    private let runtimeLease: () -> SplitShortcutRuntimeLease?
    private let focus: SplitShortcutFocusService
    private let launcherPlacement: ShortcutSplitLauncherPlacementService
    private let selectTabWithoutPersistence: (Tab, BrowserWindowState) -> Void
    private let showEmptyStateWithoutPersistence: (BrowserWindowState) -> Void
    private let performImmediateVisualHandoff: (BrowserWindowState) -> Void
    private let persistWindowSession: (BrowserWindowState) -> Void

    init(
        runtimeLease: @escaping () -> SplitShortcutRuntimeLease?,
        focus: SplitShortcutFocusService,
        launcherPlacement: ShortcutSplitLauncherPlacementService,
        selectTabWithoutPersistence: @escaping (Tab, BrowserWindowState) -> Void,
        showEmptyStateWithoutPersistence: @escaping (BrowserWindowState) -> Void,
        performImmediateVisualHandoff: @escaping (BrowserWindowState) -> Void,
        persistWindowSession: @escaping (BrowserWindowState) -> Void
    ) {
        self.runtimeLease = runtimeLease
        self.focus = focus
        self.launcherPlacement = launcherPlacement
        self.selectTabWithoutPersistence = selectTabWithoutPersistence
        self.showEmptyStateWithoutPersistence = showEmptyStateWithoutPersistence
        self.performImmediateVisualHandoff = performImmediateVisualHandoff
        self.persistWindowSession = persistWindowSession
    }

    @discardableResult
    func restoreShortcutSplitMember(
        _ itemId: UUID,
        from group: SplitGroup,
        in windowState: BrowserWindowState,
        preserveLiveInstance: Bool = true
    ) -> Bool {
        guard let runtime = runtimeLease() else { return false }
        let tabManager = runtime.tabManager
        guard let resolution = SplitShortcutMemberResolver.resolve(
            itemId: itemId,
            in: group,
            windowState: windowState,
            tabManager: tabManager
        ) else { return false }
        let wasSelected = ShortcutSelectionIdentity.isSelected(
            tabId: resolution.member.tabId,
            pinId: resolution.member.pinId,
            in: windowState
        )
        let restoration = Restoration(
            resolution: resolution,
            splitGroupId: group.id,
            remainingGroup: group.removing(tabId: resolution.removalId),
            retiresLiveInstance: !preserveLiveInstance,
            preparesVisualReplacement: !preserveLiveInstance && wasSelected
        )

        guard let commit = commit(
            restoration,
            in: windowState,
            runtime: runtime
        ) else { return false }
        if commit.needsEmptyState {
            showEmptyStateWithoutPersistence(windowState)
            performImmediateVisualHandoff(windowState)
        }
        if let retirement = commit.retirement {
            _ = tabManager.shortcutLiveTabRetirement.finish(retirement)
        }
        finishSelection(
            restoration,
            wasSelected: wasSelected,
            in: windowState
        )
        focus.refreshPresentationWithinRuntimeLease(
            in: windowState,
            runtime: runtime
        )
        persistWindowSession(windowState)
        return true
    }

    private func commit(
        _ restoration: Restoration,
        in windowState: BrowserWindowState,
        runtime: SplitShortcutRuntimeLease
    ) -> CommitResult? {
        let tabManager = runtime.tabManager
        var retirement: PreparedShortcutLiveTabRetirement?
        var needsEmptyStateAfterRetirement = false
        var didCommit = false
        tabManager.structuralLookupCoordinator.withTransaction {
            if restoration.retiresLiveInstance {
                guard let pinId = restoration.resolution.member.pinId,
                      let prepared = tabManager.shortcutLiveTabRetirement
                        .prepareRetirement(
                            pinId: pinId,
                            in: windowState.id
                        ) else { return }
                retirement = prepared
            }
            if let remainingGroup = restoration.remainingGroup {
                tabManager.splitGroupStructureOwner.upsertSplitGroup(
                    remainingGroup
                )
            } else {
                tabManager.splitGroupStructureOwner.removeSplitGroup(
                    id: restoration.splitGroupId
                )
            }
            launcherPlacement.restore(restoration.resolution.member)
            if restoration.preparesVisualReplacement {
                needsEmptyStateAfterRetirement = !prepareVisualReplacement(
                    remainingGroup: restoration.remainingGroup,
                    in: windowState,
                    runtime: runtime
                )
            }
            didCommit = true
        }
        guard didCommit else { return nil }
        return CommitResult(
            retirement: retirement,
            needsEmptyState: needsEmptyStateAfterRetirement
        )
    }

    private func finishSelection(
        _ restoration: Restoration,
        wasSelected: Bool,
        in windowState: BrowserWindowState
    ) {
        if restoration.preparesVisualReplacement { return }
        guard restoration.retiresLiveInstance == false,
              let restoredLiveTab = restoration.resolution.restoredLiveTab,
              wasSelected || restoration.remainingGroup == nil
        else { return }
        selectTabWithoutPersistence(restoredLiveTab, windowState)
    }

    private func prepareVisualReplacement(
        remainingGroup: SplitGroup?,
        in windowState: BrowserWindowState,
        runtime: SplitShortcutRuntimeLease
    ) -> Bool {
        if let remainingGroup,
           focus.applyFocusWithinRuntimeLease(
            remainingGroup,
            in: windowState,
            runtime: runtime
           ) {
            performImmediateVisualHandoff(windowState)
            return true
        }
        if let fallback = fallbackVisibleRegularTab(
            in: windowState,
            tabManager: runtime.tabManager
        ) {
            selectTabWithoutPersistence(fallback, windowState)
            performImmediateVisualHandoff(windowState)
            return true
        }
        return false
    }

    private func fallbackVisibleRegularTab(
        in windowState: BrowserWindowState,
        tabManager: TabManager
    ) -> Tab? {
        guard let spaceId = windowState.currentSpaceId,
              let space = tabManager.spaceStateOwner.space(with: spaceId)
        else { return nil }
        return tabManager.regularTabCollectionOwner.tabs(in: space).first
    }
}
