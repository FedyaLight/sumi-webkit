import Foundation

/// Coalesces per-window persistence requests into one timer and one write to
/// the unified window snapshot key. It still counts accepted window requests
/// so shutdown and tests can verify that no pending work was lost.
@MainActor
final class WindowSessionPersistenceScheduler {
    typealias LiveCommitCallback = @MainActor () -> Void

    private let delayedActions: MainActorDelayedActionScheduler
    private var cancellation: MainActorDelayedActionScheduler.Cancellation?
    private var writes: [UUID: WindowSessionDurableWrite] = [:]
    private var liveCommitCallback: LiveCommitCallback?

    init(delayedActions: MainActorDelayedActionScheduler = .live) {
        self.delayedActions = delayedActions
    }

    isolated deinit {
        cancellation?()
    }

    func schedule(
        _ write: WindowSessionDurableWrite,
        delayNanoseconds: UInt64,
        afterDurableCommit: @escaping LiveCommitCallback
    ) {
        guard write.windowState.isIncognito == false else { return }

        let windowID = write.windowID
        writes[windowID] = write
        liveCommitCallback = afterDurableCommit
        cancellation?()
        let delay = TimeInterval(delayNanoseconds) / 1_000_000_000
        cancellation = delayedActions.schedule(after: delay) { [weak self] in
            self?.executePendingWrites()
        }
    }

    /// Commits every accepted durable write as one batch and drops the
    /// per-write live callbacks. The caller owns any one-per-batch projection
    /// that should happen after these durable commits.
    @discardableResult
    func flush() -> Int {
        guard writes.isEmpty == false else { return 0 }
        let pending = writes.values.sorted {
            $0.windowID.uuidString < $1.windowID.uuidString
        }
        cancellation?()
        cancellation = nil
        writes.removeAll()
        liveCommitCallback = nil

        let trace = PerformanceTrace.beginInterval(
            "WindowSession.flushPendingPersistence"
        )
        defer {
            PerformanceTrace.endInterval(
                "WindowSession.flushPendingPersistence",
                trace
            )
        }
        // Every write targets the same unified snapshot key. Commit the
        // deterministic final window once for the whole batch.
        pending.last?.commit()
        return pending.count
    }

    /// Teardown intentionally shares only the durable batch primitive. Live
    /// callbacks have already been discarded by `flush()` and cannot reach a
    /// catalog or archive after the browser root starts deinitializing.
    @discardableResult
    func flushDurableStateForRuntimeTeardown() -> Int {
        flush()
    }

    func cancel(for windowID: UUID) {
        writes.removeValue(forKey: windowID)
        guard writes.isEmpty else { return }
        cancellation?()
        cancellation = nil
        liveCommitCallback = nil
    }

    func cancelAll() {
        cancellation?()
        cancellation = nil
        writes.removeAll()
        liveCommitCallback = nil
    }

    private func executePendingWrites() {
        cancellation = nil
        guard writes.isEmpty == false else {
            liveCommitCallback = nil
            return
        }
        let pending = writes.values.sorted {
            $0.windowID.uuidString < $1.windowID.uuidString
        }
        writes.removeAll()
        let callback = liveCommitCallback
        liveCommitCallback = nil
        pending.last?.commit()
        callback?()
    }
}
