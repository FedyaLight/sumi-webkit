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
        func applyURL(to tab: Tab) {
            switch self {
            case .navigation(let webView, let navigationID, let targetURL, _):
                tab.applyAcceptedMainFrameLifecycleURL(
                    targetURL,
                    from: webView,
                    navigationID: navigationID
                )
            case .promotion(let continuation):
                tab.applyPromotedAuthorityURL(
                    continuation.targetURL,
                    matching: continuation
                )
            }
        }
    }

    static func replayIfNeeded(
        _ continuation: TabMainFrameAuthorityContinuation,
        tab: Tab
    ) {
        if continuation.needsSharedCommitEffects,
           tab.claimPromotedSharedCommitEffects(matching: continuation) {
            publishCommit(.promotion(continuation), tab: tab)
        }
        if continuation.needsSharedFinishEffects,
           tab.claimPromotedSharedFinishEffects(matching: continuation) {
            publishFinish(.promotion(continuation), tab: tab)
        }
    }

    static func publishCommit(
        _ authority: Authority,
        tab: Tab
    ) {
        authority.applyURL(to: tab)
        tab.suspensionProtection.isPDFDocument = authority.isPDF
        StartupPerformanceTrace.firstNavigationCommitted()
        tab.loadingState = .didCommit
        tab.navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(
            tab,
            [.loading]
        )

        let isBackForward = tab.navigationRuntime.navigationTransactionOwner
            .pendingMainFrameNavigationKind == .backForward
        if isBackForward {
            tab.handleNormalTabPermissionNavigation(to: authority.targetURL)
        }
        tab.extensionPageRuntimeOwner.noteCommittedMainDocumentNavigation(
            to: authority.targetURL
        )
        tab.clearSafariContentBlockerReloadRequirementIfResolved(
            for: authority.targetURL
        )
        tab.clearProtectionReloadRequirementIfResolved(for: authority.targetURL)
        tab.clearAutoplayReloadRequirementIfResolved(for: authority.targetURL)
        tab.navigationRuntime.historyRecorder.didCommitMainFrameNavigation(
            to: authority.targetURL,
            kind: isBackForward ? .backForward : .regular,
            tab: tab
        )
        tab.navigationRuntime.lifecycleNavigationRuntime.markExtensionEligibleAfterCommit(
            tab,
            "TabMainFrameLifecycleReducer.commit"
        )
        if !isBackForward {
            tab.navigationRuntime.webViewRouting.syncTabAcrossWindows(
                tab.id,
                authority.webView
            )
        }
        tab.navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(
            tab,
            [.URL, .loading]
        )
        tab.stateChangeEmitter.postNavigationStateDidChange(for: tab)
    }

    static func publishFinish(
        _ authority: Authority,
        tab: Tab
    ) {
        authority.applyURL(to: tab)
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
        tab.mediaRuntime.callbacks.scheduleBackgroundMediaReconcile(
            "navigation-promoted-finish"
        )
        tab.navigationRuntime.lifecycleNavigationRuntime.enforceSiteDataPolicyAfterNavigation(tab)
        SafariExtensionAutofillFillDiagnostics.endInlineUISession(extensionId: nil)
    }
}
