import Foundation
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
        if continuation.needsSharedCommitEffects,
           promotion.claimSharedCommitEffects(
               matching: continuation
           ) {
            let authority = Authority.promotion(continuation)
            guard authority.applyURL(to: tab) else { return }
            publishCommitEffects(authority, tab: tab) {
                promotion.remainsCurrent(matching: continuation)
            }
        }
        if continuation.needsSharedFinishEffects,
           promotion.claimSharedFinishEffects(
               matching: continuation
           ) {
            publishFinish(.promotion(continuation), tab: tab)
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
        _ authority: Authority,
        tab: Tab
    ) {
        guard authority.applyURL(to: tab) else { return }
        StartupPerformanceTrace.firstNavigationFinished()
        tab.loadingState = .didFinish
        tab.navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(
            tab,
            [.loading]
        )
        tab.refreshFaviconExtensionCache()
        tab.updateNavigationState(from: authority.webView)

        let title = authority.webView.title?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        tab.navigationRuntime.historyRecorder.updateTitle(title, tab: tab)
        tab.navigationRuntime.persistenceCallbacks.scheduleRuntimeStatePersistence(tab)
        if tab.navigationRuntime.navigationTransactionOwner.pendingMainFrameNavigationKind
            == .backForward {
            tab.finishBackForwardNavigationTracking(using: authority.webView)
            tab.navigationRuntime.webViewRouting.syncTabAcrossWindows(
                tab.id,
                authority.webView
            )
        } else {
            tab.navigationRuntime.navigationTransactionOwner.pendingMainFrameNavigationKind = nil
        }

        if tab.audioState.isMuted {
            tab.setMuted(true)
        }
        tab.navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(
            tab,
            [.URL, .title, .loading]
        )
        tab.navigationRuntime.lifecycleNavigationRuntime
            .reconcileDocumentSuspensionState(tab)
        tab.mediaRuntime.callbacks.scheduleBackgroundMediaReconcile(
            "navigation-promoted-finish"
        )
        tab.navigationRuntime.lifecycleNavigationRuntime.enforceSiteDataPolicyAfterNavigation(tab)
        SafariExtensionAutofillFillDiagnostics.endInlineUISession(extensionId: nil)
    }
}
