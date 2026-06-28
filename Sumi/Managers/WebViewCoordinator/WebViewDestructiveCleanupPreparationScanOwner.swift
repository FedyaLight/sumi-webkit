//
//  WebViewDestructiveCleanupPreparationScanOwner.swift
//  Sumi
//
//  Owns destructive browsing-data cleanup preparation scanning policy.
//

import Foundation
import WebKit

@MainActor
final class WebViewDestructiveCleanupPreparationScanOwner {
    typealias LiveWebViewsResolver = (Tab) -> [WKWebView]
    typealias CompositorMutationProtectionChecker = (WKWebView) -> Bool

    struct PreparationResult {
        var preparedWebViewCount = 0
        var skippedProtectedWebViewCount = 0
    }

    func prepare(
        pinnedTabs: [Tab],
        tabs: [Tab],
        profileIDs: Set<UUID>,
        liveWebViews: LiveWebViewsResolver,
        isWebViewProtectedFromCompositorMutation: CompositorMutationProtectionChecker,
        cleanupPreparationOwner: WebViewDestructiveCleanupPreparationOwner
    ) -> PreparationResult {
        var seenTabIDs = Set<UUID>()
        var result = PreparationResult()

        func visit(_ tab: Tab) {
            guard seenTabIDs.insert(tab.id).inserted else { return }
            guard isTabEligible(tab, profileIDs: profileIDs) else { return }

            let tabLiveWebViews = liveWebViews(tab)
            let eligibleWebViews = tabLiveWebViews.filter { webView in
                isWebViewProtectedFromCompositorMutation(webView) == false
            }
            guard !eligibleWebViews.isEmpty else {
                result.skippedProtectedWebViewCount += tabLiveWebViews.count
                return
            }

            tab.cancelPendingMainFrameNavigation()
            for webView in eligibleWebViews {
                cleanupPreparationOwner.prepare(webView, tab: tab)
                result.preparedWebViewCount += 1
            }
        }

        pinnedTabs.forEach(visit)
        tabs.forEach(visit)

        return result
    }

    private func isTabEligible(_ tab: Tab, profileIDs: Set<UUID>) -> Bool {
        guard let profileId = tab.resolveProfile()?.id ?? tab.profileId else {
            return false
        }
        return profileIDs.contains(profileId)
            && tab.representsSumiNativeSurface == false
    }
}
