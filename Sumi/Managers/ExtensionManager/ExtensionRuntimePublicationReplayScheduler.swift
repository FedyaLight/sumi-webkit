import Foundation

/// Moves overflow reconciliation to a later MainActor turn. It owns no
/// publication state and allocates no task while the graph is settled.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimePublicationReplayScheduler {
    private var task: Task<Void, Never>?
    private var replayIsRunning = false

    var canScheduleReplay: Bool {
        replayIsRunning == false
    }

    func replaceScheduledReplay(
        _ replay: @escaping @MainActor () -> Void
    ) {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, Task.isCancelled == false else { return }
            task = nil
            replayIsRunning = true
            defer { replayIsRunning = false }
            replay()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
