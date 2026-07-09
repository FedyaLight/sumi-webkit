//
//  WebViewDestructiveCleanupFlowOwner.swift
//  Sumi
//
//  Owns the destructive browsing-data cleanup preparation flow: scanning the
//  affected profiles' live WebViews and tracking navigation suppression until
//  each WebView finishes its cleanup navigation.
//

import Foundation
import WebKit

@MainActor
final class WebViewDestructiveCleanupFlowOwner {
    struct Dependencies {
        let browserRuntimeContext: @MainActor () -> WebViewCoordinatorBrowserRuntimeContext
        let liveWebViews: @MainActor (Tab) -> [WKWebView]
        let isWebViewProtectedFromCompositorMutation: @MainActor (WKWebView) -> Bool
    }

    private struct PreparationResult {
        var preparedWebViewCount = 0
        var skippedProtectedWebViewCount = 0
    }

    private let dependencies: Dependencies
    private var blankingWebViewIDs: Set<ObjectIdentifier> = []

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func isSuppressingNavigation(on webView: WKWebView) -> Bool {
        blankingWebViewIDs.contains(ObjectIdentifier(webView))
    }

    func finishNavigationSuppression(on webView: WKWebView) {
        finishNavigationSuppression(webViewID: ObjectIdentifier(webView))
    }

    func finishNavigationSuppression(for webViewIDs: [ObjectIdentifier]) {
        guard webViewIDs.isEmpty == false else { return }
        for webViewID in webViewIDs {
            finishNavigationSuppression(webViewID: webViewID)
        }
    }

    func prepareForDestructiveDataCleanup(profileIDs: Set<UUID>) {
        guard !profileIDs.isEmpty else { return }
        let runtimeContext = dependencies.browserRuntimeContext()

        let preparationResult = prepareLiveWebViews(
            pinnedTabs: runtimeContext.pinnedTabs(),
            tabs: runtimeContext.regularTabs(),
            profileIDs: profileIDs
        )

        RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
            "Prepared \(preparationResult.preparedWebViewCount) live WebView(s) for destructive data cleanup across \(profileIDs.count) profile(s); skipped \(preparationResult.skippedProtectedWebViewCount) protected WebView(s)."
        }
    }

    // MARK: - Navigation suppression

    func beginNavigationSuppression(on webView: WKWebView) {
        blankingWebViewIDs.insert(ObjectIdentifier(webView))
    }

    func finishNavigationSuppression(webViewID: ObjectIdentifier) {
        blankingWebViewIDs.remove(webViewID)
    }

    // MARK: - Preparation

    private func prepareLiveWebViews(
        pinnedTabs: [Tab],
        tabs: [Tab],
        profileIDs: Set<UUID>
    ) -> PreparationResult {
        var seenTabIDs = Set<UUID>()
        var result = PreparationResult()

        func visit(_ tab: Tab) {
            guard seenTabIDs.insert(tab.id).inserted else { return }
            guard isTabEligible(tab, profileIDs: profileIDs) else { return }

            let tabLiveWebViews = dependencies.liveWebViews(tab)
            let eligibleWebViews = tabLiveWebViews.filter { webView in
                dependencies.isWebViewProtectedFromCompositorMutation(webView) == false
            }
            guard !eligibleWebViews.isEmpty else {
                result.skippedProtectedWebViewCount += tabLiveWebViews.count
                return
            }

            tab.cancelPendingMainFrameNavigation()
            for webView in eligibleWebViews {
                prepare(webView, tab: tab)
                result.preparedWebViewCount += 1
            }
        }

        pinnedTabs.forEach(visit)
        tabs.forEach(visit)

        return result
    }

    private func prepare(_ webView: WKWebView, tab: Tab) {
        tab.stopLoading(on: webView)
        webView.pauseAllMediaPlayback(completionHandler: nil)

        if webView.cameraCaptureState != .none {
            webView.setCameraCaptureState(.none, completionHandler: nil)
        }
        if webView.microphoneCaptureState != .none {
            webView.setMicrophoneCaptureState(.none, completionHandler: nil)
        }

        guard webView.url?.absoluteString != SumiSurface.emptyTabURL.absoluteString else {
            finishNavigationSuppression(on: webView)
            return
        }

        beginNavigationSuppression(on: webView)
        if webView.load(URLRequest(url: SumiSurface.emptyTabURL)) == nil {
            finishNavigationSuppression(on: webView)
        }
    }

    private func isTabEligible(_ tab: Tab, profileIDs: Set<UUID>) -> Bool {
        guard let profileId = tab.resolveProfile()?.id ?? tab.profileId else {
            return false
        }
        return profileIDs.contains(profileId)
            && tab.representsSumiNativeSurface == false
    }
}

extension WebViewDestructiveCleanupFlowOwner.Dependencies {
    @MainActor
    static func live(coordinator: WebViewCoordinator) -> Self {
        Self(
            browserRuntimeContext: { [weak coordinator] in
                guard let coordinator else {
                    preconditionFailure(
                        "WebViewDestructiveCleanupFlowOwner outlived its coordinator"
                    )
                }
                return coordinator.runtimeContextStore.requireBrowser()
            },
            liveWebViews: { [weak coordinator] tab in
                coordinator?.suspensionLiveWebViews(for: tab) ?? []
            },
            isWebViewProtectedFromCompositorMutation: { [weak coordinator] webView in
                coordinator?.isWebViewProtectedFromCompositorMutation(webView) ?? false
            }
        )
    }
}
