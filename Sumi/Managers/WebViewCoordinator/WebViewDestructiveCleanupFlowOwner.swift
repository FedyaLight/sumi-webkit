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

    private let dependencies: Dependencies
    private let preparationOwner = WebViewDestructiveCleanupPreparationOwner()
    private let preparationScanOwner = WebViewDestructiveCleanupPreparationScanOwner()

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func isSuppressingNavigation(on webView: WKWebView) -> Bool {
        preparationOwner.isSuppressingNavigation(on: webView)
    }

    func finishNavigationSuppression(on webView: WKWebView) {
        preparationOwner.finishNavigationSuppression(on: webView)
    }

    func finishNavigationSuppression(for webViewIDs: [ObjectIdentifier]) {
        guard webViewIDs.isEmpty == false else { return }
        for webViewID in webViewIDs {
            preparationOwner.finishNavigationSuppression(webViewID: webViewID)
        }
    }

    func prepareForDestructiveDataCleanup(profileIDs: Set<UUID>) {
        guard !profileIDs.isEmpty else { return }
        let runtimeContext = dependencies.browserRuntimeContext()

        let preparationResult = preparationScanOwner.prepare(
            pinnedTabs: runtimeContext.pinnedTabs(),
            tabs: runtimeContext.regularTabs(),
            profileIDs: profileIDs,
            liveWebViews: { [dependencies] tab in
                dependencies.liveWebViews(tab)
            },
            isWebViewProtectedFromCompositorMutation: { [dependencies] webView in
                dependencies.isWebViewProtectedFromCompositorMutation(webView)
            },
            cleanupPreparationOwner: preparationOwner
        )

        RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
            "Prepared \(preparationResult.preparedWebViewCount) live WebView(s) for destructive data cleanup across \(profileIDs.count) profile(s); skipped \(preparationResult.skippedProtectedWebViewCount) protected WebView(s)."
        }
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
