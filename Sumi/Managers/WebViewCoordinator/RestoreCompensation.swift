import Foundation

/// Keeps post-deletion restoration alive independently of the initiating UI
/// task. Only terminal browser shutdown is allowed to cancel compensation.
@MainActor
final class RestoreCompensation {
    private var jobs: [UUID: Task<Bool, Never>] = [:]

    func run(
        _ operation: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        let jobID = UUID()
        let job = Task { @MainActor in
            await operation()
        }
        jobs[jobID] = job
        let result = await job.value
        jobs.removeValue(forKey: jobID)
        return result
    }

    func cancelForTerminalShutdown() {
        jobs.values.forEach { $0.cancel() }
        jobs.removeAll()
    }
}
