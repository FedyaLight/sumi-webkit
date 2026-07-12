import Foundation
import SumiDomain
import WebKit

@MainActor
enum TabMainFrameLifecycleReducer {
    enum Authority {
        case navigation(
            webView: WKWebView,
            navigationID: ObjectIdentifier,
            targetURL: URL,
            isPDF: Bool
        )
        case promotion(TabMainFrameAuthorityContinuation)

        var webView: WKWebView {
            switch self {
            case .navigation(let webView, _, _, _): webView
            case .promotion(let continuation): continuation.webView
            }
        }

        var targetURL: URL {
            switch self {
            case .navigation(_, _, let targetURL, _): targetURL
            case .promotion(let continuation): continuation.targetURL
            }
        }

        var isPDF: Bool {
            switch self {
            case .navigation(_, _, _, let isPDF): isPDF
            case .promotion(let continuation): continuation.isPDF
            }
        }

        @MainActor
        func applyURL(to tab: Tab) -> Bool {
            switch self {
            case .navigation(let webView, let navigationID, let targetURL, _):
                return tab.applyAcceptedMainFrameLifecycleURL(
                    targetURL,
                    from: webView,
                    navigationID: navigationID
                )
            case .promotion(let continuation):
                return tab.applyPromotedAuthorityURL(
                    continuation.targetURL,
                    matching: continuation
                )
            }
        }
    }

    static func replayIfNeeded(
        _ continuation: TabMainFrameAuthorityContinuation,
        tab: Tab,
        promotion: any TabMainFramePromotionSettlement
    ) {
        guard tab.applyPromotedAuthorityURL(
            continuation.targetURL,
            matching: continuation
        ) else { return }

        if continuation.needsSharedCommitEffects,
           promotion.claimSharedCommitEffects(
               matching: continuation
           ) {
            let authority = Authority.promotion(continuation)
            publishCommitEffects(authority, tab: tab) {
                promotion.remainsCurrent(matching: continuation)
            }
        }
        guard continuation.needsSharedFinishEffects else { return }
        guard case .publish(let publication) =
                promotion.prepareSharedFinishPublication(
                    matching: continuation
                ) else {
            return
        }
        guard promotion.consumeFinishPublication(publication) else { return }
        if tab.url.absoluteString
            != publication.presentationURL.absoluteString {
            tab.url = publication.presentationURL
        }
        publishFinishEffects(from: publication.webView, tab: tab) {
            promotion.remainsCurrent(publication.authority)
        }
    }

    static func publishCommit(
        _ publication: TabMainFrameCommitPublication,
        tab: Tab,
        lifecycle: any TabMainFrameLifecycleSettlement
    ) {
        guard lifecycle.consumeCommitPublication(publication) else { return }
        let authority = Authority.navigation(
            webView: publication.webView,
            navigationID: publication.authority.navigationID,
            targetURL: publication.targetURL,
            isPDF: publication.isPDF
        )
        guard authority.applyURL(to: tab) else { return }
        publishCommitEffects(authority, tab: tab) {
            lifecycle.remainsCurrent(publication.authority)
        }
    }

    private static func publishCommitEffects(
        _ authority: Authority,
        tab: Tab,
        remainsCurrent: () -> Bool
    ) {
        StartupPerformanceTrace.firstNavigationCommitted()
        tab.loadingState = .didCommit
        guard remainsCurrent() else { return }
        tab.navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(
            tab,
            [.loading]
        )
        guard remainsCurrent() else { return }

        let isBackForward = tab.navigationRuntime.navigationTransactionOwner
            .pendingMainFrameNavigationKind == .backForward
        if isBackForward {
            tab.handleNormalTabPermissionNavigation(to: authority.targetURL)
            guard remainsCurrent() else { return }
        }
        tab.extensionPageRuntimeOwner.noteCommittedMainDocumentNavigation(
            to: authority.targetURL
        )
        guard remainsCurrent() else { return }
        tab.clearSafariContentBlockerReloadRequirementIfResolved(
            for: authority.targetURL
        )
        guard remainsCurrent() else { return }
        tab.clearProtectionReloadRequirementIfResolved(for: authority.targetURL)
        guard remainsCurrent() else { return }
        tab.clearAutoplayReloadRequirementIfResolved(for: authority.targetURL)
        guard remainsCurrent() else { return }
        tab.navigationRuntime.historyRecorder.didCommitMainFrameNavigation(
            to: authority.targetURL,
            kind: isBackForward ? .backForward : .regular,
            tab: tab
        )
        guard remainsCurrent() else { return }
        tab.navigationRuntime.lifecycleNavigationRuntime.markExtensionEligibleAfterCommit(
            tab,
            "TabMainFrameLifecycleReducer.commit"
        )
        guard remainsCurrent() else { return }
        if !isBackForward {
            tab.navigationRuntime.webViewRouting.syncTabAcrossWindows(
                tab.id,
                authority.webView
            )
            guard remainsCurrent() else { return }
        }
        tab.navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(
            tab,
            [.URL, .loading]
        )
        guard remainsCurrent() else { return }
        tab.stateChangeEmitter.postNavigationStateDidChange(for: tab)
    }

