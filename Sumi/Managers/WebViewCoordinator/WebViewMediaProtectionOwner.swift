import AppKit
import Combine
import Foundation
import WebKit

extension Notification.Name {
    static let sumiWebViewNeedsMediaTouchBarRecovery = Notification.Name(
        "SumiWebViewNeedsMediaTouchBarRecovery"
    )
}

enum SumiMediaTouchBarRecoveryNotificationKey {
    static let tabID = "tabID"
    static let windowID = "windowID"
}

@MainActor
final class WebViewMediaProtectionOwner {
    typealias WebViewResolver = (ObjectIdentifier) -> WKWebView?
    typealias TrackedOwnerResolver = (WKWebView) -> TrackedWebViewOwner?
    typealias WindowIDResolver = (WKWebView) -> UUID?
    typealias DeferredCommandFlusher = (ObjectIdentifier) -> Void
    typealias WindowCompositorRefresher = (UUID) -> Void

    private let protectedCommandOwner = WebViewProtectedCommandOwner()
    private var nowPlayingSessionCancellablesByWebViewID: [ObjectIdentifier: AnyCancellable] = [:]

    func note(_ webView: WKWebView) {
        protectedCommandOwner.note(webView)
    }

    func resolveWeakWebView(with identifier: ObjectIdentifier) -> WKWebView? {
        protectedCommandOwner.resolveWeakWebView(with: identifier)
    }

