import Foundation

/// Result of asking a resident extension runtime to join native window
/// registration without booting an otherwise unloaded optional subsystem.
@MainActor
enum InitialTabExtensionPreparation {
    case notParticipating
    case privateWindow
    case prepared(any InitialTabExtensionPublication)
    case suppressed
    case rejected
}

/// Exact two-phase capability retained by the window-registration transaction.
/// Preparation is silent; publication is allowed only after the exact window
/// has entered WindowRegistry.
@MainActor
protocol InitialTabExtensionPublication: AnyObject {
    func matches(
        window: BrowserWindowState,
        tab: Tab,
        webView: FocusableWKWebView
    ) -> Bool
    func validateBeforeWindowPublication() -> Bool
    @discardableResult
    func publishInitialTab(afterWindowOpened window: BrowserWindowState) -> Bool
    @discardableResult
    func cancel() -> Bool
    @discardableResult
    func revokePublishedIfCurrent() -> Bool
}

extension InitialTabExtensionPublication {
    @discardableResult
    func revokePublishedIfCurrent() -> Bool { false }
}
