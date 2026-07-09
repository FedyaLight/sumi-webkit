//
//  TopLinkSuggestionOwner.swift
//  Sumi
//
//

import Foundation

/// Builds the "top links" suggestion list shown with no query text: most
/// visited history sites, then bookmarks, then open tabs, deduplicated by
/// canonical URL. Depends only on narrow closures so it can be tested with
/// fixture data instead of live History/Bookmark/Tab managers.
@MainActor
final class TopLinkSuggestionOwner {
    private let topVisitedSites: @MainActor (_ limit: Int) async -> [HistoryListItem]
    private let bookmarks: @MainActor () -> [SumiBookmark]
    private let openTabs: @MainActor () -> [Tab]

    init(
        topVisitedSites: @escaping @MainActor (_ limit: Int) async -> [HistoryListItem],
        bookmarks: @escaping @MainActor () -> [SumiBookmark],
        openTabs: @escaping @MainActor () -> [Tab]
    ) {
        self.topVisitedSites = topVisitedSites
        self.bookmarks = bookmarks
        self.openTabs = openTabs
    }

    func suggestions(limit: Int) async -> [SearchManager.SearchSuggestion] {
        var suggestions: [SearchManager.SearchSuggestion] = []
        var seenURLs = Set<String>()

        func append(_ suggestion: SearchManager.SearchSuggestion, url: URL) {
            guard suggestions.count < limit else { return }
            let key = SuggestionDeduplicationPolicy.topLinkDeduplicationKey(for: url)
            guard seenURLs.insert(key).inserted else { return }
            suggestions.append(suggestion)
        }

        let topSites = await topVisitedSites(max(limit, 1))
        for entry in topSites {
            append(SearchManager.SearchSuggestion(text: entry.displayTitle, type: .history(entry)), url: entry.url)
        }

        for bookmark in bookmarks() {
            append(SearchManager.SearchSuggestion(text: bookmark.title, type: .bookmark(bookmark)), url: bookmark.url)
        }

        for tab in openTabs() {
            append(SearchManager.SearchSuggestion(text: tab.name, type: .tab(tab)), url: tab.url)
        }

        return suggestions
    }
}
