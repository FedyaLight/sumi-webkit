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
    weak var browserManager: BrowserManager?

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

    func liveWebViews(for tab: Tab) -> [WKWebView] {
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
        guard let browserManager else { return }

        let preparationResult = destructiveCleanupPreparationScanOwner.prepare(
            pinnedTabs: browserManager.tabManager.allPinnedTabsAllProfiles,
            tabs: browserManager.tabManager.allTabs(),
            profileIDs: profileIDs,
            liveWebViews: { [self] tab in
                liveWebViews(for: tab)
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
        for windowState: BrowserWindowState,
        browserManager: BrowserManager
    ) -> Bool {
        visibleWebViewRuntimeOwner.prepareVisibleWebViews(
            for: windowState,
            browserManager: browserManager,
            webViewRegistry: webViewRegistry,
            resolveTab: { [self] tabId, windowState, browserManager in
                resolveTab(for: tabId, in: windowState, browserManager: browserManager)
            },
            existingWebView: { [self] tabId, windowId in
                getWebView(for: tabId, in: windowId)
            },
            createWebView: { [self] tab, windowId in
                getOrCreateWebView(for: tab, in: windowId)
            },
            evictHiddenWebViews: { [self] windowId, visibleTabIDs, tabManager in
                evictHiddenWebViewsIfNeeded(
                    in: windowId,
                    visibleTabIDs: visibleTabIDs,
                    tabManager: tabManager
                )
            }
        )
    }

    func schedulePrepareVisibleWebViews(
        for windowState: BrowserWindowState,
        browserManager: BrowserManager
    ) {
        visibleWebViewRuntimeOwner.schedulePrepareVisibleWebViews(
            for: windowState,
            browserManager: browserManager,
            prepareVisibleWebViews: { [weak self] windowState, browserManager in
                guard let self else { return false }
                return self.prepareVisibleWebViews(
                    for: windowState,
                    browserManager: browserManager
                )
            }
        )
    }

    // MARK: - Window Cleanup

    func cleanupWindow(_ windowId: UUID, tabManager: TabManager) {
        let signpostState = PerformanceTrace.beginInterval("WebViewCoordinator.cleanupWindow")
        defer {
            PerformanceTrace.endInterval("WebViewCoordinator.cleanupWindow", signpostState)
        }

        visibleWebViewRuntimeOwner.cancelScheduledPreparation(for: windowId)
        let webViewsToCleanup = webViewRegistry.trackedWebViews(in: windowId)

        RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
            "Cleaning up \(webViewsToCleanup.count) WebViews for window \(windowId.uuidString)."
        }

        for (owner, webView) in webViewsToCleanup {
            if isWebViewProtectedFromCompositorMutation(webView) {
                _ = enqueueDeferredProtectedCommand(
                    .cleanupWindow(windowID: windowId),
                    for: webView,
                    reason: "cleanupWindow"
                )
                continue
            }

            let tab = tabManager.tab(for: owner.tabID)
            cleanupUnprotectedTrackedWebView(
                webView,
                owner: owner,
                tab: tab,
                browserManager: tabManager.browserManager
            )
            if let tab {
                refreshPrimaryTrackedWebView(for: tab, browserManager: tabManager.browserManager)
            }

            RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
                "Cleaned up WebView for tab=\(owner.tabID.uuidString.prefix(8)) in window=\(windowId.uuidString.prefix(8))."
            }
        }

        removeCompositorContainerView(for: windowId)
    }

    func cleanupAllWebViews(tabManager: TabManager) {
        let totalWebViews = webViewRegistry.totalTrackedWebViewCount
        RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
            "Starting full WebView cleanup for \(totalWebViews) tracked views."
        }

        let trackedEntries = webViewRegistry.trackedWebViews()

        for (owner, webView) in trackedEntries {
            if isWebViewProtectedFromCompositorMutation(webView) {
                _ = enqueueDeferredProtectedCommand(
                    .cleanupAllWebViews,
                    for: webView,
                    reason: "cleanupAllWebViews"
                )
                continue
            }

            let tab = tabManager.tab(for: owner.tabID)
            cleanupUnprotectedTrackedWebView(
                webView,
                owner: owner,
                tab: tab,
                browserManager: tabManager.browserManager
            )
            if let tab {
                refreshPrimaryTrackedWebView(for: tab, browserManager: tabManager.browserManager)
            }

            RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
                "Cleaned up WebView for tab=\(owner.tabID.uuidString.prefix(8)) in window=\(owner.windowID.uuidString.prefix(8))."
            }
        }

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

        SumiAuxiliaryWebViewShutdown.perform(
            on: webView,
            browserManager: browserManager,
            reason: "WebKit webViewDidClose fallback"
        )
        return true
    }

    private func flushDeferredProtectedCommands(for webViewID: ObjectIdentifier) {
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
               host.webView === webView
            {
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
                tab: tab,
                browserManager: tab.browserManager
            )
        }
        refreshPrimaryTrackedWebView(for: tab, browserManager: tab.browserManager)
        return true
    }

    @discardableResult
    func suspendWebViews(for tab: Tab, reason: String) -> Bool {
        let liveWebViews = liveWebViews(for: tab)
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
        tab._webView = nil
        tab._existingWebView = nil
        tab.primaryWindowId = nil

        RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
            "Suspension released \(cleanedIdentifiers.count) WebView(s) for tab=\(tab.id.uuidString.prefix(8)) reason=\(reason)."
        }

        return !cleanedIdentifiers.isEmpty
    }

    // MARK: - WebView Creation & Cross-Window Sync

    @available(macOS 15.5, *)
    func rebuildLiveWebViews(
        for tab: Tab,
        preferredPrimaryWindowId: UUID? = nil,
        load url: URL? = nil
    ) {
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
        deferredProtectedCommandExecutionOwner.enqueue(
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
                guard let self,
                      let windowState = self.browserManager?.windowRegistry?.windows[windowID]
                else {
                    return
                }
                self.browserManager?.refreshCompositor(for: windowState)
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
        if let tab = browserManager?.tabManager.tab(for: tabID) {
            return tab
        }
        if let windowStates = browserManager?.windowRegistry?.windows.values {
            for windowState in windowStates {
                if let tab = windowState.ephemeralTabs.first(where: { $0.id == tabID }) {
                    return tab
                }
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
        deferredProtectedCommandExecutionOwner.pruneInvalidCommands(
            reason: reason,
            mediaProtectionOwner: mediaProtectionOwner,
            runtime: deferredProtectedCommandRuntime()
        )
    }

    private func deferredProtectedCommandRuntime() -> WebViewDeferredProtectedCommandExecutionOwner.Runtime {
        let validationContext = WebViewDeferredProtectedCommandExecutionOwner.ValidationContext(
            resolveWebView: { [self] webViewID in
                resolveWebView(with: webViewID)
            },
            resolveTab: { [self] tabID in
                resolvedTab(with: tabID)
            },
            hasTabManager: { [self] in
                browserManager?.tabManager != nil
            },
            hasCleanupWindowTarget: { [self] windowID in
                webViewRegistry.trackedWebViews(in: windowID).isEmpty == false
                    || compositorContainerView(for: windowID) != nil
            },
            hasTrackedWebViews: { [self] in
                webViewRegistry.isEmpty == false
            },
            hasWindow: { [self] windowID in
                browserManager?.windowRegistry?.windows[windowID] != nil
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
            guard let tabManager = browserManager?.tabManager else {
                return false
            }
            cleanupWindow(windowID, tabManager: tabManager)
        case .cleanupAllWebViews:
            guard let tabManager = browserManager?.tabManager else {
                return false
            }
            cleanupAllWebViews(tabManager: tabManager)
        case .rebuildLiveWebViews(let tabID, let preferredPrimaryWindowID):
            guard let tab = resolvedTab(with: tabID) else {
                return false
            }
            rebuildLiveWebViews(
                for: tab,
                preferredPrimaryWindowId: preferredPrimaryWindowID
            )
        case .evictHiddenWebViews(let windowID):
            guard let browserManager,
                  browserManager.windowRegistry?.windows[windowID] != nil
            else {
                return false
            }
            evictHiddenWebViewsIfNeeded(
                in: windowID,
                visibleTabIDs: visibleTabIDSet(
                    in: windowID,
                    browserManager: browserManager
                ),
                tabManager: browserManager.tabManager
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
                    tabId: tabID,
                    browserManager: browserManager
                )
            }
        case .performFallbackWebViewCleanup(let webViewID, let tabID):
            guard let webView = resolveWebView(with: webViewID) else {
                return false
            }
            performFallbackWebViewCleanup(
                webView,
                tabId: tabID,
                browserManager: browserManager
            )
        }

        return true
    }

    private func cleanupTrackedWebView(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner
    ) {
        let tab = resolvedTab(with: owner.tabID)
        let cleanupBrowserManager = tab?.browserManager ?? browserManager
        cleanupUnprotectedTrackedWebView(
            webView,
            owner: owner,
            tab: tab,
            browserManager: cleanupBrowserManager
        )
        if let tab {
            refreshPrimaryTrackedWebView(for: tab, browserManager: cleanupBrowserManager)
        }
    }

    private func cleanupUnprotectedTrackedWebView(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner,
        tab: Tab?,
        browserManager: BrowserManager?
    ) {
        trackedCleanupExecutionOwner.cleanupUnprotectedTrackedWebView(
            webView,
            owner: owner,
            tab: tab,
            browserManager: browserManager,
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
            fallbackCleanup: { [self] webView, tabID, browserManager in
                performFallbackWebViewCleanup(
                    webView,
                    tabId: tabID,
                    browserManager: browserManager
                )
            }
        )
    }

    @discardableResult
    private func closeTrackedWebViewFromWebKit(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner
    ) -> Bool {
        guard let browserManager,
              let tab = resolvedTab(with: owner.tabID)
        else {
            cleanupTrackedWebView(webView, owner: owner)
            return true
        }

        let windowState = browserManager.windowRegistry?.windows[owner.windowID]
            ?? browserManager.windowState(containing: tab)
        closeTabForWebKitCloseRequest(tab, windowState: windowState)
        return true
    }

    private func closeTabForWebKitCloseRequest(
        _ tab: Tab,
        windowState: BrowserWindowState?
    ) {
        guard let browserManager else {
            tab.performComprehensiveWebViewCleanup()
            return
        }

        if let windowState {
            browserManager.closeTab(tab, in: windowState)
            return
        }

        if let containingWindow = browserManager.windowState(containing: tab) {
            browserManager.closeTab(tab, in: containingWindow)
            return
        }

        tab.performComprehensiveWebViewCleanup()
        browserManager.tabManager.removeTab(tab.id)
    }

    private func untrackedTabContext(
        for webView: WKWebView
    ) -> (tab: Tab, windowState: BrowserWindowState?)? {
        guard let browserManager else { return nil }

        func matches(_ tab: Tab) -> Bool {
            tab.existingWebView === webView || tab.assignedWebView === webView
        }

        if let windowStates = browserManager.windowRegistry?.allWindows {
            for windowState in windowStates {
                if let tab = windowState.ephemeralTabs.first(where: matches) {
                    return (tab, windowState)
                }
            }
        }

        if let tab = browserManager.tabManager.allTabs().first(where: matches) {
            return (
                tab,
                browserManager.windowState(containing: tab)
            )
        }

        return nil
    }

    private func visibleTabIDs(
        for windowState: BrowserWindowState,
        browserManager: BrowserManager
    ) -> [UUID] {
        visibleWebViewRuntimeOwner.visibleTabIDs(
            for: windowState,
            browserManager: browserManager,
            resolveTab: { [self] tabId, windowState, browserManager in
                resolveTab(for: tabId, in: windowState, browserManager: browserManager)
            }
        )
    }

    private func visibleTabIDSet(
        in windowId: UUID,
        browserManager: BrowserManager?
    ) -> Set<UUID> {
        visibleWebViewRuntimeOwner.visibleTabIDSet(
            in: windowId,
            browserManager: browserManager,
            resolveTab: { [self] tabId, windowState, browserManager in
                resolveTab(for: tabId, in: windowState, browserManager: browserManager)
            }
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

    private func refreshPrimaryTrackedWebView(
        for tab: Tab,
        browserManager: BrowserManager?
    ) {
        webViewAssignmentRebuildOwner.refreshPrimaryTrackedWebView(
            for: tab,
            browserManager: browserManager,
            runtime: assignmentRebuildRuntime()
        )
    }

    private func preferredPrimaryWebViewCandidate(
        for tabId: UUID,
        browserManager: BrowserManager?
    ) -> (owner: TrackedWebViewOwner, webView: WKWebView)? {
        visibleWebViewRuntimeOwner.preferredPrimaryWebViewCandidate(
            for: tabId,
            browserManager: browserManager,
            webViewRegistry: webViewRegistry,
            resolveTab: { [self] tabId, windowState, browserManager in
                resolveTab(for: tabId, in: windowState, browserManager: browserManager)
            }
        )
    }

    private func assignmentRebuildRuntime() -> WebViewAssignmentRebuildOwner.Runtime {
        WebViewAssignmentRebuildOwner.Runtime(
            webViewRegistry: webViewRegistry,
            browserManager: browserManager,
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
            primaryCandidate: { [self] tabId, browserManager in
                preferredPrimaryWebViewCandidate(
                    for: tabId,
                    browserManager: browserManager
                )
            },
            notifyTabActivatedIfCurrent: { [self] tab, windowId in
                notifyTabActivatedIfCurrent(tab, in: windowId)
            }
        )
    }

    private func evictHiddenWebViewsIfNeeded(
        in windowId: UUID,
        visibleTabIDs: Set<UUID>,
        tabManager: TabManager
    ) {
        let signpostState = PerformanceTrace.beginInterval("WebViewCoordinator.evictHiddenWebViews")
        defer {
            PerformanceTrace.endInterval("WebViewCoordinator.evictHiddenWebViews", signpostState)
        }

        let trackedEntries = webViewRegistry.trackedWebViews(in: windowId)
        let hiddenEntries = trackedEntries.filter { owner, _ in
            visibleTabIDs.contains(owner.tabID) == false
        }

        guard hiddenEntries.isEmpty == false else { return }

        guard let browserManager = tabManager.browserManager else { return }
        let globallyVisibleTabIDs = browserManager.tabSuspensionService
            .suspensionEvaluationContext()
            .visibleTabIDs

        for (owner, webView) in hiddenEntries.sorted(by: {
            if $0.0.tabID != $1.0.tabID {
                return $0.0.tabID.uuidString < $1.0.tabID.uuidString
            }
            return $0.0.windowID.uuidString < $1.0.windowID.uuidString
        }) {
            guard globallyVisibleTabIDs.contains(owner.tabID) else { continue }
            guard let tab = resolvedTab(with: owner.tabID) else { continue }
            guard liveWebViews(for: tab).count > 1 else { continue }

            if isWebViewProtectedFromCompositorMutation(webView) {
                _ = enqueueDeferredProtectedCommand(
                    .evictHiddenWebViews(windowID: windowId),
                    for: webView,
                    reason: "hiddenCloneCleanup"
                )
                continue
            }

            cleanupUnprotectedTrackedWebView(
                webView,
                owner: owner,
                tab: tab,
                browserManager: browserManager
            )
            refreshPrimaryTrackedWebView(for: tab, browserManager: browserManager)

            RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
                "Cleaned hidden clone for visible tab=\(owner.tabID.uuidString.prefix(8)) window=\(windowId.uuidString.prefix(8))."
            }
        }
    }

    private func notifyTabActivatedIfCurrent(_ tab: Tab, in windowId: UUID) {
        guard let browserManager = tab.browserManager else { return }

        if let windowState = browserManager.windowRegistry?.windows[windowId],
           browserManager.currentTab(for: windowState)?.id == tab.id
        {
            browserManager.extensionsModule.notifyTabActivatedIfLoaded(
                newTab: tab,
                previous: nil
            )
        }
    }

    private func performFallbackWebViewCleanup(
        _ webView: WKWebView,
        tabId: UUID,
        browserManager: BrowserManager?
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
            browserManager: browserManager
        )

        RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
            "Fallback WebView cleanup completed for tab=\(tabId.uuidString.prefix(8))."
        }
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
        if tab.protectionAttachmentRequiresNormalWebViewRebuild(for: reloadTargetURL)
            || tab.autoplayPolicyRequiresNormalWebViewRebuild(for: reloadTargetURL) {
            tab.refresh()
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

    /// Set mute state for a tab across all windows
    func setMuteState(_ muted: Bool, for tabId: UUID) {
        crossWindowSyncOwner.setMuteState(
            muted,
            for: tabId,
            windowWebViews: webViewRegistry.windowWebViews(for: tabId)
        )
    }

    private func resolveTab(
        for tabId: UUID,
        in windowState: BrowserWindowState,
        browserManager: BrowserManager
    ) -> Tab? {
        if windowState.isIncognito,
           let ephemeralTab = windowState.ephemeralTabs.first(where: { $0.id == tabId })
        {
            return ephemeralTab
        }
        return browserManager.tabManager.tab(for: tabId)
    }
}
