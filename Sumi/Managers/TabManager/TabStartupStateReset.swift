import Foundation

/// Retires startup-only live tab instances and clears regular collections while
/// preserving spaces, folders, and persisted launcher definitions.
@MainActor
final class TabStartupStateReset {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let runtimeReset: TabStartupRuntimeResetTransaction
    private let splitGroupReset: TabStartupSplitGroupResetTransaction
    private let regularCollectionReset: TabStartupRegularCollectionResetTransaction
    private let transientStateReset: TabStartupTransientStateResetTransaction

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        runtimeReset: TabStartupRuntimeResetTransaction,
        splitGroupReset: TabStartupSplitGroupResetTransaction,
        regularCollectionReset: TabStartupRegularCollectionResetTransaction,
        transientStateReset: TabStartupTransientStateResetTransaction
    ) {
        self.structuralLookup = structuralLookup
        self.runtimeReset = runtimeReset
        self.splitGroupReset = splitGroupReset
        self.regularCollectionReset = regularCollectionReset
        self.transientStateReset = transientStateReset
    }

    func resetRegularTabsAndShortcutLiveInstances() {
        guard let prepared = runtimeReset.prepare() else { return }
        structuralLookup.withTransaction {
            transientStateReset.reset()
            splitGroupReset.removeRegularTabs(prepared.regularTabIDs)
            regularCollectionReset.reset()
            if prepared.teardown != nil {
                structuralLookup.runAfterCurrentBatch { [runtimeReset] in
                    runtimeReset.finish(prepared)
                }
            }
        }
    }
}
