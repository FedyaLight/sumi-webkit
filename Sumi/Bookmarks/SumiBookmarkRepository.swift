import Foundation

@MainActor
protocol SumiBookmarkRepository: AnyObject, Sendable {
    func fetchBookmarks() -> [SumiBookmark]
    func snapshot(sortMode: SumiBookmarkSortMode) -> SumiBookmarksSnapshot
    func entity(id: String, sortMode: SumiBookmarkSortMode) -> SumiBookmarkEntity?
    func openableURLs(for ids: [String]) -> [URL]
    func createBookmark(url: URL, title: String, folderID: String?) throws -> SumiBookmark
    func updateBookmark(id: String, title: String, url: URL, folderID: String?) throws -> SumiBookmark
    func createFolder(title: String, parentID: String?) throws -> SumiBookmarkEntity
    func createFolderWithBookmarks(
        title: String,
        parentID: String?,
        bookmarks: [SumiBookmarkCreateRequest]
    ) throws -> SumiBookmarkFolderCreateResult
    func updateFolder(id: String, title: String, parentID: String?) throws -> SumiBookmarkEntity
    func removeEntities(ids: [String]) throws -> [SumiBookmark]
    func moveEntities(ids: [String], toParentID parentID: String?, atIndex index: Int?) throws
    func importBookmarks(
        _ bookmarks: [SumiBookmarkImportNode],
        parentID: String?,
        acceptsURL: @escaping (URL) -> Bool,
        urlKeys: @escaping (URL) -> Set<String>
    ) throws -> SumiBookmarksImportSummary
    func replaceBookmarks(
        _ bookmarks: [SumiBookmarkImportNode],
        acceptsURL: @escaping (URL) -> Bool,
        urlKeys: @escaping (URL) -> Set<String>
    ) throws -> SumiBookmarksImportSummary
    func restoreSnapshot(_ snapshot: SumiBookmarksSnapshot) throws
    func exportBookmarksHTML(to destination: URL) throws
}

final class SumiUnavailableBookmarkRepository: SumiBookmarkRepository {
    private let reason: String

    init(reason: String) {
        self.reason = reason
    }

    func fetchBookmarks() -> [SumiBookmark] {
        []
    }

    func snapshot(sortMode: SumiBookmarkSortMode) -> SumiBookmarksSnapshot {
        let favorites = SumiBookmarkEntity(
            id: SumiBookmarkConstants.favoritesFolderID,
            kind: .folder,
            title: "Favorites",
            url: nil,
            parentID: SumiBookmarkConstants.rootFolderID,
            parentTitle: "Bookmarks",
            children: [],
            childBookmarkCount: 0
        )
        let root = SumiBookmarkEntity(
            id: SumiBookmarkConstants.rootFolderID,
            kind: .folder,
            title: "Bookmarks",
            url: nil,
            parentID: nil,
            parentTitle: nil,
            children: [favorites],
            childBookmarkCount: 0
        )
        return SumiBookmarksSnapshot(
            root: root,
            flattenedFolders: [.init(id: favorites.id, title: favorites.title, depth: 0)],
            entitiesByID: [root.id: root, favorites.id: favorites]
        )
    }

    func entity(id: String, sortMode: SumiBookmarkSortMode) -> SumiBookmarkEntity? {
        snapshot(sortMode: sortMode).entitiesByID[id]
    }

    func openableURLs(for ids: [String]) -> [URL] {
        []
    }

    func createBookmark(url: URL, title: String, folderID: String?) throws -> SumiBookmark {
        throw unavailableError
    }

    func updateBookmark(id: String, title: String, url: URL, folderID: String?) throws -> SumiBookmark {
        throw unavailableError
    }

    func createFolder(title: String, parentID: String?) throws -> SumiBookmarkEntity {
        throw unavailableError
    }

    func createFolderWithBookmarks(
        title: String,
        parentID: String?,
        bookmarks: [SumiBookmarkCreateRequest]
    ) throws -> SumiBookmarkFolderCreateResult {
        throw unavailableError
    }

    func updateFolder(id: String, title: String, parentID: String?) throws -> SumiBookmarkEntity {
        throw unavailableError
    }

    func removeEntities(ids: [String]) throws -> [SumiBookmark] {
        throw unavailableError
    }

    func moveEntities(ids: [String], toParentID parentID: String?, atIndex index: Int?) throws {
        throw unavailableError
    }

    func importBookmarks(
        _ bookmarks: [SumiBookmarkImportNode],
        parentID: String?,
        acceptsURL: @escaping (URL) -> Bool,
        urlKeys: @escaping (URL) -> Set<String>
    ) throws -> SumiBookmarksImportSummary {
        throw unavailableError
    }

    func replaceBookmarks(
        _ bookmarks: [SumiBookmarkImportNode],
        acceptsURL: @escaping (URL) -> Bool,
        urlKeys: @escaping (URL) -> Set<String>
    ) throws -> SumiBookmarksImportSummary {
        throw unavailableError
    }

    func restoreSnapshot(_ snapshot: SumiBookmarksSnapshot) throws {
        throw unavailableError
    }

    func exportBookmarksHTML(to destination: URL) throws {
        throw unavailableError
    }

    private var unavailableError: SumiBookmarkError {
        .storageUnavailable(reason)
    }
}
