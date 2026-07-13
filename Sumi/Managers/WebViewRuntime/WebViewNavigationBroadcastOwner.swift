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
    ) {
        guard tab.mainFrameLoads.isCurrent(intent) else {
            return
        }
        let tabId = tab.id
        crossWindowSyncOwner.reloadTab(
            tabId,
            webViews: webViewSessions.webViews(for: tabId),
            isProtected: { [isWebViewProtectedFromCompositorMutation] webView in
                isWebViewProtectedFromCompositorMutation(webView)
            },
            deferProtectedReload: { [weak tab, webViewSessions, deferProtectedNavigation] webView in
                guard let tab,
                      case .window(let owner) = webViewSessions.residence(of: webView),
                      owner.tabID == tabId,
                      tab.mainFrameLoads.markDeferredLoad(
                          on: webView,
                          intent: intent
                      ) else {
                    return .rejected
                }
                let schedulingOutcome = deferProtectedNavigation(
                    .reloadTrackedNavigation(
                        webViewID: ObjectIdentifier(webView),
                        tabID: tabId,
                        windowID: owner.windowID,
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
                    return .deferred
                case .notProtected:
                    tab.mainFrameLoads.clearDeferredLoad(
                        on: webView,
                        intent: intent
                    )
                    return .executeNow
                case .invalidTarget, .droppedAtCapacity:
                    tab.mainFrameLoads.clearDeferredLoad(
                        on: webView,
                        intent: intent
                    )
                    return .rejected
                }
            },
            reload: { webView in
                _ = tab.navigationCommandOwner.submitExactReload(
                    on: webView,
                    tab: tab,
                    intent: intent,
                    policy: policy
                )
            }
        )
    }

    @discardableResult
    func reloadTab(
        _ tab: Tab,
        in windowId: UUID,
        intent: TabMainFrameNavigationIntent,
        policy: WebRuntimeMainFrameReloadPolicy
    ) -> TabMainFrameReloadCommandOutcome {
        guard tab.mainFrameLoads.isCurrent(intent) else {
            return .failed
        }
        guard let webView = webViewSessions.webView(for: tab.id, in: windowId) else {
            return .failed
        }
        if isWebViewProtectedFromCompositorMutation(webView) {
            RuntimeDiagnostics.protectedWebViewTrace(
                "deferReloadProtected webView=\(ObjectIdentifier(webView)) tab=\(tab.id.uuidString.prefix(8)) window=\(windowId.uuidString.prefix(8))"
            )
            guard tab.mainFrameLoads.markDeferredLoad(
                on: webView,
                intent: intent
            ) else {
                return tab.mainFrameLoads.hasOutstandingLoad(
                    on: webView,
                    targetURL: intent.targetURL
                ) ? .scheduled : .failed
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
                return .scheduled
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
                return .failed
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
