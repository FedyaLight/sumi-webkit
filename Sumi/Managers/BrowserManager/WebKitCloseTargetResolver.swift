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
    private let lifecycle: WebViewLifecycleService
    private let ownership: WebViewOwnershipQuery
    private let membership: TabCollectionMembershipOwner
    private let residences: BrowserTabResidenceAuthority
    private let windowTabs: BrowserWindowTabContext
    private let routing: BrowserWebViewRoutingService
    private let registry: @MainActor () -> WindowRegistry?

    init(
        lifecycle: WebViewLifecycleService,
        ownership: WebViewOwnershipQuery,
        membership: TabCollectionMembershipOwner,
        residences: BrowserTabResidenceAuthority,
        windowTabs: BrowserWindowTabContext,
        routing: BrowserWebViewRoutingService,
        registry: @escaping @MainActor () -> WindowRegistry?
    ) {
        self.lifecycle = lifecycle
        self.ownership = ownership
        self.membership = membership
        self.residences = residences
        self.windowTabs = windowTabs
        self.routing = routing
        self.registry = registry
    }

    func resolve(_ webView: WKWebView) -> WebKitCloseTarget {
        switch lifecycle.prepareWebKitClose(webView) {
        case .deferred:
            return .deferred
        case .ready(let trackedOwner):
            guard let trackedOwner else {
                return resolveUntracked(webView)
            }
            guard ownership.trackedOwner(containing: webView) == trackedOwner,
                  let window = registry()?.windows[trackedOwner.windowID],
                  let tab = window.ephemeralTabs.first(where: {
                      $0.id == trackedOwner.tabID
                  }) ?? membership.tab(for: trackedOwner.tabID),
                  residences.containsExact(tab, in: window),
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

        guard let tab = membership.allTabs().first(
            where: { routing.ownsLiveWebView(webView, for: $0) }
        ) else {
            return .orphan
        }
        return .untracked(UntrackedWebKitCloseTarget(
            webView: webView,
            tab: tab,
            window: windowTabs.windowState(containing: tab)
        ))
    }
}
