import Foundation

/// Coalesces per-window persistence requests while retaining enough state to
/// synchronously flush every pending window during app shutdown.
@MainActor
final class WindowSessionPersistenceScheduler {
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var states: [UUID: BrowserWindowState] = [:]

    isolated deinit {
        tasks.values.forEach { $0.cancel() }
    }

    func schedule(
        _ windowState: BrowserWindowState,
        delayNanoseconds: UInt64,
        persist: @escaping @MainActor (BrowserWindowState) -> Void
    ) {
        guard windowState.isIncognito == false else { return }

        let windowID = windowState.id
        cancel(for: windowID)
        states[windowID] = windowState
        tasks[windowID] = Task { @MainActor [weak self, weak windowState] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard Task.isCancelled == false,
                  let self,
                  let windowState else {
                return
            }

            self.tasks.removeValue(forKey: windowID)
            self.states.removeValue(forKey: windowID)
            persist(windowState)
        }
    }

    func flush(
        persist: @MainActor (BrowserWindowState) -> Void
    ) {
        guard states.isEmpty == false else { return }
        let pending = states.values.sorted {
            $0.id.uuidString < $1.id.uuidString
        }
        cancelAll()

        let trace = PerformanceTrace.beginInterval(
            "WindowSession.flushPendingPersistence"
        )
        defer {
            PerformanceTrace.endInterval(
                "WindowSession.flushPendingPersistence",
                trace
            )
        }
        pending.forEach(persist)
    }

    func cancel(for windowID: UUID) {
        tasks[windowID]?.cancel()
        tasks.removeValue(forKey: windowID)
        states.removeValue(forKey: windowID)
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        states.removeAll()
    }
}
