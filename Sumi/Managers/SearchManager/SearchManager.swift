//
//  SearchManager.swift
//  Sumi
//
//

import Foundation
import Observation

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

        let (data, _) = try await SumiNonPersistentURLSession.shared.data(from: url)
        return data
    }
}

@Observable
@MainActor
class SearchManager {
    var suggestions: [SearchSuggestion] = []
    var isLoadingSuggestions = false

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

    private struct SuggestionStoreContext {
        let bookmarkItems: [SumiSuggestionEngine.BookmarkItem]
        let bookmarksByURL: [String: [SumiBookmark]]
        let tabItems: [SumiSuggestionEngine.TabItem]
        let tabsByID: [UUID: Tab]
        let tabsByURL: [String: Tab]
    }

    private struct SuggestionQueryContext {
        let historyEntries: [HistoryListItem]
        let historyItems: [SumiSuggestionEngine.HistoryItem]
        let historyByURL: [String: [HistoryListItem]]
        let store: SuggestionStoreContext
    }

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
        isLoadingSuggestions = true
        historySuggestionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let topLinks = await self.topLinkSuggestions(limit: limit)
            guard !Task.isCancelled else { return }
            if topLinks.isEmpty {
                self.clearSuggestions()
            } else {
                self.updateSuggestionsIfNeeded(topLinks)
                self.isLoadingSuggestions = false
            }
        }
    }

    func showActiveTabSuggestions(for windowState: BrowserWindowState) {
        webSuggestionTask?.cancel()
        historySuggestionTask?.cancel()
        webSuggestionRequestGeneration &+= 1
        activeWebSuggestionGeneration = webSuggestionRequestGeneration
        isLoadingSuggestions = false

        let activeTabs = activeTabSuggestions(for: windowState)
        if activeTabs.isEmpty {
            clearSuggestions()
        } else {
            updateSuggestionsIfNeeded(activeTabs)
        }
    }

    @MainActor func updateProfileContext() {
        let pid = tabManager?.runtimeContext?.currentProfileId
        currentProfileId = pid
        #if DEBUG
        if let pid { RuntimeDiagnostics.emit("🔎 [SearchManager] Profile context updated: \(pid.uuidString)") }
        #endif
    }

    @MainActor func searchSuggestions(for query: String) {
        // Cancel previous request
        webSuggestionTask?.cancel()
        historySuggestionTask?.cancel()
        isLoadingSuggestions = true
        webSuggestionRequestGeneration &+= 1
        activeWebSuggestionGeneration = webSuggestionRequestGeneration
        let generation = activeWebSuggestionGeneration

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Clear suggestions if query is empty
        guard !normalizedQuery.isEmpty else {
            isLoadingSuggestions = false
            clearSuggestionResults()
            return
        }

        if let directURLSuggestion = directURLSuggestion(for: normalizedQuery) {
            updateSuggestionsIfNeeded([directURLSuggestion])
        }

        let storeContext = currentSuggestionStoreContext()

        historySuggestionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let historyEntries = await self.searchHistoryEntries(for: normalizedQuery)
            guard !Task.isCancelled,
                  generation == self.activeWebSuggestionGeneration
            else { return }
            let queryContext = self.suggestionQueryContext(
                historyEntries: historyEntries,
                storeContext: storeContext
            )

            let localResult = self.suggestionEngine.result(
                for: normalizedQuery,
                history: queryContext.historyItems,
                bookmarks: queryContext.store.bookmarkItems,
                openTabs: queryContext.store.tabItems,
                apiSuggestions: []
            )
            let localSuggestions = self.makeSuggestions(from: localResult, query: normalizedQuery, context: queryContext)

            if !localSuggestions.isEmpty {
                self.updateSuggestionsIfNeeded(localSuggestions)
            }

            if let cachedSuggestions = self.cachedWebSuggestions[normalizedQuery] {
                let combinedResult = self.suggestionEngine.result(
                    for: normalizedQuery,
                    history: queryContext.historyItems,
                    bookmarks: queryContext.store.bookmarkItems,
                    openTabs: queryContext.store.tabItems,
                    apiSuggestions: cachedSuggestions
                )
                let combinedSuggestions = self.makeSuggestions(from: combinedResult, query: normalizedQuery, context: queryContext)
                self.updateSuggestionsIfNeeded(combinedSuggestions)
                self.isLoadingSuggestions = false
                return
            }

            self.fetchWebSuggestions(
                for: normalizedQuery,
                context: queryContext,
                generation: generation
            )
        }
    }

    @MainActor private func searchHistoryEntries(for query: String) async -> [HistoryListItem] {
        guard let historyManager else { return [] }

        async let visitMatches = historyManager.searchSuggestions(matching: query, limit: 20)
        async let siteMatches = historyManager.historyPage(
            query: .rangeFilter(.allSites),
            searchTerm: query,
            limit: 20
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
        context: SuggestionQueryContext,
        generation: UInt64
    ) {
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

            if let webSuggestionItems {
                self.storeCachedWebSuggestions(webSuggestionItems, for: query)
                let result = self.suggestionEngine.result(
                    for: query,
                    history: context.historyItems,
                    bookmarks: context.store.bookmarkItems,
                    openTabs: context.store.tabItems,
                    apiSuggestions: webSuggestionItems
                )
                let combinedSuggestions = self.makeSuggestions(from: result, query: query, context: context)
                self.updateSuggestionsIfNeeded(combinedSuggestions)
            }
            self.isLoadingSuggestions = false
        }
    }

    private func makeSuggestions(
        from result: SumiSuggestionEngine.Result,
        query: String,
        context: SuggestionQueryContext
    ) -> [SearchSuggestion] {
        var suggestions: [SearchSuggestion] = []
        var seenKeys = Set<String>()
        for item in result.all {
            guard let suggestion = searchSuggestion(
                from: item,
                historyByURL: context.historyByURL,
                bookmarksByURL: context.store.bookmarksByURL,
                tabsByID: context.store.tabsByID,
                tabsByURL: context.store.tabsByURL
            ) else { continue }

            let key = deduplicationKey(for: suggestion)
            guard seenKeys.insert(key).inserted else { continue }

            suggestions.append(suggestion)
            if suggestions.count >= maxVisibleSuggestions {
                break
            }
        }

        appendURLMatchedHistorySuggestions(
            from: context.historyEntries,
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

    private func activeTabSuggestions(for windowState: BrowserWindowState) -> [SearchSuggestion] {
        guard let tabManager else { return [] }

        let visibleSplitTabIds = Set(tabManager.runtimeContext?.visibleSplitTabIds(for: windowState.id) ?? [])
        let rankByTabId = activeTabRankById(for: windowState, tabManager: tabManager)
        let currentSpaceId = windowState.currentSpaceId
        var seenTabIds = Set<UUID>()

        return activeTabCandidates(for: windowState, tabManager: tabManager)
            .filter { tab in
                guard seenTabIds.insert(tab.id).inserted else { return false }
                guard visibleSplitTabIds.contains(tab.id) == false else { return false }
                return tab.representsSumiNativeSurface == false
            }
            .sorted { lhs, rhs in
                let lhsRank = rankByTabId[lhs.id]
                let rhsRank = rankByTabId[rhs.id]
                if lhsRank != rhsRank {
                    return (lhsRank ?? Int.max) < (rhsRank ?? Int.max)
                }

                let lhsSelected = lhs.lastSelectedAt ?? .distantPast
                let rhsSelected = rhs.lastSelectedAt ?? .distantPast
                if lhsSelected != rhsSelected {
                    return lhsSelected > rhsSelected
                }

                if lhs.spaceId == currentSpaceId, rhs.spaceId != currentSpaceId {
                    return true
                }
                if lhs.spaceId != currentSpaceId, rhs.spaceId == currentSpaceId {
                    return false
                }

                if lhs.index != rhs.index {
                    return lhs.index < rhs.index
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map { tab in
                SearchSuggestion(text: tab.name, type: .tab(tab))
            }
    }

    private func activeTabCandidates(
        for windowState: BrowserWindowState,
        tabManager: TabManager
    ) -> [Tab] {
        if windowState.isIncognito {
            return windowState.ephemeralTabs
        }

        var candidates: [Tab] = []
        var seenTabIds = Set<UUID>()
        func append(_ tab: Tab) {
            guard seenTabIds.insert(tab.id).inserted else { return }
            candidates.append(tab)
        }

        tabManager.allTabsForCurrentProfile()
            .filter { $0.isShortcutLiveInstance == false }
            .forEach(append)
        tabManager.liveShortcutTabs(in: windowState.id)
            .forEach(append)

        return candidates
    }

    private func activeTabRankById(
        for windowState: BrowserWindowState,
        tabManager: TabManager
    ) -> [UUID: Int] {
        var orderedIds: [UUID] = []
        var seenIds = Set<UUID>()

        func append(_ tabId: UUID?) {
            guard let tabId, seenIds.insert(tabId).inserted else { return }
            orderedIds.append(tabId)
        }

        func appendSelectionHistory(_ items: [BrowserWindowSelectionHistoryItem]) {
            for item in items {
                switch item {
                case .regularTab(let tabId):
                    append(tabId)
                case .shortcutPin(let pinId):
                    append(tabManager.shortcutLiveTab(for: pinId, in: windowState.id)?.id)
                }
            }
        }

        if let currentSpaceId = windowState.currentSpaceId {
            appendSelectionHistory(windowState.recentSelectionItemsBySpace[currentSpaceId] ?? [])
            (windowState.recentRegularTabIdsBySpace[currentSpaceId] ?? []).forEach(append)
        }

        for spaceId in windowState.recentSelectionItemsBySpace.keys.sorted(by: { $0.uuidString < $1.uuidString })
            where spaceId != windowState.currentSpaceId {
            appendSelectionHistory(windowState.recentSelectionItemsBySpace[spaceId] ?? [])
        }

        windowState.activeTabForSpace.values.forEach(append)

        return Dictionary(uniqueKeysWithValues: orderedIds.enumerated().map { ($0.element, $0.offset) })
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
        bookmarksByURL: [String: [SumiBookmark]],
        tabsByID: [UUID: Tab],
        tabsByURL: [String: Tab]
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
            let tab = tabId.flatMap { tabsByID[$0] } ?? tabsByURL[url.absoluteString]
            guard let tab else {
                return SearchSuggestion(text: url.absoluteString, type: .url)
            }
            return SearchSuggestion(text: tab.name, type: .tab(tab))
        }
    }

    private func currentSuggestionStoreContext() -> SuggestionStoreContext {
        let bookmarks = bookmarkManager?.allBookmarks() ?? []
        let bookmarkItems = bookmarks.map {
            SumiSuggestionEngine.BookmarkItem(url: $0.url, title: $0.title, isFavorite: false)
        }
        let bookmarksByURL = Dictionary(grouping: bookmarks, by: { $0.url.absoluteString })

        let tabs = tabManager?.allTabsForCurrentProfile() ?? []
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

        return SuggestionStoreContext(
            bookmarkItems: bookmarkItems,
            bookmarksByURL: bookmarksByURL,
            tabItems: tabItems,
            tabsByID: tabsByID,
            tabsByURL: tabsByURL
        )
    }

    private func suggestionQueryContext(
        historyEntries: [HistoryListItem],
        storeContext: SuggestionStoreContext
    ) -> SuggestionQueryContext {
        SuggestionQueryContext(
            historyEntries: historyEntries,
            historyItems: historyEntries.map(Self.historyItem),
            historyByURL: Dictionary(grouping: historyEntries, by: { $0.url.absoluteString }),
            store: storeContext
        )
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
        guard suggestions != newSuggestions else { return }
        suggestions = newSuggestions
    }

    private func clearSuggestionResults() {
        guard !suggestions.isEmpty else { return }
        suggestions = []
    }

    func clearSuggestions() {
        webSuggestionTask?.cancel()
        historySuggestionTask?.cancel()
        isLoadingSuggestions = false
        webSuggestionRequestGeneration &+= 1
        activeWebSuggestionGeneration = webSuggestionRequestGeneration
        clearSuggestionResults()
    }
}
