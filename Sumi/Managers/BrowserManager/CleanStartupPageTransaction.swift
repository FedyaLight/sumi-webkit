import Foundation

@MainActor
final class CleanStartupPageTransaction {
    private let regularLifecycle: TabRegularLifecycleOwner
    private let windowReset: CleanStartupWindowResetTransaction
    private let selection: BrowserTabSelectionOwner
    private let commandPalette: CommandPalettePresentationService

    init(
        regularLifecycle: TabRegularLifecycleOwner,
        windowReset: CleanStartupWindowResetTransaction,
        selection: BrowserTabSelectionOwner,
        commandPalette: CommandPalettePresentationService
    ) {
        self.regularLifecycle = regularLifecycle
        self.windowReset = windowReset
        self.selection = selection
        self.commandPalette = commandPalette
    }

    func open(_ startupURL: URL?, in windowState: BrowserWindowState) {
        guard let startupURL else {
            showEmptyState(in: windowState)
            return
        }
        guard let targetSpace = windowReset.resolvedStartupSpace(
            for: windowState
        ) else {
            showEmptyState(in: windowState)
            return
        }
        let tab = regularLifecycle.createNewTab(
            url: startupURL.absoluteString,
            in: targetSpace,
            activate: false
        )
        _ = selection.selectTab(
            tab,
            in: windowState,
            loadPolicy: .deferred
        )
    }

    private func showEmptyState(in windowState: BrowserWindowState) {
        selection.showEmptyState(in: windowState)
        if windowState.isShowingEmptyState {
            commandPalette.showNewTab(in: windowState)
        }
    }
}
