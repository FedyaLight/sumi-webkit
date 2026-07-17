import Foundation

@MainActor
final class CleanStartupWorkflow {
    private let archive: CleanStartupSessionArchiveTransaction
    private let stateReset: TabStartupStateReset
    private let windows: CleanStartupWindowResetTransaction
    private let page: CleanStartupPageTransaction

    init(
        archive: CleanStartupSessionArchiveTransaction,
        stateReset: TabStartupStateReset,
        windows: CleanStartupWindowResetTransaction,
        page: CleanStartupPageTransaction
    ) {
        self.archive = archive
        self.stateReset = stateReset
        self.windows = windows
        self.page = page
    }

    var firstRegularWindow: BrowserWindowState? {
        windows.firstRegularWindow
    }

    func apply(opening startupURL: URL?) {
        archive.archiveLoadedSession()
        stateReset.resetRegularTabsAndShortcutLiveInstances()

        guard let selectedWindow = windows.firstRegularWindow else { return }
        windows.reset(selectedWindow: selectedWindow)
        page.open(startupURL, in: selectedWindow)
        archive.persistCleanState()
    }
}
