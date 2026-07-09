import AppKit
import Combine
import Foundation
import WebKit

public extension Notification.Name {
    static let sumiWebViewNeedsMediaTouchBarRecovery = Notification.Name(
        "SumiWebViewNeedsMediaTouchBarRecovery"
    )
}

public enum SumiMediaTouchBarRecoveryNotificationKey {
    public static let tabID = "tabID"
    public static let windowID = "windowID"
}

@MainActor
public final class WebViewMediaProtectionOwner {
    public init() {}

    public typealias WebViewResolver = (ObjectIdentifier) -> WKWebView?
    public typealias TrackedOwnerResolver = (WKWebView) -> TrackedWebViewOwner?
    public typealias WindowIDResolver = (WKWebView) -> UUID?
    public typealias DeferredCommandFlusher = (ObjectIdentifier) -> Void
    public typealias WindowCompositorRefresher = (UUID) -> Void
    public typealias TabSelector = (_ tabID: UUID, _ windowID: UUID) -> Void
    public typealias TabCurrentStateResolver = (_ tabID: UUID, _ windowID: UUID) -> Bool

    private let protectedCommandOwner = WebViewProtectedCommandOwner()
    private var nowPlayingSessionCancellablesByWebViewID: [ObjectIdentifier: AnyCancellable] = [:]

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
        protectedCommandOwner.finishHistorySwipeProtection(
            on: webView,
            currentURL: currentURL,
            currentHistoryItem: currentHistoryItem
        )
    }

    public func hasActiveHistorySwipe(in windowID: UUID) -> Bool {
        protectedCommandOwner.hasActiveHistorySwipe(in: windowID)
    }

    public func hasActiveFullscreen(in windowID: UUID) -> Bool {
        protectedCommandOwner.hasActiveFullscreen(in: windowID)
    }

    public func isProtected(_ webView: WKWebView) -> Bool {
        protectedCommandOwner.isProtected(webView)
    }

    public func isProtected(_ webViewID: ObjectIdentifier) -> Bool {
        protectedCommandOwner.isProtected(webViewID)
    }

    public func beginVisualHandoffProtection(for webView: WKWebView) {
        protectedCommandOwner.beginVisualHandoffProtection(for: webView)
    }

    public func finishVisualHandoffProtection(for webView: WKWebView) -> ObjectIdentifier? {
        protectedCommandOwner.finishVisualHandoffProtection(for: webView)
    }

    public func closeActiveFullscreenMedia(
        in windowID: UUID,
        resolveWebView: WebViewResolver
    ) {
        for webViewID in protectedCommandOwner.activeFullscreenWebViewIDs(in: windowID) {
            guard let webView = resolveWebView(webViewID) else { continue }
            requestFullscreenMediaExit(on: webView)
        }
    }

    public func closeFullscreenMediaIfNeeded(on webView: WKWebView) {
        let webViewID = ObjectIdentifier(webView)
        guard webView.sumiIsInFullscreenElementPresentation
            || protectedCommandOwner.isFullscreenProtected(webViewID)
        else {
            return
        }
        requestFullscreenMediaExit(on: webView)
    }

    public func removeVisualHandoffFullscreenAndNowPlayingState() {
        protectedCommandOwner.removeVisualHandoffAndFullscreenProtections()
        nowPlayingSessionCancellablesByWebViewID.values.forEach { $0.cancel() }
        nowPlayingSessionCancellablesByWebViewID.removeAll()
    }

    public func installFullscreenStateObservationIfNeeded(
        on webView: WKWebView,
        trackedOwner: @escaping TrackedOwnerResolver,
        fallbackWindowID: @escaping WindowIDResolver,
        flushDeferredProtectedCommands: @escaping DeferredCommandFlusher,
        refreshCompositor: @escaping WindowCompositorRefresher,
        selectTab: @escaping TabSelector,
        isOwnerTabCurrent: @escaping TabCurrentStateResolver
    ) {
        protectedCommandOwner.installFullscreenStateObservationIfNeeded(
            on: webView
        ) { [weak self] webView in
            self?.updateFullscreenProtection(
                for: webView,
                trackedOwner: trackedOwner,
                fallbackWindowID: fallbackWindowID,
                flushDeferredProtectedCommands: flushDeferredProtectedCommands,
                refreshCompositor: refreshCompositor,
                selectTab: selectTab,
                isOwnerTabCurrent: isOwnerTabCurrent
            )
        }
    }

    public func installNowPlayingSessionObservationIfNeeded(
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

    public func uninstallObservationsIfUntracked(_ webView: WKWebView, isTracked: Bool) {
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
    public func enqueueDeferredCommandIfNeeded(
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

    public func commandsToFlushIfUnprotected(
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

    private func updateFullscreenProtection(
        for webView: WKWebView,
        trackedOwner: TrackedOwnerResolver,
        fallbackWindowID: WindowIDResolver,
        flushDeferredProtectedCommands: DeferredCommandFlusher,
        refreshCompositor: WindowCompositorRefresher,
        selectTab: TabSelector,
        isOwnerTabCurrent: TabCurrentStateResolver
    ) {
        switch webView.fullscreenState {
        case .notInFullscreen:
            finishFullscreenProtectionIfNeeded(
                for: webView,
                trackedOwner: trackedOwner,
                flushDeferredProtectedCommands: flushDeferredProtectedCommands,
                refreshCompositor: refreshCompositor,
                selectTab: selectTab,
                isOwnerTabCurrent: isOwnerTabCurrent
            )
        case .exitingFullscreen:
            if protectedCommandOwner.activeFullscreenProtection(on: webView) == nil {
                beginFullscreenProtectionIfNeeded(
                    for: webView,
                    trackedOwner: trackedOwner,
                    fallbackWindowID: fallbackWindowID
                )
            }
            revealOwnerTabForFullscreenExitIfNeeded(
                for: webView,
                trackedOwner: trackedOwner,
                fallbackWindowID: fallbackWindowID,
                selectTab: selectTab,
                isOwnerTabCurrent: isOwnerTabCurrent
            )
        case .enteringFullscreen, .inFullscreen:
            beginFullscreenProtectionIfNeeded(
                for: webView,
                trackedOwner: trackedOwner,
                fallbackWindowID: fallbackWindowID
            )
        @unknown default:
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
                    refreshCompositor: refreshCompositor,
                    selectTab: selectTab,
                    isOwnerTabCurrent: isOwnerTabCurrent
                )
            }
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
            windowID: owner?.windowID ?? fallbackWindowID(webView),
            tabID: owner?.tabID
        )
        SumiWebRuntimeDiagnostics.protectedWebViewTrace(
            "beginFullscreenProtection webView=\(webViewID) tab=\(owner?.tabID.uuidString.prefix(8) ?? "nil") window=\(owner?.windowID.uuidString.prefix(8) ?? "nil")"
        )
    }

    private func revealOwnerTabForFullscreenExitIfNeeded(
        for webView: WKWebView,
        trackedOwner: TrackedOwnerResolver,
        fallbackWindowID: WindowIDResolver,
        selectTab: TabSelector,
        isOwnerTabCurrent: TabCurrentStateResolver
    ) {
        let activeProtection = protectedCommandOwner.activeFullscreenProtection(on: webView)
        let owner = trackedOwner(webView)
        guard let tabID = activeProtection?.tabID ?? owner?.tabID,
              let windowID = activeProtection?.windowID ?? owner?.windowID ?? fallbackWindowID(webView),
              !isOwnerTabCurrent(tabID, windowID)
        else {
            return
        }
        guard protectedCommandOwner.consumeFullscreenExitOwnerReveal(on: webView) != nil else {
            return
        }

        selectTab(tabID, windowID)
    }

    private func finishFullscreenProtectionIfNeeded(
        for webView: WKWebView,
        trackedOwner: TrackedOwnerResolver,
        flushDeferredProtectedCommands: DeferredCommandFlusher,
        refreshCompositor: WindowCompositorRefresher,
        selectTab: TabSelector,
        isOwnerTabCurrent: TabCurrentStateResolver
    ) {
        guard let result = protectedCommandOwner.finishFullscreenProtection(on: webView) else {
            return
        }
        let owner = trackedOwner(webView)

        SumiWebRuntimeDiagnostics.protectedWebViewTrace(
            "finishFullscreenProtection webView=\(result.webViewID)"
        )
        flushDeferredProtectedCommands(result.webViewID)

        if let tabID = result.tabID,
           let windowID = result.windowID,
           !isOwnerTabCurrent(tabID, windowID) {
            selectTab(tabID, windowID)
        } else if let windowID = result.windowID {
            refreshCompositor(windowID)
        }

        postMediaTouchBarRecoveryRequest(
            for: webView,
            owner: owner,
            fallbackWindowID: result.windowID
        )
    }

    private func requestFullscreenMediaExit(on webView: WKWebView) {
        webView.sumiFullscreenPresentation.requestExit()
    }

    private func postMediaTouchBarRecoveryRequest(
        for webView: WKWebView,
        owner: TrackedWebViewOwner?,
        fallbackWindowID: UUID?
    ) {
        guard let windowID = owner?.windowID ?? fallbackWindowID else { return }
        var userInfo: [String: Any] = [
            SumiMediaTouchBarRecoveryNotificationKey.windowID: windowID,
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
