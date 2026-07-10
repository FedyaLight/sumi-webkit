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
    private let runtime: BrowserManagerRuntimeReference

    init(runtime: BrowserManagerRuntimeReference) {
        self.runtime = runtime
    }

    func captureClosedTab(_ tab: Tab, sourceSpaceId: UUID?) {
        runtime.require().recentlyClosedManager.captureClosedTab(
            tab,
            sourceSpaceId: sourceSpaceId,
            currentURL: tab.url,
            canGoBack: tab.canGoBack,
            canGoForward: tab.canGoForward
        )
    }

    func captureDeletedShortcutLauncher(_ pin: ShortcutPin) {
        runtime.require().recentlyClosedManager.captureDeletedShortcutLauncher(pin)
    }

    func notifications() -> (any BrowserNotificationPresenting)? {
        runtime.require().notificationPresenter
    }

    func closeAuxiliaryMiniWindow(for tab: Tab, reason: AuxiliaryWindowCloseReason) {
        runtime.require().webViewCloseRouter.closeAuxiliaryMiniWindow(for: tab, reason: reason)
    }

    func isLiveFolder(_ folderId: UUID) -> Bool {
        runtime.require().liveFolderManager.isLiveFolder(folderId)
    }

    func deleteLiveFolderState(forFolderIds folderIds: Set<UUID>) {
        runtime.require().liveFolderManager.deleteState(forFolderIds: folderIds)
    }
}
