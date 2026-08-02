import Foundation
import WebKit

@MainActor
public final class WebViewMediaProtectionOwner {
    public init() {}

    private final class UnprotectedWaiter {
        let webViewReference: WebViewIdentityWitness
        let continuation: CheckedContinuation<Bool, Never>

        init(
            webView: WKWebView,
            continuation: CheckedContinuation<Bool, Never>
        ) {
            webViewReference = WebViewIdentityWitness(webView)
            self.continuation = continuation
        }
    }

    public typealias WebViewResolver = (ObjectIdentifier) -> WKWebView?

    private let protectedCommandOwner = WebViewProtectedCommandOwner()
    private var unprotectedWaitersByWebViewID: [
        ObjectIdentifier: [UUID: UnprotectedWaiter]
    ] = [:]

    public func note(_ webView: WKWebView) {
        protectedCommandOwner.note(webView)
    }

    public func resolveWeakWebView(with identifier: ObjectIdentifier) -> WKWebView? {
        protectedCommandOwner.resolveWeakWebView(with: identifier)
    }

    public var hasDeferredProtectedCommands: Bool {
        protectedCommandOwner.hasDeferredCommands
    }

    public func hasDeferredProtectedCommands(for sourceWebViewID: ObjectIdentifier) -> Bool {
        protectedCommandOwner.hasDeferredCommands(for: sourceWebViewID)
    }

    public func beginHistorySwipeProtection(
        on webView: WKWebView,
        windowID: UUID?,
        originURL: URL?,
        originHistoryItem: WKBackForwardListItem?
    ) -> ObjectIdentifier {
        protectedCommandOwner.beginHistorySwipeProtection(
            on: webView,
            windowID: windowID,
            originURL: originURL,
            originHistoryItem: originHistoryItem
        )
    }

    @discardableResult
    public func finishHistorySwipeProtection(
        on webView: WKWebView?,
        currentURL: URL?,
        currentHistoryItem: WKBackForwardListItem?
    ) -> (webViewID: ObjectIdentifier, wasCancelled: Bool)? {
        let result = protectedCommandOwner.finishHistorySwipeProtection(
            on: webView,
            currentURL: currentURL,
            currentHistoryItem: currentHistoryItem
        )
        if let webViewID = result?.webViewID {
            resumeUnprotectedWaitersIfPossible(for: webViewID)
        }
        return result
    }

    public func hasActiveHistorySwipe(in windowID: UUID) -> Bool {
        protectedCommandOwner.hasActiveHistorySwipe(in: windowID)
    }

    public func isProtected(_ webView: WKWebView) -> Bool {
        protectedCommandOwner.isProtected(webView)
    }

    public func isProtected(_ webViewID: ObjectIdentifier) -> Bool {
        protectedCommandOwner.isProtected(webViewID)
    }

