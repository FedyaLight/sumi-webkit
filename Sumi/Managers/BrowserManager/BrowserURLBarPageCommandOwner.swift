import Foundation

@MainActor
final class BrowserURLBarPageCommandOwner {
    private let activePages: ActivePageResolver
    private let commandPalette: CommandPalettePresentationService
    private let pageCommands: ActivePageCommandService
    private let clipboard: BrowserURLClipboardService
    private let sidebar: BrowserSidebarPresentationOwner

    init(
        activePages: ActivePageResolver,
        commandPalette: CommandPalettePresentationService,
        pageCommands: ActivePageCommandService,
        clipboard: BrowserURLClipboardService,
        sidebar: BrowserSidebarPresentationOwner
    ) {
        self.activePages = activePages
        self.commandPalette = commandPalette
        self.pageCommands = pageCommands
        self.clipboard = clipboard
        self.sidebar = sidebar
    }

    func activePage(in windowState: BrowserWindowState) -> ActivePageResolution? {
        activePages.resolve(in: windowState)
    }

    func focusCommandPalette(
        in windowState: BrowserWindowState,
        prefill: String,
        navigateCurrentTab: Bool
    ) {
        commandPalette.focus(
            in: windowState,
            prefill: prefill,
            navigateCurrentTab: navigateCurrentTab,
            reason: .keyboard
        )
    }

    func reload(_ page: ActivePageResolution, reason: String) -> Bool {
        pageCommands.reload(page, reason: reason) != .failed
    }

    func copyURL(_ urlString: String, in windowState: BrowserWindowState) {
        _ = clipboard.copy(urlString, in: windowState)
    }

    func toggleSidebar(in windowState: BrowserWindowState) {
        sidebar.toggleSidebar(for: windowState)
    }
}
