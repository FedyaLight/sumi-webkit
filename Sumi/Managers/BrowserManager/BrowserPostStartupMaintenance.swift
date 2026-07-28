import Foundation

@MainActor
enum BrowserPostStartupMaintenance {
    static func start(
        history: HistoryManager,
        bookmarks: SumiBookmarkManager
    ) {
        guard history.start() else { return }
        bookmarks.startDeferredFaviconSync()

        let stagingRoot = SumiImportBulkStagingStore.defaultRootDirectory()
        Task.detached(priority: .utility) {
            guard Task.isCancelled == false else { return }
            SumiImportBulkStagingStore(rootDirectory: stagingRoot)
                .sweepOrphans()
        }
    }
}
