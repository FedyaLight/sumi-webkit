import Foundation
import SumiWebRuntime

/// Owns retry attempts and their cancellable delayed actions. Admission clears
/// this exact ledger when fresh work supersedes a pending retry.
@MainActor
final class DeferredProtectedCommandRetryLedger {
    private static let initialDelayNanoseconds: UInt64 = 25_000_000
    private static let maximumDelayNanoseconds: UInt64 = 1_000_000_000

    private var attemptsBySourceWebViewID: [ObjectIdentifier: Int] = [:]
    private var cancellationBySourceWebViewID: [
        ObjectIdentifier: MainActorDelayedActionScheduler.Cancellation
    ] = [:]

    isolated deinit {
        cancellationBySourceWebViewID.values.forEach { $0() }
    }

    func scheduleIfNeeded(
        for webViewID: ObjectIdentifier,
        using delayedActions: MainActorDelayedActionScheduler,
        action: @escaping @MainActor () -> Void
    ) {
        guard cancellationBySourceWebViewID[webViewID] == nil else { return }
        let attempt = min((attemptsBySourceWebViewID[webViewID] ?? 0) + 1, 64)
        attemptsBySourceWebViewID[webViewID] = attempt
        let exponent = min(attempt - 1, 6)
        let delay = min(
            Self.initialDelayNanoseconds * (UInt64(1) << UInt64(exponent)),
            Self.maximumDelayNanoseconds
        )

        cancellationBySourceWebViewID[webViewID] = delayedActions.schedule(
            after: TimeInterval(delay) / 1_000_000_000,
            action: action
        )
    }

    func consumeScheduledAction(for webViewID: ObjectIdentifier) {
        cancellationBySourceWebViewID.removeValue(forKey: webViewID)
    }

    func clear(for webViewID: ObjectIdentifier) {
        cancellationBySourceWebViewID.removeValue(forKey: webViewID)?()
        attemptsBySourceWebViewID.removeValue(forKey: webViewID)
    }

    func reset() {
        cancellationBySourceWebViewID.values.forEach { $0() }
        cancellationBySourceWebViewID.removeAll()
        attemptsBySourceWebViewID.removeAll()
    }
}

/// Flushes already-admitted protected commands. Effects are delegated to the
/// terminal executor; this role owns only task de-duplication and retry timing.
@MainActor
final class DeferredProtectedCommandProcessor {
    private let mediaProtection: WebViewMediaProtectionOwner
    private let webViews: WebViewRuntimeWebViewResolver
    private let authority: DeferredWebViewCommandAuthority
    private let executor: DeferredWebViewCommandExecutor
    private let retryLedger: DeferredProtectedCommandRetryLedger
    private let delayedActions: MainActorDelayedActionScheduler
    private let finishCleanupSuppression: @MainActor ([ObjectIdentifier]) -> Void

    private var flushTasksBySourceWebViewID: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(
        mediaProtection: WebViewMediaProtectionOwner,
        webViews: WebViewRuntimeWebViewResolver,
        authority: DeferredWebViewCommandAuthority,
        executor: DeferredWebViewCommandExecutor,
        retryLedger: DeferredProtectedCommandRetryLedger,
        delayedActions: MainActorDelayedActionScheduler = .live,
        finishCleanupSuppression: @escaping @MainActor ([ObjectIdentifier]) -> Void
    ) {
        self.mediaProtection = mediaProtection
        self.webViews = webViews
        self.authority = authority
        self.executor = executor
        self.retryLedger = retryLedger
        self.delayedActions = delayedActions
        self.finishCleanupSuppression = finishCleanupSuppression
    }

    isolated deinit {
        flushTasksBySourceWebViewID.values.forEach { $0.cancel() }
        retryLedger.reset()
    }

    func flushCommands(for webViewID: ObjectIdentifier) {
        guard mediaProtection.hasDeferredProtectedCommands(for: webViewID) else {
            retryLedger.clear(for: webViewID)
            return
        }
        guard flushTasksBySourceWebViewID[webViewID] == nil else { return }

        flushTasksBySourceWebViewID[webViewID] = Task { @MainActor [weak self] in
            guard let self, Task.isCancelled == false else { return }
            defer { flushTasksBySourceWebViewID.removeValue(forKey: webViewID) }
            guard mediaProtection.hasDeferredProtectedCommands(for: webViewID) else { return }

            let interval = PerformanceTrace.beginInterval(
                "DeferredProtectedCommandProcessor.flush"
            )
            defer {
                PerformanceTrace.endInterval(
                    "DeferredProtectedCommandProcessor.flush",
                    interval
                )
            }

            mediaProtection.executeDeferredCommandsIfUnprotected(
                for: webViewID,
                resolveWebView: webViews.resolve,
                isCommandValid: isValid,
                dropCommand: drop,
                didPruneStaleWebViewIDs: finishCleanupSuppression,
                executeCommand: { [weak self] command in
                    guard let self,
                          let prepared = authority.prepare(command) else {
                        return .invalidTarget
                    }
                    let outcome = executor.execute(prepared)
                    RuntimeDiagnostics.protectedWebViewTrace(
                        "executeDeferredCommand sourceWebView=\(webViewID) command={\(command.debugSummary)}"
                    )
                    switch outcome {
                    case .executed:
                        retryLedger.clear(for: webViewID)
                    case .invalidTarget:
                        break
                    case .retry:
                        scheduleRetry(for: webViewID)
                        RuntimeDiagnostics.protectedWebViewTrace(
                            "retainDeferredCommandAfterExecutionFailure sourceWebView=\(webViewID) command={\(command.debugSummary)}"
                        )
                    }
                    return outcome
                }
            )
            if mediaProtection.hasDeferredProtectedCommands(for: webViewID) == false {
                retryLedger.clear(for: webViewID)
            }
        }
    }

    func resetForTerminalShutdown() {
        flushTasksBySourceWebViewID.values.forEach { $0.cancel() }
        flushTasksBySourceWebViewID.removeAll()
        retryLedger.reset()
    }

    private func isValid(_ command: DeferredWebViewCommand) -> Bool {
        authority.prepare(command) != nil
    }

    private func scheduleRetry(for webViewID: ObjectIdentifier) {
        retryLedger.scheduleIfNeeded(
            for: webViewID,
            using: delayedActions
        ) { [weak self] in
            guard let self else { return }
            retryLedger.consumeScheduledAction(for: webViewID)
            guard mediaProtection.hasDeferredProtectedCommands(for: webViewID) else {
                retryLedger.clear(for: webViewID)
                return
            }
            flushCommands(for: webViewID)
        }
    }

    private func drop(
        _ command: DeferredWebViewCommand,
        sourceWebViewID: ObjectIdentifier,
        reason: String
    ) {
        PerformanceTrace.emitEvent(
            "DeferredProtectedCommandProcessor.dropDeferredProtectedCommand"
        )
        RuntimeDiagnostics.protectedWebViewTrace(
            "dropDeferredCommand reason=\(reason) sourceWebView=\(sourceWebViewID) command={\(command.debugSummary)}"
        )
    }
}
