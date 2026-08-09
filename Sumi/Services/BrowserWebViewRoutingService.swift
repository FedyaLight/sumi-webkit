import WebKit
import SumiWebRuntime

@MainActor
final class BrowserWebViewRoutingService {
    typealias TabLookup = @MainActor (UUID) -> Tab?

    struct Commands {
        let sync: @MainActor (Tab, URL, WKWebView?) -> Void
        let refreshCompositor: @MainActor (UUID) -> Void
        let reloadAll: @MainActor (
            Tab,
            TabMainFrameNavigationIntent,
            WebRuntimeMainFrameReloadPolicy
        ) -> PageReloadCommandOutcome
        let reloadWindow: @MainActor (
            Tab,
            UUID,
            TabMainFrameNavigationIntent,
            WebRuntimeMainFrameReloadPolicy
        ) -> PageReloadCommandOutcome
        let retainRecovery: @MainActor (Tab, WKWebView) -> Bool
        let recover: @MainActor (Tab, WKWebView) -> TabMainFrameReloadCommandOutcome
        let cancelRecovery: @MainActor (WKWebView) -> Void
        let setMute: @MainActor (Bool, UUID) -> Void
        let materialize: @MainActor (Tab, UUID) -> WKWebView?
        let rebuildWindowConfiguration: @MainActor (
            Tab,
            UUID,
            URL,
            String
        ) -> TabWebViewReplacementOutcome
    }

    private let tabLookup: TabLookup
    private let webViewSessions: WebViewSessionRepository
    private let ownershipQuery: WebViewOwnershipQuery
    private let commands: Commands

    init(
        tabLookup: @escaping TabLookup,
        webViewSessions: WebViewSessionRepository,
        ownershipQuery: WebViewOwnershipQuery,
        commands: Commands
    ) {
        self.tabLookup = tabLookup
        self.webViewSessions = webViewSessions
        self.ownershipQuery = ownershipQuery
        self.commands = commands
    }

    func webView(for tabId: UUID, in windowId: UUID) -> WKWebView? {
        ownershipQuery.webView(for: tabId, in: windowId)
    }

    /// Soft lookup for Tab session-delegating accessors (no precondition).
    func webViewIfAvailable(for tabId: UUID, in windowId: UUID) -> WKWebView? {
        webViewSessions.webView(for: tabId, in: windowId)
    }

    func windowOwnedWebView(for tab: Tab, in windowId: UUID) -> WKWebView? {
        webView(for: tab.id, in: windowId)
    }

    /// Live WebViews known to the canonical ownership repository for this tab.
    func trackedWebViews(for tabId: UUID) -> [WKWebView] {
        ownershipQuery.trackedWebViews(for: tabId)
    }

    /// Prefer a window-tracked WebView; fall back to an untracked tab-owned instance
    /// (popup / pre-window / Glance materialization) via ownership runtime.
    func anyLiveWebView(for tab: Tab) -> WKWebView? {
        ownershipQuery.anyLiveWebView(for: tab)
    }

    /// Soft lookup for Tab session-delegating accessors (no precondition).
    func anyLiveWebViewIfAvailable(for tab: Tab) -> WKWebView? {
        tab.webViewSession.currentWebView
    }

    func ownsLiveWebView(_ webView: WKWebView, for tab: Tab) -> Bool {
        ownershipQuery.owns(webView, for: tab)
    }

    func hasLiveWebView(for tab: Tab) -> Bool {
        ownershipQuery.hasLiveWebView(for: tab)
    }

    func hasLiveWebViewIfAvailable(for tab: Tab) -> Bool {
        tab.webViewSession.currentWebView != nil
    }

    func hasUntrackedOwnedWebView(for tab: Tab) -> Bool {
        ownershipQuery.untrackedOwnedWebView(for: tab) != nil
    }

    func trackedOwner(containing webView: WKWebView) -> TrackedWebViewOwner? {
        ownershipQuery.trackedOwner(containing: webView)
    }

