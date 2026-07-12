//
//  WebViewDeferredProtectedCommandExecutionOwner.swift
//  Sumi
//
//  Owns deferred protected WebView command validation and execution flow.
//

import Foundation
import SumiWebRuntime
import WebKit

@MainActor
final class WebViewDeferredProtectedCommandExecutionOwner {
    private static let initialRetryDelayNanoseconds: UInt64 = 25_000_000
    private static let maximumRetryDelayNanoseconds: UInt64 = 1_000_000_000

    typealias WebViewResolver = (ObjectIdentifier) -> WKWebView?
    typealias TrackedOwnerResolver = (ObjectIdentifier) -> TrackedWebViewOwner?
    typealias DetachedWebViewCleanupValidator = (ObjectIdentifier, UUID) -> Bool
    typealias FallbackWebViewCleanupValidator = (
        ObjectIdentifier,
        WebViewPendingCleanupLease
    ) -> Bool
    typealias TabResolver = (UUID) -> Tab?
    typealias CommandExecutor = (
        DeferredWebViewCommand
    ) -> DeferredProtectedCommandExecutionOutcome
    typealias CleanupSuppressionFinisher = ([ObjectIdentifier]) -> Void

    private var retryAttemptsBySourceWebViewID: [ObjectIdentifier: Int] = [:]
    private var retryTasksBySourceWebViewID: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var flushTasksBySourceWebViewID: [ObjectIdentifier: Task<Void, Never>] = [:]

    deinit {
        retryTasksBySourceWebViewID.values.forEach { $0.cancel() }
        flushTasksBySourceWebViewID.values.forEach { $0.cancel() }
    }

    struct ValidationContext {
        let resolveWebView: WebViewResolver
        let resolveTrackedOwner: TrackedOwnerResolver
        let canCleanUpDetachedWebView: DetachedWebViewCleanupValidator
        let canPerformFallbackWebViewCleanup: FallbackWebViewCleanupValidator
        let resolveTab: TabResolver
        let isSpaceProfileAssignmentValid: (
            DeferredWebViewSpaceProfileAssignmentIntent
        ) -> Bool
        let isRuntimeAvailable: () -> Bool
        let hasCleanupWindowTarget: (UUID) -> Bool
        let hasTrackedWebViews: () -> Bool
        let hasWindow: (UUID) -> Bool
    }

    struct Runtime {
        let validationContext: ValidationContext
        let executeCommand: CommandExecutor
        let finishCleanupSuppression: CleanupSuppressionFinisher
    }

    @discardableResult
    func enqueue(
        _ command: DeferredWebViewCommand,
        for webView: WKWebView,
        reason: String,
        mediaProtectionOwner: WebViewMediaProtectionOwner,
        runtime: Runtime
    ) -> Bool {
        schedule(
            command,
            for: webView,
            reason: reason,
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: runtime
        ).wasScheduled
    }

    func schedule(
        _ command: DeferredWebViewCommand,
        for webView: WKWebView,
        reason: String,
        mediaProtectionOwner: WebViewMediaProtectionOwner,
        runtime: Runtime
    ) -> DeferredProtectedCommandSchedulingOutcome {
        let outcome = mediaProtectionOwner.enqueueDeferredCommandIfNeeded(
            command,
            for: webView,
            reason: reason,
            resolveWebView: runtime.validationContext.resolveWebView,
            isCommandValid: { command in
                isCommandValid(command, context: runtime.validationContext)
            },
            dropCommand: { command, sourceWebViewID, reason in
                drop(
                    command,
                    sourceWebViewID: sourceWebViewID,
                    reason: reason
                )
            },
            didPruneStaleWebViewIDs: runtime.finishCleanupSuppression
        )
        if outcome.wasScheduled {
            clearRetryState(for: ObjectIdentifier(webView))
        }
        return outcome
    }

