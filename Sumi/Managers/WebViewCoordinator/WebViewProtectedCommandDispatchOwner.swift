import AppKit
import Foundation
import WebKit

/// Routes WebView mutations that arrive while a WebView is protected from
/// compositor changes (fullscreen media, history swipe, visual handoff):
/// enqueues them as deferred commands, prunes invalidated ones, and executes
/// them once protection lifts.
@MainActor
final class WebViewProtectedCommandDispatchOwner {
    struct Dependencies {
        let mediaProtectionOwner: WebViewMediaProtectionOwner
        let executionOwner: WebViewDeferredProtectedCommandExecutionOwner
        let tabScopedCleanupValidationOwner: WebViewTabScopedCleanupValidationOwner
        let webViewRegistry: WindowWebViewRegistry
        let requireBrowserRuntimeContext: @MainActor () -> WebViewCoordinatorBrowserRuntimeContext
        let resolveWebView: @MainActor (ObjectIdentifier) -> WKWebView?
        let resolvedTab: @MainActor (UUID, WebViewCoordinatorBrowserRuntimeContext) -> Tab?
        let compositorContainerView: @MainActor (UUID) -> NSView?
        let removeWebViewFromContainers: @MainActor (WKWebView) -> Void
        let removeAllWebViews: @MainActor (Tab) -> Void
        let cleanupTrackedWebView: @MainActor (WKWebView, TrackedWebViewOwner) -> Void
        let cleanupWindow: @MainActor (UUID, TabManager) -> Void
        let cleanupAllWebViews: @MainActor (TabManager) -> Void
        let rebuildLiveWebViews: @MainActor (Tab, UUID?) -> Void
        let evictHiddenWebViews: @MainActor (UUID, Set<UUID>) -> Void
        let visibleTabIDSet: @MainActor (UUID) -> Set<UUID>
        let performFallbackWebViewCleanup: @MainActor (WKWebView, UUID) -> Void
        let finishCleanupSuppression: @MainActor ([ObjectIdentifier]) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    @discardableResult
    func enqueue(
        _ command: DeferredWebViewCommand,
        for webView: WKWebView,
        reason: String
    ) -> Bool {
        dependencies.mediaProtectionOwner.note(webView)
        guard dependencies.mediaProtectionOwner.isProtected(webView) else {
            return false
        }

        return dependencies.executionOwner.enqueue(
            command,
            for: webView,
            reason: reason,
            mediaProtectionOwner: dependencies.mediaProtectionOwner,
            runtime: executionRuntime()
        )
    }

    func flushCommands(for webViewID: ObjectIdentifier) {
        guard dependencies.mediaProtectionOwner.hasDeferredProtectedCommands(for: webViewID) else {
            return
        }
        dependencies.executionOwner.flushCommandsIfUnprotected(
            for: webViewID,
            mediaProtectionOwner: dependencies.mediaProtectionOwner,
            runtime: executionRuntime()
        )
    }

    func pruneInvalidCommands(reason: String) {
        guard dependencies.mediaProtectionOwner.hasDeferredProtectedCommands else { return }
        dependencies.executionOwner.pruneInvalidCommands(
            reason: reason,
            mediaProtectionOwner: dependencies.mediaProtectionOwner,
            runtime: executionRuntime()
        )
    }

    // MARK: - Execution

    private func executionRuntime() -> WebViewDeferredProtectedCommandExecutionOwner.Runtime {
        let runtimeContext = dependencies.requireBrowserRuntimeContext()
        let validationContext = WebViewDeferredProtectedCommandExecutionOwner.ValidationContext(
            resolveWebView: { [dependencies] webViewID in
                dependencies.resolveWebView(webViewID)
            },
            resolveTrackedOwner: { [dependencies] webViewID in
                dependencies.webViewRegistry.trackedOwner(with: webViewID)
            },
            canCleanUpTabWebView: { [self] webViewID, tabID in
                dependencies.tabScopedCleanupValidationOwner.canCleanUpTabScopedWebView(
                    with: webViewID,
                    tabID: tabID,
                    context: tabScopedCleanupValidationContext(runtimeContext)
                )
            },
            resolveTab: { [dependencies] tabID in
                dependencies.resolvedTab(tabID, runtimeContext)
            },
            hasTabManager: {
                true
            },
            hasCleanupWindowTarget: { [dependencies] windowID in
                dependencies.webViewRegistry.trackedWebViews(in: windowID).isEmpty == false
                    || dependencies.compositorContainerView(windowID) != nil
            },
            hasTrackedWebViews: { [dependencies] in
                dependencies.webViewRegistry.isEmpty == false
            },
            hasWindow: { windowID in
                runtimeContext.window(windowID) != nil
            }
        )
        return WebViewDeferredProtectedCommandExecutionOwner.Runtime(
            validationContext: validationContext,
            executeCommand: { [weak self] command in
                self?.execute(command) ?? false
            },
            finishCleanupSuppression: { [dependencies] webViewIDs in
                dependencies.finishCleanupSuppression(webViewIDs)
            }
        )
    }

