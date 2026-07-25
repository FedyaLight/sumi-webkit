import Foundation
import SumiDomain

struct ShortcutHostedSplitUnloadResult {
    let unloadedTabCount: Int
}

/// Stops presenting a shortcut-sidebar split in one window. The durable group
/// is already canonical and is therefore never rewritten during unload.
@MainActor
final class ShortcutHostedSplitUnloadService {
    private let admission: ShortcutHostedSplitUnloadAdmission
    private let splitMembership: SplitGroupMembershipQuery
    private let retirement: ShortcutLiveTabRetirementService
    private let fallback: ShortcutHostedSplitFallbackQuery
    private let visuals: BrowserWindowVisualCoordinator

    init(
        admission: ShortcutHostedSplitUnloadAdmission,
        splitMembership: SplitGroupMembershipQuery,
        retirement: ShortcutLiveTabRetirementService,
        fallback: ShortcutHostedSplitFallbackQuery,
        visuals: BrowserWindowVisualCoordinator
    ) {
        self.admission = admission
        self.splitMembership = splitMembership
        self.retirement = retirement
        self.fallback = fallback
        self.visuals = visuals
    }

    @discardableResult
    func unloadShortcutHostedSplitGroup(
        _ group: SumiDomain.SplitGroup,
        in windowState: BrowserWindowState
    ) -> ShortcutHostedSplitUnloadResult? {
        guard let pinIDs = admission.admittedPinIDs(for: group) else {
            return nil
        }
        var target = windowState.unpublishedShortcutMutationState
        target.splitSelection = nil
        if let fallback = fallback.visibleRegularTab(in: windowState) {
            _ = WindowTabSelectionStateApplicator.applyFallback(
                fallback,
                to: &target,
                splitMembership: splitMembership,
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
        ), preparedRetirement.result.didRetire else { return nil }
        let unloadedTabCount = preparedRetirement.result.retiredTabIds.count
        _ = visuals.performImmediateVisualHandoffIfPossible(in: windowState)

        _ = retirement.finish(preparedRetirement)
        visuals.refreshCompositor(for: windowState)
        return ShortcutHostedSplitUnloadResult(
            unloadedTabCount: unloadedTabCount
        )
    }
}
