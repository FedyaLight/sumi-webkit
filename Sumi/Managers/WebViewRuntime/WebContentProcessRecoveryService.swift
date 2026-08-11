import Foundation
import SumiWebRuntime
import WebKit

/// Owns delivery of one exact physical recovery attempt. Requests are woken
/// only by lifecycle events (visibility, protection release, registration, or
/// navigation binding); there is deliberately no timer or retry task.
@MainActor
final class WebContentProcessRecoveryService {
    typealias ProtectionResolver = @MainActor (WKWebView) -> Bool
    typealias VisibilityResolver = @MainActor (Tab, WKWebView) -> Bool
    typealias Submission = @MainActor (
        Tab,
        WKWebView,
        TabMainFrameNavigationIntent
    ) -> TabMainFrameReloadCommandOutcome

    private typealias WeakWebViewReference = WebViewIdentityWitness
    private typealias WeakTabReference = WeakIdentityWitness<Tab>

    private struct Request {
        let id: UUID
        let tabID: UUID
        let tabReference: WeakTabReference
        let webViewReference: WeakWebViewReference
    }

    private let isProtected: ProtectionResolver
    private let isVisible: VisibilityResolver
    private let submit: Submission
    private var requestsByWebViewID: [ObjectIdentifier: Request] = [:]

    init(
        isProtected: @escaping ProtectionResolver,
        isVisible: @escaping VisibilityResolver = { _, _ in true },
        submit: @escaping Submission
    ) {
        self.isProtected = isProtected
        self.isVisible = isVisible
        self.submit = submit
    }

    @discardableResult
    func recover(
        _ webView: WKWebView,
        for tab: Tab
    ) -> TabMainFrameReloadCommandOutcome {
        guard retain(webView, for: tab) else { return .failed }
        return attempt(webView)
    }

    /// Retains identity only. Hidden pages stay dormant until an activation
    /// event explicitly wakes this request.
    @discardableResult
    func retain(
        _ webView: WKWebView,
        for tab: Tab
    ) -> Bool {
        guard tab.webViewSession.owns(webView),
              tab.webContentRecoveryMarkers.recoveryState(on: webView)?
                .ownsFutureOrSubmittedNavigation == true else {
            return false
        }
        let webViewID = ObjectIdentifier(webView)
        if let request = requestsByWebViewID[webViewID],
           request.tabID == tab.id,
           request.tabReference.matches(tab),
           request.webViewReference.matches(webView) {
            return true
        }
        requestsByWebViewID[webViewID] = Request(
            id: UUID(),
            tabID: tab.id,
            tabReference: WeakTabReference(tab),
            webViewReference: WeakWebViewReference(webView)
        )
        return true
    }

    /// Event seam used by visibility, protection, and registration owners.
    func retryPendingImmediately(for webViewID: ObjectIdentifier) {
        guard let request = requestsByWebViewID[webViewID],
              let webView = request.webViewReference.resolve() else {
            requestsByWebViewID.removeValue(forKey: webViewID)
            return
        }
        _ = attempt(webView, matching: request.id)
    }

    func hasPendingRecovery(for webView: WKWebView) -> Bool {
        requestsByWebViewID[ObjectIdentifier(webView)]?
            .webViewReference.matches(webView) == true
    }

    func cancel(_ webView: WKWebView) {
        let webViewID = ObjectIdentifier(webView)
        guard requestsByWebViewID[webViewID]?.webViewReference
                .matches(webView) == true else { return }
        requestsByWebViewID.removeValue(forKey: webViewID)
    }

    func resetForTerminalShutdown() {
        requestsByWebViewID.removeAll()
    }

    private func attempt(
        _ webView: WKWebView,
        matching requestID: UUID? = nil
    ) -> TabMainFrameReloadCommandOutcome {
        let webViewID = ObjectIdentifier(webView)
        guard let request = requestsByWebViewID[webViewID],
              requestID == nil || request.id == requestID,
              request.webViewReference.matches(webView),
              let tab = request.tabReference.resolve(),
              tab.id == request.tabID,
              tab.webViewSession.owns(webView),
              let state = tab.webContentRecoveryMarkers.recoveryState(on: webView),
              state.ownsFutureOrSubmittedNavigation else {
            requestsByWebViewID.removeValue(forKey: webViewID)
            return .failed
        }

        if case .pendingActivation = state.phase {
            guard isVisible(tab, webView) else { return .scheduled }
            guard tab.activatePendingWebContentRecovery(on: webView) else {
                requestsByWebViewID.removeValue(forKey: webViewID)
                return .failed
            }
        }
        guard isProtected(webView) == false else { return .scheduled }

        let outcome = submit(tab, webView, tab.mainFrameLoads.currentIntent)
        guard requestsByWebViewID[webViewID]?.id == request.id else {
            return outcome
        }
        let updatedState = tab.webContentRecoveryMarkers.recoveryState(on: webView)
        if case .recovering = updatedState?.phase {
            requestsByWebViewID.removeValue(forKey: webViewID)
            return outcome
        }
        if outcome == .failed {
            requestsByWebViewID.removeValue(forKey: webViewID)
            tab.settleFailedWebContentRecoveryDelivery(on: webView)
            return .failed
        }
        return .scheduled
    }
}
