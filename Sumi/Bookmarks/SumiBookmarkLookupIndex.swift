import Foundation

/// The synchronous lookup projection used by bookmark commands. Repository
/// snapshots remain the authority for tree order and folder structure.
struct SumiBookmarkLookupIndex {
    private var bookmarksByID: [String: SumiBookmark] = [:]
    private var bookmarkIDByURLKey: [String: String] = [:]

    var isEmpty: Bool { bookmarksByID.isEmpty }
    var bookmarks: [SumiBookmark] { Array(bookmarksByID.values) }
    var urlKeys: Set<String> { Set(bookmarkIDByURLKey.keys) }

    func bookmark(for url: URL) -> SumiBookmark? {
        for variant in url.sumiBookmarkButtonURLVariants() {
            let key = Self.urlKey(variant)
            if let id = bookmarkIDByURLKey[key],
               let bookmark = bookmarksByID[id] {
                return bookmark
            }
        }
        return nil
    }

    func bookmark(id: String) -> SumiBookmark? {
        bookmarksByID[id]
    }

    mutating func replace(with bookmarks: [SumiBookmark]) {
        bookmarksByID.removeAll(keepingCapacity: true)
        bookmarkIDByURLKey.removeAll(keepingCapacity: true)
        for bookmark in bookmarks {
            upsert(bookmark)
        }
    }

    mutating func upsert(_ bookmark: SumiBookmark) {
        if let previous = bookmarksByID[bookmark.id] {
            remove(previous)
        }
        bookmarksByID[bookmark.id] = bookmark
        for variant in bookmark.url.sumiBookmarkButtonURLVariants() {
            bookmarkIDByURLKey[Self.urlKey(variant)] = bookmark.id
        }
    }

    mutating func remove(_ bookmark: SumiBookmark) {
        bookmarksByID.removeValue(forKey: bookmark.id)
        for variant in bookmark.url.sumiBookmarkButtonURLVariants() {
            let key = Self.urlKey(variant)
            if bookmarkIDByURLKey[key] == bookmark.id {
                bookmarkIDByURLKey.removeValue(forKey: key)
            }
        }
    }

    mutating func moveBookmarks(ids: [String], to parentID: String) {
        for id in ids where bookmarksByID[id] != nil {
            bookmarksByID[id]?.folderID = parentID
        }
    }

    static func urlKey(_ url: URL) -> String {
        url.absoluteString.lowercased()
    }
}
