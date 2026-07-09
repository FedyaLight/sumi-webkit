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
import SumiWebRuntime

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
    let webViewRegistry = WindowWebViewRegistry()

    /// Phase 6B: parked + untracked session material outside Tab fields (Tab remains a mirror).
    @ObservationIgnored
    private(set) lazy var tabWebViewSessionStore = TabWebViewSessionStore(
        webViewRegistry: webViewRegistry
    )

    @ObservationIgnored
    let visibleWebViewRuntimeOwner = VisibleWebViewRuntimeOwner()

    @ObservationIgnored
    let crossWindowSyncOwner = WebViewCrossWindowSyncOwner()

    @ObservationIgnored
    private let webViewAssignmentRebuildOwner = WebViewAssignmentRebuildOwner()

    @ObservationIgnored
    let webViewTrackingLifecycleOwner = WebViewTrackingLifecycleOwner()

    @ObservationIgnored
    let trackedCleanupExecutionOwner = WebViewTrackedCleanupExecutionOwner()

    @ObservationIgnored
    private lazy var trackedRegistrationOwner = WebViewTrackedRegistrationOwner(
        webViewRegistry: webViewRegistry,
        mediaProtectionOwner: mediaProtectionOwner,
        trackingLifecycleOwner: webViewTrackingLifecycleOwner,
        trackedCleanupExecutionOwner: trackedCleanupExecutionOwner,
        requireBrowserRuntimeContext: { [weak self] in
            guard let self else {
                preconditionFailure("WebViewCoordinator dependency used after deallocation")
            }
            return self.runtimeContextStore.requireBrowser()
        },
        removeWebViewFromContainers: { [weak self] webView in
            self?.removeWebViewFromContainers(webView)
        },
        pruneInvalidDeferredCommands: { [weak self] reason in
            self?.pruneInvalidDeferredProtectedCommands(reason: reason)
        },
        flushDeferredProtectedCommands: { [weak self] webViewID in
            self?.flushDeferredProtectedCommands(for: webViewID)
        },
        finishDestructiveCleanupNavigation: { [weak self] webView in
            self?.finishDestructiveDataCleanupNavigation(on: webView)
        },
        performFallbackWebViewCleanup: { [weak self] webView, tabID in
            self?.performFallbackWebViewCleanup(webView, tabId: tabID)
        },
        resolvedTab: { [weak self] tabID in
            self?.resolvedTab(with: tabID)
        },
        refreshPrimaryTrackedWebView: { [weak self] tab in
            self?.refreshPrimaryTrackedWebView(for: tab)
        }
    )

    @ObservationIgnored
    private lazy var tabTeardownOwner = WebViewTabTeardownOwner(
        webViewRegistry: webViewRegistry,
        tabWebViewSessionStore: tabWebViewSessionStore,
        mediaProtectionOwner: mediaProtectionOwner,
        isWebViewProtectedFromCompositorMutation: { [weak self] webView in
            self?.isWebViewProtectedFromCompositorMutation(webView) ?? false
        },
        enqueueDeferredProtectedCommand: { [weak self] command, webView, reason in
            self?.enqueueDeferredProtectedCommand(
                command,
                for: webView,
                reason: reason
            ) ?? false
        },
        cleanupUnprotectedTrackedWebView: { [weak self] webView, owner, tab in
            self?.cleanupUnprotectedTrackedWebView(
                webView,
                owner: owner,
                tab: tab
            )
        },
        refreshPrimaryTrackedWebView: { [weak self] tab in
            self?.refreshPrimaryTrackedWebView(for: tab)
        },
        removeWebViewFromContainers: { [weak self] webView in
            self?.removeWebViewFromContainers(webView)
        },
        unregisterTrackedWebViewSlot: { [weak self] owner, expectedWebView in
            self?.unregisterTrackedWebViewSlot(
                owner: owner,
                expectedWebView: expectedWebView
            )
        }
    )

    @ObservationIgnored
    private lazy var windowCleanupOwner = WebViewWindowCleanupOwner(
        cleanupScopeOwner: cleanupScopeOwner,
        webViewRegistry: webViewRegistry,
        visibleWebViewRuntimeOwner: visibleWebViewRuntimeOwner,
        mediaProtectionOwner: mediaProtectionOwner,
        browserRuntimeContext: { [weak self] in
            self?.runtimeContextStore.browser
        },
        isWebViewProtectedFromCompositorMutation: { [weak self] webView in
            self?.isWebViewProtectedFromCompositorMutation(webView) ?? false
        },
        enqueueDeferredProtectedCommand: { [weak self] command, webView, reason in
            self?.enqueueDeferredProtectedCommand(
                command,
                for: webView,
                reason: reason
            ) ?? false
        },
        cleanupUnprotectedTrackedWebView: { [weak self] webView, owner, tab in
            self?.cleanupUnprotectedTrackedWebView(
                webView,
                owner: owner,
                tab: tab
            )
        },
        refreshPrimaryTrackedWebView: { [weak self] tab in
            self?.refreshPrimaryTrackedWebView(for: tab)
        },
        removeCompositorContainerView: { [weak self] windowId in
            self?.removeCompositorContainerView(for: windowId)
        },
        finishCleanupSuppression: { [weak self] webViewIDs in
            self?.finishDestructiveCleanupSuppression(for: webViewIDs)
        }
    )

    @ObservationIgnored
    private lazy var navigationBroadcastOwner = WebViewNavigationBroadcastOwner(
        crossWindowSyncOwner: crossWindowSyncOwner,
        webViewRegistry: webViewRegistry,
        tabWebViewSessionStore: tabWebViewSessionStore,
        isWebViewProtectedFromCompositorMutation: { [weak self] webView in
            self?.isWebViewProtectedFromCompositorMutation(webView) ?? false
        },
        primaryTrackedWindowId: { [weak self] tabId in
            self?.primaryTrackedWindowId(for: tabId)
        },
        rebuildLiveWebViews: { [weak self] tab, preferredPrimaryWindowId, url in
            self?.rebuildLiveWebViews(
                for: tab,
                preferredPrimaryWindowId: preferredPrimaryWindowId,
                load: url
            ) ?? false
        }
    )

    @ObservationIgnored
    let tabScopedCleanupValidationOwner = WebViewTabScopedCleanupValidationOwner()

    @ObservationIgnored
    let cleanupScopeOwner = WebViewCleanupScopeOwner()

    @ObservationIgnored
    let hiddenCloneEvictionOwner = WebViewHiddenCloneEvictionOwner()

    @ObservationIgnored
    let runtimeContextStore = WebViewRuntimeContextStore()

    @ObservationIgnored
    let mediaProtectionOwner = WebViewMediaProtectionOwner()

    @ObservationIgnored
    let deferredProtectedCommandExecutionOwner = WebViewDeferredProtectedCommandExecutionOwner()

    @ObservationIgnored
    private lazy var protectedCommandDispatchOwner = WebViewProtectedCommandDispatchOwner(
        dependencies: .live(coordinator: self)
    )

    @ObservationIgnored
    private lazy var runtimeAssembler = WebViewRuntimeAssembler(
        dependencies: .live(coordinator: self)
    )

    @ObservationIgnored
    private lazy var destructiveCleanupFlowOwner = WebViewDestructiveCleanupFlowOwner(
        browserRuntimeContext: { [weak self] in
            guard let self else {
                preconditionFailure(
                    "WebViewDestructiveCleanupFlowOwner outlived its coordinator"
                )
            }
            return self.runtimeContextStore.requireBrowser()
        },
        liveWebViews: { [weak self] tab in
            self?.suspensionLiveWebViews(for: tab) ?? []
        },
        isWebViewProtectedFromCompositorMutation: { [weak self] webView in
            self?.isWebViewProtectedFromCompositorMutation(webView) ?? false
        }
    )

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

    func suspensionLiveWebViews(for tab: Tab) -> [WKWebView] {
        allKnownWebViews(for: tab)
    }

    private func allKnownWebViews(for tab: Tab) -> [WKWebView] {
        tabTeardownOwner.allKnownWebViews(for: tab)
    }

    func isPreparingForDataCleanupNavigation(on webView: WKWebView) -> Bool {
        destructiveCleanupFlowOwner.isSuppressingNavigation(on: webView)
    }

    func finishDestructiveDataCleanupNavigation(on webView: WKWebView) {
        destructiveCleanupFlowOwner.finishNavigationSuppression(on: webView)
    }

    func prepareForDestructiveDataCleanup(profileIDs: Set<UUID>) async {
        destructiveCleanupFlowOwner.prepareForDestructiveDataCleanup(profileIDs: profileIDs)
    }

    func windowIDs(for tabId: UUID) -> [UUID] {
        webViewRegistry.windowIDs(for: tabId)
    }

    /// Registry-backed primary window for a tab (preferred tracked candidate).
    /// Does not require a wired visible-runtime context — safe for bare coordinators/tests.
    func primaryTrackedWindowId(for tabId: UUID) -> UUID? {
        visibleWebViewRuntimeOwner.preferredPrimaryWebViewCandidate(
            for: tabId,
            runtime: nil,
            webViewRegistry: webViewRegistry
        )?.owner.windowID
            ?? windowIDs(for: tabId).sorted { $0.uuidString < $1.uuidString }.first
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
        let runtime = runtimeAssembler.requireVisiblePreparationRuntime()
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
        let runtime = runtimeAssembler.requireVisiblePreparationRuntime()
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
        runtimeContextStore.visible = context
    }

    func detachVisiblePreparationRuntimeContext() {
        runtimeContextStore.visible = nil
    }

    func attachBrowserRuntimeContext(_ context: WebViewCoordinatorBrowserRuntimeContext) {
        runtimeContextStore.browser = context
    }

    func detachBrowserRuntimeContext() {
        runtimeContextStore.browser = nil
    }

    func attachInitialDocumentRuntimeContext(
        _ context: InitialDocumentWebViewRuntimeContext
    ) {
        runtimeContextStore.initialDocument = context
    }

    func detachInitialDocumentRuntimeContext() {
        runtimeContextStore.initialDocument = nil
    }

    func attachShutdownRuntimeContext(_ context: WebViewCoordinatorShutdownRuntimeContext) {
        runtimeContextStore.shutdown = context
    }

    func detachShutdownRuntimeContext() {
        runtimeContextStore.shutdown = nil
    }

    // MARK: - Window Cleanup

    func cleanupWindow(_ windowId: UUID, tabManager: TabManager) {
        windowCleanupOwner.cleanupWindow(windowId, tabManager: tabManager)
    }

    func cleanupAllWebViews(tabManager: TabManager) {
        windowCleanupOwner.cleanupAllWebViews(tabManager: tabManager)
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

    func prepareWebKitClose(
        _ webView: WKWebView
    ) -> WebViewCoordinatorWebKitClosePreparation {
        let webViewID = ObjectIdentifier(webView)
        mediaProtectionOwner.note(webView)
        finishDestructiveDataCleanupNavigation(on: webView)

        if enqueueDeferredProtectedCommand(
            .closeWebViewFromWebKit(webViewID: webViewID),
            for: webView,
            reason: "webViewDidClose"
        ) {
            mediaProtectionOwner.closeFullscreenMediaIfNeeded(on: webView)
            return .deferred
        }

        return .ready(trackedOwner: trackedOwner(containing: webView))
    }

    func cleanupTrackedWebViewAfterWebKitClose(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner
    ) {
        cleanupTrackedWebView(webView, owner: owner)
    }

    func flushDeferredProtectedCommands(for webViewID: ObjectIdentifier) {
        protectedCommandDispatchOwner.flushCommands(for: webViewID)
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
            runtime: runtimeAssembler.assignmentRebuildRuntime()
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
        tabTeardownOwner.removeAllWebViews(
            for: tab,
            closeActiveFullscreenMedia: closeActiveFullscreenMedia
        )
    }

    @discardableResult
    func suspendWebViews(for tab: Tab, reason: String) -> Bool {
        tabTeardownOwner.suspendWebViews(for: tab, reason: reason)
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
            runtime: runtimeAssembler.assignmentRebuildRuntime()
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
    func enqueueDeferredProtectedCommand(
        _ command: DeferredWebViewCommand,
        for webView: WKWebView,
        reason: String
    ) -> Bool {
        protectedCommandDispatchOwner.enqueue(command, for: webView, reason: reason)
    }

    func resolveWebView(
        with identifier: ObjectIdentifier
    ) -> WKWebView? {
        if let webView = webViewRegistry.trackedWebView(with: identifier) {
            mediaProtectionOwner.note(webView)
            return webView
        }
        return mediaProtectionOwner.resolveWeakWebView(with: identifier)
    }

    func resolvedTab(with tabID: UUID) -> Tab? {
        let runtimeContext = requireBrowserRuntimeContext()
        return resolvedTab(with: tabID, runtimeContext: runtimeContext)
    }

    func resolvedTab(
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

    func pruneInvalidDeferredProtectedCommands(reason: String) {
        finishDestructiveCleanupSuppression(
            for: mediaProtectionOwner.pruneStaleBookkeeping(reason: "\(reason).staleBookkeeping")
        )
        protectedCommandDispatchOwner.pruneInvalidCommands(reason: reason)
    }

    func finishDestructiveCleanupSuppression(for webViewIDs: [ObjectIdentifier]) {
        destructiveCleanupFlowOwner.finishNavigationSuppression(for: webViewIDs)
    }

    func cleanupTrackedWebView(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner
    ) {
        trackedRegistrationOwner.cleanupTrackedWebView(webView, owner: owner)
    }

    func cleanupUnprotectedTrackedWebView(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner,
        tab: Tab?
    ) {
        trackedRegistrationOwner.cleanupUnprotectedTrackedWebView(
            webView,
            owner: owner,
            tab: tab
        )
    }

    func visibleTabIDSet(in windowId: UUID) -> Set<UUID> {
        visibleWebViewRuntimeOwner.visibleTabIDSet(
            in: windowId,
            runtime: runtimeAssembler.requireVisiblePreparationRuntime()
        )
    }

    private func requireBrowserRuntimeContext() -> WebViewCoordinatorBrowserRuntimeContext {
        runtimeContextStore.requireBrowser()
    }

    private func registerTrackedWebView(
        _ webView: WKWebView,
        for tabId: UUID,
        in windowId: UUID
    ) {
        trackedRegistrationOwner.register(webView, for: tabId, in: windowId)
    }

    @discardableResult
    func unregisterTrackedWebViewSlot(
        owner: TrackedWebViewOwner,
        expectedWebView: WKWebView? = nil,
        removeFromSuperview: Bool = false,
        removeRecentVisibility: Bool = true
    ) -> WKWebView? {
        trackedRegistrationOwner.unregisterSlot(
            owner: owner,
            expectedWebView: expectedWebView,
            removeFromSuperview: removeFromSuperview,
            removeRecentVisibility: removeRecentVisibility
        )
    }

    func trackedOwner(containing webView: WKWebView) -> TrackedWebViewOwner? {
        webViewRegistry.trackedOwner(containing: webView)
    }

    /// Window-tracked WebViews first; then an untracked tab-owned instance if present.
    func anyLiveWebView(for tab: Tab) -> WKWebView? {
        if let primaryWindowId = primaryTrackedWindowId(for: tab.id),
           let tracked = getWebView(for: tab.id, in: primaryWindowId) {
            return tracked
        }
        if let firstTracked = getAllWebViews(for: tab.id).first {
            return firstTracked
        }
        return untrackedOwnedWebView(for: tab)
    }

    func untrackedOwnedWebView(for tab: Tab) -> WKWebView? {
        guard windowIDs(for: tab.id).isEmpty else { return nil }
        tabWebViewSessionStore.promoteLocalSessionIfNeeded(
            tabId: tab.id,
            localSession: tab.webViewOwnershipOwner.localSession
        )
        guard let webView = tabWebViewSessionStore.untrackedWebView(for: tab.id) else {
            return nil
        }
        guard (webView as? FocusableWKWebView)?.owningTab === tab else { return nil }
        return webView
    }

    func hasLiveWebView(for tab: Tab) -> Bool {
        anyLiveWebView(for: tab) != nil
    }

    func ownsLiveWebView(_ webView: WKWebView, for tab: Tab) -> Bool {
        if trackedOwner(containing: webView)?.tabID == tab.id {
            return true
        }
        tabWebViewSessionStore.promoteLocalSessionIfNeeded(
            tabId: tab.id,
            localSession: tab.webViewOwnershipOwner.localSession
        )
        let session = tabWebViewSessionStore.session(for: tab.id)
        return session.untrackedWebView === webView
            || session.parkedWebView === webView
            || session.primaryWebView === webView
    }

    func assignWebView(_ webView: WKWebView, to tab: Tab, in windowId: UUID) {
        // Session note happens inside Tab.assignPrimaryWebView when runtime is attached;
        // note again here so coordinator-only paths stay authoritative even before attach.
        tabWebViewSessionStore.notePrimaryAssignment(
            windowId: windowId,
            for: tab.id,
            webView: webView
        )
        tab.assignWebViewToWindow(webView, windowId: windowId)
        setWebView(webView, for: tab.id, in: windowId)
    }

    func installUntrackedOwnedWebView(_ webView: WKWebView, for tab: Tab) {
        tabWebViewSessionStore.noteUntrackedWebView(webView, for: tab.id)
        tab.replaceUntrackedWebView(webView)
    }

    /// Materializes a tab-owned WebView without assigning a window slot.
    /// Used by Glance previews and other pre-window surfaces.
    @discardableResult
    func ensureUntrackedOwnedWebView(for tab: Tab) -> WKWebView? {
        if let existing = anyLiveWebView(for: tab) {
            return existing
        }
        let webView = tab.ensureUntrackedNormalWebView(
            reason: "WebViewCoordinator.ensureUntrackedOwnedWebView"
        )
        // Ensure path notes session via Tab mutators when runtime is attached;
        // reinforce here for coordinator-first paths.
        if let webView {
            tabWebViewSessionStore.noteUntrackedWebView(webView, for: tab.id)
        }
        return webView
    }

    /// Releases an untracked tab-owned WebView (Glance dismiss, pre-window teardown).
    func releaseUntrackedOwnedWebView(for tab: Tab) {
        if let webView = anyLiveWebView(for: tab) {
            tab.cleanupCloneWebView(webView)
        }
        tab.clearCurrentWebViewOwnership()
        tabWebViewSessionStore.clearAll(for: tab.id)
        _ = removeAllWebViews(for: tab)
    }

    /// Atomically replaces the live WebView for a tab (windowed or untracked).
    /// Creates via Tab factory, optionally validates before install, then cleans up the previous instance.
    @discardableResult
    func replaceLiveWebView(
        for tab: Tab,
        in windowId: UUID?,
        reason: String,
        prepareConfiguration: ((WKWebViewConfiguration) -> Void)? = nil,
        prepareReplacement: ((WKWebView) -> Void)? = nil,
        validate: ((WKWebView) -> Bool)? = nil
    ) -> WKWebView? {
        let previousWebView = {
            if let windowId {
                return getWebView(for: tab.id, in: windowId) ?? anyLiveWebView(for: tab)
            }
            return anyLiveWebView(for: tab)
        }()

        guard let replacementWebView = tab.makeNormalTabWebView(
            reason: reason,
            prepareConfiguration: prepareConfiguration
        ) else {
            return nil
        }
        prepareReplacement?(replacementWebView)
        if let validate, validate(replacementWebView) == false {
            tab.cleanupCloneWebView(replacementWebView)
            return nil
        }

        if let windowId {
            assignWebView(replacementWebView, to: tab, in: windowId)
        } else {
            installUntrackedOwnedWebView(replacementWebView, for: tab)
        }

        if let previousWebView, previousWebView !== replacementWebView {
            tab.cleanupCloneWebView(previousWebView)
        }

        return replacementWebView
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

    func refreshPrimaryTrackedWebView(for tab: Tab) {
        webViewAssignmentRebuildOwner.refreshPrimaryTrackedWebView(
            for: tab,
            runtime: runtimeAssembler.assignmentRebuildRuntime()
        )
    }

    func evictHiddenWebViewsIfNeeded(
        in windowId: UUID,
        visibleTabIDs: Set<UUID>
    ) {
        let runtimeContext = requireBrowserRuntimeContext()
        runtimeAssembler.evictHiddenWebViews(
            in: windowId,
            visibleTabIDs: visibleTabIDs,
            globallyVisibleTabIDs: {
                runtimeContext.globallyVisibleTabIDs()
            },
            runtimeContext: runtimeContext
        )
    }

    func performFallbackWebViewCleanup(
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
            runtime: runtimeAssembler.shutdownRuntime()
        )

        RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
            "Fallback WebView cleanup completed for tab=\(tabId.uuidString.prefix(8))."
        }
    }

    // MARK: - Cross-Window Sync

    /// Sync a tab's URL across all windows displaying it
    func syncTab(_ tab: Tab, to url: URL, originatingWebView: WKWebView? = nil) {
        navigationBroadcastOwner.syncTab(tab, to: url, originatingWebView: originatingWebView)
    }

    /// Reload a tab across all windows displaying it
    func reloadTab(_ tab: Tab) {
        navigationBroadcastOwner.reloadTab(tab)
    }

    /// Reload a tab only in the requested window.
    @discardableResult
    func reloadTab(_ tab: Tab, in windowId: UUID) -> Bool {
        navigationBroadcastOwner.reloadTab(tab, in: windowId)
    }

    /// Set mute state for a tab across all windows
    func setMuteState(_ muted: Bool, for tabId: UUID) {
        navigationBroadcastOwner.setMuteState(muted, for: tabId)
    }
}
