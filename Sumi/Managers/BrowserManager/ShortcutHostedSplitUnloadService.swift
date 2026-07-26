import Foundation
import SumiDomain

struct ShortcutHostedSplitUnloadResult {
    let unloadedTabCount: Int
}

/// Retires one shortcut-sidebar split's runtime pages in a window. The durable
/// group is never rewritten; foreground presentation changes only when that
/// exact group owns it.
@MainActor
final class ShortcutHostedSplitUnloadService {
    private let planner: ShortcutHostedSplitUnloadPlanner
    private let retirement: ShortcutLiveTabRetirementService
    private let visuals: BrowserWindowVisualCoordinator

    init(
        planner: ShortcutHostedSplitUnloadPlanner,
        retirement: ShortcutLiveTabRetirementService,
        visuals: BrowserWindowVisualCoordinator
    ) {
        self.planner = planner
        self.retirement = retirement
        self.visuals = visuals
    }

    @discardableResult
    func unloadShortcutHostedSplitGroup(
        _ group: SumiDomain.SplitGroup,
        in windowState: BrowserWindowState
    ) -> ShortcutHostedSplitUnloadResult? {
        guard let plan = planner.plan(group: group, in: windowState) else {
            return nil
        }
        guard let preparedRetirement = retirement.prepareRetirements(
            pinIds: plan.pinIDs,
            in: windowState.id,
            targetWindowState: plan.targetWindowState
        ), preparedRetirement.result.didRetire else { return nil }
        let unloadedTabCount = preparedRetirement.result.retiredTabIds.count
        if plan.replacesPresentation {
            _ = visuals.performImmediateVisualHandoffIfPossible(
                in: windowState
            )
        }

        _ = retirement.finish(preparedRetirement)
        if plan.replacesPresentation {
            visuals.refreshCompositor(for: windowState)
        }
        return ShortcutHostedSplitUnloadResult(
            unloadedTabCount: unloadedTabCount
        )
    }
}
