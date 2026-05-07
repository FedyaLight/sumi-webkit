import Foundation

@MainActor
protocol SumiFaviconMirrorSyncing: BookmarkManager {
    func initializeFetcherState()
    func syncShortcutPins(_ pins: [ShortcutPin])
    func syncBookmarks(_ bookmarks: [SumiBookmark])
    func startFetching()
}

protocol SumiBookmarkFaviconFetchScheduling: AnyObject, Sendable {
    func initializeFetcherState()
    func updateBookmarkIDs(modified: Set<String>, deleted: Set<String>)
    func startFetching() async
}