    func beginHistorySwipeProtection(
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
    func finishHistorySwipeProtection(
        on webView: WKWebView?,
        currentURL: URL?,
        currentHistoryItem: WKBackForwardListItem?
    ) -> (webViewID: ObjectIdentifier, wasCancelled: Bool)? {
        protectedCommandOwner.finishHistorySwipeProtection(
            on: webView,
            currentURL: currentURL,
            currentHistoryItem: currentHistoryItem
        )
    }

    func hasActiveHistorySwipe(in windowID: UUID) -> Bool {
        protectedCommandOwner.hasActiveHistorySwipe(in: windowID)
    }

    func hasActiveFullscreen(in windowID: UUID) -> Bool {
        protectedCommandOwner.hasActiveFullscreen(in: windowID)
    }

    func isProtected(_ webView: WKWebView) -> Bool {
        protectedCommandOwner.isProtected(webView)
    }

    func isProtected(_ webViewID: ObjectIdentifier) -> Bool {
        protectedCommandOwner.isProtected(webViewID)
    }

    func beginVisualHandoffProtection(for webView: WKWebView) {
        protectedCommandOwner.beginVisualHandoffProtection(for: webView)
    }

    func finishVisualHandoffProtection(for webView: WKWebView) -> ObjectIdentifier? {
        protectedCommandOwner.finishVisualHandoffProtection(for: webView)
    }

    func closeActiveFullscreenMedia(
        in windowID: UUID,
        resolveWebView: WebViewResolver
    ) {
        for webViewID in protectedCommandOwner.activeFullscreenWebViewIDs(in: windowID) {
            guard let webView = resolveWebView(webViewID) else { continue }
            requestFullscreenMediaExit(on: webView)
        }
    }

    func closeFullscreenMediaIfNeeded(on webView: WKWebView) {
        let webViewID = ObjectIdentifier(webView)
        guard webView.sumiIsInFullscreenElementPresentation
            || protectedCommandOwner.isFullscreenProtected(webViewID)
        else {
            return
        }
        requestFullscreenMediaExit(on: webView)
    }

    func removeVisualHandoffFullscreenAndNowPlayingState() {
        protectedCommandOwner.removeVisualHandoffAndFullscreenProtections()
        nowPlayingSessionCancellablesByWebViewID.values.forEach { $0.cancel() }
        nowPlayingSessionCancellablesByWebViewID.removeAll()
    }

    func installFullscreenStateObservationIfNeeded(
        on webView: WKWebView,
        trackedOwner: @escaping TrackedOwnerResolver,
        fallbackWindowID: @escaping WindowIDResolver,
        flushDeferredProtectedCommands: @escaping DeferredCommandFlusher,
        refreshCompositor: @escaping WindowCompositorRefresher
    ) {
        protectedCommandOwner.installFullscreenStateObservationIfNeeded(
            on: webView
        ) { [weak self] webView in
            self?.updateFullscreenProtection(
                for: webView,
                trackedOwner: trackedOwner,
                fallbackWindowID: fallbackWindowID,
                flushDeferredProtectedCommands: flushDeferredProtectedCommands,
                refreshCompositor: refreshCompositor
            )
        }
    }

    func installNowPlayingSessionObservationIfNeeded(
        on webView: WKWebView,
        trackedOwner: @escaping TrackedOwnerResolver,
        fallbackWindowID: @escaping WindowIDResolver
    ) {
        let webViewID = ObjectIdentifier(webView)
        guard nowPlayingSessionCancellablesByWebViewID[webViewID] == nil else { return }
        // WebKit can re-establish its active playback manager after the fullscreen
        // transition itself has completed, so keep one late recovery trigger.
        nowPlayingSessionCancellablesByWebViewID[webViewID] = webView
            .publisher(for: \.sumiHasActiveNowPlayingSession, options: [.new])
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak webView] hasActiveSession in
                guard hasActiveSession,
                      let self,
                      let webView
                else {
                    return
                }
                self.postMediaTouchBarRecoveryRequest(
                    for: webView,
                    owner: trackedOwner(webView),
                    fallbackWindowID: fallbackWindowID(webView)
                )
            }
    }

    func uninstallObservationsIfUntracked(_ webView: WKWebView, isTracked: Bool) {
        protectedCommandOwner.uninstallFullscreenStateObservationIfUntracked(
            webView,
            isTracked: isTracked
        )
        guard !isTracked else { return }
        nowPlayingSessionCancellablesByWebViewID.removeValue(
            forKey: ObjectIdentifier(webView)
        )?.cancel()
    }

    @discardableResult
    func enqueueDeferredCommandIfNeeded(
        _ command: DeferredWebViewCommand,
        for webView: WKWebView,
        reason: String,
        resolveWebView: WebViewResolver,
        isCommandValid: WebViewProtectedCommandOwner.CommandValidator,
        dropCommand: WebViewProtectedCommandOwner.CommandDropper,
        didPruneStaleWebViewIDs: ([ObjectIdentifier]) -> Void
    ) -> Bool {
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

    func commandsToFlushIfUnprotected(
        for webViewID: ObjectIdentifier,
        resolveWebView: WebViewResolver,
        isCommandValid: WebViewProtectedCommandOwner.CommandValidator,
        dropCommand: WebViewProtectedCommandOwner.CommandDropper,
        didPruneStaleWebViewIDs: ([ObjectIdentifier]) -> Void
    ) -> [DeferredWebViewCommand] {
        protectedCommandOwner.commandsToFlushIfUnprotected(
            for: webViewID,
            resolveWebView: resolveWebView,
            isCommandValid: isCommandValid,
            dropCommand: dropCommand,
            didPruneStaleWebViewIDs: didPruneStaleWebViewIDs
        )
    }

    @discardableResult
    func pruneInvalidDeferredCommands(
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
    func pruneStaleBookkeeping(reason: String) -> [ObjectIdentifier] {
        protectedCommandOwner.pruneStaleBookkeeping(reason: reason)
    }

    private func updateFullscreenProtection(
        for webView: WKWebView,
        trackedOwner: TrackedOwnerResolver,
        fallbackWindowID: WindowIDResolver,
        flushDeferredProtectedCommands: DeferredCommandFlusher,
        refreshCompositor: WindowCompositorRefresher
    ) {
        if webView.sumiIsInFullscreenElementPresentation {
            beginFullscreenProtectionIfNeeded(
                for: webView,
                trackedOwner: trackedOwner,
                fallbackWindowID: fallbackWindowID
            )
        } else {
            finishFullscreenProtectionIfNeeded(
                for: webView,
                trackedOwner: trackedOwner,
                flushDeferredProtectedCommands: flushDeferredProtectedCommands,
                refreshCompositor: refreshCompositor
            )
        }
    }

    private func beginFullscreenProtectionIfNeeded(
        for webView: WKWebView,
        trackedOwner: TrackedOwnerResolver,
        fallbackWindowID: WindowIDResolver
    ) {
        guard webView.sumiIsInFullscreenElementPresentation else { return }

        let owner = trackedOwner(webView)
        let webViewID = protectedCommandOwner.beginFullscreenProtection(
            on: webView,
            windowID: owner?.windowID ?? fallbackWindowID(webView)
        )
        RuntimeDiagnostics.protectedWebViewTrace(
            "beginFullscreenProtection webView=\(webViewID) tab=\(owner?.tabID.uuidString.prefix(8) ?? "nil") window=\(owner?.windowID.uuidString.prefix(8) ?? "nil")"
        )
    }

    private func finishFullscreenProtectionIfNeeded(
        for webView: WKWebView,
        trackedOwner: TrackedOwnerResolver,
        flushDeferredProtectedCommands: DeferredCommandFlusher,
        refreshCompositor: WindowCompositorRefresher
    ) {
        guard let result = protectedCommandOwner.finishFullscreenProtection(on: webView) else {
            return
        }
        let owner = trackedOwner(webView)

        RuntimeDiagnostics.protectedWebViewTrace(
            "finishFullscreenProtection webView=\(result.webViewID)"
        )
        flushDeferredProtectedCommands(result.webViewID)
        if let windowID = result.windowID {
            refreshCompositor(windowID)
        }
        postMediaTouchBarRecoveryRequest(
            for: webView,
            owner: owner,
            fallbackWindowID: result.windowID
        )
    }

    private func requestFullscreenMediaExit(on webView: WKWebView) {
        webView.sumiFullscreenWindowController?.window?.toggleFullScreen(webView)
    }

    private func postMediaTouchBarRecoveryRequest(
        for webView: WKWebView,
        owner: TrackedWebViewOwner?,
        fallbackWindowID: UUID?
    ) {
        guard let windowID = owner?.windowID ?? fallbackWindowID else { return }
        var userInfo: [String: Any] = [
            SumiMediaTouchBarRecoveryNotificationKey.windowID: windowID
        ]
        if let tabID = owner?.tabID {
            userInfo[SumiMediaTouchBarRecoveryNotificationKey.tabID] = tabID
        }
        NotificationCenter.default.post(
            name: .sumiWebViewNeedsMediaTouchBarRecovery,
            object: webView,
            userInfo: userInfo
        )
    }
}
