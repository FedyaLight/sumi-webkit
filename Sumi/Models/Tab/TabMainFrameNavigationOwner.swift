import Foundation
import WebKit

@MainActor
final class TabMainFrameNavigationOwner {
    private var pendingTask: Task<Void, Never>?
    private var pendingToken: UUID?

    func cancel(clearRelatedNavigationState: () -> Void) {
        pendingTask?.cancel()
        pendingTask = nil
        pendingToken = nil
        clearRelatedNavigationState()
    }

    func perform(
        on webView: WKWebView,
        clearRelatedNavigationState: () -> Void,
        performLoad: @escaping @MainActor (WKWebView) -> Void
    ) {
        cancel(clearRelatedNavigationState: clearRelatedNavigationState)

        let token = UUID()
        pendingToken = token

        performLoad(webView)
        pendingTask = nil
        pendingToken = nil
    }

    func performAfterPreparation(
        on webView: WKWebView,
        clearRelatedNavigationState: () -> Void,
        prepare: @escaping @MainActor () async -> Void,
        performLoad: @escaping @MainActor (WKWebView) -> Void
    ) {
        cancel(clearRelatedNavigationState: clearRelatedNavigationState)

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
}
