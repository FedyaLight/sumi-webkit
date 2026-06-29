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
        runtime: VisibleWebViewPreparationRuntime,
        webViewRegistry: WindowWebViewRegistry,
        existingWebView: (UUID, UUID) -> WKWebView?,
        createWebView: (Tab, UUID) -> WKWebView?
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
            runtime: runtime
        )
        webViewRegistry.noteVisibleTabs(visibleTabIDs, in: windowState.id)

        var didCreateWebView = false
        for tabId in visibleTabIDs {
            guard let tab = runtime.resolveTab(tabId, windowState) else {
                continue
            }
            guard runtime.canMaterializeNormalTabWebViewDuringStartup(tab) else {
                continue
            }

            runtime.markTabAccessed(tab.id)
            if existingWebView(tab.id, windowState.id) == nil,
               createWebView(tab, windowState.id) != nil {
                didCreateWebView = true
            }
        }

        runtime.evictHiddenWebViews(
            windowState.id,
            Set(visibleTabIDs)
        )
        runtime.scheduleTabSuspensionReconcile("visible-webviews-prepared")
        runtime.scheduleBackgroundMediaReconcile("visible-webviews-prepared")

        return didCreateWebView
    }

    func schedulePrepareVisibleWebViews(
        for windowState: BrowserWindowState,
        runtime: VisibleWebViewPreparationRuntime,
        prepareVisibleWebViews: @escaping @MainActor (BrowserWindowState) -> Bool
    ) {
        let windowId = windowState.id
        guard scheduledPrepareWindowIds.insert(windowId).inserted else { return }

        DispatchQueue.main.async { [weak self, weak windowState] in
            guard let self else { return }
            self.scheduledPrepareWindowIds.remove(windowId)

            guard let windowState else { return }
            let didCreateWebView = prepareVisibleWebViews(windowState)
            if didCreateWebView {
                runtime.refreshCompositor(windowState)
            }
        }
    }

    func visibleTabIDs(
        for windowState: BrowserWindowState,
        runtime: VisibleWebViewPreparationRuntime
    ) -> [UUID] {
        VisibleTabPreparationPlan.visibleTabIDs(
            currentTabId: runtime.currentTabId(windowState),
            splitTabIds: runtime.splitVisibleTabIds(windowState.id)
        ).filter { tabId in
            guard let tab = runtime.resolveTab(tabId, windowState) else {
                return false
            }
            return tab.requiresPrimaryWebView
        }
    }

    func visibleTabIDSet(
        in windowId: UUID,
        runtime: VisibleWebViewPreparationRuntime?
    ) -> Set<UUID> {
        guard let runtime,
              let windowState = runtime.windowState(windowId)
        else {
            return []
        }
        return Set(
            visibleTabIDs(
                for: windowState,
                runtime: runtime
            )
        )
    }

    func preferredPrimaryWebViewCandidate(
        for tabId: UUID,
        runtime: VisibleWebViewPreparationRuntime?,
        webViewRegistry: WindowWebViewRegistry,
    ) -> (owner: TrackedWebViewOwner, webView: WKWebView)? {
        let candidates = webViewRegistry.trackedWebViews(for: tabId)
        guard candidates.isEmpty == false else { return nil }

        return candidates.min { lhs, rhs in
            candidatePriority(
                for: lhs.0,
                runtime: runtime,
                webViewRegistry: webViewRegistry
            )
                < candidatePriority(
                    for: rhs.0,
                    runtime: runtime,
                    webViewRegistry: webViewRegistry
                )
        }
    }

    private func candidatePriority(
        for owner: TrackedWebViewOwner,
        runtime: VisibleWebViewPreparationRuntime?,
        webViewRegistry: WindowWebViewRegistry
    ) -> (Int, Int, String) {
        let visibleRank: Int
        if let runtime,
           let windowState = runtime.windowState(owner.windowID),
           visibleTabIDs(
               for: windowState,
               runtime: runtime
           ).contains(owner.tabID) {
            visibleRank = 0
        } else {
            visibleRank = 1
        }

        let mruRank = webViewRegistry.recentVisibilityRank(for: owner)
        return (visibleRank, mruRank, owner.windowID.uuidString)
    }
}
