import Foundation
import SumiDomain

/// Publishes window-local split reconciliation exactly once after physical Tab
/// cleanup has reached its terminal state.
@MainActor
final class PreparedSplitTabClosureSettlement: TabSplitClosureSettlement {
    private let presentations: WindowSplitPresentationSynchronizer
    private let previousGroups: [SumiDomain.SplitGroup]
    private let affectedGroupIDs: Set<UUID>
    private var isPublished = false

    init(
        presentations: WindowSplitPresentationSynchronizer,
        previousGroups: [SumiDomain.SplitGroup],
        affectedGroupIDs: Set<UUID>
    ) {
        self.presentations = presentations
        self.previousGroups = previousGroups
        self.affectedGroupIDs = affectedGroupIDs
    }

    func publish() {
        guard !isPublished else { return }
        isPublished = true
        presentations.synchronize(
            previousGroups: previousGroups,
            affectedGroupIDs: affectedGroupIDs
        )
    }
}

/// Applies one durable regular-tab closure batch to split topology and clears
/// only the drag-layout cache made stale by that batch.
@MainActor
final class SplitTabClosureService {
    private let dropTargets: SplitDropTargetService
    private let layout: SplitLayoutService

    init(dropTargets: SplitDropTargetService, layout: SplitLayoutService) {
        self.dropTargets = dropTargets
        self.layout = layout
    }

    func stage(
        _ tabIDs: Set<UUID>
    ) -> PreparedSplitTabClosureSettlement? {
        guard !tabIDs.isEmpty else { return nil }
        dropTargets.clearCachedLayouts()
        return layout.stageClosedRegularTabs(tabIDs)
    }
}
