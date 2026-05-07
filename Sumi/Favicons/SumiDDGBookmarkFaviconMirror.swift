import Bookmarks
import Foundation
import Persistence

@MainActor
final class SumiDDGBookmarkFaviconMirror: SumiFaviconMirrorSyncing {
    private let database: CoreDataDatabase
    private let mirrorManager: SumiBookmarkMirrorManager
    private var fetchScheduler: SumiDDGBookmarkFaviconFetchScheduler?

    init(database: CoreDataDatabase) {
        self.database = database
        self.mirrorManager = SumiBookmarkMirrorManager(database: database)
    }

    func attachDDGFetcher(
        applicationSupportURL: URL,
        faviconStore: @escaping @MainActor () async -> Bookmarks.FaviconStoring
    ) throws {
        let stateStore = try BookmarksFaviconsFetcherStateStore(applicationSupportURL: applicationSupportURL)
        attachDDGFetcher(
            stateStore: stateStore,
            fetcher: FaviconFetcher(),
            faviconStore: faviconStore
        )
    }

    func attachDDGFetcher(
        stateStore: BookmarksFaviconsFetcherStateStoring,
        fetcher: FaviconFetching,
        faviconStore: @escaping @MainActor () async -> Bookmarks.FaviconStoring
    ) {
        attach(
            fetchScheduler: SumiDDGBookmarkFaviconFetchScheduler(
                database: database,
                stateStore: stateStore,
                fetcher: fetcher,
                faviconStore: faviconStore
            )
        )
    }

    private func attach(fetchScheduler: SumiDDGBookmarkFaviconFetchScheduler) {
        self.fetchScheduler = fetchScheduler
        mirrorManager.attach(fetchScheduler: fetchScheduler)
    }

    func initializeFetcherState() {
        mirrorManager.initializeFetcherState()
    }

    func syncShortcutPins(_ pins: [ShortcutPin]) {
        mirrorManager.syncShortcutPins(pins)
    }

    func syncBookmarks(_ bookmarks: [SumiBookmark]) {
        mirrorManager.syncBookmarks(bookmarks)
    }

    func startFetching() {
        guard let fetchScheduler else { return }
        Task {
            await fetchScheduler.startFetching()
        }
    }

    func allHosts() -> Set<String> {
        mirrorManager.allHosts()
    }
}

final class SumiDDGBookmarkFaviconFetchScheduler: SumiBookmarkFaviconFetchScheduling, @unchecked Sendable {
    private let stateStore: BookmarksFaviconsFetcherStateStoring
    private let faviconFetcher: FaviconFetching
    private let fetcher: BookmarksFaviconsFetcher

    init(
        database: CoreDataDatabase,
        stateStore: BookmarksFaviconsFetcherStateStoring,
        fetcher: FaviconFetching,
        faviconStore: @escaping @MainActor () async -> Bookmarks.FaviconStoring
    ) {
        self.stateStore = stateStore
        self.faviconFetcher = fetcher
        self.fetcher = BookmarksFaviconsFetcher(
            database: database,
            stateStore: stateStore,
            fetcher: fetcher,
            faviconStore: faviconStore,
            errorEvents: nil
        )
    }

    func initializeFetcherState() {
        fetcher.initializeFetcherState()
    }

    func updateBookmarkIDs(modified: Set<String>, deleted: Set<String>) {
        fetcher.updateBookmarkIDs(modified: modified, deleted: deleted)
    }

    func startFetching() async {
        await fetcher.startFetching()
    }
}
