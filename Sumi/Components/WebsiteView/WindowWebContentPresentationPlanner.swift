import AppKit
import WebKit

@MainActor
private func hostedWebViewCount(in root: NSView, stoppingAfter limit: Int = .max) -> Int {
    var count = 0
    for subview in root.subviews {
        if subview is SumiWebViewContainerView || subview is WKWebView {
            count += 1
        } else {
            count += hostedWebViewCount(in: subview, stoppingAfter: limit - count)
        }
        if count > limit {
            return count
        }
    }
    return count
}

struct WindowWebContentPaneDecision {
    let pageID: UUID?
    let tab: Tab?
    let presentation: PagePresentation
}

enum WindowWebContentPresentationDecision {
    case single(WindowWebContentPaneDecision)
    case split(
        presentation: WindowSplitPresentation,
        panes: [WindowWebContentPaneDecision]
    )
}

@MainActor
final class WindowWebContentPresentationPlanner {
    private let browserContext: any WindowWebContentBrowserContext
    private let splitQuery: WindowSplitQuery
    private let webViewOwnershipQuery: WebViewOwnershipQuery
    private let windowState: BrowserWindowState
    private let containerView: WindowWebContentSplitHostLayoutView
    private let hostRegistry: WindowWebContentHostRegistry
    private let protectionRuntime: WebViewProtectionRuntime

    init(
        browserContext: any WindowWebContentBrowserContext,
        splitQuery: WindowSplitQuery,
        webViewOwnershipQuery: WebViewOwnershipQuery,
        windowState: BrowserWindowState,
        containerView: WindowWebContentSplitHostLayoutView,
        hostRegistry: WindowWebContentHostRegistry,
        protectionRuntime: WebViewProtectionRuntime
    ) {
        self.browserContext = browserContext
        self.splitQuery = splitQuery
        self.webViewOwnershipQuery = webViewOwnershipQuery
        self.windowState = windowState
        self.containerView = containerView
        self.hostRegistry = hostRegistry
        self.protectionRuntime = protectionRuntime
    }

    func needsDisplayStateApply(
        appliedDisplayState: WebsiteDisplayState?,
        displayState: WebsiteDisplayState,
        currentTab: Tab?
    ) -> Bool {
        appliedDisplayState != displayState
            || hasStaleHostedWebViews(
                currentTab: currentTab,
                displayState: displayState
            )
    }

    /// Uses display state only for window topology and invalidation. Each pane
    /// is resolved again at the AppKit mutation boundary because its SwiftUI
    /// presentation can predate the WebKit lifecycle transition that queued it.
    func presentationDecision(
        for displayState: WebsiteDisplayState,
        currentTab: Tab?
    ) -> WindowWebContentPresentationDecision {
        guard let presentation = displayState.activeSplitPresentation else {
            return .single(paneDecision(for: currentTab?.id))
        }
        return .split(
            presentation: presentation,
            panes: presentation.visibleTabIDs.map(paneDecision(for:))
        )
    }

    func immediatePresentationDecision(
        currentTab: Tab?
    ) -> WindowWebContentPresentationDecision? {
        guard !protectionRuntime.hasActiveHistorySwipe(in: windowState.id),
              let currentTab,
              currentTab.requiresPrimaryWebView
        else {
            return nil
        }

        let decision: WindowWebContentPresentationDecision
        if case .ready(let presentation) = splitQuery.resolution(
            in: windowState.id
        ), presentation.activeTabID == currentTab.id {
            decision = .split(
                presentation: presentation,
                panes: presentation.visibleTabIDs.map(paneDecision(for:))
            )
        } else {
            decision = .single(paneDecision(for: currentTab.id))
        }
        guard decision.hasOnlyLivePanes else { return nil }
        return decision
    }

    func incomingTabIDsForVisualHandoff(
        _ decision: WindowWebContentPresentationDecision
    ) -> Set<UUID>? {
        switch decision {
        case .single(let pane):
            guard let tab = pane.tab,
                  tab.requiresPrimaryWebView,
                  hostRegistry.displayedHost(for: tab.id) == nil
            else {
                return nil
            }
            return [tab.id]
        case .split(let presentation, _):
            return Set(presentation.visibleTabIDs)
        }
    }

    private func hasStaleHostedWebViews(
        currentTab: Tab?,
        displayState: WebsiteDisplayState
    ) -> Bool {
        guard !protectionRuntime.hasActiveHistorySwipe(in: windowState.id) else {
            return false
        }

        switch presentationDecision(
            for: displayState,
            currentTab: currentTab
        ) {
        case .single(let pane):
            let expectedCount = pane.presentation.hasLiveWebContentResidence ? 1 : 0
            if hostedWebViewCount(
                in: containerView.singlePaneView,
                stoppingAfter: expectedCount
            ) > expectedCount {
                return true
            }
            return containerView.hasHostedSplitWebViews
        case .split(let presentation, _):
            if hostedWebViewCount(
                in: containerView.singlePaneView,
                stoppingAfter: 0
            ) > 0 {
                return true
            }
            return hostRegistry.splitPaneTabIds.contains {
                !presentation.contains(tabID: $0)
            }
        }
    }

    private func paneDecision(for pageID: UUID?)
        -> WindowWebContentPaneDecision {
        guard let pageID else {
            return WindowWebContentPaneDecision(
                pageID: nil,
                tab: nil,
                presentation: .empty
            )
        }
        guard let tab = browserContext.tab(for: pageID) else {
            return WindowWebContentPaneDecision(
                pageID: pageID,
                tab: nil,
                presentation: .integrityFailure(pageID: pageID)
            )
        }
        let webView = webViewOwnershipQuery.webView(
            for: pageID,
            in: windowState.id
        )
        return WindowWebContentPaneDecision(
            pageID: pageID,
            tab: tab,
            presentation: PagePresentationResolver.resolve(
                tab: tab,
                windowState: windowState,
                webView: webView
            )
        )
    }
}

private extension WindowWebContentPresentationDecision {
    var hasOnlyLivePanes: Bool {
        switch self {
        case .single(let pane):
            return pane.presentation.hasLiveWebContentResidence
        case .split(_, let panes):
            return !panes.isEmpty && panes.allSatisfy {
                $0.presentation.hasLiveWebContentResidence
            }
        }
    }
}