    func flushCommandsIfUnprotected(
        for webViewID: ObjectIdentifier,
        mediaProtectionOwner: WebViewMediaProtectionOwner,
        runtime: Runtime
    ) {
        guard mediaProtectionOwner.hasDeferredProtectedCommands(for: webViewID) else {
            clearRetryState(for: webViewID)
            return
        }
        guard flushTasksBySourceWebViewID[webViewID] == nil else { return }
        flushTasksBySourceWebViewID[webViewID] = Task { @MainActor [weak self] in
            guard let self, Task.isCancelled == false else { return }
            defer {
                flushTasksBySourceWebViewID.removeValue(forKey: webViewID)
            }
            guard mediaProtectionOwner.hasDeferredProtectedCommands(for: webViewID) else {
                return
            }
            let signpostState = PerformanceTrace.beginInterval(
                "WebViewDeferredProtectedCommandExecutionOwner.flushDeferredProtectedCommands"
            )
            defer {
                PerformanceTrace.endInterval(
                    "WebViewDeferredProtectedCommandExecutionOwner.flushDeferredProtectedCommands",
                    signpostState
                )
            }

            mediaProtectionOwner.executeDeferredCommandsIfUnprotected(
                for: webViewID,
                resolveWebView: runtime.validationContext.resolveWebView,
                isCommandValid: { command in
                    isCommandValid(command, context: runtime.validationContext)
                },
                dropCommand: { command, sourceWebViewID, reason in
                    drop(
                        command,
                        sourceWebViewID: sourceWebViewID,
                        reason: reason
                    )
                },
                didPruneStaleWebViewIDs: runtime.finishCleanupSuppression,
                executeCommand: { [weak self] command in
                    guard let self else { return .invalidTarget }
                    let outcome = runtime.executeCommand(command)
                    RuntimeDiagnostics.protectedWebViewTrace(
                        "executeDeferredCommand sourceWebView=\(webViewID) command={\(command.debugSummary)}"
                    )
                    switch outcome {
                    case .executed:
                        clearRetryState(for: webViewID)
                    case .invalidTarget:
                        break
                    case .retry:
                        scheduleRetry(
                            for: webViewID,
                            mediaProtectionOwner: mediaProtectionOwner,
                            runtime: runtime
                        )
                        RuntimeDiagnostics.protectedWebViewTrace(
                            "retainDeferredCommandAfterExecutionFailure sourceWebView=\(webViewID) command={\(command.debugSummary)}"
                        )
                    }
                    return outcome
                }
            )
            if mediaProtectionOwner.hasDeferredProtectedCommands(for: webViewID) == false {
                clearRetryState(for: webViewID)
            }
        }
    }

    func resetForTerminalShutdown() {
        flushTasksBySourceWebViewID.values.forEach { $0.cancel() }
        flushTasksBySourceWebViewID.removeAll()
        retryTasksBySourceWebViewID.values.forEach { $0.cancel() }
        retryTasksBySourceWebViewID.removeAll()
        retryAttemptsBySourceWebViewID.removeAll()
    }

    func pruneInvalidCommands(
        reason: String,
        mediaProtectionOwner: WebViewMediaProtectionOwner,
        runtime: Runtime
    ) {
        runtime.finishCleanupSuppression(
            mediaProtectionOwner.pruneInvalidDeferredCommands(
                reason: reason,
                resolveWebView: runtime.validationContext.resolveWebView,
                isCommandValid: { command in
                    isCommandValid(command, context: runtime.validationContext)
                },
                dropCommand: { command, sourceWebViewID, reason in
                    drop(
                        command,
                        sourceWebViewID: sourceWebViewID,
                        reason: reason
                    )
                }
            )
        )
    }

