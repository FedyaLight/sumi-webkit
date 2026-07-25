import SumiDomain

/// Shortcut commands that act on the sidebar: its presentation, and the
/// structural actions it hosts.
@MainActor
final class BrowserShortcutSidebarCommands {
    private let presentation: BrowserSidebarPresentationOwner
    private let actions: BrowserSidebarActionOwner

    init(
        presentation: BrowserSidebarPresentationOwner,
        actions: BrowserSidebarActionOwner
    ) {
        self.presentation = presentation
        self.actions = actions
    }

    func toggleSidebar(for windowState: BrowserWindowState) {
        presentation.toggleSidebar(for: windowState)
    }

    func createFolderInCurrentSpace(in windowState: BrowserWindowState) {
        actions.createFolderInCurrentSpace(in: windowState)
    }

    func canCreateFolderInCurrentSpace(
        in windowState: BrowserWindowState
    ) -> Bool {
        actions.canCreateFolderInCurrentSpace(in: windowState)
    }
}
