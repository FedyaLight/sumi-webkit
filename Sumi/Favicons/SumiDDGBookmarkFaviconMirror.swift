import Bookmarks
import Foundation

@MainActor
final class SumiDDGBookmarkFaviconMirror: SumiFaviconMirrorSyncing {
    private let database: SumiDDGCoreDataDatabase
    private let mirrorManager: SumiBookmarkMirrorManager
    private var fetchScheduler: SumiDDGBookmarkFaviconFetchScheduler?

    init(database: SumiDDGCoreDataDatabase) {
        self.database = database
        self.mirrorManager = SumiBookmarkMirrorManager(database: database)
    }

    func attachDDGFetcher(
        applicationSupportURL: URL,
        faviconStore: @escaping @MainActor () async -> any SumiFaviconStoring
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
        faviconStore: @escaping @MainActor () async -> any SumiFaviconStoring
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
        database: SumiDDGCoreDataDatabase,
        stateStore: BookmarksFaviconsFetcherStateStoring,
        fetcher: FaviconFetching,
        faviconStore: @escaping @MainActor () async -> any SumiFaviconStoring
    ) {
        self.stateStore = stateStore
        self.faviconFetcher = fetcher
        self.fetcher = BookmarksFaviconsFetcher(
            database: database.ddgDatabase,
            stateStore: stateStore,
            fetcher: fetcher,
            faviconStore: {
                let storage = await faviconStore()
                return SumiDDGBookmarkFaviconStoringAdapter(storage: storage)
            },
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
