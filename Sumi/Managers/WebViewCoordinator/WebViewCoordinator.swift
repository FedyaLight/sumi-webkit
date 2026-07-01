//
//  WebViewCoordinator.swift
//  Sumi
//
//  Manages WebView instances across multiple windows
//

import AppKit
import CoreGraphics
import Foundation
import Observation
import QuartzCore
import WebKit

enum CompositorPaneDestination: String, CaseIterable {
    case single
    case left
    case right

    var viewIdentifier: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("SumiCompositorPane.\(rawValue)")
    }
}

@MainActor
@Observable
class WebViewCoordinator: SumiDestructiveBrowsingDataCleanupPreparing {
    @ObservationIgnored
    private let webViewRegistry = WindowWebViewRegistry()

    @ObservationIgnored
    private let visibleWebViewRuntimeOwner = VisibleWebViewRuntimeOwner()

    @ObservationIgnored
    private let crossWindowSyncOwner = WebViewCrossWindowSyncOwner()

    @ObservationIgnored
    private let webViewAssignmentRebuildOwner = WebViewAssignmentRebuildOwner()

    @ObservationIgnored
    private let webViewTrackingLifecycleOwner = WebViewTrackingLifecycleOwner()

    @ObservationIgnored
    private let trackedCleanupExecutionOwner = WebViewTrackedCleanupExecutionOwner()

    @ObservationIgnored
    private let tabScopedCleanupValidationOwner = WebViewTabScopedCleanupValidationOwner()

    @ObservationIgnored
    private let cleanupScopeOwner = WebViewCleanupScopeOwner()

    @ObservationIgnored
    private let hiddenCloneEvictionOwner = WebViewHiddenCloneEvictionOwner()

    @ObservationIgnored
    private var visibleRuntimeContext: WebViewCoordinatorVisibleRuntimeContext?

    @ObservationIgnored
    private var browserRuntimeContext: WebViewCoordinatorBrowserRuntimeContext?

    @ObservationIgnored
    private let mediaProtectionOwner = WebViewMediaProtectionOwner()

    @ObservationIgnored
    private let deferredProtectedCommandExecutionOwner = WebViewDeferredProtectedCommandExecutionOwner()

    @ObservationIgnored
    private let destructiveCleanupPreparationOwner = WebViewDestructiveCleanupPreparationOwner()

    @ObservationIgnored
    private let destructiveCleanupPreparationScanOwner = WebViewDestructiveCleanupPreparationScanOwner()

    // MARK: - Compositor Container Management

    func setCompositorContainerView(_ view: NSView?, for windowId: UUID) {
        visibleWebViewRuntimeOwner.setCompositorContainerView(view, for: windowId)
    }

    func setImmediateVisualHandoffHandler(
        _ handler: (@MainActor () -> Bool)?,
        for windowId: UUID
    ) {
        visibleWebViewRuntimeOwner.setImmediateVisualHandoffHandler(handler, for: windowId)
    }

    @discardableResult
    func performImmediateVisualHandoffIfPossible(in windowId: UUID) -> Bool {
        visibleWebViewRuntimeOwner.performImmediateVisualHandoffIfPossible(in: windowId)
    }

    func compositorContainerView(for windowId: UUID) -> NSView? {
        visibleWebViewRuntimeOwner.compositorContainerView(for: windowId)
    }

    func removeCompositorContainerView(for windowId: UUID) {
        visibleWebViewRuntimeOwner.removeCompositorContainerView(
            for: windowId,
            webViewRegistry: webViewRegistry,
            pruneInvalidDeferredCommands: { [self] reason in
                pruneInvalidDeferredProtectedCommands(reason: reason)
            }
        )
    }

    func compositorContainers() -> [(UUID, NSView)] {
        visibleWebViewRuntimeOwner.compositorContainers()
    }

    // MARK: - WebView Pool Management

    func getWebView(for tabId: UUID, in windowId: UUID) -> WKWebView? {
        webViewRegistry.webView(for: tabId, in: windowId)
    }

    func getAllWebViews(for tabId: UUID) -> [WKWebView] {
        webViewRegistry.webViews(for: tabId)
    }

    func trackedLiveWebViews(for tab: Tab) -> [WKWebView] {
        uniqueWebViews(Array(webViewRegistry.windowWebViews(for: tab.id).values))
    }

    private func allKnownWebViews(for tab: Tab) -> [WKWebView] {
        var seen = Set<ObjectIdentifier>()
        var result: [WKWebView] = []
        func appendUnique(_ webView: WKWebView?) {
            guard let webView else { return }
            let id = ObjectIdentifier(webView)
            if seen.insert(id).inserted {
                result.append(webView)
            }
        }
        let windowWebViews = webViewRegistry.windowWebViews(for: tab.id)
        if windowWebViews.isEmpty == false {
            result.reserveCapacity(windowWebViews.count + 2)
            for webView in windowWebViews.values {
                appendUnique(webView)
            }
        } else {
            result.reserveCapacity(2)
        }
        appendUnique(tab.assignedWebView)
        appendUnique(tab.existingWebView)
        return result
    }

    func isPreparingForDestructiveDataCleanupNavigation(on webView: WKWebView) -> Bool {
        destructiveCleanupPreparationOwner.isSuppressingNavigation(on: webView)
    }

    func finishDestructiveDataCleanupNavigation(on webView: WKWebView) {
        destructiveCleanupPreparationOwner.finishNavigationSuppression(on: webView)
    }

