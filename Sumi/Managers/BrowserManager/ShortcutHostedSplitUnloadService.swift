import Foundation
import SumiDomain

/// Stops presenting a shortcut-sidebar split in one window. The durable group
/// is already canonical and is therefore never rewritten during unload.
@MainActor
final class ShortcutHostedSplitUnloadService {
    private let runtimeConnection: TabRuntimePortConnection
    private let splitGroups: SplitGroupStore
    private let retirement: ShortcutLiveTabRetirementService
    private let fallback: ShortcutHostedSplitFallbackQuery
    private let visuals: BrowserWindowVisualCoordinator

    init(
        runtimeConnection: TabRuntimePortConnection,
        splitGroups: SplitGroupStore,
        retirement: ShortcutLiveTabRetirementService,
        fallback: ShortcutHostedSplitFallbackQuery,
        visuals: BrowserWindowVisualCoordinator
    ) {
        self.runtimeConnection = runtimeConnection
        self.splitGroups = splitGroups
        self.retirement = retirement
        self.fallback = fallback
        self.visuals = visuals
    }

    @discardableResult
    func unloadShortcutHostedSplitGroup(
        _ group: SumiDomain.SplitGroup,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard runtimeConnection.current != nil,
              group.container.isShortcutSidebar,
              splitGroups.group(id: group.id) == group
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
        if let fallback = fallback.visibleRegularTab(in: windowState) {
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
        guard let preparedRetirement = retirement.prepareRetirements(
            pinIds: pinIDs,
            in: windowState.id,
            targetWindowState: target
        ), preparedRetirement.result.didRetire else { return false }
        _ = visuals.performImmediateVisualHandoffIfPossible(in: windowState)

        _ = retirement.finish(preparedRetirement)
        visuals.refreshCompositor(for: windowState)
        return true
    }
}
