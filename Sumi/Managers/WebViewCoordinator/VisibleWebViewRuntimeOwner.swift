//
//  VisibleWebViewRuntimeOwner.swift
//  Sumi
//
//  Owns visible WebView preparation and compositor container bookkeeping.
//

import AppKit
import Foundation
import WebKit

@MainActor
final class VisibleWebViewRuntimeOwner {
    private let compositorHandoffState = WebViewCompositorHandoffState()
    private var scheduledPrepareWindowIds: Set<UUID> = []

    // MARK: - Compositor Containers

    func setCompositorContainerView(_ view: NSView?, for windowId: UUID) {
        compositorHandoffState.setContainerView(view, for: windowId)
    }

    func setImmediateVisualHandoffHandler(
        _ handler: (@MainActor () -> Bool)?,
        for windowId: UUID
    ) {
        compositorHandoffState.setImmediateVisualHandoffHandler(handler, for: windowId)
    }

    @discardableResult
    func performImmediateVisualHandoffIfPossible(in windowId: UUID) -> Bool {
        compositorHandoffState.performImmediateVisualHandoffIfPossible(in: windowId)
    }

    func compositorContainerView(for windowId: UUID) -> NSView? {
        compositorHandoffState.containerView(for: windowId)
    }

    func removeCompositorContainerView(
        for windowId: UUID,
        webViewRegistry: WindowWebViewRegistry,
        pruneInvalidDeferredCommands: (String) -> Void
    ) {
        compositorHandoffState.removeContainerView(for: windowId)
        scheduledPrepareWindowIds.remove(windowId)
        webViewRegistry.removeVisibilityHistory(for: windowId)
        pruneInvalidDeferredCommands("removeCompositorContainerView")
    }

    func compositorContainers() -> [(UUID, NSView)] {
        compositorHandoffState.containerViewsByWindow()
    }

    func resetWindowRegistrations() {
        compositorHandoffState.removeAllWindowRegistrations()
        scheduledPrepareWindowIds.removeAll()
    }

    func cancelScheduledPreparation(for windowId: UUID) {
        scheduledPrepareWindowIds.remove(windowId)
    }

    // MARK: - Promoted Host Handoff

    func registerPromotedHost(
        _ host: SumiWebViewContainerView,
        for tabId: UUID,
        in windowId: UUID,
        attachmentCompletion: (@MainActor () -> Void)? = nil
    ) {
        compositorHandoffState.registerPromotedHost(
            host,
            for: tabId,
            in: windowId,
            attachmentCompletion: attachmentCompletion
        )
    }

    func takePromotedHost(
        for tabId: UUID,
        in windowId: UUID,
        expectedWebView: WKWebView
    ) -> SumiWebViewContainerView? {
        compositorHandoffState.takePromotedHost(
            for: tabId,
            in: windowId,
            expectedWebView: expectedWebView
        )
    }

    func completePromotedHostAttachment(for tabId: UUID, in windowId: UUID) {
        compositorHandoffState.completePromotedHostAttachment(for: tabId, in: windowId)
    }

    // MARK: - Visible WebView Preparation

    @discardableResult
    func prepareVisibleWebViews(
        for windowState: BrowserWindowState,
        browserManager: BrowserManager,
        webViewRegistry: WindowWebViewRegistry,
        resolveTab: (UUID, BrowserWindowState, BrowserManager) -> Tab?,
        existingWebView: (UUID, UUID) -> WKWebView?,
        createWebView: (Tab, UUID) -> WKWebView?,
        evictHiddenWebViews: (UUID, Set<UUID>, TabManager) -> Void
    ) -> Bool {
        let signpostState = PerformanceTrace.beginInterval("WebViewCoordinator.prepareVisibleWebViews")
        defer {
            PerformanceTrace.endInterval(
                "WebViewCoordinator.prepareVisibleWebViews",
                signpostState
            )
        }

        let visibleTabIDs = visibleTabIDs(
            for: windowState,
            browserManager: browserManager,
            resolveTab: resolveTab
        )
        webViewRegistry.noteVisibleTabs(visibleTabIDs, in: windowState.id)

        var didCreateWebView = false
        for tabId in visibleTabIDs {
            guard let tab = resolveTab(tabId, windowState, browserManager) else {
                continue
            }
            guard browserManager.canMaterializeNormalTabWebViewDuringStartup(tab) else {
                continue
            }

            browserManager.compositorManager.markTabAccessed(tab.id)
            if existingWebView(tab.id, windowState.id) == nil,
               createWebView(tab, windowState.id) != nil
            {
                didCreateWebView = true
            }
        }

        evictHiddenWebViews(
            windowState.id,
            Set(visibleTabIDs),
            browserManager.tabManager
        )
        browserManager.tabSuspensionService.scheduleProactiveTimerReconcile(
            reason: "visible-webviews-prepared"
        )
        browserManager.backgroundMediaOptimizationService.scheduleReconcile(
            reason: "visible-webviews-prepared"
        )

        return didCreateWebView
    }

