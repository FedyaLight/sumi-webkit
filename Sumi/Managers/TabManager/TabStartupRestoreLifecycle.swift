import Foundation

/// Owns exact restore phase and terminal initial-data readiness.
@MainActor
final class TabStartupRestoreLifecycle {
    private enum Phase {
        case idle
        case loading(TabStartupRestoreAttempt)
        case committed(TabStartupRestoreAttempt)
        case completed
    }
    private let eventBus: TabStructureEventBus
    private let initialDataSettlement = TabInitialDataSettlement()
    private var generation: UInt64 = 0
    private var phase = Phase.idle
    var hasLoadedInitialData: Bool {
        if case .completed = phase { return true }
        return false
    }
    var didStartPersistedStateLoad: Bool {
        if case .idle = phase { return false }
        return true
    }

    init(eventBus: TabStructureEventBus) {
        self.eventBus = eventBus
    }

    func waitUntilInitialDataLoaded(startIfNeeded: @MainActor () -> Bool) async -> Bool { await initialDataSettlement.wait(startIfNeeded: startIfNeeded) }

    func markLoadFinished() {
        phase = .completed
        initialDataSettlement.settle()
        eventBus.publishInitialDataLoaded()
    }
    func makeAttempt(
        revision: UInt64,
        using attachment: TabRuntimeAttachmentWitness
    ) -> TabStartupRestoreAttempt? {
        guard case .idle = phase else { return nil }
        generation &+= 1
        return TabStartupRestoreAttempt(
            generation: generation,
            expectedStructuralRevision: revision,
            runtimeAttachment: attachment
        )
    }
    func activate(_ attempt: TabStartupRestoreAttempt) -> Bool {
        guard case .idle = phase, attempt.isRuntimeCurrent() else { return false }
        phase = .loading(attempt)
        initialDataSettlement.reset()
        eventBus.resetInitialDataLoaded()
        return true
    }
    func beginDirectLoad(
        using attachment: TabRuntimeAttachmentWitness,
        expectedStructuralRevision revision: UInt64
    ) -> TabStartupRestoreAttempt? {
        guard attachment.isCurrent() else { return nil }
        if case .completed = phase {
            phase = .idle
        }
        guard let attempt = makeAttempt(
            revision: revision,
            using: attachment
        ) else { return nil }
        return activate(attempt) ? attempt : nil
    }
    func admitsInstall(_ attempt: TabStartupRestoreAttempt) -> Bool {
        guard case .loading(let current) = phase else { return false }
        return current.matches(attempt) && attempt.isRuntimeCurrent()
    }
    func markStructuralCommit(_ attempt: TabStartupRestoreAttempt) -> Bool {
        guard admitsInstall(attempt) else { return false }
        phase = .committed(attempt)
        return true
    }

    func ownsCommitted(_ attempt: TabStartupRestoreAttempt) -> Bool {
        guard case .committed(let current) = phase else { return false }
        return current.matches(attempt)
    }

    func finish(_ attempt: TabStartupRestoreAttempt) -> Bool {
        switch phase {
        case .loading where admitsInstall(attempt),
             .committed where ownsCommitted(attempt):
            markLoadFinished()
            return true
        case .idle, .loading, .committed, .completed:
            return false
        }
    }

    func revokeLoadingAttempt() -> TabStartupRestoreAttempt? {
        guard case .loading(let attempt) = phase else { return nil }
        phase = .idle
        return attempt
    }
}
