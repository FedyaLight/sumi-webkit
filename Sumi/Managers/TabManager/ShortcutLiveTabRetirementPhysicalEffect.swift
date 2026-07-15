@MainActor
final class ShortcutLiveTabRetirementPhysicalEffect {
    private let publication: PreparedScopedTabRuntimePublication?
    private let committed: CommittedTabRuntimeRetirementCleanupOwnership?
    private let retirement: TabRuntimeRetirementService
    private let runtimeAttachment: TabRuntimeAttachmentWitness?
    private let windowCommit: @MainActor () -> Void
    private var isPublished = false

    init?(
        prepared: PreparedShortcutLiveTabRetirement,
        teardown: TabRuntimeTeardownService
    ) {
        let expectedIDs = Set(prepared.result.retiredTabIds)
        guard expectedIDs == Set(prepared.tabs.map(\.id)) else { return nil }
        if let committed = prepared.committedRuntimeRetirement {
            guard teardown.retirement.committedRetirementIsExact(committed)
            else { return nil }
            self.committed = committed
        } else {
            committed = nil
        }
        retirement = teardown.retirement
        runtimeAttachment = prepared.runtimeAttachment
        windowCommit = {
            guard prepared.windowCommitPolicy == .retirementService,
                  prepared.runtimeAttachment?.isCurrent() != false,
                  let runtime = prepared.runtime else { return }
            for window in prepared.result.windowStatesNeedingPersistence
            where runtime.windowState(for: window.id) === window {
                runtime.persistWindowSession(for: window)
            }
        }
        if prepared.runtimeAttachment?.isCurrent() == false {
            publication = nil
        } else if let runtime = prepared.runtime {
            guard let publication = teardown.terminalRetirement
                .prepareScopedRuntimePublication(
                    prepared.tabs, runtime: runtime
                ) else { return nil }
            self.publication = publication
        } else {
            guard prepared.tabs.isEmpty else { return nil }
            publication = nil
        }
    }

    func publish() {
        guard isPublished == false else { return }
        isPublished = true
        if runtimeAttachment?.isCurrent() != false {
            publication?.publish()
            windowCommit()
        }
        if let committed {
            retirement.destroyCommittedRuntime(committed)
        }
    }
}
