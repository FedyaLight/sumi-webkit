import Foundation

final class SumiPermissionCoordinatorEventStream: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations:
        [UUID: AsyncStream<SumiPermissionCoordinatorEvent>.Continuation] = [:]
    private var latestEvent: SumiPermissionCoordinatorEvent?
    private var latestSystemBlockedEvent: SumiPermissionCoordinatorEvent?

    func events() -> AsyncStream<SumiPermissionCoordinatorEvent> {
        let pair = AsyncStream<SumiPermissionCoordinatorEvent>.makeStream(
            of: SumiPermissionCoordinatorEvent.self,
            bufferingPolicy: .bufferingNewest(50)
        )
        let id = UUID()
        lock.lock()
        continuations[id] = pair.continuation
        lock.unlock()
        pair.continuation.onTermination = { [weak self] _ in
            self?.removeContinuation(id)
        }
        return pair.stream
    }

    func snapshot() -> (
        latestEvent: SumiPermissionCoordinatorEvent?,
        latestSystemBlockedEvent: SumiPermissionCoordinatorEvent?
    ) {
        lock.lock()
        let snapshot = (
            latestEvent: latestEvent,
            latestSystemBlockedEvent: latestSystemBlockedEvent
        )
        lock.unlock()
        return snapshot
    }

    func emit(_ event: SumiPermissionCoordinatorEvent) {
        lock.lock()
        latestEvent = event
        if case .systemBlocked = event {
            latestSystemBlockedEvent = event
        }
        let activeContinuations = Array(continuations.values)
        lock.unlock()

        for continuation in activeContinuations {
            continuation.yield(event)
        }
    }

    private func removeContinuation(_ id: UUID) {
        lock.lock()
        continuations.removeValue(forKey: id)
        lock.unlock()
    }
}
