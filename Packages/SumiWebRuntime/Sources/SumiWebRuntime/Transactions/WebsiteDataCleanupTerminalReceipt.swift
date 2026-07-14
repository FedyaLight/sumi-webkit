import Foundation

/// One exact terminal-event generation for a cleanup navigation. A discarded
/// receipt can only finish its own waiter, so a late timeout or cancellation
/// can never settle a replacement blank/restore attempt.
@MainActor
final class WebsiteDataCleanupTerminalReceipt {
    private let deadline: ContinuousClock.Instant
    private var bufferedResult: Bool?
    private var continuation: CheckedContinuation<Bool, Never>?

    init(deadline: ContinuousClock.Instant) {
        self.deadline = deadline
    }

    func awaitResult() async -> Bool {
        if let bufferedResult {
            self.bufferedResult = nil
            return bufferedResult
        }

        let remaining = ContinuousClock.now.duration(to: deadline)
        guard remaining > .zero else { return false }
        let watchdog = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: remaining)
            } catch {
                return
            }
            self?.complete(with: false)
        }
        defer { watchdog.cancel() }

        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                precondition(self.continuation == nil)
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else if let bufferedResult = self.bufferedResult {
                    self.bufferedResult = nil
                    continuation.resume(returning: bufferedResult)
                } else {
                    self.continuation = continuation
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.complete(with: false)
            }
        }
        bufferedResult = nil
        return result
    }

    func complete(with result: Bool) {
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: result)
        } else {
            bufferedResult = result
        }
    }

    func discard() {
        bufferedResult = nil
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: false)
        }
    }
}
