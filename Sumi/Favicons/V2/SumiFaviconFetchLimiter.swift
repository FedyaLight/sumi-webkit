import Foundation

actor SumiFaviconFetchLimiter {
    private struct Waiter {
        let id: UUID
        let partition: SumiFaviconPartition
        let origin: String
        let priority: SumiFaviconFetchPriority
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let globalLimit: Int
    private let perOriginLimit: Int
    private var activeGlobal = 0
    private var activeByOrigin: [String: Int] = [:]
    private var waiters: [Waiter] = []

    init(globalLimit: Int, perOriginLimit: Int) {
        self.globalLimit = max(1, globalLimit)
        self.perOriginLimit = max(1, perOriginLimit)
    }

    func acquire(
        partition: SumiFaviconPartition,
        origin: String,
        priority: SumiFaviconFetchPriority
    ) async -> Bool {
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                if canAcquire(origin: origin) {
                    markAcquired(origin: origin)
                    continuation.resume(returning: true)
                    return
                }
                waiters.append(
                    Waiter(
                        id: waiterID,
                        partition: partition,
                        origin: origin,
                        priority: priority,
                        continuation: continuation
                    )
                )
                waiters.sort {
                    if $0.priority != $1.priority {
                        return $0.priority > $1.priority
                    }
                    return $0.origin < $1.origin
                }
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(id: waiterID)
            }
        }
    }

    func cancelQueuedFetches() {
        let queuedWaiters = waiters
        waiters.removeAll()
        for waiter in queuedWaiters {
            waiter.continuation.resume(returning: false)
        }
    }

    func cancelQueuedFetches(partition: SumiFaviconPartition) {
        let cancelledWaiters = waiters.filter { $0.partition == partition }
        waiters.removeAll { $0.partition == partition }
        for waiter in cancelledWaiters {
            waiter.continuation.resume(returning: false)
        }
    }

    func release(origin: String) {
        activeGlobal = max(0, activeGlobal - 1)
        activeByOrigin[origin] = max(0, (activeByOrigin[origin] ?? 1) - 1)
        if activeByOrigin[origin] == 0 {
            activeByOrigin[origin] = nil
        }
        drainWaiters()
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: false)
    }

    private func drainWaiters() {
        var index = 0
        while index < waiters.count {
            let waiter = waiters[index]
            guard canAcquire(origin: waiter.origin) else {
                index += 1
                continue
            }
            waiters.remove(at: index)
            markAcquired(origin: waiter.origin)
            waiter.continuation.resume(returning: true)
        }
    }

    private func canAcquire(origin: String) -> Bool {
        activeGlobal < globalLimit
            && (activeByOrigin[origin] ?? 0) < perOriginLimit
    }

    private func markAcquired(origin: String) {
        activeGlobal += 1
        activeByOrigin[origin, default: 0] += 1
    }
}
