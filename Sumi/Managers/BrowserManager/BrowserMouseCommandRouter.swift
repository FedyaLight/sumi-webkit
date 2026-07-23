import Foundation

/// Routes the three AppKit auxiliary-mouse commands to their two concrete
/// browser capabilities. It owns no unrelated tab, window, persistence, or
/// termination commands.
@MainActor
final class BrowserMouseCommandRouter: BrowserMouseButtonCommandRouting {
    private let commandPalette: @MainActor () -> CommandPalettePresentationService?
    private let history: @MainActor () -> BrowserHistoryNavigationOwner?

    init(
        commandPalette: @escaping @MainActor () -> CommandPalettePresentationService?,
        history: @escaping @MainActor () -> BrowserHistoryNavigationOwner?
    ) {
        self.commandPalette = commandPalette
        self.history = history
    }

    func focusCommandPalette(
        in windowState: BrowserWindowState,
        prefill: String,
        navigateCurrentTab: Bool
    ) {
        commandPalette()?.focus(
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
