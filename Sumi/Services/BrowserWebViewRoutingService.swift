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
            }
        )
    }
}
