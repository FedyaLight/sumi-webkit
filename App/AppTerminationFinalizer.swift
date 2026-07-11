import Foundation

@MainActor
final class AppTerminationFinalizer {
    enum ReplyReason: Equatable {
        case completed
        case timedOut
    }

    typealias Finalize = @MainActor () async -> Void
    typealias Reply = @MainActor (_ shouldTerminate: Bool) -> Void
    typealias TimeoutWaiter = @MainActor () async -> Void
    typealias ReplyObserver = @MainActor (ReplyReason) -> Void

    private enum State {
        case idle
        case finalizing
        case replied
    }

    private var state: State = .idle
    private var finalizationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var reply: Reply?
    private let waitForTimeout: TimeoutWaiter
    private let observeReply: ReplyObserver

    init(
        timeout: Duration = .seconds(15),
        waitForTimeout: TimeoutWaiter? = nil,
        observeReply: @escaping ReplyObserver = { _ in }
    ) {
        self.waitForTimeout = waitForTimeout ?? {
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
        }
        self.observeReply = observeReply
    }

    var isFinalizing: Bool {
        if case .finalizing = state { return true }
        return false
    }

    var didReply: Bool {
        if case .replied = state { return true }
        return false
    }

    /// Starts exactly one finalization attempt. Later quit requests join the
    /// existing AppKit terminate-later decision and cannot replace its work or
    /// reply callback.
    @discardableResult
    func begin(finalize: @escaping Finalize, reply: @escaping Reply) -> Bool {
        guard case .idle = state else { return false }
        state = .finalizing
        self.reply = reply

        finalizationTask = Task { @MainActor [weak self] in
            await finalize()
            self?.finalizationCompleted()
        }
        timeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await waitForTimeout()
            guard Task.isCancelled == false else { return }
            finish(reason: .timedOut)
        }
        return true
    }

    private func finalizationCompleted() {
        finalizationTask = nil
        finish(reason: .completed)
    }

    private func finish(reason: ReplyReason) {
        guard case .finalizing = state else { return }
        state = .replied
        timeoutTask?.cancel()
        timeoutTask = nil
        let reply = self.reply
        self.reply = nil
        observeReply(reason)
        reply?(true)
    }
}
