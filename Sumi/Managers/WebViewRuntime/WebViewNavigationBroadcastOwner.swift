import Foundation
import WebKit
import SumiWebRuntime

/// Broadcasts navigation state for a tab to every window displaying it:
/// URL sync, reloads (with configuration-policy rebuilds), and mute state.
@MainActor
final class WebViewNavigationBroadcastOwner {
    private let crossWindowSyncOwner: WebViewCrossWindowSyncOwner
    private let webViewSessions: WebViewSessionRepository
    private let isWebViewProtectedFromCompositorMutation: @MainActor (WKWebView) -> Bool
    private let deferProtectedNavigation: @MainActor (
        DeferredWebViewCommand,
        WKWebView
    ) -> DeferredProtectedCommandSchedulingOutcome

    init(
        crossWindowSyncOwner: WebViewCrossWindowSyncOwner,
        webViewSessions: WebViewSessionRepository,
        isWebViewProtectedFromCompositorMutation: @escaping @MainActor (WKWebView) -> Bool,
        deferProtectedNavigation: @escaping @MainActor (
            DeferredWebViewCommand,
            WKWebView
        ) -> DeferredProtectedCommandSchedulingOutcome
    ) {
        self.crossWindowSyncOwner = crossWindowSyncOwner
        self.webViewSessions = webViewSessions
        self.isWebViewProtectedFromCompositorMutation = isWebViewProtectedFromCompositorMutation
        self.deferProtectedNavigation = deferProtectedNavigation
    }

    func syncTab(_ tab: Tab, to url: URL, originatingWebView: WKWebView?) {
        let tabId = tab.id
        crossWindowSyncOwner.syncTab(
            tabId,
            to: url,
            webViews: webViewSessions.webViews(for: tabId),
            originatingWebView: originatingWebView,
            hasPendingTarget: { webView, targetURL in
                tab.mainFrameLoads.hasOutstandingLoad(
                    on: webView,
                    targetURL: targetURL
                )
            },
            isProtected: { [isWebViewProtectedFromCompositorMutation] webView in
                isWebViewProtectedFromCompositorMutation(webView)
            },
            deferProtectedTarget: { [webViewSessions, deferProtectedNavigation] webView in
                guard case .window(let owner) = webViewSessions.residence(of: webView),
                      owner.tabID == tabId,
                      let navigationIntent = tab.mainFrameLoads.currentIntent(
                          matching: url
                      ), tab.mainFrameLoads.markDeferredLoad(
                          on: webView,
                          intent: navigationIntent
                      ) else {
                    return .rejected
                }
                let schedulingOutcome = deferProtectedNavigation(
                    .synchronizeTrackedNavigation(
                        webViewID: ObjectIdentifier(webView),
                        tabID: tabId,
                        windowID: owner.windowID,
                        intent: DeferredWebViewNavigationIntent(
                            revision: navigationIntent.revision,
                            targetURL: navigationIntent.targetURL
                        )
                    ),
                    webView
                )
                switch schedulingOutcome {
                case .scheduled:
                    return .deferred
                case .notProtected:
                    tab.mainFrameLoads.clearDeferredLoad(
                        on: webView,
                        intent: navigationIntent
                    )
                    return .executeNow
                case .invalidTarget, .droppedAtCapacity:
                    tab.mainFrameLoads.clearDeferredLoad(
                        on: webView,
                        intent: navigationIntent
                    )
                    return .rejected
                }
            },
            load: { webView in
                tab.performMainFrameNavigationAfterHydrationIfNeeded(
                    on: webView
                ) { resolvedWebView in
                    WebRuntimeMainFrameLoader.load(url, on: resolvedWebView)
                }
            }
        )
    }

