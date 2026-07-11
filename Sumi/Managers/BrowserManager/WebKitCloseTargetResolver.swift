import SumiWebRuntime
import WebKit

struct TrackedWebKitCloseTarget {
    let webView: WKWebView
    let owner: TrackedWebViewOwner
    let tab: Tab
    let window: BrowserWindowState
}

struct UntrackedWebKitCloseTarget {
    let webView: WKWebView
    let tab: Tab
    let window: BrowserWindowState?
}

enum WebKitCloseTarget {
    case deferred
    case tracked(TrackedWebKitCloseTarget)
    case untracked(UntrackedWebKitCloseTarget)
    case staleTracked(TrackedWebViewOwner)
    case orphan
}

@MainActor
protocol WebKitCloseTargetResolving: AnyObject {
    func resolve(_ webView: WKWebView) -> WebKitCloseTarget
}

/// Resolves the exact physical owner of a WebKit close callback before any
/// structural mutation. A stale tracked slot is never reinterpreted through a
/// process-global current Tab or window.
@MainActor
final class WebKitCloseTargetResolver: WebKitCloseTargetResolving {
    private weak var lifecycle: WebViewLifecycleService?
    private weak var ownership: WebViewOwnershipQuery?
    private weak var tabs: TabManager?
    private weak var windowTabs: BrowserWindowTabContext?
    private weak var routing: BrowserWebViewRoutingService?
    private let registry: @MainActor () -> WindowRegistry?

    init(
        lifecycle: WebViewLifecycleService,
        ownership: WebViewOwnershipQuery,
        tabs: TabManager,
        windowTabs: BrowserWindowTabContext,
        routing: BrowserWebViewRoutingService,
        registry: @escaping @MainActor () -> WindowRegistry?
    ) {
        self.lifecycle = lifecycle
        self.ownership = ownership
        self.tabs = tabs
        self.windowTabs = windowTabs
        self.routing = routing
        self.registry = registry
    }

    func resolve(_ webView: WKWebView) -> WebKitCloseTarget {
        guard let lifecycle else { return .orphan }
        switch lifecycle.prepareWebKitClose(webView) {
        case .deferred:
            return .deferred
        case .ready(let trackedOwner):
            guard let trackedOwner else {
                return resolveUntracked(webView)
            }
            guard let ownership,
                  ownership.trackedOwner(containing: webView) == trackedOwner,
                  let window = registry()?.windows[trackedOwner.windowID],
                  let tab = window.ephemeralTabs.first(where: {
                      $0.id == trackedOwner.tabID
                  }) ?? tabs?.tabCollectionMembershipOwner.tab(
                      for: trackedOwner.tabID
                  ),
                  (webView as? FocusableWKWebView)?.owningTab === tab
            else {
                return .staleTracked(trackedOwner)
            }
            return .tracked(TrackedWebKitCloseTarget(
                webView: webView,
                owner: trackedOwner,
                tab: tab,
                window: window
            ))
        }
    }

    private func resolveUntracked(_ webView: WKWebView) -> WebKitCloseTarget {
        guard let tabs, let routing else { return .orphan }
        if let windows = registry()?.allWindows {
            for window in windows {
                if let tab = window.ephemeralTabs.first(where: {
                    routing.ownsLiveWebView(webView, for: $0)
                }) {
                    return .untracked(UntrackedWebKitCloseTarget(
                        webView: webView,
                        tab: tab,
                        window: window
                    ))
                }
            }
        }

        guard let tab = tabs.tabCollectionMembershipOwner.allTabs().first(
            where: { routing.ownsLiveWebView(webView, for: $0) }
        ) else {
            return .orphan
        }
        return .untracked(UntrackedWebKitCloseTarget(
            webView: webView,
            tab: tab,
            window: windowTabs?.windowState(containing: tab)
        ))
    }
}