    private func isCommandValid(
        _ command: DeferredWebViewCommand,
        context: ValidationContext
    ) -> Bool {
        switch command {
        case .removeWebViewFromContainers(let webViewID):
            return context.resolveWebView(webViewID) != nil
        case .removeTrackedWebView(let webViewID, let tabID, let windowID):
            return context.resolveTrackedOwner(webViewID) == TrackedWebViewOwner(
                tabID: tabID,
                windowID: windowID
            )
        case .closeWebViewFromWebKit(let webViewID):
            return context.resolveWebView(webViewID) != nil
        case .cleanupWindow(let windowID):
            return context.isRuntimeAvailable()
                && context.hasCleanupWindowTarget(windowID)
        case .cleanupAllWebViews:
            return context.isRuntimeAvailable()
                && context.hasTrackedWebViews()
        case .rebuildLiveWebViews(let tabID, _, let intent):
            guard let tab = context.resolveTab(tabID) else { return false }
            return tab.webViewRebuildEpoch.isCurrent(intent.revision)
        case .assignProfile(let tabID, _, let intent):
            guard let tab = context.resolveTab(tabID) else { return false }
            return tab.profileAssignment.isCurrent(intent)
        case .assignSpaceProfile(let intent):
            return context.isSpaceProfileAssignmentValid(intent)
        case .synchronizeTrackedNavigation(
            let webViewID,
            let tabID,
            let windowID,
            let intent
        ):
            guard context.resolveWebView(webViewID) != nil,
                  context.resolveTrackedOwner(webViewID) == TrackedWebViewOwner(
                      tabID: tabID,
                      windowID: windowID
                  ),
                  let tab = context.resolveTab(tabID) else {
                return false
            }
            return tab.mainFrameLoads.isCurrent(
                revision: intent.revision,
                targetURL: intent.targetURL
            )
        case .reloadTrackedNavigation(
            let webViewID,
            let tabID,
            let windowID,
            let intent
        ):
            guard context.resolveWebView(webViewID) != nil,
                  context.resolveTrackedOwner(webViewID) == TrackedWebViewOwner(
                      tabID: tabID,
                      windowID: windowID
                  ),
                  let tab = context.resolveTab(tabID) else {
                return false
            }
            return tab.mainFrameLoads.isCurrent(
                revision: intent.revision,
                targetURL: intent.targetURL
            )
        case .evictHiddenWebViews(let windowID):
            return context.isRuntimeAvailable()
                && context.hasWindow(windowID)
        case .cleanupTabWebView(let webViewID, let tabID):
            return context.canCleanUpDetachedWebView(webViewID, tabID)
        case .performFallbackWebViewCleanup(let webViewID, let lease):
            return context.canPerformFallbackWebViewCleanup(webViewID, lease)
        }
    }

    private func scheduleRetry(
        for webViewID: ObjectIdentifier,
        mediaProtectionOwner: WebViewMediaProtectionOwner,
        runtime: Runtime
    ) {
        guard retryTasksBySourceWebViewID[webViewID] == nil else { return }
        let attempt = min((retryAttemptsBySourceWebViewID[webViewID] ?? 0) + 1, 64)
        retryAttemptsBySourceWebViewID[webViewID] = attempt
        let exponent = min(attempt - 1, 6)
        let delayNanoseconds = min(
            Self.initialRetryDelayNanoseconds * (UInt64(1) << UInt64(exponent)),
            Self.maximumRetryDelayNanoseconds
        )

        retryTasksBySourceWebViewID[webViewID] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }
            guard Task.isCancelled == false, let self else { return }
            retryTasksBySourceWebViewID.removeValue(forKey: webViewID)
            guard mediaProtectionOwner.hasDeferredProtectedCommands(for: webViewID) else {
                clearRetryState(for: webViewID)
                return
            }
            flushCommandsIfUnprotected(
                for: webViewID,
                mediaProtectionOwner: mediaProtectionOwner,
                runtime: runtime
            )
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
            "WebViewDeferredProtectedCommandExecutionOwner.dropDeferredProtectedCommand"
        )
        RuntimeDiagnostics.protectedWebViewTrace(
            "dropDeferredCommand reason=\(reason) sourceWebView=\(sourceWebViewID) command={\(command.debugSummary)}"
        )
    }
}
