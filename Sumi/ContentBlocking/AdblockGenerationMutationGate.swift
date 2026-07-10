import Foundation

/// Serializes generation mutations across MainActor reentrancy. A stopped
/// runtime rejects queued work and invalidates work that has not reached its
/// durable commit point yet.
@MainActor
final class AdblockGenerationMutationGate {
    struct Lease: Equatable, Sendable {
        fileprivate let id: UUID
    }

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Lease?, Never>
    }

    private var activeLease: Lease?
    private var waiters = [Waiter]()
    private var isStopped = false

    func acquire() async -> Lease? {
        guard !isStopped, !Task.isCancelled else { return nil }
        if activeLease == nil {
            return installLease()
        }

        let waiterID = UUID()
        let lease: Lease? = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Lease?, Never>) in
                if isStopped || Task.isCancelled {
                    continuation.resume(returning: nil)
                } else if activeLease == nil {
                    continuation.resume(returning: installLease())
                } else {
                    waiters.append(Waiter(id: waiterID, continuation: continuation))
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancelWaiter(waiterID)
            }
        }
        guard !Task.isCancelled else {
            if let lease {
                release(lease)
            }
            return nil
        }
        return lease
    }

    func owns(_ lease: Lease) -> Bool {
        !isStopped && activeLease == lease
    }

    func release(_ lease: Lease) {
        guard activeLease == lease else { return }
        activeLease = nil
        installNextLeaseIfPossible()
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.continuation.resume(returning: nil) }
    }

    private func installLease() -> Lease {
        let lease = Lease(id: UUID())
        activeLease = lease
        return lease
    }

    private func installNextLeaseIfPossible() {
        guard !isStopped, activeLease == nil, !waiters.isEmpty else { return }
        let waiter = waiters.removeFirst()
        waiter.continuation.resume(returning: installLease())
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: nil)
    }
}
