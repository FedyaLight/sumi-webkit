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
        let updateNavigationStateIfCurrentWebViewExists: @MainActor () -> Void
        let scheduleRuntimeStatePersistence: @MainActor () -> Void
        let syncAcrossWindows: @MainActor (WKWebView) -> Void
    }

    private var pendingTask: Task<Void, Never>?
    private var pendingToken: UUID?
    private var pendingBackForwardNavigationContext: TabBackForwardNavigationContext?
    private var pendingBackForwardSettleTask: Task<Void, Never>?
    var pendingMainFrameNavigationKind: TabMainFrameNavigationKind?
    var isFreezingNavigationStateDuringBackForwardGesture = false

    func cancelPendingMainFrameNavigation() {
        cancelPendingPreparedLoad()
        clearRelatedNavigationState()
    }

    func perform(
        on webView: WKWebView,
        performLoad: @escaping @MainActor (WKWebView) -> Void
    ) {
        cancelPendingMainFrameNavigation()

        let token = UUID()
        pendingToken = token

        performLoad(webView)
        pendingTask = nil
        pendingToken = nil
    }

    func performAfterPreparation(
        on webView: WKWebView,
        prepare: @escaping @MainActor () async -> Void,
        performLoad: @escaping @MainActor (WKWebView) -> Void
    ) {
        cancelPendingMainFrameNavigation()

        let token = UUID()
        pendingToken = token
        pendingTask = Task { @MainActor [weak self, weak webView] in
            await prepare()
            guard let self,
                  let webView,
                  self.pendingToken == token
            else { return }

            performLoad(webView)
            self.pendingTask = nil
            self.pendingToken = nil
        }
    }

    func clearRelatedNavigationState() {
        pendingBackForwardSettleTask?.cancel()
        pendingBackForwardSettleTask = nil
        pendingMainFrameNavigationKind = nil
        pendingBackForwardNavigationContext = nil
        isFreezingNavigationStateDuringBackForwardGesture = false
    }

    func markRegularMainFrameNavigation(
        on webView: WKWebView?,
        environment: HistorySwipeEnvironment
    ) {
        cancelPendingPreparedLoad()

        let wasFreezingNavigationState = isFreezingNavigationStateDuringBackForwardGesture
        let protectedWebView = webView ?? environment.currentWebView()
        let settledWindowId = protectedWebView.flatMap(environment.windowIDContaining)

        pendingBackForwardSettleTask?.cancel()
        pendingBackForwardSettleTask = nil
        pendingMainFrameNavigationKind = .load
        pendingBackForwardNavigationContext = nil
        isFreezingNavigationStateDuringBackForwardGesture = false

        if wasFreezingNavigationState {
            let wasCancelled = environment.finishHistorySwipeProtection(
                environment.tabId,
                protectedWebView,
                protectedWebView?.url,
                protectedWebView?.backForwardList.currentItem
            )

            applyWindowMutationResult(
                wasCancelled: wasCancelled,
                settledWindowId: settledWindowId,
                environment: environment
            )
        }

        if wasFreezingNavigationState {
            environment.updateNavigationStateIfCurrentWebViewExists()
        }
    }

    func beginBackForwardNavigationTracking(
        on webView: WKWebView,
        environment: HistorySwipeEnvironment
    ) {
        cancelPendingPreparedLoad()
        pendingBackForwardSettleTask?.cancel()
        pendingMainFrameNavigationKind = .backForward

        let originURL = webView.url ?? environment.currentURL()
        let originHistoryItem = webView.backForwardList.currentItem
        pendingBackForwardNavigationContext = TabBackForwardNavigationContext(
            originURL: originURL,
            originHistoryURL: originHistoryItem?.url,
            originHistoryItem: originHistoryItem
        )
        isFreezingNavigationStateDuringBackForwardGesture = true

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
        let wasFreezingNavigationState = isFreezingNavigationStateDuringBackForwardGesture
        let resolvedWebView = webView ?? environment.currentWebView()
        let settledWindowId = resolvedWebView.flatMap(environment.windowIDContaining)

        pendingBackForwardSettleTask?.cancel()
        pendingBackForwardSettleTask = nil
        pendingMainFrameNavigationKind = nil
        pendingBackForwardNavigationContext = nil
        isFreezingNavigationStateDuringBackForwardGesture = false

        let wasCancelled = environment.finishHistorySwipeProtection(
            environment.tabId,
            resolvedWebView,
            resolvedWebView?.url,
            resolvedWebView?.backForwardList.currentItem
        )

        applyWindowMutationResult(
            wasCancelled: wasCancelled,
            settledWindowId: settledWindowId,
            environment: environment
        )

        if wasFreezingNavigationState {
            environment.updateNavigationStateIfCurrentWebViewExists()
        }
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
        pendingTask?.cancel()
        pendingTask = nil
        pendingToken = nil
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