    func prepareForDestructiveDataCleanup(profileIDs: Set<UUID>) async {
        guard !profileIDs.isEmpty else { return }
        let runtimeContext = requireBrowserRuntimeContext()

        let preparationResult = destructiveCleanupPreparationScanOwner.prepare(
            pinnedTabs: runtimeContext.pinnedTabs(),
            tabs: runtimeContext.regularTabs(),
            profileIDs: profileIDs,
            liveWebViews: { [self] tab in
                allKnownWebViews(for: tab)
            },
            isWebViewProtectedFromCompositorMutation: { [self] webView in
                isWebViewProtectedFromCompositorMutation(webView)
            },
            cleanupPreparationOwner: destructiveCleanupPreparationOwner
        )

        RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
            "Prepared \(preparationResult.preparedWebViewCount) live WebView(s) for destructive data cleanup across \(profileIDs.count) profile(s); skipped \(preparationResult.skippedProtectedWebViewCount) protected WebView(s)."
        }
    }

    func windowIDs(for tabId: UUID) -> [UUID] {
        webViewRegistry.windowIDs(for: tabId)
    }

    func setWebView(_ webView: WKWebView, for tabId: UUID, in windowId: UUID) {
        registerTrackedWebView(webView, for: tabId, in: windowId)
    }

    func registerPromotedHost(
        _ host: SumiWebViewContainerView,
        for tabId: UUID,
        in windowId: UUID,
        attachmentCompletion: (@MainActor () -> Void)? = nil
    ) {
        visibleWebViewRuntimeOwner.registerPromotedHost(
            host,
            for: tabId,
            in: windowId,
            attachmentCompletion: attachmentCompletion
        )
    }

    func takePromotedHost(for tabId: UUID, in windowId: UUID, expectedWebView: WKWebView) -> SumiWebViewContainerView? {
        visibleWebViewRuntimeOwner.takePromotedHost(
            for: tabId,
            in: windowId,
            expectedWebView: expectedWebView
        )
    }

    func completePromotedHostAttachment(for tabId: UUID, in windowId: UUID) {
        visibleWebViewRuntimeOwner.completePromotedHostAttachment(for: tabId, in: windowId)
    }

    @discardableResult
    func prepareVisibleWebViews(
        for windowState: BrowserWindowState
    ) -> Bool {
        let runtime = requireVisibleWebViewPreparationRuntime()
        return prepareVisibleWebViews(
            for: windowState,
            runtime: runtime
        )
    }

    @discardableResult
    func prepareVisibleWebViews(
        for windowState: BrowserWindowState,
        runtime: VisibleWebViewPreparationRuntime
    ) -> Bool {
        visibleWebViewRuntimeOwner.prepareVisibleWebViews(
            for: windowState,
            runtime: runtime,
            webViewRegistry: webViewRegistry,
            existingWebView: { [self] tabId, windowId in
                getWebView(for: tabId, in: windowId)
            },
            createWebView: { [self] tab, windowId in
                getOrCreateWebView(for: tab, in: windowId)
            }
        )
    }

    func schedulePrepareVisibleWebViews(
        for windowState: BrowserWindowState
    ) {
        let runtime = requireVisibleWebViewPreparationRuntime()
        visibleWebViewRuntimeOwner.schedulePrepareVisibleWebViews(
            for: windowState,
            runtime: runtime,
            prepareVisibleWebViews: { [weak self] windowState in
                guard let self else { return false }
                return self.prepareVisibleWebViews(
                    for: windowState,
                    runtime: runtime
                )
            }
        )
    }

    func attachVisiblePreparationRuntimeContext(_ context: WebViewCoordinatorVisibleRuntimeContext) {
        visibleRuntimeContext = context
    }

    func detachVisiblePreparationRuntimeContext() {
        visibleRuntimeContext = nil
    }

    func attachBrowserRuntimeContext(_ context: WebViewCoordinatorBrowserRuntimeContext) {
        browserRuntimeContext = context
    }

    func detachBrowserRuntimeContext() {
        browserRuntimeContext = nil
    }

    // MARK: - Window Cleanup

    func cleanupWindow(_ windowId: UUID, tabManager: TabManager) {
        let signpostState = PerformanceTrace.beginInterval("WebViewCoordinator.cleanupWindow")
        defer {
            PerformanceTrace.endInterval("WebViewCoordinator.cleanupWindow", signpostState)
        }

        visibleWebViewRuntimeOwner.cancelScheduledPreparation(for: windowId)
        cleanupScopeOwner.cleanupWindow(
            windowId,
            entries: webViewRegistry.trackedWebViews(in: windowId),
            runtime: cleanupScopeRuntime(tabManager: tabManager)
        )
        removeCompositorContainerView(for: windowId)
    }

    func cleanupAllWebViews(tabManager: TabManager) {
        cleanupScopeOwner.cleanupAllWebViews(
            entries: webViewRegistry.trackedWebViews(),
            totalWebViewCount: webViewRegistry.totalTrackedWebViewCount,
            runtime: cleanupScopeRuntime(tabManager: tabManager)
        )

        if webViewRegistry.isEmpty {
            webViewRegistry.removeAll()
            visibleWebViewRuntimeOwner.resetWindowRegistrations()
            mediaProtectionOwner.removeVisualHandoffFullscreenAndNowPlayingState()
        }

        RuntimeDiagnostics.debug("Completed full WebView cleanup.", category: "WebViewCoordinator")

        pruneStaleWebViewBookkeeping(reason: "cleanupAllWebViews")
    }

    // MARK: - History Swipe Protection

    func beginHistorySwipeProtection(
        tabId: UUID,
        webView: WKWebView,
        originURL: URL?,
        originHistoryItem: WKBackForwardListItem?
    ) {
        let windowId = windowId(containing: webView)
        let webViewID = mediaProtectionOwner.beginHistorySwipeProtection(
            on: webView,
            windowID: windowId,
            originURL: originURL,
            originHistoryItem: originHistoryItem
        )
        RuntimeDiagnostics.swipeTrace(
            "begin tab=\(tabId.uuidString.prefix(8)) window=\(windowId?.uuidString.prefix(8) ?? "nil") webView=\(webViewID) url=\((originURL ?? originHistoryItem?.url)?.absoluteString ?? "nil")"
        )
    }

    @discardableResult
    func finishHistorySwipeProtection(
        tabId: UUID,
        webView: WKWebView?,
        currentURL: URL?,
        currentHistoryItem: WKBackForwardListItem?
    ) -> Bool {
        guard let result = mediaProtectionOwner.finishHistorySwipeProtection(
            on: webView,
            currentURL: currentURL,
            currentHistoryItem: currentHistoryItem
        ) else { return false }
        RuntimeDiagnostics.swipeTrace(
            "finish tab=\(tabId.uuidString.prefix(8)) webView=\(result.webViewID) cancelled=\(result.wasCancelled) url=\((currentURL ?? currentHistoryItem?.url)?.absoluteString ?? "nil")"
        )
        flushDeferredProtectedCommands(for: result.webViewID)
        return result.wasCancelled
    }

    func hasActiveHistorySwipe(in windowId: UUID) -> Bool {
        mediaProtectionOwner.hasActiveHistorySwipe(in: windowId)
    }

    func hasActiveFullscreen(in windowId: UUID) -> Bool {
        mediaProtectionOwner.hasActiveFullscreen(in: windowId)
    }

    func closeActiveFullscreenMedia(in windowId: UUID) {
        mediaProtectionOwner.closeActiveFullscreenMedia(in: windowId) { [self] webViewID in
            resolveWebView(with: webViewID)
        }
    }

    func isWebViewProtectedFromCompositorMutation(_ webView: WKWebView) -> Bool {
        mediaProtectionOwner.isProtected(webView)
    }

    func beginVisualHandoffProtection(for webView: WKWebView) {
        mediaProtectionOwner.beginVisualHandoffProtection(for: webView)
    }

    func finishVisualHandoffProtection(for webView: WKWebView) {
        guard let webViewID = mediaProtectionOwner.finishVisualHandoffProtection(for: webView) else {
            return
        }
        flushDeferredProtectedCommands(for: webViewID)
    }

    func windowID(containing webView: WKWebView) -> UUID? {
        windowId(containing: webView)
    }

    @discardableResult
    func handleWebViewDidClose(_ webView: WKWebView) -> Bool {
        let webViewID = ObjectIdentifier(webView)
        mediaProtectionOwner.note(webView)
        finishDestructiveDataCleanupNavigation(on: webView)

        if enqueueDeferredProtectedCommand(
            .closeWebViewFromWebKit(webViewID: webViewID),
            for: webView,
            reason: "webViewDidClose"
        ) {
            mediaProtectionOwner.closeFullscreenMediaIfNeeded(on: webView)
            return true
        }

        if let owner = trackedOwner(containing: webView) {
            return closeTrackedWebViewFromWebKit(webView, owner: owner)
        }

        if let (tab, windowState) = untrackedTabContext(for: webView) {
            closeTabForWebKitCloseRequest(tab, windowState: windowState)
            return true
        }

        SumiAuxiliaryWebViewShutdown.perform(on: webView)
        return true
    }

    private func flushDeferredProtectedCommands(for webViewID: ObjectIdentifier) {
        guard mediaProtectionOwner.hasDeferredProtectedCommands(for: webViewID) else { return }
        deferredProtectedCommandExecutionOwner.flushCommandsIfUnprotected(
            for: webViewID,
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: deferredProtectedCommandRuntime()
        )
    }

    // MARK: - Smart WebView Assignment (Memory Optimization)

    /// Gets or creates a WebView for the specified tab and window.
    /// Implements smart assignment to prevent duplicate WebViews:
    /// - If no window is displaying this tab yet, creates a "primary" WebView
    /// - If another window is already displaying this tab, creates a "clone" WebView
    /// - Returns existing WebView if this window already has one
    func getOrCreateWebView(for tab: Tab, in windowId: UUID) -> WKWebView? {
        webViewAssignmentRebuildOwner.getOrCreateWebView(
            for: tab,
            in: windowId,
            runtime: assignmentRebuildRuntime()
        )
    }

    func removeWebViewFromContainers(_ webView: WKWebView) {
        if enqueueDeferredProtectedCommand(
            .removeWebViewFromContainers(webViewID: ObjectIdentifier(webView)),
            for: webView,
            reason: "removeWebViewFromContainers"
        ) {
            return
        }

        for (_, container) in compositorContainers() {
            removeMatchingWebView(webView, from: container)
        }
    }

    /// `WKWebView` instances live under pane views, not only as direct children of the compositor container.
    private func removeMatchingWebView(_ webView: WKWebView, from root: NSView) {
        for subview in Array(root.subviews) {
            if let host = subview as? SumiWebViewContainerView,
               host.webView === webView {
                host.removeFromSuperview()
            } else if subview === webView {
                subview.removeFromSuperview()
            } else {
                removeMatchingWebView(webView, from: subview)
            }
        }
    }

    private func windowId(containing webView: WKWebView) -> UUID? {
        guard let owner = trackedOwner(containing: webView) else { return nil }
        return owner.windowID
    }

    @discardableResult
    func removeAllWebViews(
        for tab: Tab,
        closeActiveFullscreenMedia: Bool = false
    ) -> Bool {
        let currentEntries = webViewRegistry.windowWebViews(for: tab.id)
        let protectedCandidateWebViews = uniqueWebViews(
            Array(currentEntries.values)
                + [tab.assignedWebView, tab.existingWebView].compactMap { $0 }
        )
        if protectedCandidateWebViews.contains(where: isWebViewProtectedFromCompositorMutation) {
            let protectedTrackedIDs = Set(
                currentEntries.values
                    .filter { isWebViewProtectedFromCompositorMutation($0) }
                    .map(ObjectIdentifier.init)
            )
            var closedMediaWebViewIDs: Set<ObjectIdentifier> = []

            func closeFullscreenMediaOnce(on webView: WKWebView) {
                guard closeActiveFullscreenMedia else { return }
                guard closedMediaWebViewIDs.insert(ObjectIdentifier(webView)).inserted else { return }
                mediaProtectionOwner.closeFullscreenMediaIfNeeded(on: webView)
            }

            for (windowId, protectedWebView) in currentEntries where isWebViewProtectedFromCompositorMutation(protectedWebView) {
                closeFullscreenMediaOnce(on: protectedWebView)
                _ = enqueueDeferredProtectedCommand(
                    .removeTrackedWebView(
                        webViewID: ObjectIdentifier(protectedWebView),
                        tabID: tab.id,
                        windowID: windowId
                    ),
                    for: protectedWebView,
                    reason: "removeAllWebViews"
                )
            }
            for protectedWebView in protectedCandidateWebViews where isWebViewProtectedFromCompositorMutation(protectedWebView) {
                let protectedWebViewID = ObjectIdentifier(protectedWebView)
                closeFullscreenMediaOnce(on: protectedWebView)

                guard !protectedTrackedIDs.contains(protectedWebViewID) else { continue }
                _ = enqueueDeferredProtectedCommand(
                    .cleanupTabWebView(
                        webViewID: protectedWebViewID,
                        tabID: tab.id
                    ),
                    for: protectedWebView,
                    reason: "removeAllWebViews.untracked"
                )
            }
            return false
        }

        let trackedEntries = currentEntries.map { windowId, webView in
            (TrackedWebViewOwner(tabID: tab.id, windowID: windowId), webView)
        }
        guard trackedEntries.isEmpty == false else { return false }

        for (owner, webView) in trackedEntries {
            cleanupUnprotectedTrackedWebView(
                webView,
                owner: owner,
                tab: tab
            )
        }
        refreshPrimaryTrackedWebView(for: tab)
        return true
    }

    @discardableResult
    func suspendWebViews(for tab: Tab, reason: String) -> Bool {
        let liveWebViews = allKnownWebViews(for: tab)
        guard !liveWebViews.isEmpty else { return false }
        guard !liveWebViews.contains(where: isWebViewProtectedFromCompositorMutation) else {
            RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
                "Skipping suspension cleanup for protected tab=\(tab.id.uuidString.prefix(8)) reason=\(reason)."
            }
            return false
        }

        let trackedEntries = webViewRegistry.trackedWebViews(for: tab.id)
        var cleanedIdentifiers: Set<ObjectIdentifier> = []

        func cleanup(_ webView: WKWebView) {
            let identifier = ObjectIdentifier(webView)
            guard cleanedIdentifiers.insert(identifier).inserted else { return }
            tab.cleanupCloneWebView(webView)
        }

        for (owner, webView) in trackedEntries {
            removeWebViewFromContainers(webView)
            _ = unregisterTrackedWebViewSlot(
                owner: owner,
                expectedWebView: webView
            )
            cleanup(webView)
        }

        for webView in liveWebViews {
            cleanup(webView)
        }

        tab.cancelPendingMainFrameNavigation()
        tab.clearAllWebViewOwnership()

        RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
            "Suspension released \(cleanedIdentifiers.count) WebView(s) for tab=\(tab.id.uuidString.prefix(8)) reason=\(reason)."
        }

        return !cleanedIdentifiers.isEmpty
    }

    // MARK: - WebView Creation & Cross-Window Sync

    @available(macOS 15.5, *)
    @discardableResult
    func rebuildLiveWebViews(
        for tab: Tab,
        preferredPrimaryWindowId: UUID? = nil,
        load url: URL? = nil
    ) -> Bool {
        webViewAssignmentRebuildOwner.rebuildLiveWebViews(
            for: tab,
            preferredPrimaryWindowId: preferredPrimaryWindowId,
            load: url,
            runtime: assignmentRebuildRuntime()
        )
    }

    @discardableResult
    func deferProtectedWebViewCleanup(
        _ webView: WKWebView,
        tabID: UUID,
        reason: String
    ) -> Bool {
        enqueueDeferredProtectedCommand(
            .cleanupTabWebView(
                webViewID: ObjectIdentifier(webView),
                tabID: tabID
            ),
            for: webView,
            reason: reason
        )
    }

    // MARK: - Private Helpers

    @discardableResult
    private func enqueueDeferredProtectedCommand(
        _ command: DeferredWebViewCommand,
        for webView: WKWebView,
        reason: String
    ) -> Bool {
        mediaProtectionOwner.note(webView)
        guard mediaProtectionOwner.isProtected(webView) else {
            return false
        }

        return deferredProtectedCommandExecutionOwner.enqueue(
            command,
            for: webView,
            reason: reason,
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: deferredProtectedCommandRuntime()
        )
    }

    private func installMediaProtectionObservationsIfNeeded(on webView: WKWebView) {
        mediaProtectionOwner.installFullscreenStateObservationIfNeeded(
            on: webView,
            trackedOwner: { [weak self] webView in
                self?.trackedOwner(containing: webView)
            },
            fallbackWindowID: { [weak self] webView in
                self?.windowId(containing: webView)
            },
            flushDeferredProtectedCommands: { [weak self] webViewID in
                self?.flushDeferredProtectedCommands(for: webViewID)
            },
            refreshCompositor: { [weak self] windowID in
                guard let self else { return }
                let runtimeContext = requireBrowserRuntimeContext()
                guard let windowState = runtimeContext.window(windowID)
                else {
                    return
                }
                runtimeContext.refreshCompositor(windowState)
            }
        )

        mediaProtectionOwner.installNowPlayingSessionObservationIfNeeded(
            on: webView,
            trackedOwner: { [weak self] webView in
                self?.trackedOwner(containing: webView)
            },
            fallbackWindowID: { [weak self] webView in
                self?.windowId(containing: webView)
            }
        )
    }

    private func uninstallMediaProtectionObservationsIfUntracked(_ webView: WKWebView) {
        mediaProtectionOwner.uninstallObservationsIfUntracked(
            webView,
            isTracked: webViewRegistry.isIndexed(webView)
        )
    }

    private func resolveWebView(
        with identifier: ObjectIdentifier
    ) -> WKWebView? {
        if let webView = webViewRegistry.trackedWebView(with: identifier) {
            mediaProtectionOwner.note(webView)
            return webView
        }
        return mediaProtectionOwner.resolveWeakWebView(with: identifier)
    }

    private func resolvedTab(with tabID: UUID) -> Tab? {
        let runtimeContext = requireBrowserRuntimeContext()
        return resolvedTab(with: tabID, runtimeContext: runtimeContext)
    }

    private func resolvedTab(
        with tabID: UUID,
        runtimeContext: WebViewCoordinatorBrowserRuntimeContext
    ) -> Tab? {
        if let tab = runtimeContext.tab(tabID) {
            return tab
        }
        for windowState in runtimeContext.allWindows() {
            if let tab = windowState.ephemeralTabs.first(where: { $0.id == tabID }) {
                return tab
            }
        }
        return nil
    }

    private func pruneStaleWebViewBookkeeping(reason: String) {
        finishDestructiveCleanupSuppression(
            for: mediaProtectionOwner.pruneStaleBookkeeping(reason: reason)
        )
    }

    private func pruneInvalidDeferredProtectedCommands(reason: String) {
        finishDestructiveCleanupSuppression(
            for: mediaProtectionOwner.pruneStaleBookkeeping(reason: "\(reason).staleBookkeeping")
        )
        guard mediaProtectionOwner.hasDeferredProtectedCommands else { return }
        deferredProtectedCommandExecutionOwner.pruneInvalidCommands(
            reason: reason,
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: deferredProtectedCommandRuntime()
        )
    }

    private func deferredProtectedCommandRuntime() -> WebViewDeferredProtectedCommandExecutionOwner.Runtime {
        let runtimeContext = requireBrowserRuntimeContext()
        let validationContext = WebViewDeferredProtectedCommandExecutionOwner.ValidationContext(
            resolveWebView: { [self] webViewID in
                resolveWebView(with: webViewID)
            },
            resolveTrackedOwner: { [self] webViewID in
                webViewRegistry.trackedOwner(with: webViewID)
            },
            canCleanUpTabWebView: { [self] webViewID, tabID in
                tabScopedCleanupValidationOwner.canCleanUpTabScopedWebView(
                    with: webViewID,
                    tabID: tabID,
                    context: tabScopedCleanupValidationContext(runtimeContext)
                )
            },
            resolveTab: { [self] tabID in
                resolvedTab(with: tabID, runtimeContext: runtimeContext)
            },
            hasTabManager: {
                true
            },
            hasCleanupWindowTarget: { [self] windowID in
                webViewRegistry.trackedWebViews(in: windowID).isEmpty == false
                    || compositorContainerView(for: windowID) != nil
            },
            hasTrackedWebViews: { [self] in
                webViewRegistry.isEmpty == false
            },
            hasWindow: { windowID in
                runtimeContext.window(windowID) != nil
            }
        )
        return WebViewDeferredProtectedCommandExecutionOwner.Runtime(
            validationContext: validationContext,
            executeCommand: { [self] command in
                performDeferredProtectedCommand(command)
            },
            finishCleanupSuppression: { [self] webViewIDs in
                finishDestructiveCleanupSuppression(for: webViewIDs)
            }
        )
    }

    private func finishDestructiveCleanupSuppression(for webViewIDs: [ObjectIdentifier]) {
        guard webViewIDs.isEmpty == false else { return }
        for webViewID in webViewIDs {
            destructiveCleanupPreparationOwner.finishNavigationSuppression(webViewID: webViewID)
        }
    }

    private func cleanupScopeRuntime(tabManager: TabManager) -> WebViewCleanupScopeOwner.Runtime {
        let runtimeContext = resolvedBrowserRuntimeContext()
        return WebViewCleanupScopeOwner.Runtime(
            tabForID: { tabID in
                runtimeContext?.tab(tabID) ?? tabManager.tab(for: tabID)
            },
            isWebViewProtectedFromCompositorMutation: { [self] webView in
                isWebViewProtectedFromCompositorMutation(webView)
            },
            enqueueDeferredProtectedCommand: { [self] command, webView, reason in
                enqueueDeferredProtectedCommand(command, for: webView, reason: reason)
            },
            cleanupUnprotectedTrackedWebView: { [self] webView, owner, tab in
                cleanupUnprotectedTrackedWebView(
                    webView,
                    owner: owner,
                    tab: tab
                )
            },
            refreshPrimaryTrackedWebView: { [self] tab in
                refreshPrimaryTrackedWebView(for: tab)
            }
        )
    }

    private func hiddenCloneEvictionRuntime(
        globallyVisibleTabIDs: @escaping @MainActor () -> Set<UUID>,
        runtimeContext: WebViewCoordinatorBrowserRuntimeContext? = nil
    ) -> WebViewHiddenCloneEvictionOwner.Runtime {
        WebViewHiddenCloneEvictionOwner.Runtime(
            tabForID: { [self] tabID in
                if let runtimeContext {
                    return resolvedTab(with: tabID, runtimeContext: runtimeContext)
                }
                return resolvedTab(with: tabID)
            },
            liveWebViews: { [self] tab in
                trackedLiveWebViews(for: tab)
            },
            globallyVisibleTabIDs: globallyVisibleTabIDs,
            isWebViewProtectedFromCompositorMutation: { [self] webView in
                isWebViewProtectedFromCompositorMutation(webView)
            },
            enqueueDeferredProtectedCommand: { [self] command, webView, reason in
                enqueueDeferredProtectedCommand(command, for: webView, reason: reason)
            },
            cleanupUnprotectedTrackedWebView: { [self] webView, owner, tab in
                cleanupUnprotectedTrackedWebView(
                    webView,
                    owner: owner,
                    tab: tab
                )
            },
            refreshPrimaryTrackedWebView: { [self] tab in
                refreshPrimaryTrackedWebView(for: tab)
            }
        )
    }

    @discardableResult
    private func performDeferredProtectedCommand(_ command: DeferredWebViewCommand) -> Bool {
        switch command {
        case .removeWebViewFromContainers(let webViewID):
            guard let webView = resolveWebView(with: webViewID) else {
                return false
            }
            removeWebViewFromContainers(webView)
        case .removeAllWebViews(let tabID):
            guard let tab = resolvedTab(with: tabID) else {
                return false
            }
            _ = removeAllWebViews(for: tab)
        case .removeTrackedWebView(let webViewID, let tabID, let windowID):
            guard let webView = resolveWebView(with: webViewID) else {
                return false
            }
            cleanupTrackedWebView(
                webView,
                owner: TrackedWebViewOwner(tabID: tabID, windowID: windowID)
            )
        case .closeWebViewFromWebKit(let webViewID):
            guard let webView = resolveWebView(with: webViewID) else {
                return false
            }
            handleWebViewDidClose(webView)
        case .cleanupWindow(let windowID):
            cleanupWindow(windowID, tabManager: requireBrowserRuntimeContext().tabManager())
        case .cleanupAllWebViews:
            cleanupAllWebViews(tabManager: requireBrowserRuntimeContext().tabManager())
        case .rebuildLiveWebViews(let tabID, let preferredPrimaryWindowID):
            guard let tab = resolvedTab(with: tabID) else {
                return false
            }
            rebuildLiveWebViews(
                for: tab,
                preferredPrimaryWindowId: preferredPrimaryWindowID
            )
        case .evictHiddenWebViews(let windowID):
            let runtimeContext = requireBrowserRuntimeContext()
            guard runtimeContext.window(windowID) != nil
            else {
                return false
            }
            evictHiddenWebViewsIfNeeded(
                in: windowID,
                visibleTabIDs: visibleTabIDSet(in: windowID)
            )
        case .cleanupTabWebView(let webViewID, let tabID):
            guard let webView = resolveWebView(with: webViewID) else {
                return false
            }
            if let tab = resolvedTab(with: tabID) {
                tab.cleanupCloneWebView(webView)
            } else {
                performFallbackWebViewCleanup(
                    webView,
                    tabId: tabID
                )
            }
        case .performFallbackWebViewCleanup(let webViewID, let tabID):
            guard let webView = resolveWebView(with: webViewID) else {
                return false
            }
            performFallbackWebViewCleanup(
                webView,
                tabId: tabID
            )
        }

        return true
    }

    private func cleanupTrackedWebView(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner
    ) {
        let tab = resolvedTab(with: owner.tabID)
        cleanupUnprotectedTrackedWebView(
            webView,
            owner: owner,
            tab: tab
        )
        if let tab {
            refreshPrimaryTrackedWebView(for: tab)
        }
    }

    private func cleanupUnprotectedTrackedWebView(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner,
        tab: Tab?
    ) {
        trackedCleanupExecutionOwner.cleanupUnprotectedTrackedWebView(
            webView,
            owner: owner,
            tab: tab,
            webViewRegistry: webViewRegistry,
            trackingLifecycleOwner: webViewTrackingLifecycleOwner,
            runtime: trackedCleanupExecutionRuntime()
        )
    }

    private func trackedCleanupExecutionRuntime() -> WebViewTrackedCleanupExecutionOwner.Runtime {
        WebViewTrackedCleanupExecutionOwner.Runtime(
            finishDestructiveCleanupSuppression: { [self] webView in
                finishDestructiveDataCleanupNavigation(on: webView)
            },
            removeFromContainers: { [self] webView in
                removeWebViewFromContainers(webView)
            },
            uninstallRuntimeObservationsIfUntracked: { [self] webView in
                uninstallMediaProtectionObservationsIfUntracked(webView)
            },
            pruneInvalidDeferredCommands: { [self] reason in
                pruneInvalidDeferredProtectedCommands(reason: reason)
            },
            fallbackCleanup: { [self] webView, tabID in
                performFallbackWebViewCleanup(
                    webView,
                    tabId: tabID
                )
            }
        )
    }

    @discardableResult
    private func closeTrackedWebViewFromWebKit(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner
    ) -> Bool {
        let runtimeContext = requireBrowserRuntimeContext()
        guard let tab = resolvedTab(with: owner.tabID, runtimeContext: runtimeContext) else {
            cleanupTrackedWebView(webView, owner: owner)
            return true
        }

        let windowState = runtimeContext.window(owner.windowID)
            ?? runtimeContext.windowContaining(tab)
        closeTabForWebKitCloseRequest(
            tab,
            windowState: windowState,
            runtimeContext: runtimeContext
        )
        return true
    }

    private func closeTabForWebKitCloseRequest(
        _ tab: Tab,
        windowState: BrowserWindowState?,
        runtimeContext: WebViewCoordinatorBrowserRuntimeContext? = nil
    ) {
        let runtimeContext = runtimeContext ?? requireBrowserRuntimeContext()

        if let windowState {
            runtimeContext.closeTab(tab, windowState)
            return
        }

        if let containingWindow = runtimeContext.windowContaining(tab) {
            runtimeContext.closeTab(tab, containingWindow)
            return
        }

        tab.performComprehensiveWebViewCleanup()
        runtimeContext.removeTab(tab.id)
    }

    private func untrackedTabContext(
        for webView: WKWebView
    ) -> (tab: Tab, windowState: BrowserWindowState?)? {
        let runtimeContext = requireBrowserRuntimeContext()

        func matches(_ tab: Tab) -> Bool {
            tab.existingWebView === webView || tab.assignedWebView === webView
        }

        for windowState in runtimeContext.allWindows() {
            if let tab = windowState.ephemeralTabs.first(where: matches) {
                return (tab, windowState)
            }
        }

        if let tab = runtimeContext.regularTabs().first(where: matches) {
            return (
                tab,
                runtimeContext.windowContaining(tab)
            )
        }

        return nil
    }

    private func tabScopedCleanupValidationContext(
        _ runtimeContext: WebViewCoordinatorBrowserRuntimeContext
    ) -> WebViewTabScopedCleanupValidationOwner.Context {
        WebViewTabScopedCleanupValidationOwner.Context(
            trackedOwner: { [self] webViewID in
                webViewRegistry.trackedOwner(with: webViewID)
            },
            resolveWebView: { [self] webViewID in
                resolveWebView(with: webViewID)
            },
            resolveTab: { [self] tabID in
                resolvedTab(with: tabID, runtimeContext: runtimeContext)
            },
            allTabs: {
                runtimeContext.regularTabs()
                    + runtimeContext.pinnedTabs()
                    + runtimeContext.allWindows().flatMap(\.ephemeralTabs)
            }
        )
    }

    private func visibleTabIDSet(in windowId: UUID) -> Set<UUID> {
        visibleWebViewRuntimeOwner.visibleTabIDSet(
            in: windowId,
            runtime: requireVisibleWebViewPreparationRuntime()
        )
    }

    private func resolvedBrowserRuntimeContext() -> WebViewCoordinatorBrowserRuntimeContext? {
        if let browserRuntimeContext {
            return browserRuntimeContext
        }
        return nil
    }

    private func visibleWebViewPreparationRuntime() -> VisibleWebViewPreparationRuntime? {
        if let visibleRuntimeContext {
            return visibleWebViewPreparationRuntime(context: visibleRuntimeContext)
        }
        return nil
    }

    private func requireBrowserRuntimeContext() -> WebViewCoordinatorBrowserRuntimeContext {
        guard let browserRuntimeContext else {
            preconditionFailure(
                "WebViewCoordinator browser runtime context is nil. Attach it via BrowserManager.webViewCoordinator before runtime-dependent WebView operations."
            )
        }
        return browserRuntimeContext
    }

    private func requireVisibleWebViewPreparationRuntime() -> VisibleWebViewPreparationRuntime {
        guard let visibleRuntimeContext else {
            preconditionFailure(
                "WebViewCoordinator visible runtime context is nil. Attach it via BrowserManager.webViewCoordinator before preparing visible WebViews."
            )
        }
        return visibleWebViewPreparationRuntime(context: visibleRuntimeContext)
    }

    private func visibleWebViewPreparationRuntime(
        context: WebViewCoordinatorVisibleRuntimeContext
    ) -> VisibleWebViewPreparationRuntime {
        VisibleWebViewPreparationRuntime(
            windowState: context.windowState,
            currentTabId: context.currentTabId,
            splitVisibleTabIds: context.splitVisibleTabIds,
            resolveTab: context.resolveTab,
            canMaterializeNormalTabWebViewDuringStartup: context.canMaterializeNormalTabWebViewDuringStartup,
            markTabAccessed: context.markTabAccessed,
            evictHiddenWebViews: { [weak self] windowId, visibleTabIDs in
                guard let self else { return }
                hiddenCloneEvictionOwner.evictHiddenWebViews(
                    in: windowId,
                    visibleTabIDs: visibleTabIDs,
                    entries: webViewRegistry.trackedWebViews(in: windowId),
                    runtime: hiddenCloneEvictionRuntime(
                        globallyVisibleTabIDs: context.globallyVisibleTabIDs
                    )
                )
            },
            scheduleTabSuspensionReconcile: context.scheduleTabSuspensionReconcile,
            scheduleBackgroundMediaReconcile: context.scheduleBackgroundMediaReconcile,
            refreshCompositor: context.refreshCompositor
        )
    }

    private func registerTrackedWebView(
        _ webView: WKWebView,
        for tabId: UUID,
        in windowId: UUID
    ) {
        let owner = TrackedWebViewOwner(tabID: tabId, windowID: windowId)
        mediaProtectionOwner.note(webView)
        webViewTrackingLifecycleOwner.registerTrackedWebView(
            webView,
            for: owner,
            in: webViewRegistry,
            removeFromContainers: { [self] webView in
                removeWebViewFromContainers(webView)
            },
            installRuntimeObservations: { [self] webView in
                installMediaProtectionObservationsIfNeeded(on: webView)
            },
            uninstallRuntimeObservationsIfUntracked: { [self] webView in
                uninstallMediaProtectionObservationsIfUntracked(webView)
            },
            pruneInvalidDeferredCommands: { [self] reason in
                pruneInvalidDeferredProtectedCommands(reason: reason)
            }
        )
    }

    @discardableResult
    private func unregisterTrackedWebViewSlot(
        owner: TrackedWebViewOwner,
        expectedWebView: WKWebView? = nil,
        removeFromSuperview: Bool = false,
        removeRecentVisibility: Bool = true
    ) -> WKWebView? {
        webViewTrackingLifecycleOwner.unregisterTrackedWebViewSlot(
            owner: owner,
            expectedWebView: expectedWebView,
            removeFromSuperview: removeFromSuperview,
            removeRecentVisibility: removeRecentVisibility,
            in: webViewRegistry,
            removeFromContainers: { [self] webView in
                removeWebViewFromContainers(webView)
            },
            uninstallRuntimeObservationsIfUntracked: { [self] webView in
                uninstallMediaProtectionObservationsIfUntracked(webView)
            },
            pruneInvalidDeferredCommands: { [self] reason in
                pruneInvalidDeferredProtectedCommands(reason: reason)
            }
        )
    }

    private func trackedOwner(containing webView: WKWebView) -> TrackedWebViewOwner? {
        webViewRegistry.trackedOwner(containing: webView)
    }

    private func uniqueWebViews(_ webViews: [WKWebView]) -> [WKWebView] {
        var seen: Set<ObjectIdentifier> = []
        var unique: [WKWebView] = []
        for webView in webViews {
            let identifier = ObjectIdentifier(webView)
            if seen.insert(identifier).inserted {
                unique.append(webView)
            }
        }
        return unique
    }

    private func refreshPrimaryTrackedWebView(for tab: Tab) {
        webViewAssignmentRebuildOwner.refreshPrimaryTrackedWebView(
            for: tab,
            runtime: assignmentRebuildRuntime()
        )
    }

    private func preferredPrimaryWebViewCandidate(
        for tabId: UUID
    ) -> (owner: TrackedWebViewOwner, webView: WKWebView)? {
        visibleWebViewRuntimeOwner.preferredPrimaryWebViewCandidate(
            for: tabId,
            runtime: requireVisibleWebViewPreparationRuntime(),
            webViewRegistry: webViewRegistry
        )
    }

    private func assignmentRebuildRuntime() -> WebViewAssignmentRebuildOwner.Runtime {
        let runtimeContext = requireBrowserRuntimeContext()
        return WebViewAssignmentRebuildOwner.Runtime(
            webViewRegistry: webViewRegistry,
            initialDocumentWarmupRuntime: initialDocumentWarmupRuntime(
                runtimeContext: runtimeContext
            ),
            registerTrackedWebView: { [self] webView, tabId, windowId in
                registerTrackedWebView(webView, for: tabId, in: windowId)
            },
            unregisterTrackedWebViewSlot: { [self] owner, expectedWebView in
                unregisterTrackedWebViewSlot(
                    owner: owner,
                    expectedWebView: expectedWebView
                )
            },
            removeFromContainers: { [self] webView in
                removeWebViewFromContainers(webView)
            },
            isWebViewProtectedFromCompositorMutation: { [self] webView in
                isWebViewProtectedFromCompositorMutation(webView)
            },
            deferProtectedRebuild: { [self] webView, tabID, preferredPrimaryWindowId in
                _ = enqueueDeferredProtectedCommand(
                    .rebuildLiveWebViews(
                        tabID: tabID,
                        preferredPrimaryWindowID: preferredPrimaryWindowId
                    ),
                    for: webView,
                    reason: "rebuildLiveWebViews"
                )
            },
            primaryCandidate: { [self] tabId in
                preferredPrimaryWebViewCandidate(for: tabId)
            },
            liveWindowIDs: {
                return Set(runtimeContext.allWindows().map(\.id))
            },
            refreshCompositor: { windowId in
                guard let windowState = runtimeContext.window(windowId) else {
                    return
                }
                runtimeContext.refreshCompositor(windowState)
            },
            notifyTabActivatedIfCurrent: { tab, windowId in
                guard let windowState = runtimeContext.window(windowId),
                      runtimeContext.currentTab(windowState)?.id == tab.id
                else {
                    return
                }
                runtimeContext.notifyTabActivatedIfLoaded(tab)
            }
        )
    }

    private func initialDocumentWarmupRuntime(
        runtimeContext: WebViewCoordinatorBrowserRuntimeContext
    ) -> InitialDocumentWarmupRuntime {
        return InitialDocumentWarmupRuntime(
            needsInitialDocumentExtensionContextLoad: { profileId in
                runtimeContext.needsInitialDocumentExtensionContextLoad(profileId)
            },
            ensureInitialDocumentExtensionContextsLoaded: { profileId in
                await runtimeContext.ensureInitialDocumentExtensionContextsLoaded(profileId)
            },
            refreshCompositorForWindow: { windowId in
                guard let windowState = runtimeContext.window(windowId)
                else { return }
                runtimeContext.refreshCompositor(windowState)
            }
        )
    }

    private func evictHiddenWebViewsIfNeeded(
        in windowId: UUID,
        visibleTabIDs: Set<UUID>
    ) {
        let runtimeContext = requireBrowserRuntimeContext()
        hiddenCloneEvictionOwner.evictHiddenWebViews(
            in: windowId,
            visibleTabIDs: visibleTabIDs,
            entries: webViewRegistry.trackedWebViews(in: windowId),
            runtime: hiddenCloneEvictionRuntime(
                globallyVisibleTabIDs: {
                    runtimeContext.globallyVisibleTabIDs()
                },
                runtimeContext: runtimeContext
            )
        )
    }

    private func notifyTabActivatedIfCurrent(_ tab: Tab, in windowId: UUID) {
        let runtimeContext = requireBrowserRuntimeContext()

        if let windowState = runtimeContext.window(windowId),
           runtimeContext.currentTab(windowState)?.id == tab.id {
            runtimeContext.notifyTabActivatedIfLoaded(tab)
        }
    }

    private func performFallbackWebViewCleanup(
        _ webView: WKWebView,
        tabId: UUID
    ) {
        if enqueueDeferredProtectedCommand(
            .performFallbackWebViewCleanup(
                webViewID: ObjectIdentifier(webView),
                tabID: tabId
            ),
            for: webView,
            reason: "performFallbackWebViewCleanup"
        ) {
            return
        }

        RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
            "Performing fallback WebView cleanup for tab=\(tabId.uuidString.prefix(8))."
        }

        SumiWebViewShutdown.perform(
            on: webView,
            tabId: tabId,
            runtime: webViewShutdownRuntime()
        )

        RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
            "Fallback WebView cleanup completed for tab=\(tabId.uuidString.prefix(8))."
        }
    }

    private func webViewShutdownRuntime() -> SumiWebViewShutdown.NormalTabRuntime {
        let runtimeContext = requireBrowserRuntimeContext()
        return SumiWebViewShutdown.NormalTabRuntime(
            cleanupUserScripts: { controller, webViewId in
                runtimeContext.cleanupUserScripts(controller, webViewId)
            },
            removeWebViewFromContainers: { [weak self] webView in
                self?.removeWebViewFromContainers(webView)
            }
        )
    }

    // MARK: - Cross-Window Sync

    /// Sync a tab's URL across all windows displaying it
    func syncTab(_ tab: Tab, to url: URL, originatingWebView: WKWebView? = nil) {
        let tabId = tab.id
        crossWindowSyncOwner.syncTab(
            tabId,
            to: url,
            webViews: getAllWebViews(for: tabId),
            originatingWebView: originatingWebView,
            isProtected: { [self] webView in
                isWebViewProtectedFromCompositorMutation(webView)
            },
            load: { webView in
                tab.performMainFrameNavigationAfterHydrationIfNeeded(
                    on: webView
                ) { resolvedWebView in
                    resolvedWebView.load(URLRequest(url: url))
                }
            }
        )
    }

    /// Reload a tab across all windows displaying it
    func reloadTab(_ tab: Tab) {
        let reloadTargetURL = tab.existingWebView?.url ?? tab.url
        let protectionReloadWasRequired = tab.isProtectionReloadRequired
        if tab.configurationPolicyRequiresNormalWebViewRebuild(for: reloadTargetURL) {
            if rebuildLiveWebViews(
                for: tab,
                preferredPrimaryWindowId: tab.primaryWindowId,
                load: reloadTargetURL
            ), protectionReloadWasRequired {
                tab.noteProtectionManualReloadResult(
                    rebuiltForConfigurationPolicy: true,
                    targetURL: reloadTargetURL
                )
            }
            return
        }
        let tabId = tab.id
        crossWindowSyncOwner.reloadTab(
            tabId,
            webViews: getAllWebViews(for: tabId),
            isProtected: { [self] webView in
                isWebViewProtectedFromCompositorMutation(webView)
            },
            reload: { webView in
                tab.performMainFrameNavigationAfterHydrationIfNeeded(
                    on: webView
                ) { resolvedWebView in
                    resolvedWebView.reload()
                }
            }
        )
    }

    /// Reload a tab only in the requested window.
    @discardableResult
    func reloadTab(_ tab: Tab, in windowId: UUID) -> Bool {
        guard let webView = getWebView(for: tab.id, in: windowId) else { return false }
        if isWebViewProtectedFromCompositorMutation(webView) {
            RuntimeDiagnostics.protectedWebViewTrace(
                "skipReloadProtected webView=\(ObjectIdentifier(webView)) tab=\(tab.id.uuidString.prefix(8)) window=\(windowId.uuidString.prefix(8))"
            )
            return false
        }
        tab.performMainFrameNavigationAfterHydrationIfNeeded(
            on: webView
        ) { resolvedWebView in
            resolvedWebView.reload()
        }
        return true
    }

    /// Set mute state for a tab across all windows
    func setMuteState(_ muted: Bool, for tabId: UUID) {
        crossWindowSyncOwner.setMuteState(
            muted,
            for: tabId,
            windowWebViews: webViewRegistry.windowWebViews(for: tabId)
        )
    }
}
