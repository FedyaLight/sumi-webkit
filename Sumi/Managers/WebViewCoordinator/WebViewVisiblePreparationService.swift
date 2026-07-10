import Foundation
import SumiWebRuntime

/// Joins visibility planning to the two narrow ownership capabilities.
/// Materialization occurs only for tabs selected by the native visibility plan.
@MainActor
final class WebViewVisiblePreparationService {
    private let visibility: WebViewVisibilityRuntime
    private let webViewSessions: WebViewSessionRepository
    private let ownershipQuery: WebViewOwnershipQuery
    private let ownershipService: WebViewOwnershipService

    init(
        visibility: WebViewVisibilityRuntime,
        webViewSessions: WebViewSessionRepository,
        ownershipQuery: WebViewOwnershipQuery,
        ownershipService: WebViewOwnershipService
    ) {
        self.visibility = visibility
        self.webViewSessions = webViewSessions
        self.ownershipQuery = ownershipQuery
        self.ownershipService = ownershipService
    }

    @discardableResult
    func prepare(for windowState: BrowserWindowState) -> Bool {
        prepare(
            for: windowState,
            runtime: visibility.visiblePreparationRuntime()
        )
    }

    @discardableResult
    func prepare(
        for windowState: BrowserWindowState,
        runtime: VisibleWebViewPreparationRuntime
    ) -> Bool {
        visibility.prepareVisibleWebViews(
            for: windowState,
            runtime: runtime,
            webViewSessions: webViewSessions,
            existingWebView: { [ownershipQuery] tabID, windowID in
                ownershipQuery.webView(for: tabID, in: windowID)
            },
            createWebView: { [ownershipService] tabHandle, windowID in
                guard let tab = tabHandle.concreteTab else { return nil }
                return ownershipService.webView(for: tab, in: windowID)
            }
        )
    }

    func schedule(for windowState: BrowserWindowState) {
        let runtime = visibility.visiblePreparationRuntime()
        visibility.schedulePrepareVisibleWebViews(
            for: windowState,
            runtime: runtime,
            prepare: { [weak self] windowHandle in
                guard let self,
                      let concreteWindow = windowHandle.concreteWindowState else {
                    return false
                }
                return prepare(for: concreteWindow, runtime: runtime)
            }
        )
    }
}
