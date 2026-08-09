import Foundation
import SumiWebRuntime
import WebKit

struct RetiredTabWebViewGeneration {
    let tabID: UUID
    let snapshot: WebViewSessionSnapshot
}

/// Performs terminal cleanup for WebView generations whose canonical
/// repository ownership has already been committed away.
@MainActor
final class WebViewRetiredGenerationDestroyer {
    struct Runtime {
        let webViewSessions: WebViewSessionRepository
        let retireNavigationGeneration: (UUID, [WKWebView], WKWebView?) -> Void
        let destroy: (UUID, WKWebView) -> Void
        let uninstallObservationsIfUntracked: (WKWebView) -> Void
    }

    private let runtime: Runtime

    init(runtime: Runtime) {
        self.runtime = runtime
    }

    func destroy(_ snapshots: [UUID: WebViewSessionSnapshot]) {
        destroy(
            snapshots.keys.sorted(by: Self.uuidOrder).compactMap { tabID in
                snapshots[tabID].map {
                    RetiredTabWebViewGeneration(tabID: tabID, snapshot: $0)
                }
            }
        )
    }

    func destroy(
        _ generations: [RetiredTabWebViewGeneration],
        navigationTabsByID: [UUID: Tab]? = nil
    ) {
        precondition(
            generations.map(\.tabID)
                == generations.map(\.tabID).sorted(by: Self.uuidOrder),
            "Retired generations require deterministic Tab identity order"
        )
        if let navigationTabsByID {
            precondition(
                Set(generations.map(\.tabID))
                    .isSubset(of: Set(navigationTabsByID.keys)),
                "Exact retirement navigation Tabs do not cover every generation"
            )
        }
        for generation in generations {
            let webViews = orderedWebViews(in: generation.snapshot)
            let surviving = runtime.webViewSessions.snapshot(
                for: generation.tabID
            )
            let preferredWebView = preferredWebView(in: surviving)
            if let tab = navigationTabsByID?[generation.tabID] {
                tab.webViewsWillLeaveRuntime(webViews)
            } else {
                runtime.retireNavigationGeneration(
                    generation.tabID,
                    webViews,
                    preferredWebView
                )
            }
            for webView in webViews {
                runtime.uninstallObservationsIfUntracked(webView)
                runtime.destroy(generation.tabID, webView)
            }
        }
    }

    private func orderedWebViews(
        in snapshot: WebViewSessionSnapshot
    ) -> [WKWebView] {
        var seen: Set<ObjectIdentifier> = []
        var result: [WKWebView] = []
        func append(_ webView: WKWebView?) {
            guard let webView,
                  seen.insert(ObjectIdentifier(webView)).inserted else { return }
            result.append(webView)
        }

        snapshot.windowWebViews.keys.sorted(by: Self.uuidOrder).forEach {
            append(snapshot.windowWebViews[$0])
        }
        append(snapshot.untrackedWebView)
        append(snapshot.parkedWebView)
        return result
    }

    private func preferredWebView(
        in snapshot: WebViewSessionSnapshot
    ) -> WKWebView? {
        if let primaryWindowID = snapshot.primaryWindowID {
            return snapshot.windowWebViews[primaryWindowID]
        }
        return snapshot.untrackedWebView ?? snapshot.parkedWebView
    }

    private static func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}