    func schedulePrepareVisibleWebViews(
        for windowState: BrowserWindowState,
        browserManager: BrowserManager,
        prepareVisibleWebViews: @escaping @MainActor (BrowserWindowState, BrowserManager) -> Bool
    ) {
        let windowId = windowState.id
        guard scheduledPrepareWindowIds.insert(windowId).inserted else { return }

        DispatchQueue.main.async { [weak self, weak browserManager, weak windowState] in
            guard let self else { return }
            self.scheduledPrepareWindowIds.remove(windowId)

            guard let browserManager, let windowState else { return }
            let didCreateWebView = prepareVisibleWebViews(windowState, browserManager)
            if didCreateWebView {
                browserManager.refreshCompositor(for: windowState)
            }
        }
    }

    func visibleTabIDs(
        for windowState: BrowserWindowState,
        browserManager: BrowserManager,
        resolveTab: (UUID, BrowserWindowState, BrowserManager) -> Tab?
    ) -> [UUID] {
        VisibleTabPreparationPlan.visibleTabIDs(
            currentTabId: browserManager.currentTab(for: windowState)?.id,
            splitTabIds: browserManager.splitManager.visibleTabIds(for: windowState.id)
        ).filter { tabId in
            guard let tab = resolveTab(tabId, windowState, browserManager) else {
                return false
            }
            return tab.requiresPrimaryWebView
        }
    }

    func visibleTabIDSet(
        in windowId: UUID,
        browserManager: BrowserManager?,
        resolveTab: (UUID, BrowserWindowState, BrowserManager) -> Tab?
    ) -> Set<UUID> {
        guard let browserManager,
              let windowState = browserManager.windowRegistry?.windows[windowId]
        else {
            return []
        }
        return Set(
            visibleTabIDs(
                for: windowState,
                browserManager: browserManager,
                resolveTab: resolveTab
            )
        )
    }

    func preferredPrimaryWebViewCandidate(
        for tabId: UUID,
        browserManager: BrowserManager?,
        webViewRegistry: WindowWebViewRegistry,
        resolveTab: (UUID, BrowserWindowState, BrowserManager) -> Tab?
    ) -> (owner: TrackedWebViewOwner, webView: WKWebView)? {
        let candidates = webViewRegistry.trackedWebViews(for: tabId)
        guard candidates.isEmpty == false else { return nil }

        return candidates.min { lhs, rhs in
            candidatePriority(
                for: lhs.0,
                browserManager: browserManager,
                webViewRegistry: webViewRegistry,
                resolveTab: resolveTab
            )
                < candidatePriority(
                    for: rhs.0,
                    browserManager: browserManager,
                    webViewRegistry: webViewRegistry,
                    resolveTab: resolveTab
                )
        }
    }

    private func candidatePriority(
        for owner: TrackedWebViewOwner,
        browserManager: BrowserManager?,
        webViewRegistry: WindowWebViewRegistry,
        resolveTab: (UUID, BrowserWindowState, BrowserManager) -> Tab?
    ) -> (Int, Int, String) {
        let visibleRank: Int
        if let browserManager,
           let windowState = browserManager.windowRegistry?.windows[owner.windowID],
           visibleTabIDs(
               for: windowState,
               browserManager: browserManager,
               resolveTab: resolveTab
           ).contains(owner.tabID)
        {
            visibleRank = 0
        } else {
            visibleRank = 1
        }

        let mruRank = webViewRegistry.recentVisibilityRank(for: owner)
        return (visibleRank, mruRank, owner.windowID.uuidString)
    }
}
