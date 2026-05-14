//
//  SearchManager.swift
//  Alto
//
//  Created by Maciek Bagiński on 31/07/2025.
//

import Foundation
import Observation
import SwiftUI

@MainActor
protocol SearchSuggestionDataProviding {
    func data(for query: String) async throws -> Data
}

@MainActor
struct DuckDuckGoSearchSuggestionDataProvider: SearchSuggestionDataProviding {
    func data(for query: String) async throws -> Data {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://duckduckgo.com/ac/?q=\(encodedQuery)&is_nav=1"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
}

@Observable
@MainActor
class SearchManager {
    var suggestions: [SearchSuggestion] = []
    var isLoading: Bool = false
    
    private let suggestionDataProvider: SearchSuggestionDataProviding
    private var webSuggestionTask: Task<Void, Never>?
    private var historySuggestionTask: Task<Void, Never>?
    private weak var tabManager: TabManager?
    private weak var historyManager: HistoryManager?
    private weak var bookmarkManager: SumiBookmarkManager?
    private var currentProfileId: UUID?
    private var webSuggestionRequestGeneration: UInt64 = 0
    private var activeWebSuggestionGeneration: UInt64 = 0
    private var cachedWebSuggestions: [String: [SumiSuggestionEngine.APISuggestion]] = [:]
    private var cachedWebSuggestionOrder: [String] = []
    private let maxCachedWebSuggestionQueries = 24
    private let suggestionEngine = SumiSuggestionEngine()
    // Zen inherits Firefox's browser.urlbar.maxRichResults default.
    private let maxVisibleSuggestions = 10

    init(suggestionDataProvider: SearchSuggestionDataProviding = DuckDuckGoSearchSuggestionDataProvider()) {
        self.suggestionDataProvider = suggestionDataProvider
    }
    
    struct SearchSuggestion: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let type: SuggestionType
        
        enum SuggestionType {
            case search
            case url
            case tab(Tab)
            case history(HistoryListItem)
            case bookmark(SumiBookmark)
        }
        
        static func == (lhs: SearchSuggestion, rhs: SearchSuggestion) -> Bool {
            switch (lhs.type, rhs.type) {
            case (.search, .search), (.url, .url):
                return lhs.text == rhs.text
            case (.tab(let lhsTab), .tab(let rhsTab)):
                return lhs.text == rhs.text && lhsTab.id == rhsTab.id
            case (.history(let lhsHistory), .history(let rhsHistory)):
                return lhs.text == rhs.text && lhsHistory.id == rhsHistory.id
            case (.bookmark(let lhsBookmark), .bookmark(let rhsBookmark)):
                return lhs.text == rhs.text && lhsBookmark.id == rhsBookmark.id
            default:
                return false
            }
        }
    }

    private struct RankedTabSuggestion {
        let tab: Tab
        let text: String
        let nameMatches: Bool
        let nameLength: Int
    }

    private struct RankedHistorySuggestion {
        let entry: HistoryListItem
        let text: String
        let titleMatches: Bool
        let visitedAt: Date?
    }
    
    func setTabManager(_ tabManager: TabManager?) {
        self.tabManager = tabManager
        updateProfileContext()
    }
    
    func setHistoryManager(_ historyManager: HistoryManager?) {
        self.historyManager = historyManager
    }

    func setBookmarkManager(_ bookmarkManager: SumiBookmarkManager?) {
        self.bookmarkManager = bookmarkManager
    }

