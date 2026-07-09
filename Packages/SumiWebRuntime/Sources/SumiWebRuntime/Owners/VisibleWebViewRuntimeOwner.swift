//
//  VisibleWebViewRuntimeOwner.swift
//  SumiWebRuntime
//
//  Owns visible WebView preparation and compositor container bookkeeping.
//

import AppKit
import Foundation
import WebKit

@MainActor
public final class VisibleWebViewRuntimeOwner: WebRuntimeVisiblePreparationControlling {
    private let compositorHandoffState = WebViewCompositorHandoffState()
    private var scheduledPrepareWindowIds: Set<UUID> = []

    public init() {}

    // MARK: - Compositor Containers

    public func setCompositorContainerView(_ view: NSView?, for windowId: UUID) {
        compositorHandoffState.setContainerView(view, for: windowId)
    }

    public func setImmediateVisualHandoffHandler(
        _ handler: (@MainActor () -> Bool)?,
        for windowId: UUID
    ) {
        compositorHandoffState.setImmediateVisualHandoffHandler(handler, for: windowId)
    }

    @discardableResult
    public func performImmediateVisualHandoffIfPossible(in windowId: UUID) -> Bool {
        compositorHandoffState.performImmediateVisualHandoffIfPossible(in: windowId)
    }

    public func compositorContainerView(for windowId: UUID) -> NSView? {
        compositorHandoffState.containerView(for: windowId)
    }

    public func removeCompositorContainerView(
        for windowId: UUID,
        webViewRegistry: WindowWebViewRegistry,
        pruneInvalidDeferredCommands: (String) -> Void
    ) {
        compositorHandoffState.removeContainerView(for: windowId)
        scheduledPrepareWindowIds.remove(windowId)
        webViewRegistry.removeVisibilityHistory(for: windowId)
        pruneInvalidDeferredCommands("removeCompositorContainerView")
    }

    public func compositorContainers() -> [(UUID, NSView)] {
        compositorHandoffState.containerViewsByWindow()
    }

    public func resetWindowRegistrations() {
        compositorHandoffState.removeAllWindowRegistrations()
        scheduledPrepareWindowIds.removeAll()
    }

    public func cancelScheduledPreparation(for windowId: UUID) {
        scheduledPrepareWindowIds.remove(windowId)
    }

    // MARK: - Promoted Host Handoff

    public func registerPromotedHost(
        _ host: any WebRuntimePromotedHost,
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

    public func takePromotedHost(
        for tabId: UUID,
        in windowId: UUID,
        expectedWebView: WKWebView
    ) -> (any WebRuntimePromotedHost)? {
        compositorHandoffState.takePromotedHost(
            for: tabId,
            in: windowId,
            expectedWebView: expectedWebView
        )
    }

    public func completePromotedHostAttachment(for tabId: UUID, in windowId: UUID) {
        compositorHandoffState.completePromotedHostAttachment(for: tabId, in: windowId)
    }

    // MARK: - Visible WebView Preparation

    @discardableResult
    public func prepareVisibleWebViews(
        for windowHandle: any WebRuntimeWindowHandle,
        runtime: VisibleWebViewPreparationRuntime,
        webViewRegistry: WindowWebViewRegistry,
        existingWebView: (UUID, UUID) -> WKWebView?,
        createWebView: (any WebRuntimeTabHandle, UUID) -> WKWebView?
    ) -> Bool {
        let signpostState = SumiWebRuntimeDiagnostics.beginInterval(
            "WebViewCoordinator.prepareVisibleWebViews"
        )
        defer {
            SumiWebRuntimeDiagnostics.endInterval(
                "WebViewCoordinator.prepareVisibleWebViews",
                signpostState
            )
        }

        let visibleTabIDs = visibleTabIDs(
            for: windowHandle,
            runtime: runtime
        )
        webViewRegistry.noteVisibleTabs(visibleTabIDs, in: windowHandle.id)

        var didCreateWebView = false
        for tabId in visibleTabIDs {
            guard let tab = runtime.resolveTab(tabId, windowHandle) else {
                continue
            }
            guard runtime.canMaterializeWebViewDuringStartup(tab) else {
                continue
            }

            runtime.markTabAccessed(tab.id)
            if existingWebView(tab.id, windowHandle.id) == nil,
               createWebView(tab, windowHandle.id) != nil {
                didCreateWebView = true
            }
        }

        runtime.evictHiddenWebViews(
            windowHandle.id,
            Set(visibleTabIDs)
        )
        runtime.scheduleTabSuspensionReconcile("visible-webviews-prepared")
        runtime.scheduleBackgroundMediaReconcile("visible-webviews-prepared")

        return didCreateWebView
    }

    public func schedulePrepareVisibleWebViews(
        for windowHandle: any WebRuntimeWindowHandle,
        runtime: VisibleWebViewPreparationRuntime,
        prepareVisibleWebViews: @escaping @MainActor (any WebRuntimeWindowHandle) -> Bool
    ) {
        let windowId = windowHandle.id
        guard scheduledPrepareWindowIds.insert(windowId).inserted else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scheduledPrepareWindowIds.remove(windowId)

            guard let windowHandle = runtime.windowState(windowId) else { return }
            let didCreateWebView = prepareVisibleWebViews(windowHandle)
            if didCreateWebView {
                runtime.refreshCompositor(windowId)
            }
        }
    }

    public func visibleTabIDs(
        for windowHandle: any WebRuntimeWindowHandle,
        runtime: VisibleWebViewPreparationRuntime
    ) -> [UUID] {
        VisibleTabPreparationPlan.visibleTabIDs(
            currentTabId: runtime.currentTabId(windowHandle),
            splitTabIds: runtime.splitVisibleTabIds(windowHandle.id)
        ).filter { tabId in
            guard let tab = runtime.resolveTab(tabId, windowHandle) else {
                return false
            }
            return tab.requiresPrimaryWebView
        }
    }

    public func visibleTabIDSet(
        in windowId: UUID,
        runtime: VisibleWebViewPreparationRuntime?
    ) -> Set<UUID> {
        guard let runtime,
              let windowHandle = runtime.windowState(windowId)
        else {
            return []
        }
        return Set(
            visibleTabIDs(
                for: windowHandle,
                runtime: runtime
            )
        )
    }

    public func preferredPrimaryWebViewCandidate(
        for tabId: UUID,
        runtime: VisibleWebViewPreparationRuntime?,
        webViewRegistry: WindowWebViewRegistry
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
           let windowHandle = runtime.windowState(owner.windowID),
           visibleTabIDs(
               for: windowHandle,
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
