import Foundation
import SumiWebRuntime
import WebKit

/// Owns physical WebContent-process repair independently from the semantic
/// main-frame transaction. A crash marker is retained by
/// `TabWebContentRecoveryPlanner`; this service keeps attempting delivery until
/// a concrete Navigation binds and consumes that marker, or the exact WebView
/// leaves its canonical residence.
@MainActor
final class WebContentProcessRecoveryService {
    typealias ProtectionResolver = @MainActor (WKWebView) -> Bool
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
        var retryAttempt: Int
    }

    private static let initialRetryDelayNanoseconds: UInt64 = 25_000_000
    private static let maximumRetryDelayNanoseconds: UInt64 = 1_000_000_000

    private let isProtected: ProtectionResolver
    private let submit: Submission
    private var requestsByWebViewID: [ObjectIdentifier: Request] = [:]
    private var retryTasksByWebViewID: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(
        isProtected: @escaping ProtectionResolver,
        submit: @escaping Submission
    ) {
        self.isProtected = isProtected
        self.submit = submit
    }

    deinit {
        retryTasksByWebViewID.values.forEach { $0.cancel() }
    }

    /// Accepts responsibility for repairing one exact physical WebView. Once
    /// accepted, transient protection and submission failures are represented
    /// as `.scheduled`; callers never need to invent a second retry policy.
    @discardableResult
    func recover(
        _ webView: WKWebView,
        for tab: Tab
    ) -> TabMainFrameReloadCommandOutcome {
        guard retain(webView, for: tab) else { return .failed }
        let webViewID = ObjectIdentifier(webView)
        guard let request = requestsByWebViewID[webViewID] else {
            return .failed
        }
        retryTasksByWebViewID.removeValue(forKey: webViewID)?.cancel()
        return attempt(
            requestID: request.id,
            webViewID: webViewID,
            expectedWebView: webView
        )
    }

    /// Retains responsibility before higher-level configuration recovery runs.
    /// That pipeline can fail before it reaches physical delivery; the retained
    /// retry guarantees the crash marker still has an owner and a wake-up.
    @discardableResult
    func retain(
        _ webView: WKWebView,
        for tab: Tab
    ) -> Bool {
        guard tab.webViewSession.owns(webView),
              tab.requiresWebContentProcessRecovery(on: webView) else {
            return false
        }
        let webViewID = ObjectIdentifier(webView)
        if let request = requestsByWebViewID[webViewID],
           request.tabID == tab.id,
           request.tabReference.matches(tab),
           request.webViewReference.matches(webView) {
            return true
        }

        finish(webViewID: webViewID)
        let request = Request(
            id: UUID(),
            tabID: tab.id,
            tabReference: WeakTabReference(tab),
            webViewReference: WeakWebViewReference(webView),
            retryAttempt: 1
        )
        requestsByWebViewID[webViewID] = request
        scheduleRetry(for: request, webViewID: webViewID)
        return true
    }

    /// Protection transitions and canonical registration changes can wake a
    /// retained recovery immediately instead of waiting for its bounded retry.
    func retryPendingImmediately(for webViewID: ObjectIdentifier) {
        guard let request = requestsByWebViewID[webViewID],
              let webView = request.webViewReference.resolve() else {
            finish(webViewID: webViewID)
            return
        }
        retryTasksByWebViewID.removeValue(forKey: webViewID)?.cancel()
        _ = attempt(
            requestID: request.id,
            webViewID: webViewID,
            expectedWebView: webView
        )
    }

    func hasPendingRecovery(for webView: WKWebView) -> Bool {
        requestsByWebViewID[ObjectIdentifier(webView)]?
            .webViewReference.matches(webView) == true
    }

    func cancel(_ webView: WKWebView) {
        let webViewID = ObjectIdentifier(webView)
        guard requestsByWebViewID[webViewID]?.webViewReference
                .matches(webView) == true else {
            return
        }
        finish(webViewID: webViewID)
    }

    func resetForTerminalShutdown() {
        retryTasksByWebViewID.values.forEach { $0.cancel() }
        retryTasksByWebViewID.removeAll()
        requestsByWebViewID.removeAll()
    }

    private func attempt(
        requestID: UUID,
        webViewID: ObjectIdentifier,
        expectedWebView: WKWebView
    ) -> TabMainFrameReloadCommandOutcome {
        guard var request = requestsByWebViewID[webViewID],
              request.id == requestID,
              request.webViewReference.matches(expectedWebView),
              let tab = request.tabReference.resolve(),
              tab.id == request.tabID,
              tab.webViewSession.owns(expectedWebView),
              tab.requiresWebContentProcessRecovery(on: expectedWebView) else {
            finish(webViewID: webViewID, matching: requestID)
            return .failed
        }

        guard isProtected(expectedWebView) == false else {
            request.retryAttempt += 1
            requestsByWebViewID[webViewID] = request
            scheduleRetry(for: request, webViewID: webViewID)
            return .scheduled
        }

        let outcome = submit(
            tab,
            expectedWebView,
            tab.currentMainFrameNavigationIntent()
        )

        guard let currentRequest = requestsByWebViewID[webViewID],
              currentRequest.id == requestID,
              currentRequest.webViewReference.matches(expectedWebView) else {
            return outcome
        }
        guard tab.webViewSession.owns(expectedWebView),
              tab.requiresWebContentProcessRecovery(on: expectedWebView) else {
            finish(webViewID: webViewID, matching: requestID)
            return outcome
        }

        request.retryAttempt += 1
        requestsByWebViewID[webViewID] = request
        scheduleRetry(for: request, webViewID: webViewID)
        return .scheduled
    }

    private func scheduleRetry(
        for request: Request,
        webViewID: ObjectIdentifier
    ) {
        retryTasksByWebViewID.removeValue(forKey: webViewID)?.cancel()
        let shift = min(max(request.retryAttempt - 1, 0), 6)
        let delay = min(
            Self.initialRetryDelayNanoseconds << UInt64(shift),
            Self.maximumRetryDelayNanoseconds
        )
        retryTasksByWebViewID[webViewID] = Task { @MainActor [
            weak self,
            weak webView = request.webViewReference.value
        ] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard Task.isCancelled == false,
                  let self else { return }
            guard let webView else {
                self.finish(webViewID: webViewID, matching: request.id)
                return
            }
            _ = self.attempt(
                requestID: request.id,
                webViewID: webViewID,
                expectedWebView: webView
            )
        }
    }

    private func finish(
        webViewID: ObjectIdentifier,
        matching requestID: UUID? = nil
    ) {
        if let requestID,
           requestsByWebViewID[webViewID]?.id != requestID {
            return
        }
        requestsByWebViewID.removeValue(forKey: webViewID)
        retryTasksByWebViewID.removeValue(forKey: webViewID)?.cancel()
    }
}