    static func publishFinish(
        _ publication: TabMainFrameFinishPublication,
        tab: Tab,
        lifecycle: any TabMainFrameLifecycleSettlement
    ) {
        guard lifecycle.consumeFinishPublication(publication) else { return }
        if tab.url.absoluteString
            != publication.presentationURL.absoluteString {
            tab.url = publication.presentationURL
        }
        publishFinishEffects(from: publication.webView, tab: tab) {
            lifecycle.remainsCurrent(publication.authority)
        }
    }

    static func publishSameDocument(
        _ publication: TabMainFrameSameDocumentPublication,
        navigationType: SumiSameDocumentNavigationType,
        tab: Tab,
        lifecycle: any TabMainFrameLifecycleSettlement
    ) {
        guard lifecycle.consumeSameDocumentPublication(publication) else { return }
        guard tab.publishSameDocumentPresentation(
            to: publication.presentationURL,
            remainsCurrent: {
                lifecycle.remainsCurrent(publication.authority)
            }
        ) else { return }
        tab.navigationRuntime.historyRecorder.didSameDocumentNavigation(
            to: publication.presentationURL,
            type: navigationType,
            tab: tab
        )
        guard lifecycle.remainsCurrent(publication.authority) else { return }
        if tab.navigationRuntime.navigationTransactionOwner
            .pendingMainFrameNavigationKind == .backForward {
            tab.scheduleBackForwardSameDocumentSettle(
                using: publication.webView
            )
            guard lifecycle.remainsCurrent(publication.authority) else {
                return
            }
        } else {
            tab.navigationRuntime.persistenceCallbacks
                .scheduleRuntimeStatePersistence(tab)
            guard lifecycle.remainsCurrent(publication.authority) else {
                return
            }
            tab.navigationRuntime.webViewRouting.syncTabAcrossWindows(
                tab.id,
                publication.webView
            )
            guard lifecycle.remainsCurrent(publication.authority) else {
                return
            }
            tab.navigationRuntime.navigationTransactionOwner
                .pendingMainFrameNavigationKind = nil
        }
        tab.navigationRuntime.extensionPropertiesRuntime
            .notifyTabPropertiesChanged(tab, [.URL])
    }

    private static func publishFinishEffects(
        from webView: WKWebView,
        tab: Tab,
        remainsCurrent: () -> Bool
    ) {
        StartupPerformanceTrace.firstNavigationFinished()
        tab.loadingState = .didFinish
        guard remainsCurrent() else { return }
        tab.navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(
            tab,
            [.loading]
        )
        guard remainsCurrent() else { return }
        tab.refreshFaviconExtensionCache()
        guard remainsCurrent() else { return }
        tab.updateNavigationState(from: webView)
        guard remainsCurrent() else { return }

        let title = webView.title?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        tab.navigationRuntime.historyRecorder.updateTitle(title, tab: tab)
        guard remainsCurrent() else { return }
        tab.navigationRuntime.persistenceCallbacks.scheduleRuntimeStatePersistence(tab)
        guard remainsCurrent() else { return }
        if tab.navigationRuntime.navigationTransactionOwner.pendingMainFrameNavigationKind
            == .backForward {
            tab.finishBackForwardNavigationTracking(using: webView)
            guard remainsCurrent() else { return }
            tab.navigationRuntime.webViewRouting.syncTabAcrossWindows(
                tab.id,
                webView
            )
            guard remainsCurrent() else { return }
        } else {
            tab.navigationRuntime.navigationTransactionOwner.pendingMainFrameNavigationKind = nil
        }

        if tab.audioState.isMuted {
            tab.setMuted(true)
            guard remainsCurrent() else { return }
        }
        tab.navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(
            tab,
            [.URL, .title, .loading]
        )
        guard remainsCurrent() else { return }
        tab.navigationRuntime.lifecycleNavigationRuntime
            .reconcileDocumentSuspensionState(tab)
        guard remainsCurrent() else { return }
        tab.mediaRuntime.callbacks.scheduleBackgroundMediaReconcile(
            "navigation-promoted-finish"
        )
        guard remainsCurrent() else { return }
        tab.navigationRuntime.lifecycleNavigationRuntime.enforceSiteDataPolicyAfterNavigation(tab)
        guard remainsCurrent() else { return }
        SafariExtensionAutofillFillDiagnostics.endInlineUISession(extensionId: nil)
    }
}
