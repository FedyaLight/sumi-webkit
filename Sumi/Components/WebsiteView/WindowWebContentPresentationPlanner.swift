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

enum WindowWebContentPresentationDecision {
    case single(tab: Tab?)
    case split(presentation: WindowSplitPresentation, tabs: [Tab])
}

@MainActor
final class WindowWebContentPresentationPlanner {
    private let browserContext: any WindowWebContentBrowserContext
    private let splitQuery: WindowSplitQuery
    private let windowState: BrowserWindowState
    private let containerView: WindowWebContentSplitHostLayoutView
    private let hostRegistry: WindowWebContentHostRegistry
    private let protectionRuntime: WebViewProtectionRuntime

    init(
        browserContext: any WindowWebContentBrowserContext,
        splitQuery: WindowSplitQuery,
        windowState: BrowserWindowState,
        containerView: WindowWebContentSplitHostLayoutView,
        hostRegistry: WindowWebContentHostRegistry,
        protectionRuntime: WebViewProtectionRuntime
    ) {
        self.browserContext = browserContext
        self.splitQuery = splitQuery
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
            || hasStaleHostedWebViews(currentTab: currentTab, displayState: displayState)
    }

    func presentationDecision(
        for displayState: WebsiteDisplayState,
        currentTab: Tab?
    ) -> WindowWebContentPresentationDecision {
        guard let presentation = displayState.activeSplitPresentation else {
            return .single(tab: currentTab)
        }

        let tabs = presentation.visibleTabIDs.compactMap(browserContext.tab(for:))
        guard tabs.count == presentation.visibleTabIDs.count else {
            return .single(tab: currentTab)
        }
        return .split(presentation: presentation, tabs: tabs)
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

        if case .ready(let presentation) = splitQuery.resolution(
            in: windowState.id
        ),
           presentation.activeTabID == currentTab.id {
            let tabs = presentation.visibleTabIDs.compactMap(browserContext.tab(for:))
            guard tabs.count == presentation.visibleTabIDs.count else { return nil }
            return .split(presentation: presentation, tabs: tabs)
        }
        return .single(tab: currentTab)
    }

    func incomingTabIDsForVisualHandoff(
        _ decision: WindowWebContentPresentationDecision
    ) -> Set<UUID>? {
        switch decision {
        case .single(let tab):
            guard let tab,
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

        guard let activeSplitPresentation = displayState.activeSplitPresentation else {
            let expectedCount = currentTab != nil && !displayState.currentTabUnloaded ? 1 : 0
            if hostedWebViewCount(
                in: containerView.singlePaneView,
                stoppingAfter: expectedCount
            ) > expectedCount {
                return true
            }
            return containerView.hasHostedSplitWebViews
        }

        if hostedWebViewCount(in: containerView.singlePaneView, stoppingAfter: 0) > 0 {
            return true
        }
        return hostRegistry.splitPaneTabIds.contains {
            !activeSplitPresentation.contains(tabID: $0)
        }
    }
}
