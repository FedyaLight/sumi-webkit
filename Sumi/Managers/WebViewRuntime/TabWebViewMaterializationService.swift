import Foundation
import SumiWebRuntime
import WebKit

/// Materializes or adopts one normal-tab WebView for one window. Whole-session
/// replacement is deliberately delegated to `WebViewReplacementPipeline`.
@MainActor
final class TabWebViewMaterializationService {
    struct Runtime {
        let webViewSessions: WebViewSessionRepository
        let initialDocumentWarmup: @MainActor () -> InitialDocumentWarmupRuntime
        let placement: CanonicalWebViewPlacementService
        let primaryCandidate: @MainActor (UUID) -> (
            owner: TrackedWebViewOwner,
            webView: WKWebView
        )?
        let notifyActivatedIfCurrent: @MainActor (Tab, UUID) -> Void
    }

    private let runtime: Runtime
    private let planner: WebViewCreationPlanner

    init(runtime: Runtime, planner: WebViewCreationPlanner) {
        self.runtime = runtime
        self.planner = planner
    }

    func webView(for tab: Tab, in windowID: UUID) -> WKWebView? {
        precondition(
            tab.webViewSession.isBacked(by: runtime.webViewSessions),
            "WebView materialization requires the canonical repository"
        )
        let warmup = runtime.initialDocumentWarmup()
        switch planner.creationPlan(
            for: tab,
            in: windowID,
            initialDocumentWarmupRuntime: warmup,
            existingWebView: runtime.webViewSessions.webView(
                for: tab.id,
                in: windowID
            ),
            windowWebViews: runtime.webViewSessions.windowWebViews(for: tab.id)
        ) {
        case .useExisting(let webView):
            return webView
        case .adoptExistingPrimary(let webView):
            TabWebViewProcessPrewarmingService.checkOut(webView)
            adopt(webView, for: tab, in: windowID)
            return webView
        case .deferForInitialDocumentWarmup(let deferral):
            planner.startInitialDocumentWarmupIfNeeded(
                deferral,
                runtime: warmup
            )
            return nil
        case .createPrimary:
            return createPrimary(for: tab, in: windowID)
        case .createClone(let primaryWindowID):
            return createClone(
                for: tab,
                in: windowID,
                primaryWindowID: primaryWindowID
            )
        }
    }

    func refreshPrimary(for tab: Tab) {
        guard let replacement = runtime.primaryCandidate(tab.id) else { return }
        guard tab.webViewSession.primaryWebView !== replacement.webView
                || tab.webViewSession.primaryWindowID
                    != replacement.owner.windowID else {
            return
        }
        let outcome = replacement.webView.configuration
            .sumiIsNormalTabWebViewConfiguration
            ? runtime.placement.placeNormalTracked(
                replacement.webView,
                for: tab,
                in: replacement.owner.windowID,
                promoteToPrimary: true
            )
            : runtime.placement.placeAuxiliaryTracked(
                replacement.webView,
                for: tab,
                in: replacement.owner.windowID,
                promoteToPrimary: true
            )
        precondition(outcome.isAccepted)
    }

    private func createPrimary(
        for tab: Tab,
        in windowID: UUID
    ) -> WKWebView? {
        guard let webView = tab.makeNormalTabWebView(
            reason: "TabWebViewMaterializationService.createPrimary"
        ) else {
            assertionFailure("Unable to create a normal-tab WebView")
            return nil
        }
        guard runtime.placement.placeNormalTracked(
            webView,
            for: tab,
            in: windowID,
            promoteToPrimary: true
        ).isAccepted else {
            tab.cleanupCloneWebView(webView)
            assertionFailure("Primary WebView carried stale policy evidence")
            return nil
        }
        schedulePrimary(webView, tab: tab, windowID: windowID)
        return webView
    }

    private func createClone(
        for tab: Tab,
        in windowID: UUID,
        primaryWindowID: UUID
    ) -> WKWebView? {
        guard runtime.webViewSessions.webView(
            for: tab.id,
            in: primaryWindowID
        ) != nil else {
            assertionFailure("Cannot create a clone before its primary")
            return nil
        }
        guard let webView = tab.makeNormalTabWebView(
            reason: "TabWebViewMaterializationService.createClone"
        ) else {
            assertionFailure("Unable to create a normal-tab clone")
            return nil
        }
        guard runtime.placement.placeNormalTracked(
            webView,
            for: tab,
            in: windowID,
            promoteToPrimary: false
        ).isAccepted else {
            tab.cleanupCloneWebView(webView)
            _ = tab.rebuildNormalWebViewForConfigurationPolicyOutcome(
                targetURL: tab.url,
                reason: "TabWebViewMaterializationService.clonePolicyMismatch"
            )
            return nil
        }
        schedule(
            webView,
            tab: tab,
            windowID: windowID,
            updatesPresentation: false
        )
        webView.sumiSetAudioMuted(tab.isAudioMuted)
        runtime.notifyActivatedIfCurrent(tab, windowID)
        return webView
    }

    private func adopt(
        _ webView: WKWebView,
        for tab: Tab,
        in windowID: UUID
    ) {
        let outcome = webView.configuration
            .sumiIsNormalTabWebViewConfiguration
            ? runtime.placement.placeNormalTracked(
                webView,
                for: tab,
                in: windowID,
                promoteToPrimary: true
            )
            : runtime.placement.placeAuxiliaryTracked(
                webView,
                for: tab,
                in: windowID,
                promoteToPrimary: true
            )
        precondition(outcome.isAccepted)
        schedulePrimary(webView, tab: tab, windowID: windowID)
    }

    private func schedulePrimary(
        _ webView: WKWebView,
        tab: Tab,
        windowID: UUID
    ) {
        schedule(
            webView,
            tab: tab,
            windowID: windowID,
            updatesPresentation: true
        )
    }

    private func schedule(
        _ webView: WKWebView,
        tab: Tab,
        windowID: UUID,
        updatesPresentation: Bool
    ) {
        NormalTabInitialDocumentRuntimeHandoff.scheduleTrackedInitialLoad(
            tab: tab,
            webView: webView,
            targetURL: tab.url,
            expectedOwner: .init(tabID: tab.id, windowID: windowID),
            profileId: tab.resolveProfile()?.id ?? tab.profileId,
            registrationReason:
                "TabWebViewMaterializationService.beforeInitialLoad",
            updatesTabPresentation: updatesPresentation
        )
    }
}
