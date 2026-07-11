import Foundation

/// Routes the three AppKit auxiliary-mouse commands to their two concrete
/// browser capabilities. It owns no unrelated tab, window, persistence, or
/// termination commands.
@MainActor
final class BrowserMouseCommandRouter: BrowserMouseButtonCommandRouting {
    private let floatingBar: @MainActor () -> FloatingBarPresentationService?
    private let history: @MainActor () -> BrowserHistoryNavigationOwner?

    init(
        floatingBar: @escaping @MainActor () -> FloatingBarPresentationService?,
        history: @escaping @MainActor () -> BrowserHistoryNavigationOwner?
    ) {
        self.floatingBar = floatingBar
        self.history = history
    }

    func focusFloatingBar(
        in windowState: BrowserWindowState,
        prefill: String,
        navigateCurrentTab: Bool
    ) {
        floatingBar()?.focus(
            in: windowState,
            prefill: prefill,
            navigateCurrentTab: navigateCurrentTab,
            reason: .keyboard
        )
    }

    func goBack(in windowState: BrowserWindowState) {
        history()?.goBack(in: windowState)
    }

    func goForward(in windowState: BrowserWindowState) {
        history()?.goForward(in: windowState)
    }
}
