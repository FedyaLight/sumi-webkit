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
    public typealias TrackedOwnerResolver = (WKWebView) -> TrackedWebViewOwner?
    public typealias WindowIDResolver = (WKWebView) -> UUID?
    public typealias DeferredCommandFlusher = (ObjectIdentifier) -> Void
    public typealias WindowCompositorRefresher = (UUID) -> Void
    public typealias TabSelector = (_ tabID: UUID, _ windowID: UUID) -> Void
    public typealias TabCurrentStateResolver = (_ tabID: UUID, _ windowID: UUID) -> Bool

    private let protectedCommandOwner = WebViewProtectedCommandOwner()
    private var nowPlayingSessionCancellablesByWebViewID: [ObjectIdentifier: AnyCancellable] = [:]
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

    public func hasActiveFullscreen(in windowID: UUID) -> Bool {
        protectedCommandOwner.hasActiveFullscreen(in: windowID)
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

    @discardableResult
    public func removeVisualHandoffFullscreenAndNowPlayingState() -> [ObjectIdentifier] {
        let newlyUnprotectedSourceIDs = protectedCommandOwner
            .removeVisualHandoffAndFullscreenProtections()
        newlyUnprotectedSourceIDs.forEach(resumeUnprotectedWaitersIfPossible)
        nowPlayingSessionCancellablesByWebViewID.values.forEach { $0.cancel() }
        nowPlayingSessionCancellablesByWebViewID.removeAll()
        return newlyUnprotectedSourceIDs
    }

    public func resetForTerminalShutdown() {
        protectedCommandOwner.resetForTerminalShutdown()
        resumeAllUnprotectedWaiters(returning: false)
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
        executeCommand: (DeferredWebViewCommand) -> Bool
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
        resumeUnprotectedWaitersIfPossible(for: result.webViewID)
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
