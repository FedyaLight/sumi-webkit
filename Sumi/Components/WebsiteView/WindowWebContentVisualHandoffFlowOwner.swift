import AppKit
import Foundation
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
    case single(tab: Tab?, repairSplitGroupId: UUID?)
    case split(group: SplitGroup, tabs: [Tab])
}

@MainActor
final class WindowWebContentVisualHandoffFlowOwner {
    struct Runtime {
        let hasActiveHistorySwipe: () -> Bool
        let tab: (UUID) -> Tab?
        let splitGroup: () -> SplitGroup?
        let displayedHost: (UUID) -> SumiWebViewContainerView?
        let splitPaneTabIds: () -> [UUID]
        let singlePaneRoot: () -> NSView?
        let hasHostedSplitWebViews: () -> Bool
    }

    private let runtime: Runtime

    init(runtime: Runtime) {
        self.runtime = runtime
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
            return .single(tab: currentTab, repairSplitGroupId: nil)
        }

        let tabs = group.tabIds.compactMap { runtime.tab($0) }
        guard tabs.count == group.tabIds.count else {
            return .single(tab: currentTab, repairSplitGroupId: group.id)
        }

        return .split(group: group, tabs: tabs)
    }

    func immediatePresentationDecision(
        currentTab: Tab?
    ) -> WindowWebContentPresentationDecision? {
        guard !runtime.hasActiveHistorySwipe(),
              let currentTab,
              currentTab.requiresPrimaryWebView
        else {
            return nil
        }

        if let group = runtime.splitGroup(),
           group.contains(currentTab.id) {
            let tabs = group.tabIds.compactMap { runtime.tab($0) }
            guard tabs.count == group.tabIds.count else { return nil }
            return .split(group: group, tabs: tabs)
        }

        return .single(tab: currentTab, repairSplitGroupId: nil)
    }

    func incomingTabIDsForVisualHandoff(
        _ decision: WindowWebContentPresentationDecision
    ) -> Set<UUID>? {
        switch decision {
        case .single(let tab, _):
            guard let tab,
                  tab.requiresPrimaryWebView,
                  runtime.displayedHost(tab.id) == nil
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
        guard !runtime.hasActiveHistorySwipe() else {
            return false
        }

        guard let activeSplitGroup = displayState.activeSplitGroup else {
            let expected = (currentTab != nil && displayState.currentTabUnloaded == false) ? 1 : 0
            if let singlePaneRoot = runtime.singlePaneRoot(),
               hostedWebViewCount(in: singlePaneRoot, stoppingAfter: expected) > expected {
                return true
            }
            if runtime.hasHostedSplitWebViews() { return true }
            return false
        }

        if let singlePaneRoot = runtime.singlePaneRoot(),
           hostedWebViewCount(in: singlePaneRoot, stoppingAfter: 0) > 0 {
            return true
        }
        for tabId in runtime.splitPaneTabIds() where activeSplitGroup.contains(tabId) == false {
            return true
        }
        return false
    }
}