    func primaryTrackedWindowId(for tabId: UUID) -> UUID? {
        ownershipQuery.primaryWindowID(for: tabId)
    }

    /// Soft lookup for Tab session-delegating accessors (no precondition).
    func primaryTrackedWindowIdIfAvailable(for tabId: UUID) -> UUID? {
        webViewSessions.primaryWindowID(for: tabId)
    }

    func windowIDs(for tabId: UUID) -> [UUID] {
        ownershipQuery.windowIDs(for: tabId)
    }

    func syncTabAcrossWindows(_ tabId: UUID, originatingWebView: WKWebView? = nil) {
        guard let tab = tabLookup(tabId) else { return }
        guard ExtensionURLIdentity.isOwned(tab.url) == false else { return }
        commands.sync(tab, tab.url, originatingWebView)
    }

    func pagePresentationDidChange(
        _ tabId: UUID,
        on webView: WKWebView
    ) {
        guard let owner = ownershipQuery.trackedOwner(containing: webView),
              owner.tabID == tabId else { return }
        commands.refreshCompositor(owner.windowID)
    }

    func reloadTabAcrossWindows(
        _ tabId: UUID,
        intent: TabMainFrameNavigationIntent,
        policy: WebRuntimeMainFrameReloadPolicy
    ) -> PageReloadCommandOutcome {
        guard let tab = tabLookup(tabId),
              tab.mainFrameLoads.isCurrent(intent) else {
            return .failed(intent: intent, reason: .staleAttempt)
        }
        return commands.reloadAll(tab, intent, policy)
    }

    @discardableResult
    func reloadTab(
        _ tabId: UUID,
        in windowId: UUID,
        intent: TabMainFrameNavigationIntent,
        policy: WebRuntimeMainFrameReloadPolicy
    ) -> PageReloadCommandOutcome {
        guard let tab = tabLookup(tabId),
              tab.mainFrameLoads.isCurrent(intent) else {
            return .failed(intent: intent, reason: .staleAttempt)
        }
        return commands.reloadWindow(tab, windowId, intent, policy)
    }

    @discardableResult
    func retainWebContentProcessRecovery(
        _ tabId: UUID,
        on webView: WKWebView
    ) -> Bool {
        guard let tab = tabLookup(tabId),
              tab.webViewSession.owns(webView),
              tab.webContentRecoveryMarkers.isRecoveryRequired(on: webView) else {
            return false
        }
        return commands.retainRecovery(tab, webView)
    }

    @discardableResult
    func recoverWebContentProcess(
        _ tabId: UUID,
        on webView: WKWebView
    ) -> TabMainFrameReloadCommandOutcome {
        guard let tab = tabLookup(tabId),
              tab.webViewSession.owns(webView),
              tab.webContentRecoveryMarkers.isRecoveryRequired(on: webView) else {
            return .failed
        }
        return commands.recover(tab, webView)
    }

    func cancelWebContentProcessRecovery(on webView: WKWebView) {
        commands.cancelRecovery(webView)
    }

    func setMuteState(_ muted: Bool, for tabId: UUID) {
        commands.setMute(muted, tabId)
    }

    func bindWebViewSession(_ handle: WebViewSessionHandle) {
        handle.requireBacking(by: webViewSessions)
    }

    func loadPage(
        _ url: URL,
        for tab: Tab,
        in windowState: BrowserWindowState,
        reason: String
    ) {
        tab.navigationCommandOwner.loadURL(
            url,
            for: tab,
            resolvedWebView: windowWebViewResolver(
                for: tab,
                in: windowState.id
            ),
            reason: reason,
            configurationPolicyRebuilder: {
                [weak self, weak tab, weak windowState] targetURL, reason in
                guard let self, let tab, let windowState else { return .failed }
                return self.rebuildWindowConfigurationIfNeeded(
                    for: tab,
                    targetURL: targetURL,
                    in: windowState.id,
                    reason: reason
                )
            }
        )
    }

