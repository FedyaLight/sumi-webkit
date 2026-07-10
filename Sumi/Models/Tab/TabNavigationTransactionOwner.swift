import Foundation
import WebKit

@MainActor
final class TabNavigationTransactionOwner {
    struct HistorySwipeEnvironment {
        let tabId: UUID
        let currentWebView: @MainActor () -> WKWebView?
        let currentURL: @MainActor () -> URL?
        let windowIDContaining: @MainActor (WKWebView) -> UUID?
        let beginHistorySwipeProtection: @MainActor (
            _ tabId: UUID,
            _ webView: WKWebView,
            _ originURL: URL?,
            _ originHistoryItem: WKBackForwardListItem?
        ) -> Void
        let finishHistorySwipeProtection: @MainActor (
            _ tabId: UUID,
            _ webView: WKWebView?,
            _ currentURL: URL?,
            _ currentHistoryItem: WKBackForwardListItem?
        ) -> Bool
        let cancelWindowMutationsAfterHistorySwipe: @MainActor (UUID) -> Void
        let flushWindowMutationsAfterHistorySwipe: @MainActor (UUID) -> Void
        let updateNavStateIfCurrentWebViewExists: @MainActor () -> Void
        let scheduleRuntimeStatePersistence: @MainActor () -> Void
        let syncAcrossWindows: @MainActor (WKWebView) -> Void
    }

    private var pendingTask: Task<Void, Never>?
    private var pendingToken: UUID?
    private var pendingCancellation: (@MainActor () -> Void)?
    private var pendingBackForwardNavigationContext: TabBackForwardNavigationContext?
    private var pendingBackForwardSettleTask: Task<Void, Never>?
    var pendingMainFrameNavigationKind: TabMainFrameNavigationKind?
    var isFreezingNavDuringBackForwardGesture = false

    func cancelPendingMainFrameNavigation() {
        precondition(
            isFreezingNavDuringBackForwardGesture == false,
            "History-swipe cancellation requires its runtime environment"
        )
        cancelPendingPreparedLoad()
        clearRelatedNavigationState()
    }

    func cancelPendingMainFrameNavigation(environment: HistorySwipeEnvironment) {
        cancelPendingPreparedLoad()
        guard isFreezingNavDuringBackForwardGesture else {
            clearRelatedNavigationState()
            return
        }
        finishBackForwardNavigationTracking(
            using: nil,
            environment: environment
        )
    }

    func perform(
        on webView: WKWebView,
        performLoad: @MainActor (WKWebView) -> Bool
    ) -> Bool {
        cancelPendingPreparedLoad()
        return performLoad(webView)
    }

    func performAfterPreparation(
        on webView: WKWebView,
        prepare: @escaping @MainActor () async -> Void,
        didCancel: @escaping @MainActor () -> Void = {},
        performLoad: @escaping @MainActor @Sendable (WKWebView) -> Void
    ) {
        cancelPendingPreparedLoad()

        let token = UUID()
        pendingToken = token
        pendingCancellation = didCancel
        pendingTask = Task { @MainActor [weak self, weak webView] in
            await prepare()
            guard Task.isCancelled == false else { return }
            guard let self else {
                didCancel()
                return
            }
            guard self.pendingToken == token else { return }
            guard let webView else {
                self.cancelPendingPreparedLoad()
                return
            }

            self.pendingTask = nil
            self.pendingToken = nil
            self.pendingCancellation = nil
            performLoad(webView)
        }
    }

    func clearRelatedNavigationState() {
        pendingBackForwardSettleTask?.cancel()
        pendingBackForwardSettleTask = nil
        pendingMainFrameNavigationKind = nil
        pendingBackForwardNavigationContext = nil
        isFreezingNavDuringBackForwardGesture = false
    }

    func markRegularMainFrameNavigation(
        on webView: WKWebView?,
        environment: HistorySwipeEnvironment
    ) {
        cancelPendingPreparedLoad()
        if isFreezingNavDuringBackForwardGesture {
            finishBackForwardNavigationTracking(using: webView, environment: environment)
        } else {
            pendingBackForwardSettleTask?.cancel()
            pendingBackForwardSettleTask = nil
            pendingBackForwardNavigationContext = nil
        }
        pendingMainFrameNavigationKind = .load
    }

