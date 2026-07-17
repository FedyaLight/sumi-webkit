import Foundation

@MainActor
final class BrowserProfileDataScopeTransition {
    private let bookmarks: SumiBookmarkManager
    private let extensions: SumiExtensionsModule
    private let favicons: any BrowserFaviconServicing
    private let history: HistoryManager

    init(
        bookmarks: SumiBookmarkManager,
        extensions: SumiExtensionsModule,
        favicons: any BrowserFaviconServicing,
        history: HistoryManager
    ) {
        self.bookmarks = bookmarks
        self.extensions = extensions
        self.favicons = favicons
        self.history = history
    }

    func transition(
        to profile: Profile,
        mutationLease: ProfileReferenceMutationLease
    ) {
        bookmarks.setFaviconPrefetchPartition(
            favicons.partition(profile: profile)
        )
        extensions.switchProfileIfLoaded(
            profile,
            mutationLease: mutationLease
        )
        history.switchProfile(profile.id)
    }
}
