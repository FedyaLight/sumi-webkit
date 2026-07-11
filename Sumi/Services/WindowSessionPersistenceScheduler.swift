import Foundation

/// Coalesces per-window persistence requests while retaining enough state to
/// synchronously flush every pending window during app shutdown.
@MainActor
final class WindowSessionPersistenceScheduler {
    typealias LiveCommitCallback = @MainActor () -> Void

    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var writes: [UUID: WindowSessionDurableWrite] = [:]
    private var liveCommitCallbacks: [UUID: LiveCommitCallback] = [:]

    isolated deinit {
        tasks.values.forEach { $0.cancel() }
    }

    func schedule(
        _ write: WindowSessionDurableWrite,
        delayNanoseconds: UInt64,
        afterDurableCommit: @escaping LiveCommitCallback
    ) {
        guard write.windowState.isIncognito == false else { return }

        let windowID = write.windowID
        cancel(for: windowID)
        writes[windowID] = write
        liveCommitCallbacks[windowID] = afterDurableCommit
        tasks[windowID] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }
            guard Task.isCancelled == false else { return }
            self?.execute(windowID)
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
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        writes.removeAll()
        liveCommitCallbacks.removeAll()

        let trace = PerformanceTrace.beginInterval(
            "WindowSession.flushPendingPersistence"
        )
        defer {
            PerformanceTrace.endInterval(
                "WindowSession.flushPendingPersistence",
                trace
            )
        }
        pending.forEach { $0.commit() }
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
        tasks[windowID]?.cancel()
        tasks.removeValue(forKey: windowID)
        writes.removeValue(forKey: windowID)
        liveCommitCallbacks.removeValue(forKey: windowID)
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        writes.removeAll()
        liveCommitCallbacks.removeAll()
    }

    private func execute(_ windowID: UUID) {
        tasks.removeValue(forKey: windowID)
        guard let write = writes.removeValue(forKey: windowID) else {
            liveCommitCallbacks.removeValue(forKey: windowID)
            return
        }
        let callback = liveCommitCallbacks.removeValue(forKey: windowID)
        write.commit()
        callback?()
    }
}
