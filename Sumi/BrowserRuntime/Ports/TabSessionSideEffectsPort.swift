import Foundation

@MainActor
protocol TabSessionSideEffectsPort {
    func captureClosedTab(_ tab: Tab, sourceSpaceId: UUID?)
    func captureDeletedShortcutLauncher(_ pin: ShortcutPin)
    func notifications() -> (any BrowserNotificationPresenting)?
    func closeAuxiliaryMiniWindow(for tab: Tab, reason: AuxiliaryWindowCloseReason)
    func isLiveFolder(_ folderId: UUID) -> Bool
    func reconcileLiveFolderItemMove(
        shortcutPinID: UUID,
        fromFolderID: UUID,
        toFolderID: UUID?,
        targetIndex: Int?
    )
    func deleteLiveFolderState(forFolderIds folderIds: Set<UUID>)
}

@MainActor
struct LiveTabSessionSideEffectsPort: TabSessionSideEffectsPort {
    private let recentlyClosedManager: RecentlyClosedManager
    private let notificationPresenter: any BrowserNotificationPresenting
    private let webViewCloseRouter: BrowserWebViewCloseRouter
    private let folders: TabFolderCollectionStateOwner
    private let liveFolderManager: SumiLiveFolderManager

    init(
        recentlyClosedManager: RecentlyClosedManager,
        notificationPresenter: any BrowserNotificationPresenting,
        webViewCloseRouter: BrowserWebViewCloseRouter,
        folders: TabFolderCollectionStateOwner,
        liveFolderManager: SumiLiveFolderManager
    ) {
        self.recentlyClosedManager = recentlyClosedManager
        self.notificationPresenter = notificationPresenter
        self.webViewCloseRouter = webViewCloseRouter
        self.folders = folders
        self.liveFolderManager = liveFolderManager
    }

    func captureClosedTab(_ tab: Tab, sourceSpaceId: UUID?) {
        recentlyClosedManager.captureClosedTab(
            tab,
            sourceSpaceId: sourceSpaceId,
            currentURL: tab.url,
            canGoBack: tab.canGoBack,
            canGoForward: tab.canGoForward
        )
    }

    func captureDeletedShortcutLauncher(_ pin: ShortcutPin) {
        recentlyClosedManager.captureDeletedShortcutLauncher(pin)
    }

    func notifications() -> (any BrowserNotificationPresenting)? {
        notificationPresenter
    }

    func closeAuxiliaryMiniWindow(for tab: Tab, reason: AuxiliaryWindowCloseReason) {
        webViewCloseRouter.closeAuxiliaryMiniWindow(for: tab, reason: reason)
    }

    func isLiveFolder(_ folderId: UUID) -> Bool {
        folders.folder(by: folderId)?.isLiveFolder == true
    }

    func reconcileLiveFolderItemMove(
        shortcutPinID: UUID,
        fromFolderID: UUID,
        toFolderID: UUID?,
        targetIndex: Int?
    ) {
        liveFolderManager.reconcileExternalMove(
            shortcutPinID: shortcutPinID,
            fromFolderID: fromFolderID,
            toFolderID: toFolderID,
            targetIndex: targetIndex
        )
    }

    func deleteLiveFolderState(forFolderIds folderIds: Set<UUID>) {
        liveFolderManager.deleteState(forFolderIds: folderIds)
    }
}
