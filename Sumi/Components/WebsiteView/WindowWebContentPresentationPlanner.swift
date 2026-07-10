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
    case single(tab: Tab?, repairSplitGroupID: UUID?)
    case split(group: SplitGroup, tabs: [Tab])
}

@MainActor
final class WindowWebContentPresentationPlanner {
    private let browserContext: any WindowWebContentBrowserContext
    private let windowID: UUID
    private let containerView: WindowWebContentSplitHostLayoutView
    private let hostRegistry: WindowWebContentHostRegistry
    private let protectionRuntime: WebViewProtectionRuntime

    init(
        browserContext: any WindowWebContentBrowserContext,
        windowID: UUID,
        containerView: WindowWebContentSplitHostLayoutView,
        hostRegistry: WindowWebContentHostRegistry,
        protectionRuntime: WebViewProtectionRuntime
    ) {
        self.browserContext = browserContext
        self.windowID = windowID
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
        guard let group = displayState.activeSplitGroup else {
            return .single(tab: currentTab, repairSplitGroupID: nil)
        }

        let tabs = group.tabIds.compactMap(browserContext.tab(for:))
        guard tabs.count == group.tabIds.count else {
            return .single(tab: currentTab, repairSplitGroupID: group.id)
        }
        return .split(group: group, tabs: tabs)
    }

    func immediatePresentationDecision(
        currentTab: Tab?
    ) -> WindowWebContentPresentationDecision? {
        guard !protectionRuntime.hasActiveHistorySwipe(in: windowID),
              let currentTab,
              currentTab.requiresPrimaryWebView
        else {
            return nil
        }

        if let group = browserContext.splitGroup(for: windowID),
           group.contains(currentTab.id) {
            let tabs = group.tabIds.compactMap(browserContext.tab(for:))
            guard tabs.count == group.tabIds.count else { return nil }
            return .split(group: group, tabs: tabs)
        }
        return .single(tab: currentTab, repairSplitGroupID: nil)
    }

    func incomingTabIDsForVisualHandoff(
        _ decision: WindowWebContentPresentationDecision
    ) -> Set<UUID>? {
        switch decision {
        case .single(let tab, _):
            guard let tab,
                  tab.requiresPrimaryWebView,
                  hostRegistry.displayedHost(for: tab.id) == nil
            else {
                return nil
            }
            return [tab.id]
        case .split(let group, _):
            return Set(group.tabIds)
        }
    }

    private func hasStaleHostedWebViews(
        currentTab: Tab?,
        displayState: WebsiteDisplayState
    ) -> Bool {
        guard !protectionRuntime.hasActiveHistorySwipe(in: windowID) else {
            return false
        }

        guard let activeSplitGroup = displayState.activeSplitGroup else {
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
            !activeSplitGroup.contains($0)
        }
    }
}
