import Combine
import Foundation

@MainActor
final class SumiBookmarkManager: ObservableObject {
    @Published private(set) var publicationRevision: UInt = 0
    private(set) var revision: UInt = 0

    private let repository: any SumiBookmarkRepository
    private let syncFavicons: Bool
    private let faviconService: (any BrowserFaviconServicing)?
    private var faviconPrefetchPartition: SumiFaviconPartition = .regular()
    private var bookmarkIndex = SumiBookmarkLookupIndex()
    private var foldersCache: [SumiBookmarkFolder] = []
    private var foldersCacheNeedsReload = false
    private var pendingFaviconBookmarksByID: [String: SumiBookmark] = [:]
    private var publicationTask: Task<Void, Never>?
    private var isInitialFaviconSyncDeferred: Bool

    convenience init(
        database: SumiDatabase,
        faviconService: any BrowserFaviconServicing,
        defersInitialFaviconSync: Bool = false
    ) {
        self.init(
            database: database,
            syncFavicons: true,
            faviconService: faviconService,
            defersInitialFaviconSync: defersInitialFaviconSync
        )
    }

    convenience init(
        database: SumiDatabase,
        syncFavicons: Bool
    ) {
        self.init(
            database: database,
            syncFavicons: syncFavicons,
            faviconService: nil,
            defersInitialFaviconSync: false
        )
    }

    private init(
        database: SumiDatabase,
        syncFavicons: Bool,
        faviconService: (any BrowserFaviconServicing)?,
        defersInitialFaviconSync: Bool
    ) {
        self.repository = SumiDatabaseBookmarkRepository(database: database)
        self.syncFavicons = syncFavicons
        self.faviconService = faviconService
        self.isInitialFaviconSyncDeferred =
            syncFavicons && defersInitialFaviconSync
        reload(notify: false)
    }

    isolated deinit {
        publicationTask?.cancel()
    }

    func canBookmark(_ tab: Tab?) -> Bool {
        guard let tab,
              !tab.isEphemeral,
              !tab.representsSumiEmptySurface,
              !tab.representsSumiInternalSurface
        else {
            return false
        }
        return Self.canBookmark(tab.url)
    }

