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

    func syncTab(_ tab: any WebRuntimeTabHandle, to url: URL, originatingWebView: WKWebView?) {
        let tabId = tab.id
        guard let concreteTab = tab.concreteTab else { return }
        crossWindowSyncOwner.syncTab(
            tabId,
            to: url,
            webViews: webViewSessions.webViews(for: tabId),
            originatingWebView: originatingWebView,
            hasPendingTarget: { webView, targetURL in
                concreteTab.hasOutstandingMainFrameLoad(
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
                      let navigationIntent = concreteTab.currentMainFrameNavigationIntent(
                          matching: url
                      ), concreteTab.markDeferredMainFrameLoad(
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
                    concreteTab.clearDeferredMainFrameLoad(
                        on: webView,
                        intent: navigationIntent
                    )
                    return .executeNow
                case .invalidTarget, .droppedAtCapacity:
                    concreteTab.clearDeferredMainFrameLoad(
                        on: webView,
                        intent: navigationIntent
                    )
                    return .rejected
                }
            },
            load: { webView in
                concreteTab.performMainFrameNavigationAfterHydrationIfNeeded(
                    on: webView
                ) { resolvedWebView in
                    return WebRuntimeMainFrameLoader.load(url, on: resolvedWebView)
                }
            }
        )
    }

    func reloadTab(
        _ tab: any WebRuntimeTabHandle,
        intent: TabMainFrameNavigationIntent,
        policy: WebRuntimeMainFrameReloadPolicy
    ) {
        guard let concreteTab = tab.concreteTab,
              concreteTab.isCurrentMainFrameNavigationIntent(intent) else {
            return
        }
        let tabId = tab.id
        crossWindowSyncOwner.reloadTab(
            tabId,
            webViews: webViewSessions.webViews(for: tabId),
            isProtected: { [isWebViewProtectedFromCompositorMutation] webView in
                isWebViewProtectedFromCompositorMutation(webView)
            },
            deferProtectedReload: { [weak concreteTab, webViewSessions, deferProtectedNavigation] webView in
                guard let concreteTab,
                      case .window(let owner) = webViewSessions.residence(of: webView),
                      owner.tabID == tabId,
                      concreteTab.markDeferredMainFrameLoad(
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
                    concreteTab.clearDeferredMainFrameLoad(
                        on: webView,
                        intent: intent
                    )
                    return .executeNow
                case .invalidTarget, .droppedAtCapacity:
                    concreteTab.clearDeferredMainFrameLoad(
                        on: webView,
                        intent: intent
                    )
                    return .rejected
                }
            },
            reload: { webView in
                _ = concreteTab.navigationCommandOwner.submitExactReload(
                    on: webView,
                    tab: concreteTab,
                    intent: intent,
                    policy: policy
                )
            }
        )
    }

    @discardableResult
    func reloadTab(
        _ tab: any WebRuntimeTabHandle,
        in windowId: UUID,
        intent: TabMainFrameNavigationIntent,
        policy: WebRuntimeMainFrameReloadPolicy
    ) -> TabMainFrameReloadCommandOutcome {
        guard let concreteTab = tab.concreteTab,
              concreteTab.isCurrentMainFrameNavigationIntent(intent) else {
            return .failed
        }
        guard let webView = webViewSessions.webView(for: tab.id, in: windowId) else {
            return .failed
        }
        if isWebViewProtectedFromCompositorMutation(webView) {
            RuntimeDiagnostics.protectedWebViewTrace(
                "deferReloadProtected webView=\(ObjectIdentifier(webView)) tab=\(tab.id.uuidString.prefix(8)) window=\(windowId.uuidString.prefix(8))"
            )
            guard concreteTab.markDeferredMainFrameLoad(
                on: webView,
                intent: intent
            ) else {
                return concreteTab.hasOutstandingMainFrameLoad(
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
                concreteTab.clearDeferredMainFrameLoad(
                    on: webView,
                    intent: intent
                )
            case .invalidTarget, .droppedAtCapacity:
                concreteTab.clearDeferredMainFrameLoad(
                    on: webView,
                    intent: intent
                )
                return .failed
            }
        }
        return concreteTab.navigationCommandOwner.submitExactReload(
            on: webView,
            tab: concreteTab,
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
