import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionProfileRuntimeTaskOwner<Result: Sendable> {
    private struct ScheduledTask {
        let token: UUID
        let task: Task<Result, Never>
    }

    private var tasksByProfile: [UUID: ScheduledTask] = [:]
    private var retiredTokens = Set<UUID>()
    private var finishedBeforeRegistrationTokens = Set<UUID>()

    func run(
        profileID: UUID,
        operation: @escaping @MainActor @Sendable () async -> Result
    ) async -> Result {
        if let scheduled = tasksByProfile[profileID] {
            return await scheduled.task.value
        }

        let token = UUID()
        let task = Self.runtimeTask { [weak self] in
            let result = await operation()
            self?.finish(profileID: profileID, token: token)
            return result
        }
        tasksByProfile[profileID] = ScheduledTask(token: token, task: task)
        clearIfFinishedBeforeRegistration(profileID: profileID, token: token)
        return await task.value
    }

    func cancelAll() {
        for scheduled in tasksByProfile.values {
            scheduled.task.cancel()
            retiredTokens.insert(scheduled.token)
        }
        tasksByProfile.removeAll()
        finishedBeforeRegistrationTokens.removeAll()
    }

    #if DEBUG
        func tasksForDrain() -> [Task<Void, Never>] {
            tasksByProfile.values.map(\.task).map { task in
                Task { _ = await task.value }
            }
        }
    #endif

    private func finish(profileID: UUID, token: UUID) {
        var resolved = false
        if tasksByProfile[profileID]?.token == token {
            tasksByProfile.removeValue(forKey: profileID)
            resolved = true
        }
        if retiredTokens.remove(token) != nil { resolved = true }
        guard resolved == false else { return }
        finishedBeforeRegistrationTokens.insert(token)
    }

    private func clearIfFinishedBeforeRegistration(
        profileID: UUID,
        token: UUID
    ) {
        guard finishedBeforeRegistrationTokens.remove(token) != nil else {
            return
        }
        if tasksByProfile[profileID]?.token == token {
            tasksByProfile.removeValue(forKey: profileID)
        }
    }

    nonisolated private static func runtimeTask(
        _ operation: @escaping @MainActor @Sendable () async -> Result
    ) -> Task<Result, Never> {
        Task { @MainActor in await operation() }
    }
}