    static func canBookmark(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return false
        }
        return url.host?.isEmpty == false
    }

    func isBookmarked(_ url: URL) -> Bool {
        bookmark(for: url) != nil
    }

    func bookmark(for url: URL) -> SumiBookmark? {
        bookmarkIndex.bookmark(for: url)
    }

    func folders() -> [SumiBookmarkFolder] {
        refreshFoldersCacheIfNeeded()
        return foldersCache
    }

    func setFaviconPrefetchPartition(_ partition: SumiFaviconPartition) {
        guard faviconPrefetchPartition != partition else { return }
        faviconPrefetchPartition = partition
        guard syncFavicons,
              isInitialFaviconSyncDeferred == false,
              !bookmarkIndex.isEmpty
        else {
            return
        }
        faviconService?.syncBookmarks(
            bookmarkIndex.bookmarks,
            partition: faviconPrefetchPartition
        )
        pendingFaviconBookmarksByID.removeAll(keepingCapacity: true)
    }

    func startDeferredFaviconSync() {
        guard isInitialFaviconSyncDeferred else { return }
        isInitialFaviconSyncDeferred = false
        guard !bookmarkIndex.isEmpty else { return }
        faviconService?.syncBookmarks(
            bookmarkIndex.bookmarks,
            partition: faviconPrefetchPartition
        )
        pendingFaviconBookmarksByID.removeAll(keepingCapacity: true)
    }

    func allBookmarks() -> [SumiBookmark] {
        bookmarkIndex.bookmarks.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    func snapshot(sortMode: SumiBookmarkSortMode = .manual) -> SumiBookmarksSnapshot {
        repository.snapshot(sortMode: sortMode)
    }

    func visibleEntities(
        in folderID: String?,
        query: String,
        sortMode: SumiBookmarkSortMode
    ) -> [SumiBookmarkEntity] {
        let snapshot = snapshot(sortMode: sortMode)
        let folder = folderID.flatMap { snapshot.entitiesByID[$0] } ?? snapshot.root
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return folder.children
        }

        return flattenedDescendants(of: folder).filter { $0.matchesSearch(trimmedQuery) }
    }

    func entity(id: String, sortMode: SumiBookmarkSortMode = .manual) -> SumiBookmarkEntity? {
        repository.entity(id: id, sortMode: sortMode)
    }

    func openableURLs(for ids: some Sequence<String>) -> [URL] {
        repository.openableURLs(for: Array(ids))
    }

    func editorState(for tab: Tab) throws -> SumiBookmarkEditorState {
        guard canBookmark(tab) else { throw SumiBookmarkError.unsupportedURL }

        if let bookmark = bookmark(for: tab.url) {
            return SumiBookmarkEditorState(
                mode: .edit,
                bookmarkID: bookmark.id,
                tabID: tab.id,
                pageURL: tab.url,
                title: bookmark.title,
                urlString: bookmark.url.absoluteString,
                folderID: bookmark.folderID
            )
        }

        return SumiBookmarkEditorState(
            mode: .add,
            bookmarkID: nil,
            tabID: tab.id,
            pageURL: tab.url,
            title: suggestedTitle(for: tab),
            urlString: tab.url.absoluteString,
            folderID: nil
        )
    }

    @discardableResult
    func createBookmark(
        url: URL,
        title: String,
        folderID: String? = nil
    ) throws -> SumiBookmark {
        guard Self.canBookmark(url) else { throw SumiBookmarkError.unsupportedURL }
        if let existing = bookmark(for: url) {
            return existing
        }

        let bookmark = try repository.createBookmark(
            url: url,
            title: sanitizedTitle(title, fallbackURL: url),
            folderID: folderID
        )
        applyBookmark(bookmark, queueFavicon: true)
        recordLocalMutation()
        return bookmark
    }

    @discardableResult
    func updateBookmark(
        id: String,
        title: String,
        url: URL,
        folderID: String?
    ) throws -> SumiBookmark {
        guard Self.canBookmark(url) else { throw SumiBookmarkError.unsupportedURL }
        if let duplicate = bookmark(for: url),
           duplicate.id != id {
            throw SumiBookmarkError.duplicateURL
        }

        let bookmark = try repository.updateBookmark(
            id: id,
            title: sanitizedTitle(title, fallbackURL: url),
            url: url,
            folderID: folderID
        )
        let queueFavicon = bookmarkIndex.bookmark(id: id)?.url != bookmark.url
        applyBookmark(bookmark, queueFavicon: queueFavicon)
        recordLocalMutation()
        return bookmark
    }

    @discardableResult
    func createFolder(title: String, parentID: String? = nil) throws -> SumiBookmarkEntity {
        let folder = try repository.createFolder(
            title: sanitizedFolderTitle(title),
            parentID: parentID
        )
        recordLocalMutation()
        return folder
    }

    @discardableResult
    func createFolderWithBookmarks(
        title: String,
        parentID: String? = nil,
        bookmarks: [SumiBookmarkCreateRequest]
    ) throws -> SumiBookmarkFolderBatchCreateResult {
        let prepared = try prepareUniqueBookmarkRequests(bookmarks)
        let result = try repository.createFolderWithBookmarks(
            title: sanitizedFolderTitle(title),
            parentID: parentID,
            bookmarks: prepared.requests
        )
        for bookmark in result.bookmarks {
            applyBookmark(bookmark, queueFavicon: true)
        }
        recordLocalMutation()
        return SumiBookmarkFolderBatchCreateResult(
            folder: result.folder,
            bookmarks: result.bookmarks,
            duplicates: prepared.duplicates
        )
    }

    @discardableResult
    func updateFolder(id: String, title: String, parentID: String?) throws -> SumiBookmarkEntity {
        let folder = try repository.updateFolder(
            id: id,
            title: sanitizedFolderTitle(title),
            parentID: parentID
        )
        recordLocalMutation()
        return folder
    }

    func removeBookmark(id: String) throws {
        try removeEntities(ids: [id])
    }

    func removeEntities(ids: some Sequence<String>) throws {
        let ids = Array(ids)
        guard !ids.isEmpty else { return }
        let removedBookmarks = try repository.removeEntities(ids: ids)
        for bookmark in removedBookmarks {
            bookmarkIndex.remove(bookmark)
            pendingFaviconBookmarksByID.removeValue(forKey: bookmark.id)
        }
        recordLocalMutation()
    }

    func moveEntities(
        ids: [String],
        toParentID parentID: String?,
        atIndex index: Int? = nil
    ) throws {
        guard !ids.isEmpty else { return }
        try repository.moveEntities(ids: ids, toParentID: parentID, atIndex: index)
        let resolvedParentID = parentID ?? SumiBookmarkConstants.favoritesFolderID
        bookmarkIndex.moveBookmarks(ids: ids, to: resolvedParentID)
        recordLocalMutation()
    }

    func importBookmarks(
        _ bookmarks: [SumiBookmarkImportNode],
        parentID: String? = nil
    ) throws -> SumiBookmarksImportSummary {
        let summary = try repository.importBookmarks(
            bookmarks,
            parentID: parentID,
            acceptsURL: Self.canBookmark(_:),
            urlKeys: {
                Set($0.sumiBookmarkButtonURLVariants().map(
                    SumiBookmarkLookupIndex.urlKey
                ))
            }
        )
        reload()
        return summary
    }

    func replaceBookmarks(
        _ bookmarks: [SumiBookmarkImportNode]
    ) throws -> SumiBookmarksImportSummary {
        let summary = try repository.replaceBookmarks(
            bookmarks,
            acceptsURL: Self.canBookmark(_:),
            urlKeys: {
                Set($0.sumiBookmarkButtonURLVariants().map(
                    SumiBookmarkLookupIndex.urlKey
                ))
            }
        )
        reload()
        return summary
    }

    func restoreSnapshot(_ snapshot: SumiBookmarksSnapshot) throws {
        try repository.restoreSnapshot(snapshot)
        reload()
    }

    func exportBookmarksHTML(to destination: URL) throws {
        try repository.exportBookmarksHTML(to: destination)
    }

    private func reload(notify: Bool = true) {
        let bookmarks = repository.fetchBookmarks()
        bookmarkIndex.replace(with: bookmarks)
        foldersCache = repository.snapshot(sortMode: .manual).flattenedFolders
        foldersCacheNeedsReload = false
        pendingFaviconBookmarksByID.removeAll(keepingCapacity: true)

        if syncFavicons, isInitialFaviconSyncDeferred == false {
            faviconService?.syncBookmarks(
                bookmarks,
                partition: faviconPrefetchPartition
            )
        }

        if notify {
            revision &+= 1
            schedulePublication()
        }
    }

    private func recordLocalMutation() {
        foldersCacheNeedsReload = true
        revision &+= 1
        schedulePublication()
    }

    private func applyBookmark(
        _ bookmark: SumiBookmark,
        queueFavicon: Bool
    ) {
        bookmarkIndex.upsert(bookmark)
        if queueFavicon, syncFavicons, faviconService != nil {
            pendingFaviconBookmarksByID[bookmark.id] = bookmark
        }
    }

    private func schedulePublication() {
        guard publicationTask == nil else { return }
        publicationTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.publishPendingChanges()
        }
    }

    private func publishPendingChanges() {
        publicationTask = nil
        refreshFoldersCacheIfNeeded()

        if syncFavicons,
           isInitialFaviconSyncDeferred == false,
           !pendingFaviconBookmarksByID.isEmpty {
            let bookmarks = pendingFaviconBookmarksByID.values.sorted {
                $0.id < $1.id
            }
            pendingFaviconBookmarksByID.removeAll(keepingCapacity: true)
            faviconService?.syncBookmarks(
                bookmarks,
                partition: faviconPrefetchPartition
            )
        }

        publicationRevision &+= 1
    }

    private func refreshFoldersCacheIfNeeded() {
        guard foldersCacheNeedsReload else { return }
        foldersCache = repository.snapshot(sortMode: .manual).flattenedFolders
        foldersCacheNeedsReload = false
    }

    private func flattenedDescendants(of entity: SumiBookmarkEntity) -> [SumiBookmarkEntity] {
        entity.children.flatMap { child in
            [child] + flattenedDescendants(of: child)
        }
    }

    private func suggestedTitle(for tab: Tab) -> String {
        let title = tab.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, !tab.representsSumiEmptySurface {
            return title
        }
        return tab.url.sumiSuggestedTitlePlaceholder ?? tab.url.absoluteString
    }

    private func sanitizedTitle(_ title: String, fallbackURL: URL) -> String {
        title.nilIfTrimmedEmpty
            ?? fallbackURL.sumiSuggestedTitlePlaceholder
            ?? fallbackURL.absoluteString
    }

    private func sanitizedFolderTitle(_ title: String) -> String {
        title.nilIfTrimmedEmpty ?? "Folder"
    }

    private func prepareUniqueBookmarkRequests(
        _ requests: [SumiBookmarkCreateRequest]
    ) throws -> (requests: [SumiBookmarkCreateRequest], duplicates: Int) {
        var seenURLKeys = bookmarkIndex.urlKeys
        var preparedRequests: [SumiBookmarkCreateRequest] = []
        preparedRequests.reserveCapacity(requests.count)
        var duplicates = 0

        for request in requests {
            guard Self.canBookmark(request.url) else {
                throw SumiBookmarkError.unsupportedURL
            }

            let urlKeys = Set(
                request.url.sumiBookmarkButtonURLVariants().map(
                    SumiBookmarkLookupIndex.urlKey
                )
            )
            if urlKeys.contains(where: { seenURLKeys.contains($0) }) {
                duplicates += 1
                continue
            }

            seenURLKeys.formUnion(urlKeys)
            preparedRequests.append(
                SumiBookmarkCreateRequest(
                    url: request.url,
                    title: sanitizedTitle(request.title, fallbackURL: request.url)
                )
            )
        }

        return (preparedRequests, duplicates)
    }
}

private extension String {
    var nilIfTrimmedEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
