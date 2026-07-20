import Foundation

/// Commits a non-split live shortcut retirement. History publication runs
/// only after exact retirement preparation and before visible handoff.
@MainActor
final class ShortcutLiveTabStandaloneCloseTransaction {
    private let tabStore: any ShellSelectionTabStore
    private let structuralLookup: TabStructuralLookupCoordinator
    private let retirement: ShortcutLiveTabRetirementService
    private let fallbackPlanner: BrowserTabCloseFallbackPlanner
    private let splitMembership: SplitGroupMembershipQuery
    private let visuals: BrowserWindowVisualCoordinator

    init(
        tabStore: any ShellSelectionTabStore,
        structuralLookup: TabStructuralLookupCoordinator,
        retirement: ShortcutLiveTabRetirementService,
        fallbackPlanner: BrowserTabCloseFallbackPlanner,
        splitMembership: SplitGroupMembershipQuery,
        visuals: BrowserWindowVisualCoordinator
    ) {
        self.tabStore = tabStore
        self.structuralLookup = structuralLookup
        self.retirement = retirement
        self.fallbackPlanner = fallbackPlanner
        self.splitMembership = splitMembership
        self.visuals = visuals
    }

    func close(
        _ tab: Tab,
        pinID: UUID,
        in windowState: BrowserWindowState,
        publishingHistory: @MainActor () -> Void
    ) -> Bool {
        guard tabStore.liveShortcutTabs(in: windowState.id).contains(where: {
            $0 === tab && $0.shortcutPinId == pinID
        }) else { return false }
        let wasCurrent = ShortcutSelectionIdentity.isSelected(
            tabId: tab.id,
            pinId: pinID,
            in: windowState
        )
        let fallback = wasCurrent
            ? fallbackPlanner.fallbackAfterClosingShortcutLiveTab(
                tab,
                in: windowState
            )
            : nil

        var target = windowState.unpublishedShortcutMutationState
        if wasCurrent, let fallback {
            _ = WindowTabSelectionStateApplicator.applyFallback(
                fallback,
                to: &target,
                splitMembership: splitMembership,
                updateSpaceFromTab: true,
                rememberSelection: true
            )
        } else if wasCurrent {
            target.currentTabId = nil
            target.currentShortcutPinId = nil
            target.currentShortcutPinRole = nil
            target.isShowingEmptyState = true
        }
        let preparedRetirement = structuralLookup.withTransaction {
            retirement.prepareRetirement(
                pinId: pinID,
                in: windowState.id,
                targetWindowState: target
            )
        }
        guard let preparedRetirement,
              preparedRetirement.result.didRetire else { return false }

        publishingHistory()
        if wasCurrent {
            _ = visuals.performImmediateVisualHandoffIfPossible(
                in: windowState
            )
        }
        _ = retirement.finish(preparedRetirement)
        return true
    }
}
