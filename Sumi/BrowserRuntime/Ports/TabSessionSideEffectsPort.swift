import Foundation

@MainActor
protocol TabSessionSideEffectsPort {
    func captureClosedTab(_ tab: Tab, sourceSpaceId: UUID?)
    func captureDeletedShortcutLauncher(_ pin: ShortcutPin)
    func notifications() -> (any BrowserNotificationPresenting)?
    func closeAuxiliaryMiniWindow(for tab: Tab, reason: AuxiliaryWindowCloseReason)
    func isLiveFolder(_ folderId: UUID) -> Bool
    func deleteLiveFolderState(forFolderIds folderIds: Set<UUID>)
}

@MainActor
struct LiveTabSessionSideEffectsPort: TabSessionSideEffectsPort {
    private weak var browserManager: BrowserManager?

    init(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    func captureClosedTab(_ tab: Tab, sourceSpaceId: UUID?) {
        browserManager?.recentlyClosedManager.captureClosedTab(
            tab,
            sourceSpaceId: sourceSpaceId,
            currentURL: tab.url,
            canGoBack: tab.canGoBack,
            canGoForward: tab.canGoForward
        )
    }

    func captureDeletedShortcutLauncher(_ pin: ShortcutPin) {
        browserManager?.recentlyClosedManager.captureDeletedShortcutLauncher(pin)
    }

    func notifications() -> (any BrowserNotificationPresenting)? {
        browserManager?.notificationPresenter
    }

    func closeAuxiliaryMiniWindow(for tab: Tab, reason: AuxiliaryWindowCloseReason) {
        browserManager?.webViewCloseRouter.closeAuxiliaryMiniWindow(for: tab, reason: reason)
    }

    func isLiveFolder(_ folderId: UUID) -> Bool {
        browserManager?.liveFolderManager.isLiveFolder(folderId) == true
    }

    func deleteLiveFolderState(forFolderIds folderIds: Set<UUID>) {
        browserManager?.liveFolderManager.deleteState(forFolderIds: folderIds)
    }
}
