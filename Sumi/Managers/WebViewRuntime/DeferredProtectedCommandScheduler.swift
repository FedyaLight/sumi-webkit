import Foundation
import SumiWebRuntime
import WebKit

/// Owns buffering, flush de-duplication, and retry timing for protected WebView
/// commands. Command validity belongs to the authority; effects belong to the
/// executor.
@MainActor
final class DeferredProtectedCommandScheduler {
    private static let initialRetryDelayNanoseconds: UInt64 = 25_000_000
    private static let maximumRetryDelayNanoseconds: UInt64 = 1_000_000_000

    private let mediaProtection: WebViewMediaProtectionOwner
    private let webViews: WebViewRuntimeWebViewResolver
    private let authority: DeferredWebViewCommandAuthority
    private let executor: DeferredWebViewCommandExecutor
    private let finishCleanupSuppression: @MainActor ([ObjectIdentifier]) -> Void

    private var retryAttemptsBySourceWebViewID: [ObjectIdentifier: Int] = [:]
    private var retryTasksBySourceWebViewID: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var flushTasksBySourceWebViewID: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(
        mediaProtection: WebViewMediaProtectionOwner,
        webViews: WebViewRuntimeWebViewResolver,
        authority: DeferredWebViewCommandAuthority,
        executor: DeferredWebViewCommandExecutor,
        finishCleanupSuppression: @escaping @MainActor ([ObjectIdentifier]) -> Void
    ) {
        self.mediaProtection = mediaProtection
        self.webViews = webViews
        self.authority = authority
        self.executor = executor
        self.finishCleanupSuppression = finishCleanupSuppression
    }

    deinit {
        retryTasksBySourceWebViewID.values.forEach { $0.cancel() }
        flushTasksBySourceWebViewID.values.forEach { $0.cancel() }
    }

    func schedule(
        _ command: DeferredWebViewCommand,
        for webView: WKWebView,
        reason: String
    ) -> DeferredProtectedCommandSchedulingOutcome {
        mediaProtection.note(webView)
        guard mediaProtection.isProtected(webView) else { return .notProtected }

        let outcome = mediaProtection.enqueueDeferredCommandIfNeeded(
            command,
            for: webView,
            reason: reason,
            resolveWebView: webViews.resolve,
            isCommandValid: isValid,
            dropCommand: drop,
            didPruneStaleWebViewIDs: finishCleanupSuppression
        )
        if outcome.wasScheduled {
            clearRetryState(for: ObjectIdentifier(webView))
        }
        return outcome
    }

    func flushCommands(for webViewID: ObjectIdentifier) {
        guard mediaProtection.hasDeferredProtectedCommands(for: webViewID) else {
            clearRetryState(for: webViewID)
            return
        }
        guard flushTasksBySourceWebViewID[webViewID] == nil else { return }

        flushTasksBySourceWebViewID[webViewID] = Task { @MainActor [weak self] in
            guard let self, Task.isCancelled == false else { return }
            defer { flushTasksBySourceWebViewID.removeValue(forKey: webViewID) }
            guard mediaProtection.hasDeferredProtectedCommands(for: webViewID) else { return }

            let interval = PerformanceTrace.beginInterval(
                "DeferredProtectedCommandScheduler.flush"
            )
            defer {
                PerformanceTrace.endInterval(
                    "DeferredProtectedCommandScheduler.flush",
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
                        clearRetryState(for: webViewID)
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
                clearRetryState(for: webViewID)
            }
        }
    }

    func pruneInvalidCommands(reason: String) {
        guard mediaProtection.hasDeferredProtectedCommands else { return }
        finishCleanupSuppression(mediaProtection.pruneInvalidDeferredCommands(
            reason: reason,
            resolveWebView: webViews.resolve,
            isCommandValid: isValid,
            dropCommand: drop
        ))
    }

    func resetForTerminalShutdown() {
        flushTasksBySourceWebViewID.values.forEach { $0.cancel() }
        flushTasksBySourceWebViewID.removeAll()
        retryTasksBySourceWebViewID.values.forEach { $0.cancel() }
        retryTasksBySourceWebViewID.removeAll()
        retryAttemptsBySourceWebViewID.removeAll()
    }

    private func isValid(_ command: DeferredWebViewCommand) -> Bool {
        authority.prepare(command) != nil
    }

    private func scheduleRetry(for webViewID: ObjectIdentifier) {
        guard retryTasksBySourceWebViewID[webViewID] == nil else { return }
        let attempt = min((retryAttemptsBySourceWebViewID[webViewID] ?? 0) + 1, 64)
        retryAttemptsBySourceWebViewID[webViewID] = attempt
        let exponent = min(attempt - 1, 6)
        let delay = min(
            Self.initialRetryDelayNanoseconds * (UInt64(1) << UInt64(exponent)),
            Self.maximumRetryDelayNanoseconds
        )

        retryTasksBySourceWebViewID[webViewID] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard Task.isCancelled == false, let self else { return }
            retryTasksBySourceWebViewID.removeValue(forKey: webViewID)
            guard mediaProtection.hasDeferredProtectedCommands(for: webViewID) else {
                clearRetryState(for: webViewID)
                return
            }
            flushCommands(for: webViewID)
        }
    }

    private func clearRetryState(for webViewID: ObjectIdentifier) {
        retryTasksBySourceWebViewID.removeValue(forKey: webViewID)?.cancel()
        retryAttemptsBySourceWebViewID.removeValue(forKey: webViewID)
    }

    private func drop(
        _ command: DeferredWebViewCommand,
        sourceWebViewID: ObjectIdentifier,
        reason: String
    ) {
        PerformanceTrace.emitEvent(
            "DeferredProtectedCommandScheduler.dropDeferredProtectedCommand"
        )
        RuntimeDiagnostics.protectedWebViewTrace(
            "dropDeferredCommand reason=\(reason) sourceWebView=\(sourceWebViewID) command={\(command.debugSummary)}"
        )
    }
}