    @discardableResult
    func execute(_ command: DeferredWebViewCommand) -> Bool {
        switch command {
        case .removeWebViewFromContainers(let webViewID):
            guard let webView = dependencies.resolveWebView(webViewID) else {
                return false
            }
            dependencies.removeWebViewFromContainers(webView)
        case .removeAllWebViews(let tabID):
            guard let tab = resolvedTab(with: tabID) else {
                return false
            }
            dependencies.removeAllWebViews(tab)
        case .removeTrackedWebView(let webViewID, let tabID, let windowID):
            guard let webView = dependencies.resolveWebView(webViewID) else {
                return false
            }
            dependencies.cleanupTrackedWebView(
                webView,
                TrackedWebViewOwner(tabID: tabID, windowID: windowID)
            )
        case .closeWebViewFromWebKit(let webViewID):
            guard let webView = dependencies.resolveWebView(webViewID) else {
                return false
            }
            guard dependencies.requireBrowserRuntimeContext()
                .handleUnprotectedWebViewDidClose(webView) else {
                return false
            }
        case .cleanupWindow(let windowID):
            dependencies.cleanupWindow(
                windowID,
                dependencies.requireBrowserRuntimeContext().tabManager()
            )
        case .cleanupAllWebViews:
            dependencies.cleanupAllWebViews(
                dependencies.requireBrowserRuntimeContext().tabManager()
            )
        case .rebuildLiveWebViews(let tabID, let preferredPrimaryWindowID):
            guard let tab = resolvedTab(with: tabID) else {
                return false
            }
            dependencies.rebuildLiveWebViews(tab, preferredPrimaryWindowID)
        case .evictHiddenWebViews(let windowID):
            let runtimeContext = dependencies.requireBrowserRuntimeContext()
            guard runtimeContext.window(windowID) != nil
            else {
                return false
            }
            dependencies.evictHiddenWebViews(
                windowID,
                dependencies.visibleTabIDSet(windowID)
            )
        case .cleanupTabWebView(let webViewID, let tabID):
            guard let webView = dependencies.resolveWebView(webViewID) else {
                return false
            }
            if let tab = resolvedTab(with: tabID) {
                tab.cleanupCloneWebView(webView)
            } else {
                dependencies.performFallbackWebViewCleanup(webView, tabID)
            }
        case .performFallbackWebViewCleanup(let webViewID, let tabID):
            guard let webView = dependencies.resolveWebView(webViewID) else {
                return false
            }
            dependencies.performFallbackWebViewCleanup(webView, tabID)
        }

        return true
    }

    private func resolvedTab(with tabID: UUID) -> Tab? {
        dependencies.resolvedTab(tabID, dependencies.requireBrowserRuntimeContext())
    }

    private func tabScopedCleanupValidationContext(
        _ runtimeContext: WebViewCoordinatorBrowserRuntimeContext
    ) -> WebViewTabScopedCleanupValidationOwner.Context {
        WebViewTabScopedCleanupValidationOwner.Context(
            trackedOwner: { [dependencies] webViewID in
                dependencies.webViewRegistry.trackedOwner(with: webViewID)
            },
            resolveWebView: { [dependencies] webViewID in
                dependencies.resolveWebView(webViewID)
            },
            resolveTab: { [dependencies] tabID in
                dependencies.resolvedTab(tabID, runtimeContext)
            },
            allTabs: {
                runtimeContext.regularTabs()
                    + runtimeContext.pinnedTabs()
                    + runtimeContext.allWindows().flatMap(\.ephemeralTabs)
            }
        )
    }
}

extension WebViewProtectedCommandDispatchOwner.Dependencies {
    @MainActor
    static func live(coordinator: WebViewCoordinator) -> Self {
        Self(
            mediaProtectionOwner: coordinator.mediaProtectionOwner,
            executionOwner: coordinator.deferredProtectedCommandExecutionOwner,
            tabScopedCleanupValidationOwner: coordinator.tabScopedCleanupValidationOwner,
            webViewRegistry: coordinator.webViewRegistry,
            requireBrowserRuntimeContext: { [weak coordinator] in
                guard let coordinator else {
                    preconditionFailure("WebViewCoordinator dependency used after deallocation")
                }
                return coordinator.runtimeContextStore.requireBrowser()
            },
            resolveWebView: { [weak coordinator] webViewID in
                coordinator?.resolveWebView(with: webViewID)
            },
            resolvedTab: { [weak coordinator] tabID, runtimeContext in
                coordinator?.resolvedTab(with: tabID, runtimeContext: runtimeContext)
            },
            compositorContainerView: { [weak coordinator] windowID in
                coordinator?.compositorContainerView(for: windowID)
            },
            removeWebViewFromContainers: { [weak coordinator] webView in
                coordinator?.removeWebViewFromContainers(webView)
            },
            removeAllWebViews: { [weak coordinator] tab in
                _ = coordinator?.removeAllWebViews(for: tab)
            },
            cleanupTrackedWebView: { [weak coordinator] webView, owner in
                coordinator?.cleanupTrackedWebView(webView, owner: owner)
            },
            cleanupWindow: { [weak coordinator] windowID, tabManager in
                coordinator?.cleanupWindow(windowID, tabManager: tabManager)
            },
            cleanupAllWebViews: { [weak coordinator] tabManager in
                coordinator?.cleanupAllWebViews(tabManager: tabManager)
            },
            rebuildLiveWebViews: { [weak coordinator] tab, preferredPrimaryWindowId in
                _ = coordinator?.rebuildLiveWebViews(
                    for: tab,
                    preferredPrimaryWindowId: preferredPrimaryWindowId
                )
            },
            evictHiddenWebViews: { [weak coordinator] windowID, visibleTabIDs in
                coordinator?.evictHiddenWebViewsIfNeeded(
                    in: windowID,
                    visibleTabIDs: visibleTabIDs
                )
            },
            visibleTabIDSet: { [weak coordinator] windowID in
                coordinator?.visibleTabIDSet(in: windowID) ?? []
            },
            performFallbackWebViewCleanup: { [weak coordinator] webView, tabID in
                coordinator?.performFallbackWebViewCleanup(webView, tabId: tabID)
            },
            finishCleanupSuppression: { [weak coordinator] webViewIDs in
                coordinator?.finishDestructiveCleanupSuppression(for: webViewIDs)
            }
        )
    }
}