    @discardableResult
    func refreshPage(
        for tab: Tab,
        in windowState: BrowserWindowState,
        reason: String,
        policy: WebRuntimeMainFrameReloadPolicy = .standard
    ) -> PageReloadCommandOutcome {
        tab.navigationCommandOwner.refresh(
            tab,
            resolvedWebView: windowWebViewResolver(
                for: tab,
                in: windowState.id
            ),
            reason: reason,
            policy: policy,
            deliverTrackedReload: {
                [weak self, weak tab, weak windowState] intent, policy in
                guard let self, let tab, let windowState else {
                    return .failed(
                        intent: intent,
                        reason: .deliveryContextUnavailable
                    )
                }
                return self.reloadTab(
                    tab.id,
                    in: windowState.id,
                    intent: intent,
                    policy: policy
                )
            }
        )
    }

    private func windowWebViewResolver(
        for tab: Tab,
        in windowID: UUID
    ) -> TabNavigationCommandOwner.WebViewResolver {
        { [weak self, weak tab] in
            guard let self, let tab else { return nil }
            return self.windowOwnedWebView(for: tab, in: windowID)
                ?? self.commands.materialize(tab, windowID)
        }
    }

    private func rebuildWindowConfigurationIfNeeded(
        for tab: Tab,
        targetURL: URL,
        in windowID: UUID,
        reason: String
    ) -> TabWebViewReplacementOutcome {
        guard tab.configurationPolicyRequiresNormalWebViewRebuild(for: targetURL) else {
            return .notNeeded
        }
        return commands.rebuildWindowConfiguration(
            tab,
            windowID,
            targetURL,
            reason
        )
    }
}

extension BrowserWebViewRoutingService.Commands {
    static func live(
        navigationBroadcast: WebViewNavigationBroadcastOwner,
        processRecovery: WebContentProcessRecoveryService,
        trackedAdmission: TrackedWebViewAdmissionService,
        rebuild: WebViewRebuildService,
        refreshCompositor: @escaping @MainActor (UUID) -> Void
    ) -> Self {
        Self(
            sync: { tab, url, originatingWebView in
                navigationBroadcast.syncTab(
                    tab,
                    to: url,
                    originatingWebView: originatingWebView
                )
            },
            refreshCompositor: refreshCompositor,
            reloadAll: { tab, intent, policy in
                navigationBroadcast.reloadTab(
                    tab,
                    intent: intent,
                    policy: policy
                )
            },
            reloadWindow: { tab, windowID, intent, policy in
                navigationBroadcast.reloadTab(
                    tab,
                    in: windowID,
                    intent: intent,
                    policy: policy
                )
            },
            retainRecovery: { tab, webView in
                processRecovery.retain(webView, for: tab)
            },
            recover: { tab, webView in
                processRecovery.recover(webView, for: tab)
            },
            cancelRecovery: { webView in
                processRecovery.cancel(webView)
            },
            setMute: { muted, tabID in
                navigationBroadcast.setMuteState(
                    muted,
                    for: tabID
                )
            },
            materialize: { tab, windowID in
                trackedAdmission.webView(
                    for: tab,
                    in: windowID
                )
            },
            rebuildWindowConfiguration: {
                tab, windowID, targetURL, reason in
                let result = rebuild.rebuildLiveWebViewsResult(
                    for: tab,
                    preferredPrimaryWindowID: windowID,
                    load: targetURL,
                    reason: reason,
                    intentRevision: tab.webViewRebuildEpoch.current,
                    rebuildKind: .semanticNavigation
                )
                switch result {
                case .committed:
                    return .replacedAndScheduledNavigation
                case .deferred:
                    return .deferred
                case .noLiveWindows, .failed:
                    return .failed
                }
            }
        )
    }
}
