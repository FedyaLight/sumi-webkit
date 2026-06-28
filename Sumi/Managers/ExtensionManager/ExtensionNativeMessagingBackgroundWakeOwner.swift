import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionNativeMessagingBackgroundWakeOwner {
    typealias WakeOperation = @MainActor @Sendable () async throws -> Void
    typealias FailureLogger = @MainActor @Sendable (
        _ error: any Error,
        _ operation: String
    ) -> Void

    private struct ScheduledWakeTask {
        let token: UUID
        let task: Task<Void, Never>
    }

    private var tasksByWakeKey: [String: ScheduledWakeTask] = [:]

    func scheduleWake(
        wakeKey: String,
        operation: String,
        wake: @escaping WakeOperation,
        logFailure: @escaping FailureLogger
    ) {
        guard tasksByWakeKey[wakeKey] == nil else { return }

        let token = UUID()
        let task = Self.detachedMainActorRuntimeTask { [weak self] in
            guard let self else { return }
            defer {
                if self.tasksByWakeKey[wakeKey]?.token == token {
                    self.tasksByWakeKey.removeValue(forKey: wakeKey)
                }
            }
            guard Task.isCancelled == false else { return }

            do {
                try await wake()
            } catch {
                logFailure(error, operation)
            }
        }
        tasksByWakeKey[wakeKey] = ScheduledWakeTask(token: token, task: task)
    }

    func cancelWakeTasks(
        forExtensionId extensionId: String,
        wakeKeyBelongsToExtension: (_ wakeKey: String, _ extensionId: String) -> Bool
    ) {
        for (wakeKey, scheduledTask) in tasksByWakeKey {
            guard wakeKeyBelongsToExtension(wakeKey, extensionId) else { continue }

            scheduledTask.task.cancel()
            tasksByWakeKey.removeValue(forKey: wakeKey)
        }
    }

    func cancelAllWakeTasks() {
        tasksByWakeKey.values.forEach { $0.task.cancel() }
        tasksByWakeKey.removeAll()
    }

    #if DEBUG
        func runtimeTasksForDrain() -> [Task<Void, Never>] {
            tasksByWakeKey.values.map(\.task)
        }
    #endif

    private nonisolated static func detachedMainActorRuntimeTask(
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) -> Task<Void, Never> {
        Task.detached {
            await operation()
        }
    }
}
