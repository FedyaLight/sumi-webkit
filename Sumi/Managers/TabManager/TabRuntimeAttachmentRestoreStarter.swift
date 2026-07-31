import Foundation

/// Schedules restore starts and cancels only the exact attachment-owned attempt.
@MainActor
final class TabRuntimeAttachmentRestoreStarter {
    private struct PendingStart {
        let revision: UInt64
        let attempt: TabStartupRestoreAttempt
        let task: Task<Void, Never>
    }

    private let connection: TabRuntimePortConnection
    private let policy: TabStartupRestorePolicy
    private let lifecycle: TabStartupRestoreLifecycle
    private let restore: TabStoreRestoreService
    private var pendingStart: PendingStart?
    private var startRevision: UInt64 = 0

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

    @discardableResult
    func startAutomatically(using lease: TabRuntimePortLease) -> Bool {
        guard policy.automaticallyStarts else { return false }
        return start(using: lease)
    }

    @discardableResult
    func startManually(using lease: TabRuntimePortLease) -> Bool {
        start(using: lease)
    }

    private func start(using lease: TabRuntimePortLease) -> Bool {
        guard policy.isEnabled, connection.accepts(lease) else {
            return false
        }
        if pendingStart != nil || lifecycle.didStartPersistedStateLoad {
            return true
        }
        let runtimeAttachment = TabRuntimeAttachmentWitness(
            connection: connection,
            lease: lease
        )
        guard let attempt = lifecycle.makeAttempt(
            revision: policy.requestedStructuralRevision,
            using: runtimeAttachment
        ) else {
            return false
        }
        startRevision &+= 1
        let revision = startRevision
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            activatePending(revision: revision)
        }
        pendingStart = PendingStart(
            revision: revision,
            attempt: attempt,
            task: task
        )
        return true
    }

    private func activatePending(revision: UInt64) {
        guard Task.isCancelled == false,
              let pendingStart,
              pendingStart.revision == revision else {
            return
        }
        self.pendingStart = nil
        let attempt = pendingStart.attempt
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
