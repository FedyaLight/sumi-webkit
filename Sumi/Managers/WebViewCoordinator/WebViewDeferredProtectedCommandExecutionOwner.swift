//
//  WebViewDeferredProtectedCommandExecutionOwner.swift
//  Sumi
//
//  Owns deferred protected WebView command validation and execution flow.
//

import Foundation
import WebKit

@MainActor
struct WebViewDeferredProtectedCommandExecutionOwner {
    typealias WebViewResolver = (ObjectIdentifier) -> WKWebView?
    typealias TrackedOwnerResolver = (ObjectIdentifier) -> TrackedWebViewOwner?
    typealias TabWebViewCleanupValidator = (ObjectIdentifier, UUID) -> Bool
    typealias TabResolver = (UUID) -> Tab?
    typealias CommandExecutor = (DeferredWebViewCommand) -> Bool
    typealias CleanupSuppressionFinisher = ([ObjectIdentifier]) -> Void

    struct ValidationContext {
        let resolveWebView: WebViewResolver
        let resolveTrackedOwner: TrackedOwnerResolver
        let canCleanUpTabWebView: TabWebViewCleanupValidator
        let resolveTab: TabResolver
        let hasTabManager: () -> Bool
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
        mediaProtectionOwner.enqueueDeferredCommandIfNeeded(
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
    }

    func flushCommandsIfUnprotected(
        for webViewID: ObjectIdentifier,
        mediaProtectionOwner: WebViewMediaProtectionOwner,
        runtime: Runtime
    ) {
        let commands = mediaProtectionOwner.commandsToFlushIfUnprotected(
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
            didPruneStaleWebViewIDs: runtime.finishCleanupSuppression
        )
        guard !commands.isEmpty else { return }
        Task { @MainActor in
            let signpostState = PerformanceTrace.beginInterval(
                "WebViewCoordinator.flushDeferredProtectedCommands"
            )
            defer {
                PerformanceTrace.endInterval(
                    "WebViewCoordinator.flushDeferredProtectedCommands",
                    signpostState
                )
            }

            RuntimeDiagnostics.protectedWebViewTrace(
                "flushDeferredCommands sourceWebView=\(webViewID) count=\(commands.count)"
            )

            for command in commands {
                if execute(
                    command,
                    sourceWebViewID: webViewID,
                    runtime: runtime
                ) == false {
                    drop(
                        command,
                        sourceWebViewID: webViewID,
                        reason: "flush.invalidTarget"
                    )
                }
            }
        }
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

    @discardableResult
    private func execute(
        _ command: DeferredWebViewCommand,
        sourceWebViewID: ObjectIdentifier,
        runtime: Runtime
    ) -> Bool {
        guard isCommandValid(command, context: runtime.validationContext) else {
            return false
        }

        RuntimeDiagnostics.protectedWebViewTrace(
            "executeDeferredCommand sourceWebView=\(sourceWebViewID) command={\(command.debugSummary)}"
        )

        return runtime.executeCommand(command)
    }

    private func isCommandValid(
        _ command: DeferredWebViewCommand,
        context: ValidationContext
    ) -> Bool {
        switch command {
        case .removeWebViewFromContainers(let webViewID):
            return context.resolveWebView(webViewID) != nil
        case .removeAllWebViews(let tabID):
            return context.resolveTab(tabID) != nil
        case .removeTrackedWebView(let webViewID, let tabID, let windowID):
            return context.resolveTrackedOwner(webViewID) == TrackedWebViewOwner(
                tabID: tabID,
                windowID: windowID
            )
        case .closeWebViewFromWebKit(let webViewID):
            return context.resolveWebView(webViewID) != nil
        case .cleanupWindow(let windowID):
            return context.hasTabManager()
                && context.hasCleanupWindowTarget(windowID)
        case .cleanupAllWebViews:
            return context.hasTabManager()
                && context.hasTrackedWebViews()
        case .rebuildLiveWebViews(let tabID, _):
            return context.resolveTab(tabID) != nil
        case .evictHiddenWebViews(let windowID):
            return context.hasTabManager()
                && context.hasWindow(windowID)
        case .cleanupTabWebView(let webViewID, let tabID):
            return context.canCleanUpTabWebView(webViewID, tabID)
        case .performFallbackWebViewCleanup(let webViewID, let tabID):
            return context.canCleanUpTabWebView(webViewID, tabID)
        }
    }

    private func drop(
        _ command: DeferredWebViewCommand,
        sourceWebViewID: ObjectIdentifier,
        reason: String
    ) {
        PerformanceTrace.emitEvent("WebViewCoordinator.dropDeferredProtectedCommand")
        RuntimeDiagnostics.protectedWebViewTrace(
            "dropDeferredCommand reason=\(reason) sourceWebView=\(sourceWebViewID) command={\(command.debugSummary)}"
        )
    }
}