    func showTopLinkSuggestions(limit: Int = 5) {
        historySuggestionTask?.cancel()
        historySuggestionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let topLinks = await self.topLinkSuggestions(limit: limit)
            guard !Task.isCancelled else { return }
            if topLinks.isEmpty {
                self.clearSuggestions()
            } else {
                self.updateSuggestionsIfNeeded(topLinks)
            }
        }
    }

    @MainActor func updateProfileContext() {
        let pid = tabManager?.browserManager?.currentProfile?.id
        currentProfileId = pid
        #if DEBUG
        if let pid { RuntimeDiagnostics.emit("🔎 [SearchManager] Profile context updated: \(pid.uuidString)") }
        #endif
    }
    
    @MainActor func searchSuggestions(for query: String) {
        // Cancel previous request
        webSuggestionTask?.cancel()
        historySuggestionTask?.cancel()
        webSuggestionRequestGeneration &+= 1
        activeWebSuggestionGeneration = webSuggestionRequestGeneration
        let generation = activeWebSuggestionGeneration

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Clear suggestions if query is empty
        guard !normalizedQuery.isEmpty else {
            isLoading = false
            if !suggestions.isEmpty {
                withAnimation(.easeInOut(duration: 0.2)) {
                    suggestions = []
                }
            }
            return
        }
        
        if let directURLSuggestion = directURLSuggestion(for: normalizedQuery) {
            updateSuggestionsIfNeeded([directURLSuggestion])
        }

        let tabItems = currentTabSuggestionItems()
        let bookmarkItems = currentBookmarkSuggestionItems()

        historySuggestionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let historyEntries = await self.searchHistoryEntries(for: normalizedQuery)
            guard !Task.isCancelled,
                  generation == self.activeWebSuggestionGeneration
            else { return }

            let localResult = self.suggestionEngine.result(
                for: normalizedQuery,
                history: historyEntries.map(Self.historyItem),
                bookmarks: bookmarkItems,
                openTabs: tabItems,
                apiSuggestions: []
            )
            let localSuggestions = self.makeSuggestions(from: localResult, query: normalizedQuery, historyEntries: historyEntries)

            if !localSuggestions.isEmpty {
                self.updateSuggestionsIfNeeded(localSuggestions)
            }

            if let cachedSuggestions = self.cachedWebSuggestions[normalizedQuery] {
                let combinedResult = self.suggestionEngine.result(
                    for: normalizedQuery,
                    history: historyEntries.map(Self.historyItem),
                    bookmarks: bookmarkItems,
                    openTabs: tabItems,
                    apiSuggestions: cachedSuggestions
                )
                let combinedSuggestions = self.makeSuggestions(from: combinedResult, query: normalizedQuery, historyEntries: historyEntries)
                self.updateSuggestionsIfNeeded(combinedSuggestions)
                self.isLoading = false
                return
            }

            self.fetchWebSuggestions(
                for: normalizedQuery,
                historyEntries: historyEntries,
                bookmarkItems: bookmarkItems,
                tabItems: tabItems,
                generation: generation
            )
        }
    }

    @MainActor private func currentTabSuggestionItems() -> [SumiSuggestionEngine.TabItem] {
        guard let tabManager else { return [] }

        return tabManager.allTabsForCurrentProfile().map {
            SumiSuggestionEngine.TabItem(id: $0.id, url: $0.url, title: $0.name)
        }
    }

    @MainActor private func currentBookmarkSuggestionItems() -> [SumiSuggestionEngine.BookmarkItem] {
        guard let bookmarkManager else { return [] }

        return bookmarkManager.allBookmarks().map {
            SumiSuggestionEngine.BookmarkItem(url: $0.url, title: $0.title, isFavorite: false)
        }
    }

    @MainActor private func searchHistoryEntries(for query: String) async -> [HistoryListItem] {
        guard let historyManager else { return [] }

        async let visitMatches = historyManager.searchSuggestions(matching: query, limit: 100)
        async let siteMatches = historyManager.historyPage(
            query: .rangeFilter(.allSites),
            searchTerm: query,
            limit: 100
        ).items

        return mergeHistorySuggestionItems(
            siteMatches: await siteMatches,
            visitMatches: await visitMatches
        )
    }

    private func mergeHistorySuggestionItems(
        siteMatches: [HistoryListItem],
        visitMatches: [HistoryListItem]
    ) -> [HistoryListItem] {
        var merged: [HistoryListItem] = []
        var seen = Set<String>()

        func append(_ item: HistoryListItem) {
            let key = topLinkDeduplicationKey(for: item.url)
            guard seen.insert(key).inserted else { return }
            merged.append(item)
        }

        siteMatches.forEach(append)
        visitMatches.forEach(append)
        return merged
    }

    private static func historyItem(_ entry: HistoryListItem) -> SumiSuggestionEngine.HistoryItem {
        SumiSuggestionEngine.HistoryItem(
            url: entry.url,
            title: entry.displayTitle,
            visitCount: entry.visitCount,
            failedToLoad: false
        )
    }
    
    private func fetchWebSuggestions(
        for query: String,
        historyEntries: [HistoryListItem],
        bookmarkItems: [SumiSuggestionEngine.BookmarkItem],
        tabItems: [SumiSuggestionEngine.TabItem],
        generation: UInt64
    ) {
        isLoading = true

        webSuggestionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var webSuggestionItems: [SumiSuggestionEngine.APISuggestion]?
            do {
                let data = try await self.suggestionDataProvider.data(for: query)
                guard !Task.isCancelled else { return }
                do {
                    webSuggestionItems = try JSONDecoder().decode([SumiSuggestionEngine.APISuggestion].self, from: data)
                } catch {
                    RuntimeDiagnostics.emit("JSON parsing error: \(error.localizedDescription)")
                    webSuggestionItems = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                RuntimeDiagnostics.emit("Search suggestions error: \(error.localizedDescription)")
                webSuggestionItems = nil
            }

            guard generation == self.activeWebSuggestionGeneration else { return }

            self.isLoading = false

            if let webSuggestionItems {
                self.storeCachedWebSuggestions(webSuggestionItems, for: query)
                let result = self.suggestionEngine.result(
                    for: query,
                    history: historyEntries.map(Self.historyItem),
                    bookmarks: bookmarkItems,
                    openTabs: tabItems,
                    apiSuggestions: webSuggestionItems
                )
                let combinedSuggestions = self.makeSuggestions(from: result, query: query, historyEntries: historyEntries)
                self.updateSuggestionsIfNeeded(combinedSuggestions)
            }
        }
    }

    private func makeSuggestions(
        from result: SumiSuggestionEngine.Result,
        query: String,
        historyEntries: [HistoryListItem]
    ) -> [SearchSuggestion] {
        let historyByURL = Dictionary(grouping: historyEntries, by: { $0.url.absoluteString })
        let bookmarksByURL = Dictionary(grouping: bookmarkManager?.allBookmarks() ?? [], by: { $0.url.absoluteString })

        var suggestions: [SearchSuggestion] = []
        var seenKeys = Set<String>()
        for item in result.all {
            guard let suggestion = searchSuggestion(
                from: item,
                historyByURL: historyByURL,
                bookmarksByURL: bookmarksByURL
            ) else { continue }

            let key = deduplicationKey(for: suggestion)
            guard seenKeys.insert(key).inserted else { continue }

            suggestions.append(suggestion)
            if suggestions.count >= maxVisibleSuggestions {
                break
            }
        }

        appendURLMatchedHistorySuggestions(
            from: historyEntries,
            query: query,
            suggestions: &suggestions,
            seenKeys: &seenKeys
        )

        if let directURLSuggestion = directURLSuggestion(for: query) {
            let directKey = deduplicationKey(for: directURLSuggestion)
            if !seenKeys.contains(directKey) {
                if suggestions.count >= maxVisibleSuggestions {
                    let removed = suggestions.removeLast()
                    seenKeys.remove(deduplicationKey(for: removed))
                }
                seenKeys.insert(directKey)
                suggestions.append(directURLSuggestion)
            }
        }

        return suggestions
    }

    private func appendURLMatchedHistorySuggestions(
        from historyEntries: [HistoryListItem],
        query: String,
        suggestions: inout [SearchSuggestion],
        seenKeys: inout Set<String>
    ) {
        let searchQuery = SearchTextQuery(query)
        guard !searchQuery.isEmpty else { return }

        let urlMatches = historyEntries
            .filter { historyEntryMatchesURL($0, query: searchQuery) }
            .sorted { lhs, rhs in
                let lhsRoot = lhs.url.path.isEmpty || lhs.url.path == "/"
                let rhsRoot = rhs.url.path.isEmpty || rhs.url.path == "/"
                if lhsRoot != rhsRoot {
                    return !lhsRoot && rhsRoot
                }

                let lhsAggregate = lhs.isSiteAggregate
                let rhsAggregate = rhs.isSiteAggregate
                if lhsAggregate != rhsAggregate {
                    return !lhsAggregate && rhsAggregate
                }

                return (lhs.visitedAt ?? .distantPast) > (rhs.visitedAt ?? .distantPast)
            }

        for entry in urlMatches {
            let suggestion = SearchSuggestion(text: entry.displayTitle, type: .history(entry))
            let key = deduplicationKey(for: suggestion)
            guard seenKeys.insert(key).inserted else { continue }

            if suggestions.count < maxVisibleSuggestions {
                suggestions.append(suggestion)
                continue
            }

            guard let replacementIndex = suggestions.lastIndex(where: { !isLocalNavigationSuggestion($0) }) else {
                seenKeys.remove(key)
                continue
            }

            let removed = suggestions[replacementIndex]
            seenKeys.remove(deduplicationKey(for: removed))
            suggestions[replacementIndex] = suggestion
        }
    }

    private func historyEntryMatchesURL(_ entry: HistoryListItem, query: SearchTextQuery) -> Bool {
        query.matches(entry.url.absoluteString)
            || query.matches(entry.domain)
            || (entry.siteDomain.map(query.matches) ?? false)
    }

    private func isLocalNavigationSuggestion(_ suggestion: SearchSuggestion) -> Bool {
        switch suggestion.type {
        case .history, .bookmark, .tab:
            return true
        case .search, .url:
            return false
        }
    }

    private func deduplicationKey(for suggestion: SearchSuggestion) -> String {
        switch suggestion.type {
        case .search:
            return "search:\(suggestion.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        case .url:
            guard let url = URL(string: normalizeURL(suggestion.text, queryTemplate: SearchProvider.duckDuckGo.queryTemplate)) else {
                return "url:\(suggestion.text.lowercased())"
            }
            return "url:\(topLinkDeduplicationKey(for: url).lowercased())"
        case .history(let entry):
            return "url:\(topLinkDeduplicationKey(for: entry.url).lowercased())"
        case .bookmark(let bookmark):
            return "url:\(topLinkDeduplicationKey(for: bookmark.url).lowercased())"
        case .tab(let tab):
            return "url:\(topLinkDeduplicationKey(for: tab.url).lowercased())"
        }
    }

    private func directURLSuggestion(for query: String) -> SearchSuggestion? {
        guard isLikelyURL(query) else { return nil }
        let normalizedURL = normalizeURL(query, queryTemplate: SearchProvider.duckDuckGo.queryTemplate)
        return SearchSuggestion(text: normalizedURL, type: .url)
    }

    private func topLinkSuggestions(limit: Int) async -> [SearchSuggestion] {
        var suggestions: [SearchSuggestion] = []
        var seenURLs = Set<String>()

        func append(_ suggestion: SearchSuggestion, url: URL) {
            guard suggestions.count < limit else { return }
            let key = topLinkDeduplicationKey(for: url)
            guard seenURLs.insert(key).inserted else { return }
            suggestions.append(suggestion)
        }

        let topSites = await historyManager?.topVisitedSites(limit: max(limit, 1)) ?? []

        for entry in topSites {
            append(SearchSuggestion(text: entry.displayTitle, type: .history(entry)), url: entry.url)
        }

        let bookmarks = bookmarkManager?.allBookmarks() ?? []
        for bookmark in bookmarks {
            append(SearchSuggestion(text: bookmark.title, type: .bookmark(bookmark)), url: bookmark.url)
        }

        let tabs = tabManager?.allTabsForCurrentProfile() ?? []
        for tab in tabs {
            append(SearchSuggestion(text: tab.name, type: .tab(tab)), url: tab.url)
        }

        return suggestions
    }

    private func topLinkDeduplicationKey(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.scheme = nil
        components.user = nil
        components.password = nil
        components.fragment = nil
        if components.path == "/" {
            components.path = ""
        }
        return components.string ?? url.absoluteString
    }

    private func searchSuggestion(
        from item: SumiSuggestionEngine.Item,
        historyByURL: [String: [HistoryListItem]],
        bookmarksByURL: [String: [SumiBookmark]]
    ) -> SearchSuggestion? {
        switch item {
        case .phrase(let phrase):
            return SearchSuggestion(text: phrase, type: .search)
        case .website(let url):
            return SearchSuggestion(text: url.absoluteString, type: .url)
        case .bookmark(let title, let url, _, _):
            if let bookmark = bookmarksByURL[url.absoluteString]?.first {
                return SearchSuggestion(text: title, type: .bookmark(bookmark))
            }
            return SearchSuggestion(text: url.absoluteString, type: .url)
        case .history(_, let url, _):
            if let history = historyByURL[url.absoluteString]?.first {
                return SearchSuggestion(text: history.displayTitle, type: .history(history))
            }
            return SearchSuggestion(text: url.absoluteString, type: .url)
        case .openTab(_, let url, let tabId, _):
            guard let tab = tabForSuggestion(id: tabId, url: url) else {
                return SearchSuggestion(text: url.absoluteString, type: .url)
            }
            return SearchSuggestion(text: tab.name, type: .tab(tab))
        }
    }

    private func tabForSuggestion(id: UUID?, url: URL) -> Tab? {
        guard let tabManager else { return nil }
        let tabs = tabManager.allTabsForCurrentProfile()
        if let id, let tab = tabs.first(where: { $0.id == id }) {
            return tab
        }
        return tabs.first { $0.url == url }
    }

    private func storeCachedWebSuggestions(_ suggestions: [SumiSuggestionEngine.APISuggestion], for query: String) {
        cachedWebSuggestions[query] = suggestions
        cachedWebSuggestionOrder.removeAll { $0 == query }
        cachedWebSuggestionOrder.append(query)

        while cachedWebSuggestionOrder.count > maxCachedWebSuggestionQueries {
            let evictedQuery = cachedWebSuggestionOrder.removeFirst()
            cachedWebSuggestions.removeValue(forKey: evictedQuery)
        }
    }
    
    private func updateSuggestionsIfNeeded(_ newSuggestions: [SearchSuggestion]) {
        let shouldAnimate = shouldAnimateChange(from: suggestions, to: newSuggestions)
        
        if shouldAnimate {
            withAnimation(.easeInOut(duration: 0.25)) {
                suggestions = newSuggestions
            }
        } else {
            suggestions = newSuggestions
        }
    }
    
    private func shouldAnimateChange(from oldSuggestions: [SearchSuggestion], to newSuggestions: [SearchSuggestion]) -> Bool {
        if oldSuggestions.isEmpty != newSuggestions.isEmpty {
            return true
        }
        
        // Always animate if count changes significantly
        if abs(oldSuggestions.count - newSuggestions.count) > 2 {
            return true
        }
        
        // Compare suggestion texts to see if there are significant changes
        let oldTexts = Set(oldSuggestions.map { $0.text })
        let newTexts = Set(newSuggestions.map { $0.text })
        
        // Calculate how many suggestions are different
        let intersection = oldTexts.intersection(newTexts)
        let totalUnique = oldTexts.union(newTexts).count
        let similarityRatio = Double(intersection.count) / Double(max(totalUnique, 1))
        
        // Only animate if less than 60% of suggestions are the same
        return similarityRatio < 0.6
    }
    
    
    
    func clearSuggestions() {
        webSuggestionTask?.cancel()
        historySuggestionTask?.cancel()
        webSuggestionRequestGeneration &+= 1
        activeWebSuggestionGeneration = webSuggestionRequestGeneration
        if !suggestions.isEmpty {
            withAnimation(.easeInOut(duration: 0.2)) {
                suggestions = []
            }
        }
        isLoading = false
    }
}
