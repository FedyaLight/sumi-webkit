//
//  SuggestionContextBuilder.swift
//  Sumi
//
//

import Foundation

/// Pure translation layer between raw store data (bookmarks/tabs/history
/// already fetched by the caller) and the lookup structures the suggestion
/// engine and result-mapping code need. Also owns mapping a raw
/// `SumiSuggestionEngine.Item` back to a domain `SearchManager.SearchSuggestion`.
///
/// Deliberately takes already-fetched arrays rather than manager references
/// so it can be exercised with plain fixtures.
@MainActor
enum SuggestionContextBuilder {
    struct StoreContext {
        let bookmarkItems: [SumiSuggestionEngine.BookmarkItem]
        let bookmarksByURL: [String: [SumiBookmark]]
        let tabItems: [SumiSuggestionEngine.TabItem]
        let tabsByID: [UUID: Tab]
        let tabsByURL: [String: Tab]
    }

    struct QueryContext {
        let historyEntries: [HistoryListItem]
        let historyItems: [SumiSuggestionEngine.HistoryItem]
        let historyByURL: [String: [HistoryListItem]]
        let store: StoreContext
    }

    static func historyItem(_ entry: HistoryListItem) -> SumiSuggestionEngine.HistoryItem {
        SumiSuggestionEngine.HistoryItem(
            url: entry.url,
            title: entry.displayTitle,
            visitCount: entry.visitCount,
            failedToLoad: false
        )
    }

    static func storeContext(bookmarks: [SumiBookmark], tabs: [Tab]) -> StoreContext {
        let bookmarkItems = bookmarks.map {
            SumiSuggestionEngine.BookmarkItem(url: $0.url, title: $0.title, isFavorite: false)
        }
        let bookmarksByURL = Dictionary(grouping: bookmarks, by: { $0.url.absoluteString })

        let tabItems = tabs.map {
            SumiSuggestionEngine.TabItem(id: $0.id, url: $0.url, title: $0.name)
        }
        var tabsByID: [UUID: Tab] = [:]
        var tabsByURL: [String: Tab] = [:]

        for tab in tabs {
            if tabsByID[tab.id] == nil {
                tabsByID[tab.id] = tab
            }
            let urlKey = tab.url.absoluteString
            if tabsByURL[urlKey] == nil {
                tabsByURL[urlKey] = tab
            }
        }

        return StoreContext(
            bookmarkItems: bookmarkItems,
            bookmarksByURL: bookmarksByURL,
            tabItems: tabItems,
            tabsByID: tabsByID,
            tabsByURL: tabsByURL
        )
    }

    static func queryContext(
        historyEntries: [HistoryListItem],
        store: StoreContext
    ) -> QueryContext {
        QueryContext(
            historyEntries: historyEntries,
            historyItems: historyEntries.map(historyItem),
            historyByURL: Dictionary(grouping: historyEntries, by: { $0.url.absoluteString }),
            store: store
        )
    }

    static func suggestion(
        from item: SumiSuggestionEngine.Item,
        historyByURL: [String: [HistoryListItem]],
        bookmarksByURL: [String: [SumiBookmark]],
        tabsByID: [UUID: Tab],
        tabsByURL: [String: Tab]
    ) -> SearchManager.SearchSuggestion? {
        switch item {
        case .phrase(let phrase):
            return SearchManager.SearchSuggestion(text: phrase, type: .search)
        case .website(let url):
            return SearchManager.SearchSuggestion(text: url.absoluteString, type: .url)
        case .bookmark(let title, let url, _, _):
            if let bookmark = bookmarksByURL[url.absoluteString]?.first {
                return SearchManager.SearchSuggestion(text: title, type: .bookmark(bookmark))
            }
            return SearchManager.SearchSuggestion(text: url.absoluteString, type: .url)
        case .history(_, let url, _):
            if let history = historyByURL[url.absoluteString]?.first {
                return SearchManager.SearchSuggestion(text: history.displayTitle, type: .history(history))
            }
            return SearchManager.SearchSuggestion(text: url.absoluteString, type: .url)
        case .openTab(_, let url, let tabId, _):
            let tab = tabId.flatMap { tabsByID[$0] } ?? tabsByURL[url.absoluteString]
            guard let tab else {
                return SearchManager.SearchSuggestion(text: url.absoluteString, type: .url)
            }
            return SearchManager.SearchSuggestion(text: tab.name, type: .tab(tab))
        }
    }
}
