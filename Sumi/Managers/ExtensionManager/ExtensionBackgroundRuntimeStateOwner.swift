import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionBackgroundRuntimeStateOwner {
    typealias RuntimeState = ExtensionManager.BackgroundRuntimeState
    typealias WakeReason = ExtensionManager.ExtensionBackgroundWakeReason

    private var wakeTasks: [String: Task<Void, Error>] = [:]
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
            if let existingTask = wakeTasks[wakeKey] {
                trace("Awaiting required background wake already in flight for \(wakeKey)")
                try await existingTask.value
                return false
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
            loadBackgroundContent: loadBackgroundContent,
            recordWakeMetric: recordWakeMetric
        )
        try await task.value
        return true
    }

    func cancelAndRemoveRuntime(for wakeKey: String) {
        wakeTasks[wakeKey]?.cancel()
        wakeTasks.removeValue(forKey: wakeKey)
        runtimeStatesByWakeKey.removeValue(forKey: wakeKey)
    }

    func removeRuntimeState(for wakeKey: String) {
        runtimeStatesByWakeKey.removeValue(forKey: wakeKey)
    }

    func cancelAllWakeTasks() {
        wakeTasks.values.forEach { $0.cancel() }
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
        loadBackgroundContent: @escaping @MainActor () async throws -> Void,
        recordWakeMetric: @escaping @MainActor (
            _ duration: TimeInterval,
            _ reason: WakeReason,
            _ didFail: Bool
        ) -> Void
    ) -> Task<Void, Error> {
        setState(.wakeInFlight, for: wakeKey)
        trace("Starting \(mode) background wake for \(wakeKey) reason=\(reason.rawValue)")

        let task = Self.detachedMainActorWakeTask { [weak self] in
            guard let self else { return }
            defer {
                self.wakeTasks.removeValue(forKey: wakeKey)
            }

            let wakeStart = CFAbsoluteTimeGetCurrent()
            do {
                try await loadBackgroundContent()
                self.setState(.loaded, for: wakeKey)
                recordWakeMetric(
                    CFAbsoluteTimeGetCurrent() - wakeStart,
                    reason,
                    false
                )
            } catch {
                self.setState(.loadFailed, for: wakeKey)
                recordWakeMetric(
                    CFAbsoluteTimeGetCurrent() - wakeStart,
                    reason,
                    true
                )
                throw error
            }
        }

        wakeTasks[wakeKey] = task
        return task
    }

    #if DEBUG
        @discardableResult
        func drainWakeTasksForTests(cancel: Bool = false) async -> Bool {
            var drainedTask = false

            while true {
                let tasks = Array(wakeTasks.values)
                guard tasks.isEmpty == false else { return drainedTask }

                drainedTask = true
                if cancel {
                    tasks.forEach { $0.cancel() }
                }

                for task in tasks {
                    _ = try? await task.value
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
