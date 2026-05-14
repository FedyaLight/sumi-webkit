import Combine
import Foundation

@MainActor
final class SumiBookmarkManager: ObservableObject {
    @Published private(set) var revision: UInt = 0

    private let repository: any SumiBookmarkRepository
    private let syncFavicons: Bool
    private var bookmarksByID: [String: SumiBookmark] = [:]
    private var bookmarkIDByURLKey: [String: String] = [:]
    private var foldersCache: [SumiBookmarkFolder] = []
    private var didInstallSaveObserver = false
    private var saveObserver: NSObjectProtocol?

    init(
        database: SumiBookmarkDatabase = SumiBookmarkDatabase(),
        syncFavicons: Bool = true
    ) {
        self.repository = SumiDDGBookmarkRepository(database: database)
        self.syncFavicons = syncFavicons
        reload(notify: false)
        installSaveObserver()
    }

    init(
        repository: any SumiBookmarkRepository,
        syncFavicons: Bool = true
    ) {
        self.repository = repository
        self.syncFavicons = syncFavicons
        reload(notify: false)
        installSaveObserver()
    }

    isolated deinit {
        if let saveObserver {
            NotificationCenter.default.removeObserver(saveObserver)
        }
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
        for variant in url.sumiBookmarkButtonURLVariants() {
            let key = Self.urlKey(variant)
            if let id = bookmarkIDByURLKey[key],
               let bookmark = bookmarksByID[id]
            {
                return bookmark
            }
        }
        return nil
    }

    func folders() -> [SumiBookmarkFolder] {
        foldersCache
    }

    func allBookmarks() -> [SumiBookmark] {
        Array(bookmarksByID.values).sorted {
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
        reload()
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
           duplicate.id != id
        {
            throw SumiBookmarkError.duplicateURL
        }

        let bookmark = try repository.updateBookmark(
            id: id,
            title: sanitizedTitle(title, fallbackURL: url),
            url: url,
            folderID: folderID
        )
        reload()
        return bookmark
    }

    @discardableResult
    func createFolder(title: String, parentID: String? = nil) throws -> SumiBookmarkEntity {
        let folder = try repository.createFolder(
            title: sanitizedFolderTitle(title),
            parentID: parentID
        )
        reload()
        return folder
    }

    @discardableResult
    func updateFolder(id: String, title: String, parentID: String?) throws -> SumiBookmarkEntity {
        let folder = try repository.updateFolder(
            id: id,
            title: sanitizedFolderTitle(title),
            parentID: parentID
        )
        reload()
        return folder
    }

    func removeBookmark(id: String) throws {
        try removeEntities(ids: [id])
    }

    func removeEntities(ids: some Sequence<String>) throws {
        try repository.removeEntities(ids: Array(ids))
        reload()
    }

    func moveEntities(
        ids: [String],
        toParentID parentID: String?,
        atIndex index: Int? = nil
    ) throws {
        try repository.moveEntities(ids: ids, toParentID: parentID, atIndex: index)
        reload()
    }

    func importBookmarks(
        _ bookmarks: [SumiBookmarkImportNode],
        parentID: String? = nil
    ) throws -> SumiBookmarksImportSummary {
        let summary = try repository.importBookmarks(
            bookmarks,
            parentID: parentID,
            acceptsURL: Self.canBookmark(_:),
            urlKeys: { Set($0.sumiBookmarkButtonURLVariants().map(Self.urlKey)) }
        )
        reload()
        return summary
    }

    func exportBookmarksHTML(to destination: URL) throws {
        try repository.exportBookmarksHTML(to: destination)
    }

    private func installSaveObserver() {
        guard !didInstallSaveObserver else { return }
        didInstallSaveObserver = true
        let repository = repository
        saveObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: .main
        ) { [weak self, repository] notification in
            guard repository.mergeChanges(fromContextDidSave: notification) else {
                return
            }
            Task { @MainActor [weak self] in
                self?.reload()
            }
        }
    }

    private func reload(notify: Bool = true) {
        let bookmarks = repository.fetchBookmarks()
        bookmarksByID = Dictionary(
            uniqueKeysWithValues: bookmarks.map { ($0.id, $0) }
        )
        var urlIndex: [String: String] = [:]
        for bookmark in bookmarks {
            for variant in bookmark.url.sumiBookmarkButtonURLVariants() {
                urlIndex[Self.urlKey(variant), default: bookmark.id] = bookmark.id
            }
        }
        bookmarkIDByURLKey = urlIndex
        foldersCache = repository.snapshot(sortMode: .manual).flattenedFolders

        if syncFavicons {
            SumiFaviconSystem.shared.syncBookmarks(bookmarks)
        }

        if notify {
            revision &+= 1
        }
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

    private static func urlKey(_ url: URL) -> String {
        url.absoluteString.lowercased()
    }
}

private extension String {
    var nilIfTrimmedEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
