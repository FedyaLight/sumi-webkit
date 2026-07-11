import WebKit
import SumiWebRuntime

@MainActor
final class BrowserWebViewRoutingService {
    typealias TabLookup = @MainActor (UUID) -> Tab?

    struct Commands {
        let sync: @MainActor (Tab, URL, WKWebView?) -> Void
        let reloadAll: @MainActor (
            Tab,
            TabMainFrameNavigationIntent,
            WebRuntimeMainFrameReloadPolicy
        ) -> Void
        let reloadWindow: @MainActor (
            Tab,
            UUID,
            TabMainFrameNavigationIntent,
            WebRuntimeMainFrameReloadPolicy
        ) -> TabMainFrameReloadCommandOutcome
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

    typealias CommandsProvider = @MainActor () -> Commands?

    private let tabLookup: TabLookup
    private let webViewSessions: WebViewSessionRepository
    private let ownershipQuery: WebViewOwnershipQuery
    private let commandsProvider: CommandsProvider

    init(
        tabLookup: @escaping TabLookup,
        webViewSessions: WebViewSessionRepository,
        ownershipQuery: WebViewOwnershipQuery,
        commandsProvider: @escaping CommandsProvider
    ) {
        self.tabLookup = tabLookup
        self.webViewSessions = webViewSessions
        self.ownershipQuery = ownershipQuery
        self.commandsProvider = commandsProvider
    }

    private func requireCommands(
        operation: String = #function
    ) -> Commands {
        guard let commands = commandsProvider() else {
            preconditionFailure(
                "WebView routing commands are unavailable during \(operation). Bind the browser runtime first."
            )
        }
        return commands
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

    /// Live WebViews known to the coordinator registry for this tab.
    func trackedWebViews(for tabId: UUID) -> [WKWebView] {
        ownershipQuery.trackedWebViews(for: tabId)
    }

    /// Prefer a window-tracked WebView; fall back to an untracked tab-owned instance
    /// (popup / pre-window / Glance materialization) via the coordinator.
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
        guard ExtensionUtils.isExtensionOwnedURL(tab.url) == false else { return }
        requireCommands().sync(tab, tab.url, originatingWebView)
    }

    func reloadTabAcrossWindows(
        _ tabId: UUID,
        intent: TabMainFrameNavigationIntent,
        policy: WebRuntimeMainFrameReloadPolicy
    ) {
        guard let tab = tabLookup(tabId),
              tab.isCurrentMainFrameNavigationIntent(intent) else {
            return
        }
        requireCommands().reloadAll(tab, intent, policy)
    }

    @discardableResult
    func reloadTab(
        _ tabId: UUID,
        in windowId: UUID,
        intent: TabMainFrameNavigationIntent,
        policy: WebRuntimeMainFrameReloadPolicy
    ) -> TabMainFrameReloadCommandOutcome {
        guard let tab = tabLookup(tabId),
              tab.isCurrentMainFrameNavigationIntent(intent) else {
            return .failed
        }
        return requireCommands().reloadWindow(tab, windowId, intent, policy)
    }

    @discardableResult
    func retainWebContentProcessRecovery(
        _ tabId: UUID,
        on webView: WKWebView
    ) -> Bool {
        guard let tab = tabLookup(tabId),
              tab.webViewSession.owns(webView),
              tab.requiresWebContentProcessRecovery(on: webView) else {
            return false
        }
        return requireCommands().retainRecovery(tab, webView)
    }

    @discardableResult
    func recoverWebContentProcess(
        _ tabId: UUID,
        on webView: WKWebView
    ) -> TabMainFrameReloadCommandOutcome {
        guard let tab = tabLookup(tabId),
              tab.webViewSession.owns(webView),
              tab.requiresWebContentProcessRecovery(on: webView) else {
            return .failed
        }
        return requireCommands().recover(tab, webView)
    }

    func cancelWebContentProcessRecovery(on webView: WKWebView) {
        commandsProvider()?.cancelRecovery(webView)
    }

    func setMuteState(_ muted: Bool, for tabId: UUID) {
        requireCommands().setMute(muted, tabId)
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
    ) -> TabMainFrameReloadCommandOutcome {
        tab.navigationCommandOwner.refresh(
            tab,
            resolvedWebView: windowWebViewResolver(
                for: tab,
                in: windowState.id
            ),
            reason: reason,
            policy: policy,
            configurationPolicyRebuilder: {
                [weak self, weak tab, weak windowState] targetURL, reason in
                guard let self, let tab, let windowState else { return .failed }
                return self.rebuildWindowConfigurationIfNeeded(
                    for: tab,
                    targetURL: targetURL,
                    in: windowState.id,
                    reason: reason
                )
            },
            deliverTrackedReload: {
                [weak self, weak tab, weak windowState] intent, policy in
                guard let self, let tab, let windowState else { return .failed }
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
                ?? self.commandsProvider()?.materialize(tab, windowID)
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
        guard let commands = commandsProvider() else {
            RuntimeDiagnostics.emit(
                "Cannot rebuild window WebView for \(reason): routing commands unavailable."
            )
            return .failed
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
    static func live(coordinator: WebViewCoordinator) -> Self {
        Self(
            sync: { [weak coordinator] tab, url, originatingWebView in
                coordinator?.navigationBroadcastOwner.syncTab(
                    tab,
                    to: url,
                    originatingWebView: originatingWebView
                )
            },
            reloadAll: { [weak coordinator] tab, intent, policy in
                coordinator?.navigationBroadcastOwner.reloadTab(
                    tab,
                    intent: intent,
                    policy: policy
                )
            },
            reloadWindow: { [weak coordinator] tab, windowID, intent, policy in
                coordinator?.navigationBroadcastOwner.reloadTab(
                    tab,
                    in: windowID,
                    intent: intent,
                    policy: policy
                ) ?? .failed
            },
            retainRecovery: { [weak coordinator] tab, webView in
                coordinator?.processRecoveryService.retain(webView, for: tab)
                    ?? false
            },
            recover: { [weak coordinator] tab, webView in
                coordinator?.processRecoveryService.recover(webView, for: tab)
                    ?? .failed
            },
            cancelRecovery: { [weak coordinator] webView in
                coordinator?.processRecoveryService.cancel(webView)
            },
            setMute: { [weak coordinator] muted, tabID in
                coordinator?.navigationBroadcastOwner.setMuteState(
                    muted,
                    for: tabID
                )
            },
            materialize: { [weak coordinator] tab, windowID in
                coordinator?.ownershipService.webView(
                    for: tab,
                    in: windowID
                )
            },
            rebuildWindowConfiguration: {
                [weak coordinator] tab, windowID, targetURL, reason in
                guard let coordinator else { return .failed }
                let result = coordinator.rebuildService.rebuildLiveWebViewsResult(
                    for: tab,
                    preferredPrimaryWindowID: windowID,
                    load: targetURL,
                    reason: reason,
                    intentRevision: tab.currentWebViewRebuildIntentRevision,
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
