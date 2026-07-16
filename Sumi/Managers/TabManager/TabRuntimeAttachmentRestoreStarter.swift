import Foundation

/// Schedules restore starts and cancels only the exact attachment-owned attempt.
@MainActor
final class TabRuntimeAttachmentRestoreStarter {
    private struct PendingStart {
        let attempt: TabStartupRestoreAttempt
        let task: Task<Void, Never>
    }

    private let connection: TabRuntimePortConnection
    private let policy: TabStartupRestorePolicy
    private let lifecycle: TabStartupRestoreLifecycle
    private let restore: TabStoreRestoreService
    private var pendingStart: PendingStart?

    init(
        connection: TabRuntimePortConnection,
        policy: TabStartupRestorePolicy,
        lifecycle: TabStartupRestoreLifecycle,
        restore: TabStoreRestoreService
    ) {
        self.connection = connection
        self.policy = policy
        self.lifecycle = lifecycle
        self.restore = restore
    }

    deinit {
        MainActor.assumeIsolated {
            pendingStart?.task.cancel()
            pendingStart = nil
        }
    }

    func startAutomatically(using lease: TabRuntimePortLease) {
        guard policy.automaticallyStarts else { return }
        start(using: lease)
    }

    func startManually(using lease: TabRuntimePortLease) {
        start(using: lease)
    }

    private func start(using lease: TabRuntimePortLease) {
        guard policy.isEnabled,
              pendingStart == nil,
              connection.accepts(lease) else { return }
        let runtimeAttachment = TabRuntimeAttachmentWitness(
            connection: connection,
            lease: lease
        )
        guard let attempt = lifecycle.makeAttempt(
            revision: policy.requestedStructuralRevision,
            using: runtimeAttachment
        ) else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            activatePending(attempt)
        }
        pendingStart = PendingStart(attempt: attempt, task: task)
    }

    private func activatePending(_ attempt: TabStartupRestoreAttempt) {
        guard Task.isCancelled == false,
              pendingStart?.attempt.matches(attempt) == true else {
            return
        }
        pendingStart = nil
        guard lifecycle.activate(attempt) else { return }
        restore.loadFromStore(attempt)
    }

    func prepareForDetach() {
        if let pendingStart {
            pendingStart.task.cancel()
            self.pendingStart = nil
            return
        }
        if let attempt = lifecycle.revokeLoadingAttempt() {
            restore.cancelPendingRestore(attempt)
        }
    }
}