    func beginBackForwardNavigationTracking(
        on webView: WKWebView,
        environment: HistorySwipeEnvironment
    ) {
        cancelPendingPreparedLoad()
        if isFreezingNavDuringBackForwardGesture {
            finishBackForwardNavigationTracking(using: nil, environment: environment)
        } else {
            pendingBackForwardSettleTask?.cancel()
            pendingBackForwardSettleTask = nil
            pendingBackForwardNavigationContext = nil
        }
        pendingMainFrameNavigationKind = .backForward

        let originURL = webView.url ?? environment.currentURL()
        let originHistoryItem = webView.backForwardList.currentItem
        pendingBackForwardNavigationContext = TabBackForwardNavigationContext(
            webView: webView,
            originURL: originURL,
            originHistoryURL: originHistoryItem?.url,
            originHistoryItem: originHistoryItem
        )
        isFreezingNavDuringBackForwardGesture = true

        environment.beginHistorySwipeProtection(
            environment.tabId,
            webView,
            originURL,
            originHistoryItem
        )
        pendingBackForwardSettleTask = Task { @MainActor [weak self, weak webView] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            guard self.pendingMainFrameNavigationKind == .backForward else { return }

            self.finishBackForwardNavigationTracking(using: webView, environment: environment)
        }
    }

    func finishBackForwardNavigationTracking(
        using webView: WKWebView?,
        environment: HistorySwipeEnvironment
    ) {
        let wasFreezingNavigationState = isFreezingNavDuringBackForwardGesture
        let context = pendingBackForwardNavigationContext

        pendingBackForwardSettleTask?.cancel()
        pendingBackForwardSettleTask = nil
        pendingMainFrameNavigationKind = nil
        pendingBackForwardNavigationContext = nil
        isFreezingNavDuringBackForwardGesture = false

        guard wasFreezingNavigationState else { return }
        guard let context else {
            assertionFailure("A frozen history swipe must retain its exact WebView context")
            return
        }
        let protectedWebView = context.webView
        if let webView, webView !== protectedWebView {
            RuntimeDiagnostics.debug(
                "Ignoring non-owning history-swipe finish WebView.",
                category: "TabNavigation"
            )
        }
        let settledWindowId = environment.windowIDContaining(protectedWebView)

        let wasCancelled = environment.finishHistorySwipeProtection(
            environment.tabId,
            protectedWebView,
            protectedWebView.url,
            protectedWebView.backForwardList.currentItem
        )

        applyWindowMutationResult(
            wasCancelled: wasCancelled,
            settledWindowId: settledWindowId,
            environment: environment
        )

        environment.updateNavStateIfCurrentWebViewExists()
    }

    @discardableResult
    func finishBackForwardNavigationTrackingIfOwned(
        by webView: WKWebView,
        environment: HistorySwipeEnvironment
    ) -> Bool {
        guard isFreezingNavDuringBackForwardGesture,
              pendingBackForwardNavigationContext?.webView === webView else {
            return false
        }
        finishBackForwardNavigationTracking(
            using: webView,
            environment: environment
        )
        return true
    }

    func scheduleBackForwardSameDocumentSettle(
        using webView: WKWebView,
        environment: HistorySwipeEnvironment
    ) {
        guard pendingMainFrameNavigationKind == .backForward,
              let context = pendingBackForwardNavigationContext
        else {
            return
        }

        pendingBackForwardSettleTask?.cancel()
        pendingBackForwardSettleTask = Task { @MainActor [weak self, weak webView] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }

            guard let webView else {
                self.finishBackForwardNavigationTracking(using: nil, environment: environment)
                return
            }

            let shouldApplyDeferredActions = BackForwardNavigationSettleDecision
                .shouldApplyDeferredActions(
                    originURL: context.originURL,
                    originHistoryURL: context.originHistoryURL,
                    originHistoryItem: context.originHistoryItem,
                    currentURL: webView.url,
                    currentHistoryURL: webView.backForwardList.currentItem?.url,
                    currentHistoryItem: webView.backForwardList.currentItem
                )

            self.finishBackForwardNavigationTracking(using: webView, environment: environment)

            if shouldApplyDeferredActions {
                environment.scheduleRuntimeStatePersistence()
                environment.syncAcrossWindows(webView)
            }
        }
    }

    private func cancelPendingPreparedLoad() {
        let cancellation = pendingCancellation
        let task = pendingTask
        pendingCancellation = nil
        pendingTask = nil
        pendingToken = nil
        task?.cancel()
        cancellation?()
    }

    private func applyWindowMutationResult(
        wasCancelled: Bool,
        settledWindowId: UUID?,
        environment: HistorySwipeEnvironment
    ) {
        guard let settledWindowId else { return }

        if wasCancelled {
            environment.cancelWindowMutationsAfterHistorySwipe(settledWindowId)
        } else {
            environment.flushWindowMutationsAfterHistorySwipe(settledWindowId)
        }
    }
}
