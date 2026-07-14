import Foundation

/// A cancellation-aware stand-in for long scheduler sleeps. Tests observe
/// exact request and cancellation receipts instead of waiting for wall time.
@MainActor
final class ControlledSuspensionTimerWait {
    private struct CountWaiter {
        let target: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var sleeps: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var requestWaiters: [CountWaiter] = []
    private var cancellationWaiters: [CountWaiter] = []

    private(set) var requestedDelays: [TimeInterval] = []
    private(set) var cancellationCount = 0

    func wait(for delay: TimeInterval) async throws {
        let id = UUID()
        requestedDelays.append(delay)
        resumeSatisfiedRequestWaiters()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    sleeps[id] = continuation
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancel(id)
            }
        }
    }

    func waitForRequestCount(_ target: Int) async {
        guard requestedDelays.count < target else { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append(.init(
                target: target,
                continuation: continuation
            ))
        }
    }

    func waitForCancellationCount(_ target: Int) async {
        guard cancellationCount < target else { return }
        await withCheckedContinuation { continuation in
            cancellationWaiters.append(.init(
                target: target,
                continuation: continuation
            ))
        }
    }

    private func cancel(_ id: UUID) {
        guard let continuation = sleeps.removeValue(forKey: id) else { return }
        cancellationCount += 1
        continuation.resume(throwing: CancellationError())
        resumeSatisfiedCancellationWaiters()
    }

    private func resumeSatisfiedRequestWaiters() {
        let satisfied = requestWaiters.filter {
            requestedDelays.count >= $0.target
        }
        requestWaiters.removeAll {
            requestedDelays.count >= $0.target
        }
        satisfied.forEach { $0.continuation.resume() }
    }

    private func resumeSatisfiedCancellationWaiters() {
        let satisfied = cancellationWaiters.filter {
            cancellationCount >= $0.target
        }
        cancellationWaiters.removeAll {
            cancellationCount >= $0.target
        }
        satisfied.forEach { $0.continuation.resume() }
    }
}
