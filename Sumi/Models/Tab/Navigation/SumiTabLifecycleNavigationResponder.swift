import Foundation
import WebKit

@MainActor
final class SumiTabLifecycleNavigationResponder:
    SumiNavigationStartResponding,
    SumiNavigationResponseResponding,
    SumiNavigationCommitResponding,
    SumiNavigationCompletionResponding,
    SumiSameDocumentNavigationResponding,
    SumiNavigationAuthChallengeResponding {
    private weak var tab: Tab?

    init(tab: Tab) {
        self.tab = tab
    }

    func navigationWillStart(_ context: SumiNavigationContext) {
        guard let tab,
              context.isMainFrame == true,
              let webView = context.webView
        else { return }

        if context.action?.navigationType.isBackForward == true {
            tab.beginBackForwardNavigationTracking(on: webView)
        } else {
            tab.handleNormalTabPermissionNavigation(to: context.url)
            tab.markRegularMainFrameNavigation(on: webView)
        }
        tab.resetPageSuspensionRuntimeState()
        tab.browserManager?.tabSuspensionService.resetRevisitProtection(for: tab)

        if let url = context.url {
            tab.browserManager?.extensionsModule.prepareWebViewForExtensionRuntime(
                webView,
                currentURL: url,
                reason: "SumiTabLifecycleNavigationResponder.willStart"
            )
        }
    }

    func navigationDidStart(_ context: SumiNavigationContext) {
        guard let tab,
              context.isMainFrame == true,
              let webView = context.webView
        else { return }

        tab.beginLoadingPresentationIfNeeded()
        tab.browserManager?.extensionsModule.notifyTabPropertiesChangedIfLoaded(tab, properties: [.loading])

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

    func decidePolicy(for response: SumiNavigationResponse) async -> SumiNavigationResponsePolicy? {
        guard let tab,
              response.isForMainFrame
        else { return .next }

        tab.isDisplayingPDFDocument =
            response.mimeType?.lowercased() == "application/pdf"
        return .next
    }

    func navigationDidCommit(_ context: SumiNavigationContext) {
        guard let tab,
              context.isMainFrame == true,
              let webView = context.webView
        else { return }

        tab.loadingState = .didCommit
        tab.browserManager?.extensionsModule.notifyTabPropertiesChangedIfLoaded(tab, properties: [.loading])

        if let newURL = webView.url {
            tab.url = newURL
            if tab.pendingMainFrameNavigationKind == .backForward {
                tab.handleNormalTabPermissionNavigation(to: newURL)
            }
            tab.noteCommittedMainDocumentNavigation(to: newURL)
            tab.clearTrackingProtectionReloadRequirementIfResolved(for: newURL)
            tab.clearAutoplayReloadRequirementIfResolved(for: newURL)
            tab.historyRecorder.didCommitMainFrameNavigation(
                to: newURL,
                kind: tab.pendingMainFrameNavigationKind == .backForward ? .backForward : .regular,
                tab: tab
            )
            tab.browserManager?.extensionsModule.markTabEligibleAfterCommittedNavigationIfLoaded(
                tab,
                reason: "SumiTabLifecycleNavigationResponder.didCommit"
            )
            if tab.pendingMainFrameNavigationKind != .backForward {
                tab.browserManager?.syncTabAcrossWindows(tab.id, originatingWebView: webView)
            }
            tab.browserManager?.extensionsModule.notifyTabPropertiesChangedIfLoaded(tab, properties: [.URL, .loading])
        }

        NotificationCenter.default.post(
            name: .sumiTabNavigationStateDidChange,
            object: tab,
            userInfo: ["tabId": tab.id]
        )
    }

    func navigationDidFinish(_ context: SumiNavigationContext?) {
        guard let tab,
              context?.isMainFrame == true,
              let webView = context?.webView
        else { return }

        tab.loadingState = .didFinish
        tab.browserManager?.extensionsModule.notifyTabPropertiesChangedIfLoaded(tab, properties: [.loading])

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

        if tab.audioState.isMuted {
            tab.setMuted(true)
        }

        tab.browserManager?.enforceSiteDataPolicyAfterNavigation(for: tab)
    }

    func navigationDidSameDocumentNavigation(
        type navigationType: SumiSameDocumentNavigationType,
        context: SumiNavigationContext?
    ) {
        guard let tab,
              let webView = context?.webView,
              let newURL = webView.url
        else { return }

        tab.handleSameDocumentNavigation(to: newURL)
        tab.historyRecorder.didSameDocumentNavigation(
            to: newURL,
            type: navigationType,
            tab: tab
        )
        if tab.pendingMainFrameNavigationKind == .backForward {
            tab.scheduleBackForwardSameDocumentSettle(using: webView)
        } else {
            tab.browserManager?.tabManager.scheduleRuntimeStatePersistence(for: tab)
            tab.browserManager?.syncTabAcrossWindows(tab.id, originatingWebView: webView)
            tab.pendingMainFrameNavigationKind = nil
        }

        tab.browserManager?.extensionsModule.notifyTabPropertiesChangedIfLoaded(tab, properties: [.URL])
    }

    func navigationDidFail(_ error: WKError, context: SumiNavigationContext?) {
        guard let tab,
              context?.isMainFrame == true
        else { return }

        let webView = context?.webView
        let isBackForwardNavigation = context?.action?.navigationType.isBackForward == true
        if isBackForwardNavigation {
            tab.finishBackForwardNavigationTracking(using: webView)
        }

        if error.sumiIsNavigationCancelled {
            if tab.loadingState.isLoading {
                tab.loadingState = .idle
            }
            tab.updateNavigationState()
            tab.browserManager?.extensionsModule.notifyTabPropertiesChangedIfLoaded(tab, properties: [.loading])
            return
        }

        guard context?.isCurrent == true else { return }

        tab.loadingState = .didFail(error)
        if !isBackForwardNavigation {
            tab.finishBackForwardNavigationTracking(using: webView)
        }
        tab.updateNavigationState()
        tab.browserManager?.extensionsModule.notifyTabPropertiesChangedIfLoaded(tab, properties: [.loading])
    }

    func didReceive(
        _ authenticationChallenge: URLAuthenticationChallenge,
        context _: SumiNavigationContext?
    ) async -> SumiAuthChallengeDisposition? {
        await sumiAuthChallengeDisposition(for: authenticationChallenge)
    }

    func didReceive(_ authenticationChallenge: URLAuthenticationChallenge) async -> SumiAuthChallengeDisposition? {
        await didReceive(authenticationChallenge, context: nil)
    }

    private func sumiAuthChallengeDisposition(
        for authenticationChallenge: URLAuthenticationChallenge
    ) async -> SumiAuthChallengeDisposition? {
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
}

private extension WKError {
    var sumiIsNavigationCancelled: Bool {
        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
