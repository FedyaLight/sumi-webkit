import Foundation

@MainActor
final class TabInitialDataSettlement {
    private var isSettled = false
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    func wait(
        startIfNeeded: @MainActor () -> Bool
    ) async -> Bool {
        if isSettled {
            return true
        }
        guard startIfNeeded() else {
            return false
        }
        if isSettled {
            return true
        }
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if isSettled {
                    continuation.resume(returning: true)
                } else if Task.isCancelled {
                    continuation.resume(returning: false)
                } else {
                    waiters[waiterID] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelWaiter(waiterID)
            }
        }
    }

    func settle() {
        isSettled = true
        let pending = Array(waiters.values)
        waiters.removeAll()
        for waiter in pending {
            waiter.resume(returning: true)
        }
    }

    func reset() {
        isSettled = false
    }

    private func cancelWaiter(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume(returning: false)
    }
}