    /// Suspends active maintenance work until all compositor/media ownership
    /// claims for this exact WebView have ended. This is event-driven: disabled
    /// maintenance installs no timers or polling work.
    public func waitUntilUnprotected(_ webView: WKWebView) async -> Bool {
        note(webView)
        guard isProtected(webView) else { return true }

        let webViewID = ObjectIdentifier(webView)
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                    return
                }
                if isProtected(webView) == false {
                    continuation.resume(returning: true)
                    return
                }
                unprotectedWaitersByWebViewID[webViewID, default: [:]][waiterID] =
                    UnprotectedWaiter(
                        webView: webView,
                        continuation: continuation
                    )
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.cancelUnprotectedWaiter(
                    waiterID,
                    webViewID: webViewID
                )
            }
        }
    }

    public func beginVisualHandoffProtection(
        for webView: WKWebView
    ) -> WebViewVisualHandoffProtectionLease {
        protectedCommandOwner.beginVisualHandoffProtection(for: webView)
    }

    public func finishVisualHandoffProtection(
        _ lease: WebViewVisualHandoffProtectionLease
    ) -> ObjectIdentifier? {
        let webViewID = protectedCommandOwner.finishVisualHandoffProtection(lease)
        if let webViewID {
            resumeUnprotectedWaitersIfPossible(for: webViewID)
        }
        return webViewID
    }

    @discardableResult
    public func removeVisualHandoffState() -> [ObjectIdentifier] {
        let newlyUnprotectedSourceIDs = protectedCommandOwner
            .removeVisualHandoffProtections()
        newlyUnprotectedSourceIDs.forEach(resumeUnprotectedWaitersIfPossible)
        return newlyUnprotectedSourceIDs
    }

    public func resetForTerminalShutdown() {
        protectedCommandOwner.resetForTerminalShutdown()
        resumeAllUnprotectedWaiters(returning: false)
    }

    public func uninstallObservationsIfUntracked(_ webView: WKWebView, isTracked: Bool) {
        guard !isTracked else { return }
        resumeUnprotectedWaitersIfPossible(for: ObjectIdentifier(webView))
    }

    @discardableResult
    public func enqueueDeferredCommandIfNeeded(
        _ command: DeferredWebViewCommand,
        for webView: WKWebView,
        reason: String,
        resolveWebView: WebViewResolver,
        isCommandValid: WebViewProtectedCommandOwner.CommandValidator,
        dropCommand: WebViewProtectedCommandOwner.CommandDropper,
        didPruneStaleWebViewIDs: ([ObjectIdentifier]) -> Void
    ) -> DeferredProtectedCommandSchedulingOutcome {
        protectedCommandOwner.enqueueDeferredCommandIfNeeded(
            command,
            for: webView,
            reason: reason,
            resolveWebView: resolveWebView,
            isCommandValid: isCommandValid,
            dropCommand: dropCommand,
            didPruneStaleWebViewIDs: didPruneStaleWebViewIDs
        )
    }

    @discardableResult
    public func executeDeferredCommandsIfUnprotected(
        for webViewID: ObjectIdentifier,
        resolveWebView: WebViewResolver,
        isCommandValid: WebViewProtectedCommandOwner.CommandValidator,
        dropCommand: WebViewProtectedCommandOwner.CommandDropper,
        didPruneStaleWebViewIDs: ([ObjectIdentifier]) -> Void,
        executeCommand: WebViewProtectedCommandOwner.CommandExecutor
    ) -> Int {
        protectedCommandOwner.executeDeferredCommandsIfUnprotected(
            for: webViewID,
            resolveWebView: resolveWebView,
            isCommandValid: isCommandValid,
            dropCommand: dropCommand,
            didPruneStaleWebViewIDs: didPruneStaleWebViewIDs,
            executeCommand: executeCommand
        )
    }

    @discardableResult
    public func pruneInvalidDeferredCommands(
        reason: String,
        resolveWebView: WebViewResolver,
        isCommandValid: WebViewProtectedCommandOwner.CommandValidator,
        dropCommand: WebViewProtectedCommandOwner.CommandDropper
    ) -> [ObjectIdentifier] {
        protectedCommandOwner.pruneInvalidDeferredCommands(
            reason: reason,
            resolveWebView: resolveWebView,
            isCommandValid: isCommandValid,
            dropCommand: dropCommand
        )
    }

    @discardableResult
    public func pruneStaleBookkeeping(reason: String) -> [ObjectIdentifier] {
        protectedCommandOwner.pruneStaleBookkeeping(reason: reason)
    }

    private func resumeUnprotectedWaitersIfPossible(
        for webViewID: ObjectIdentifier
    ) {
        guard isProtected(webViewID) == false,
              let waiters = unprotectedWaitersByWebViewID.removeValue(
                  forKey: webViewID
              )
        else {
            return
        }
        for waiter in waiters.values {
            waiter.continuation.resume(
                returning: waiter.webViewReference.identifier == webViewID
                    && waiter.webViewReference.resolve() != nil
            )
        }
    }

    private func cancelUnprotectedWaiter(
        _ waiterID: UUID,
        webViewID: ObjectIdentifier
    ) {
        guard let waiter = unprotectedWaitersByWebViewID[webViewID]?
            .removeValue(forKey: waiterID)
        else {
            return
        }
        if unprotectedWaitersByWebViewID[webViewID]?.isEmpty == true {
            unprotectedWaitersByWebViewID.removeValue(forKey: webViewID)
        }
        waiter.continuation.resume(returning: false)
    }

    private func resumeAllUnprotectedWaiters(returning result: Bool) {
        let waiters = unprotectedWaitersByWebViewID.values.flatMap(\.values)
        unprotectedWaitersByWebViewID.removeAll()
        waiters.forEach { $0.continuation.resume(returning: result) }
    }
}
