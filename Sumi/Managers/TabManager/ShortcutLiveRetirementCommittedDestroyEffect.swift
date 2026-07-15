@MainActor
final class ShortcutLiveRetirementCommittedDestroyEffect {
    private let committed: CommittedTabRuntimeRetirementCleanupOwnership
    private let retirement: TabRuntimeRetirementService

    init(
        committed: CommittedTabRuntimeRetirementCleanupOwnership,
        retirement: TabRuntimeRetirementService
    ) {
        self.committed = committed
        self.retirement = retirement
    }

    func publish() {
        retirement.destroyCommittedRuntime(committed)
    }
}