    func reloadTab(
        _ tab: Tab,
        intent: TabMainFrameNavigationIntent,
        policy: WebRuntimeMainFrameReloadPolicy
    ) -> PageReloadCommandOutcome {
        guard tab.mainFrameLoads.isCurrent(intent) else {
            return .failed(intent: intent, reason: .staleAttempt)
        }
        let tabId = tab.id
        let webViews = webViewSessions.webViews(for: tabId)
        guard webViews.isEmpty == false else {
            return .failed(intent: intent, reason: .noResidence)
        }
        var dispositions: [PageReloadDisposition] = []
        for webView in webViews {
            if isWebViewProtectedFromCompositorMutation(webView) {
                let admission = tab.mainFrameLoads.deferAttempt(
                    on: webView,
                    intent: intent
                )
                let owner: TabMainFramePendingAttemptOwner
                switch admission {
                case .waiting(let admittedOwner):
                    owner = admittedOwner
                case .coalesced(let admittedOwner):
                    dispositions.append(.coalesced(admittedOwner))
                    continue
                case .rejected:
                    dispositions.append(.failed(PageReloadFailure(
                        intent: intent,
                        webViewID: ObjectIdentifier(webView),
                        reason: .protectedDeliveryRejected
                    )))
                    continue
                }
                guard case .window(let residence) = webViewSessions.residence(of: webView),
                      residence.tabID == tabId else {
                    tab.mainFrameLoads.clearDeferredLoad(on: webView, intent: intent)
                    dispositions.append(.failed(PageReloadFailure(
                        intent: intent,
                        webViewID: ObjectIdentifier(webView),
                        reason: .noResidence
                    )))
                    continue
                }
                let schedulingOutcome = deferProtectedNavigation(
                    .reloadTrackedNavigation(
                        webViewID: ObjectIdentifier(webView),
                        tabID: tabId,
                        windowID: residence.windowID,
                        intent: DeferredWebViewReloadIntent(
                            revision: intent.revision,
                            targetURL: intent.targetURL,
                            policy: policy
                        )
                    ),
                    webView
                )
                switch schedulingOutcome {
                case .scheduled:
                    dispositions.append(.waiting(owner))
                    continue
                case .notProtected:
                    tab.mainFrameLoads.clearDeferredLoad(on: webView, intent: intent)
                case .invalidTarget, .droppedAtCapacity:
                    tab.mainFrameLoads.clearDeferredLoad(on: webView, intent: intent)
                    dispositions.append(.failed(PageReloadFailure(
                        intent: intent,
                        webViewID: ObjectIdentifier(webView),
                        reason: .protectedDeliveryRejected
                    )))
                    continue
                }
            }
            dispositions.append(contentsOf: tab.navigationCommandOwner
                .submitExactReload(
                    on: webView,
                    tab: tab,
                    intent: intent,
                    policy: policy
                ).dispositions)
        }
        return PageReloadCommandOutcome(dispositions: dispositions)
    }

    @discardableResult
    func reloadTab(
        _ tab: Tab,
        in windowId: UUID,
        intent: TabMainFrameNavigationIntent,
        policy: WebRuntimeMainFrameReloadPolicy
    ) -> PageReloadCommandOutcome {
        guard tab.mainFrameLoads.isCurrent(intent) else {
            return .failed(intent: intent, reason: .staleAttempt)
        }
        guard let webView = webViewSessions.webView(for: tab.id, in: windowId) else {
            return .failed(intent: intent, reason: .noResidence)
        }
        if isWebViewProtectedFromCompositorMutation(webView) {
            RuntimeDiagnostics.protectedWebViewTrace(
                "deferReloadProtected webView=\(ObjectIdentifier(webView)) tab=\(tab.id.uuidString.prefix(8)) window=\(windowId.uuidString.prefix(8))"
            )
            let admission = tab.mainFrameLoads.deferAttempt(
                on: webView,
                intent: intent
            )
            let owner: TabMainFramePendingAttemptOwner
            switch admission {
            case .waiting(let admittedOwner):
                owner = admittedOwner
            case .coalesced(let admittedOwner):
                return PageReloadCommandOutcome(.coalesced(admittedOwner))
            case .rejected:
                return .failed(
                    intent: intent,
                    webView: webView,
                    reason: .protectedDeliveryRejected
                )
            }
            let schedulingOutcome = deferProtectedNavigation(
                .reloadTrackedNavigation(
                    webViewID: ObjectIdentifier(webView),
                    tabID: tab.id,
                    windowID: windowId,
                    intent: DeferredWebViewReloadIntent(
                        revision: intent.revision,
                        targetURL: intent.targetURL,
                        policy: policy
                    )
                ),
                webView
            )
            switch schedulingOutcome {
            case .scheduled:
                return PageReloadCommandOutcome(.waiting(owner))
            case .notProtected:
                tab.mainFrameLoads.clearDeferredLoad(
                    on: webView,
                    intent: intent
                )
            case .invalidTarget, .droppedAtCapacity:
                tab.mainFrameLoads.clearDeferredLoad(
                    on: webView,
                    intent: intent
                )
                return .failed(
                    intent: intent,
                    webView: webView,
                    reason: .protectedDeliveryRejected
                )
            }
        }
        return tab.navigationCommandOwner.submitExactReload(
            on: webView,
            tab: tab,
            intent: intent,
            policy: policy
        )
    }

    func setMuteState(_ muted: Bool, for tabId: UUID) {
        crossWindowSyncOwner.setMuteState(
            muted,
            for: tabId,
            windowWebViews: webViewSessions.windowWebViews(for: tabId)
        )
    }
}
