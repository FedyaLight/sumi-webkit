import Foundation

@MainActor
final class SumiContentBlockingScheduledTaskOwner {
    private struct ScheduledTask {
        let token: UUID
        let task: Task<Void, Never>
    }

    private var compilationTask: ScheduledTask?
    private var ruleListRefreshTask: ScheduledTask?
    private var profileRefreshTasksByKey: [String: ScheduledTask] = [:]
    private var retiredScheduledTaskTokens = Set<UUID>()
    private var finishedUnregisteredScheduledTaskTokens = Set<UUID>()

    #if DEBUG
        private var retiredScheduledTasksByToken: [UUID: Task<Void, Never>] = [:]
    #endif

    func scheduleCompilationTask(
        _ makeTask: (UUID) -> Task<Void, Never>
    ) {
        retireScheduledTask(compilationTask)
        let scheduledTask = makeScheduledTask(makeTask)
        compilationTask = scheduledTask
        clearCompilationTaskIfFinishedBeforeRegistration(token: scheduledTask.token)
    }

    func scheduleRuleListRefreshTask(
        _ makeTask: (UUID) -> Task<Void, Never>
    ) {
        retireScheduledTask(ruleListRefreshTask)
        let scheduledTask = makeScheduledTask(makeTask)
        ruleListRefreshTask = scheduledTask
        clearRuleListRefreshTaskIfFinishedBeforeRegistration(token: scheduledTask.token)
    }

    func scheduleProfileRefreshTask(
        key: String,
        _ makeTask: (UUID) -> Task<Void, Never>
    ) {
        retireScheduledTask(profileRefreshTasksByKey[key])
        let scheduledTask = makeScheduledTask(makeTask)
        profileRefreshTasksByKey[key] = scheduledTask
        clearProfileRefreshTaskIfFinishedBeforeRegistration(
            key: key,
            token: scheduledTask.token
        )
    }

    func cancelCompilationTask() {
        retireScheduledTask(compilationTask)
        compilationTask = nil
    }

    func cancelAllTasksForShutdown() {
        retireScheduledTask(compilationTask)
        retireScheduledTask(ruleListRefreshTask)
        for scheduledTask in profileRefreshTasksByKey.values {
            retireScheduledTask(scheduledTask)
        }
        compilationTask = nil
        ruleListRefreshTask = nil
        profileRefreshTasksByKey.removeAll(keepingCapacity: false)
        finishedUnregisteredScheduledTaskTokens.removeAll(keepingCapacity: false)
    }

    func finishCompilationTask(token: UUID) {
        var didResolveTask = false
        if compilationTask?.token == token {
            compilationTask = nil
            didResolveTask = true
        }
        didResolveTask = resolveRetiredScheduledTask(token: token) || didResolveTask
        rememberFinishedScheduledTaskIfUnregistered(token: token, didResolveTask: didResolveTask)
    }

    func finishRuleListRefreshTask(token: UUID) {
        var didResolveTask = false
        if ruleListRefreshTask?.token == token {
            ruleListRefreshTask = nil
            didResolveTask = true
        }
        didResolveTask = resolveRetiredScheduledTask(token: token) || didResolveTask
        rememberFinishedScheduledTaskIfUnregistered(token: token, didResolveTask: didResolveTask)
    }

    func finishProfileRefreshTask(key: String, token: UUID) {
        var didResolveTask = false
        if profileRefreshTasksByKey[key]?.token == token {
            profileRefreshTasksByKey.removeValue(forKey: key)
            didResolveTask = true
        }
        didResolveTask = resolveRetiredScheduledTask(token: token) || didResolveTask
        rememberFinishedScheduledTaskIfUnregistered(token: token, didResolveTask: didResolveTask)
    }

    private func makeScheduledTask(
        _ makeTask: (UUID) -> Task<Void, Never>
    ) -> ScheduledTask {
        let token = UUID()
        return ScheduledTask(token: token, task: makeTask(token))
    }

    private func retireScheduledTask(_ scheduledTask: ScheduledTask?) {
        guard let scheduledTask else { return }
        scheduledTask.task.cancel()
        retiredScheduledTaskTokens.insert(scheduledTask.token)
        #if DEBUG
            retiredScheduledTasksByToken[scheduledTask.token] = scheduledTask.task
        #endif
    }

    private func resolveRetiredScheduledTask(token: UUID) -> Bool {
        let didResolveTask = retiredScheduledTaskTokens.remove(token) != nil
        #if DEBUG
            retiredScheduledTasksByToken.removeValue(forKey: token)
        #endif
        return didResolveTask
    }

    private func rememberFinishedScheduledTaskIfUnregistered(
        token: UUID,
        didResolveTask: Bool
    ) {
        guard !didResolveTask else { return }
        finishedUnregisteredScheduledTaskTokens.insert(token)
    }

    private func clearCompilationTaskIfFinishedBeforeRegistration(token: UUID) {
        guard finishedUnregisteredScheduledTaskTokens.remove(token) != nil else { return }
        if compilationTask?.token == token {
            compilationTask = nil
        }
    }

    private func clearRuleListRefreshTaskIfFinishedBeforeRegistration(token: UUID) {
        guard finishedUnregisteredScheduledTaskTokens.remove(token) != nil else { return }
        if ruleListRefreshTask?.token == token {
            ruleListRefreshTask = nil
        }
    }

    private func clearProfileRefreshTaskIfFinishedBeforeRegistration(
        key: String,
        token: UUID
    ) {
        guard finishedUnregisteredScheduledTaskTokens.remove(token) != nil else { return }
        if profileRefreshTasksByKey[key]?.token == token {
            profileRefreshTasksByKey.removeValue(forKey: key)
        }
    }

    #if DEBUG
        func drainScheduledTasksForTests(cancel: Bool = false) async {
            while true {
                let tasks = scheduledTasksForTests()
                guard tasks.isEmpty == false else { return }
                if cancel {
                    tasks.forEach { $0.cancel() }
                }
                for task in tasks {
                    await task.value
                }
            }
        }

        private func scheduledTasksForTests() -> [Task<Void, Never>] {
            var tasks: [Task<Void, Never>] = []
            if let compilationTask {
                tasks.append(compilationTask.task)
            }
            if let ruleListRefreshTask {
                tasks.append(ruleListRefreshTask.task)
            }
            tasks.append(contentsOf: profileRefreshTasksByKey.values.map(\.task))
            tasks.append(contentsOf: retiredScheduledTasksByToken.values)
            return tasks
        }
    #endif
}
