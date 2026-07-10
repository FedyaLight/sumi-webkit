import Foundation

@MainActor
final class ContentBlockingTaskRegistry<Key: Hashable> {
    private struct Entry {
        let token: UUID
        let task: Task<Void, Never>
    }

    private var activeTasks = [Key: Entry]()
    private var retiringTasks = [UUID: Task<Void, Never>]()

    isolated deinit {
        activeTasks.values.forEach { $0.task.cancel() }
        retiringTasks.values.forEach { $0.cancel() }
    }

    func replaceTask(
        for key: Key,
        operation: @escaping @MainActor () async -> Void
    ) {
        retire(activeTasks.removeValue(forKey: key))
        let token = UUID()
        let task = Task { @MainActor [weak self] in
            await operation()
            self?.finishTask(for: key, token: token)
        }
        activeTasks[key] = Entry(token: token, task: task)
    }

    func cancelTask(for key: Key) {
        retire(activeTasks.removeValue(forKey: key))
    }

    func cancelAll() {
        let entries = Array(activeTasks.values)
        activeTasks.removeAll(keepingCapacity: false)
        entries.forEach(retire)
    }

    private func retire(_ entry: Entry?) {
        guard let entry else { return }
        entry.task.cancel()
        retiringTasks[entry.token] = entry.task
    }

    private func finishTask(for key: Key, token: UUID) {
        if activeTasks[key]?.token == token {
            activeTasks.removeValue(forKey: key)
        } else {
            retiringTasks.removeValue(forKey: token)
        }
    }

    #if DEBUG
        func drainTasksForTests(cancel: Bool = false) async {
            while true {
                let tasks = activeTasks.values.map(\.task) + Array(retiringTasks.values)
                guard !tasks.isEmpty else { return }
                if cancel {
                    tasks.forEach { $0.cancel() }
                }
                for task in tasks {
                    await task.value
                }
            }
        }
    #endif
}
