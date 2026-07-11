import Foundation

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

    func handle(_ tabID: UUID) {
        handle([tabID])
    }

    func handle(_ tabIDs: Set<UUID>) {
        guard !tabIDs.isEmpty else { return }
        dropTargets.clearCachedLayouts()
        layout.handleClosedRegularTabs(tabIDs)
    }
}
