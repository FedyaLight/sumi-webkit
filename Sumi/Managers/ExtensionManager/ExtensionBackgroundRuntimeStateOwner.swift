import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionBackgroundRuntimeStateOwner {
    typealias RuntimeState = ExtensionManager.BackgroundRuntimeState
    typealias WakeReason = ExtensionManager.ExtensionBackgroundWakeReason

    private struct WakeTask {
        let token: UUID
        let task: Task<Void, Error>
        let isCurrent: @MainActor () -> Bool
    }

    private var wakeTasks: [String: WakeTask] = [:]
    private var runtimeStatesByWakeKey: [String: RuntimeState] = [:]

    func state(for wakeKey: String) -> RuntimeState {
        runtimeStatesByWakeKey[wakeKey] ?? .neverLoaded
    }

    @discardableResult
    func ensureBackgroundAvailableIfRequired(
        wakeKey: String,
        hasBackgroundContent: Bool,
        reason: WakeReason,
        trace: (String) -> Void,
        isCurrent: @escaping @MainActor () -> Bool = { true },
        loadBackgroundContent: @escaping @MainActor () async throws -> Void,
        recordWakeMetric: @escaping @MainActor (
            _ duration: TimeInterval,
            _ reason: WakeReason,
            _ didFail: Bool
        ) -> Void
    ) async throws -> Bool {
        guard hasBackgroundContent else { return false }

        switch state(for: wakeKey) {
        case .loaded:
            trace("Skipping required background wake for \(wakeKey): already loaded")
            return false
        case .wakeInFlight:
            if let existingWake = wakeTasks[wakeKey] {
                if existingWake.isCurrent() {
                    trace("Awaiting required background wake already in flight for \(wakeKey)")
                    try await existingWake.task.value
                    return false
                }
                existingWake.task.cancel()
                wakeTasks.removeValue(forKey: wakeKey)
            }
            setState(.neverLoaded, for: wakeKey)
        case .neverLoaded, .loadFailed:
            break
        }

        let task = startWakeTask(
            wakeKey: wakeKey,
            reason: reason,
            mode: "required",
            trace: trace,
            isCurrent: isCurrent,
            loadBackgroundContent: loadBackgroundContent,
            recordWakeMetric: recordWakeMetric
        )
        try await task.value
        return true
    }

    func cancelAndRemoveRuntime(for wakeKey: String) {
        wakeTasks[wakeKey]?.task.cancel()
        wakeTasks.removeValue(forKey: wakeKey)
        runtimeStatesByWakeKey.removeValue(forKey: wakeKey)
    }

    func removeRuntimeState(for wakeKey: String) {
        runtimeStatesByWakeKey.removeValue(forKey: wakeKey)
    }

    func cancelAllWakeTasks() {
        wakeTasks.values.forEach { $0.task.cancel() }
    }

    func removeAll() {
        cancelAllWakeTasks()
        wakeTasks.removeAll()
        runtimeStatesByWakeKey.removeAll()
    }

    private func setState(_ state: RuntimeState, for wakeKey: String) {
        if state == .neverLoaded {
            runtimeStatesByWakeKey.removeValue(forKey: wakeKey)
        } else {
            runtimeStatesByWakeKey[wakeKey] = state
        }
    }

    @discardableResult
    private func startWakeTask(
        wakeKey: String,
        reason: WakeReason,
        mode: String,
        trace: (String) -> Void,
        isCurrent: @escaping @MainActor () -> Bool,
        loadBackgroundContent: @escaping @MainActor () async throws -> Void,
        recordWakeMetric: @escaping @MainActor (
            _ duration: TimeInterval,
            _ reason: WakeReason,
            _ didFail: Bool
        ) -> Void
    ) -> Task<Void, Error> {
        setState(.wakeInFlight, for: wakeKey)
        trace("Starting \(mode) background wake for \(wakeKey) reason=\(reason.rawValue)")

        let token = UUID()
        let task = Self.detachedMainActorWakeTask { [weak self] in
            guard let self else { return }
            defer {
                if self.wakeTasks[wakeKey]?.token == token {
                    self.wakeTasks.removeValue(forKey: wakeKey)
                }
            }

            let wakeStart = CFAbsoluteTimeGetCurrent()
            do {
                try Task.checkCancellation()
                guard isCurrent() else { throw CancellationError() }
                try await loadBackgroundContent()
                try Task.checkCancellation()
                guard isCurrent(), self.wakeTasks[wakeKey]?.token == token else {
                    throw CancellationError()
                }
                self.setState(.loaded, for: wakeKey)
                recordWakeMetric(
                    CFAbsoluteTimeGetCurrent() - wakeStart,
                    reason,
                    false
                )
            } catch {
                if self.wakeTasks[wakeKey]?.token == token {
                    if error is CancellationError || isCurrent() == false {
                        self.setState(.neverLoaded, for: wakeKey)
                    } else {
                        self.setState(.loadFailed, for: wakeKey)
                        recordWakeMetric(
                            CFAbsoluteTimeGetCurrent() - wakeStart,
                            reason,
                            true
                        )
                    }
                }
                throw error
            }
        }

        wakeTasks[wakeKey] = WakeTask(
            token: token,
            task: task,
            isCurrent: isCurrent
        )
        return task
    }

    #if DEBUG
        @discardableResult
        func drainWakeTasksForTests(cancel: Bool = false) async -> Bool {
            var drainedTask = false

            while true {
                let tasks = wakeTasks.values.map(\.task)
                guard tasks.isEmpty == false else { return drainedTask }

                drainedTask = true
                if cancel {
                    tasks.forEach { $0.cancel() }
                }

                for task in tasks {
                    do {
                        try await task.value
                    } catch is CancellationError {
                        // Expected when tests explicitly drain with cancellation.
                    } catch {
                        assertionFailure("Background wake test drain failed: \(error)")
                    }
                }
            }
        }
    #endif

    private nonisolated static func detachedMainActorWakeTask(
        _ operation: @escaping @MainActor @Sendable () async throws -> Void
    ) -> Task<Void, Error> {
        Task.detached {
            try await operation()
        }
    }
}
