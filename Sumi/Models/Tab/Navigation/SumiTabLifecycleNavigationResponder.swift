import Foundation
import Navigation
import WebKit

@MainActor
final class SumiTabLifecycleNavigationResponder: NavigationResponder {
    private weak var tab: Tab?

    init(tab: Tab) {
        self.tab = tab
    }

    func willStart(_ navigation: Navigation) {
        guard let tab,
              navigation.navigationAction.isForMainFrame,
              let webView = webView(for: navigation)
        else { return }

        if navigation.navigationAction.navigationType.isBackForward {
            tab.beginBackForwardNavigationTracking(on: webView)
        } else {
            tab.markRegularMainFrameNavigation(on: webView)
        }

        if let url = navigation.request.url {
            tab.browserManager?.extensionManager.prepareWebViewForExtensionRuntime(
                webView,
                currentURL: url,
                reason: "SumiTabLifecycleNavigationResponder.willStart"
            )
            tab.browserManager?.sumiScriptsManager.installContentController(
                webView.configuration.userContentController,
                for: url,
                webViewId: tab.id,
                profileId: tab.resolveProfile()?.id ?? tab.profileId,
                isEphemeral: tab.isEphemeral
            )
        }
    }

    func didStart(_ navigation: Navigation) {
        guard let tab,
              navigation.navigationAction.isForMainFrame,
              let webView = webView(for: navigation)
        else { return }

        tab.loadingState = .didStartProvisionalNavigation
        tab.browserManager?.extensionManager.notifyTabPropertiesChanged(tab, properties: [.loading])

        if let newURL = webView.url {
            if newURL.absoluteString != tab.url.absoluteString {
                tab.resetPlaybackActivity()
                tab.url = newURL
                tab.applyCachedFaviconOrPlaceholder(for: newURL)
                tab.faviconsTabExtension?.loadCachedFavicon(previousURL: nil, error: nil)
            } else {
                tab.url = newURL
            }
        }
    }

    func didCommit(_ navigation: Navigation) {
        guard let tab,
              navigation.navigationAction.isForMainFrame,
              let webView = webView(for: navigation)
        else { return }

        tab.loadingState = .didCommit
        tab.browserManager?.extensionManager.notifyTabPropertiesChanged(tab, properties: [.loading])

        if let newURL = webView.url {
            tab.url = newURL
            tab.noteCommittedMainDocumentNavigation(to: newURL)
            tab.historyRecorder.didCommitMainFrameNavigation(
                to: newURL,
                kind: tab.pendingMainFrameNavigationKind == .backForward ? .backForward : .regular,
                tab: tab
            )
            tab.browserManager?.extensionManager.markTabEligibleAfterCommittedNavigation(
                tab,
                reason: "SumiTabLifecycleNavigationResponder.didCommit"
            )
            if tab.pendingMainFrameNavigationKind != .backForward {
                tab.browserManager?.syncTabAcrossWindows(tab.id, originatingWebView: webView)
            }
            tab.browserManager?.extensionManager.notifyTabPropertiesChanged(tab, properties: [.URL, .loading])
        }

        NotificationCenter.default.post(
            name: .sumiTabNavigationStateDidChange,
            object: tab,
            userInfo: ["tabId": tab.id]
        )
    }

    func navigationDidFinish(_ navigation: Navigation) {
        guard let tab,
              navigation.navigationAction.isForMainFrame,
              let webView = webView(for: navigation)
        else { return }

        tab.loadingState = .didFinish
        tab.browserManager?.extensionManager.notifyTabPropertiesChanged(tab, properties: [.loading])

        if let newURL = webView.url {
            tab.url = newURL
            tab.browserManager?.loadZoomForTab(tab.id)
            tab.faviconsTabExtension?.loadCachedFavicon(previousURL: nil, error: nil)
        }

        tab.updateNavigationState()
        let resolvedTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if webView.url != nil {
            tab.historyRecorder.updateTitle(resolvedTitle, tab: tab)
        }
        tab.browserManager?.tabManager.scheduleRuntimeStatePersistence(for: tab)
        if tab.pendingMainFrameNavigationKind == .backForward {
            tab.finishBackForwardNavigationTracking(using: webView)
            tab.browserManager?.syncTabAcrossWindows(tab.id, originatingWebView: webView)
        } else {
            tab.pendingMainFrameNavigationKind = nil
        }

        tab.injectLinkHoverJavaScript(to: webView)
        if let currentURL = webView.url {
            tab.browserManager?.sumiScriptsManager.injectDocumentIdleScripts(for: webView, url: currentURL)
        }

        if tab.audioState.isMuted {
            tab.setMuted(true)
        }

        SumiNativeNowPlayingController.shared.scheduleRefresh(delayNanoseconds: 0)
    }

    func navigation(_ navigation: Navigation, didSameDocumentNavigationOf navigationType: WKSameDocumentNavigationType) {
        guard let tab,
              let webView = webView(for: navigation),
              let newURL = webView.url
        else { return }

        tab.handleSameDocumentNavigation(to: newURL)
        tab.historyRecorder.didSameDocumentNavigation(to: newURL, type: navigationType, tab: tab)
        if tab.pendingMainFrameNavigationKind == .backForward {
            tab.scheduleBackForwardSameDocumentSettle(using: webView)
        } else {
            tab.browserManager?.tabManager.scheduleRuntimeStatePersistence(for: tab)
            tab.browserManager?.syncTabAcrossWindows(tab.id, originatingWebView: webView)
            tab.pendingMainFrameNavigationKind = nil
        }

        tab.browserManager?.extensionManager.notifyTabPropertiesChanged(tab, properties: [.URL])
    }

    func navigation(_ navigation: Navigation, didFailWith error: WKError) {
        guard let tab,
              navigation.navigationAction.isForMainFrame
        else { return }

        let webView = webView(for: navigation)
        tab.loadingState = .didFail(error)
        tab.finishBackForwardNavigationTracking(using: webView)
        tab.updateNavigationState()
        tab.browserManager?.extensionManager.notifyTabPropertiesChanged(tab, properties: [.loading])
    }

    func didReceive(
        _ authenticationChallenge: URLAuthenticationChallenge,
        for _: Navigation?
    ) async -> AuthChallengeDisposition? {
        guard let tab,
              let authenticationManager = tab.browserManager?.authenticationManager
        else { return .next }

        return await withCheckedContinuation { continuation in
            let handled = authenticationManager.handleAuthenticationChallenge(authenticationChallenge, for: tab) { disposition, credential in
                switch disposition {
                case .useCredential:
                    if let credential {
                        continuation.resume(returning: .credential(credential))
                    } else {
                        continuation.resume(returning: .next)
                    }
                case .cancelAuthenticationChallenge:
                    continuation.resume(returning: .cancel)
                case .rejectProtectionSpace:
                    continuation.resume(returning: .rejectProtectionSpace)
                default:
                    continuation.resume(returning: .next)
                }
            }

            if !handled {
                continuation.resume(returning: .next)
            }
        }
    }

    private func webView(for navigation: Navigation) -> WKWebView? {
        navigation.navigationAction.targetFrame?.webView
            ?? navigation.navigationAction.sourceFrame.webView
    }
}
