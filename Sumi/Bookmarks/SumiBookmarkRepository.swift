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
    func updateFolder(id: String, title: String, parentID: String?) throws -> SumiBookmarkEntity
    func removeEntities(ids: [String]) throws
    func moveEntities(ids: [String], toParentID parentID: String?, atIndex index: Int?) throws
    func importBookmarks(
        _ bookmarks: [SumiBookmarkImportNode],
        parentID: String?,
        acceptsURL: @escaping (URL) -> Bool,
        urlKeys: @escaping (URL) -> Set<String>
    ) throws -> SumiBookmarksImportSummary
    func exportBookmarksHTML(to destination: URL) throws
    nonisolated func mergeChanges(fromContextDidSave notification: Notification) -> Bool
}
