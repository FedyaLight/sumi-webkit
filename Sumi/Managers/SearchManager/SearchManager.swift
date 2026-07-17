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
    let session: URLSession

    init(session: URLSession = SumiNonPersistentURLSession.make()) {
        self.session = session
    }

    func data(for query: String) async throws -> Data {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://duckduckgo.com/ac/?q=\(encodedQuery)&is_nav=1"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await session.data(from: url)
        return data
    }
}

/// Orchestrates the browser's search/omnibox suggestion pipeline: query
/// debouncing, task/generation bookkeeping, and merging local (history,
/// bookmarks, open tabs) results with cached/remote DuckDuckGo results.
///
/// The actual policy logic (dedup identity, history matching/ranking,
/// top-link/active-tab ranking, web-suggestion caching, context mapping) is
/// delegated to standalone role-named types in this directory — see
/// `SuggestionDeduplicationPolicy`, `HistorySuggestionMatcher`,
/// `TopLinkSuggestionOwner`, `ActiveTabSuggestionOwner`, `WebSuggestionCache`,
/// and `SuggestionContextBuilder`. This class keeps only the parts that are
/// genuinely about orchestration: task cancellation/generation tracking,
/// the debounced request lifecycle, and composing those collaborators.
@Observable
@MainActor
class SearchManager {
    var suggestions: [SearchSuggestion] = []
    var isLoadingSuggestions = false

    private let suggestionDataProvider: SearchSuggestionDataProviding
    private var webSuggestionTask: Task<Void, Never>?
    private var historySuggestionTask: Task<Void, Never>?
    private weak var tabMembership: TabCollectionMembershipOwner?
    private weak var shortcutPresentation: TabShortcutPresentationOwner?
    private weak var runtimeConnection: TabRuntimePortConnection?
    private weak var historyManager: HistoryManager?
    private weak var bookmarkManager: SumiBookmarkManager?
    private var currentProfileId: UUID?
    private var webSuggestionRequestGeneration: UInt64 = 0
    private var activeWebSuggestionGeneration: UInt64 = 0
    private var webSuggestionCache = WebSuggestionCache()
    // Zen inherits Firefox's browser.urlbar.maxRichResults default.
    private let maxVisibleSuggestions = 10

    private typealias SuggestionStoreContext = SuggestionContextBuilder.StoreContext
    private typealias SuggestionQueryContext = SuggestionContextBuilder.QueryContext

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

    func setTabSources(
        membership: TabCollectionMembershipOwner,
        shortcutPresentation: TabShortcutPresentationOwner,
        runtimeConnection: TabRuntimePortConnection
    ) {
        tabMembership = membership
        self.shortcutPresentation = shortcutPresentation
        self.runtimeConnection = runtimeConnection
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
        let owner = TopLinkSuggestionOwner(
            topVisitedSites: { [weak historyManager] limit in
                await historyManager?.topVisitedSites(limit: limit) ?? []
            },
            bookmarks: { [weak bookmarkManager] in
                bookmarkManager?.allBookmarks() ?? []
            },
            openTabs: { [weak tabMembership] in
                tabMembership?.allTabsForCurrentProfile() ?? []
            }
        )
        historySuggestionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let topLinks = await owner.suggestions(limit: limit)
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

        guard let tabMembership,
              let shortcutPresentation,
              let runtimeConnection
        else {
            clearSuggestions()
            return
        }

        let owner = ActiveTabSuggestionOwner(
            allTabsForCurrentProfile: { [weak tabMembership] in
                tabMembership?.allTabsForCurrentProfile() ?? []
            },
            liveShortcutTabs: { [weak shortcutPresentation] windowId in
                shortcutPresentation?.liveShortcutTabs(in: windowId) ?? []
            },
            shortcutLiveTab: { [weak shortcutPresentation] pinId, windowId in
                shortcutPresentation?.shortcutLiveTab(
                    for: pinId,
                    in: windowId
                )
            },
            visibleSplitTabIds: { [weak runtimeConnection] windowId in
                Set(
                    runtimeConnection?.current?
                        .visibleSplitTabIds(for: windowId) ?? []
                )
            }
        )
        let activeTabs = owner.suggestions(for: windowState)
        if activeTabs.isEmpty {
            clearSuggestions()
        } else {
            updateSuggestionsIfNeeded(activeTabs)
        }
    }

    @MainActor func updateProfileContext() {
        let pid = runtimeConnection?.current?.currentProfileId
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

        if let directURLSuggestion = SuggestionDeduplicationPolicy.directURLSuggestion(for: normalizedQuery) {
            updateSuggestionsIfNeeded([directURLSuggestion])
        }

        let storeContext = currentSuggestionStoreContext()

        historySuggestionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let queryInterval = PerformanceTrace.beginInterval("Omnibox.queryToPublish")
            defer { PerformanceTrace.endInterval("Omnibox.queryToPublish", queryInterval) }
            let historyEntries = await self.searchHistoryEntries(for: normalizedQuery)
            guard !Task.isCancelled,
                  generation == self.activeWebSuggestionGeneration
            else { return }
            let queryContext = SuggestionContextBuilder.queryContext(
                historyEntries: historyEntries,
                store: storeContext
            )

            if let cachedSuggestions = self.webSuggestionCache.suggestions(for: normalizedQuery) {
                guard let combinedResult = try? await SuggestionScoringWorker.result(
                    for: normalizedQuery,
                    history: queryContext.historyItems,
                    bookmarks: queryContext.store.bookmarkItems,
                    openTabs: queryContext.store.tabItems,
                    apiSuggestions: cachedSuggestions,
                    intervalName: "Omnibox.combinedScore"
                ), !Task.isCancelled,
                   generation == self.activeWebSuggestionGeneration else { return }
                let combinedSuggestions = self.makeSuggestions(from: combinedResult, query: normalizedQuery, context: queryContext)
                self.updateSuggestionsIfNeeded(combinedSuggestions)
                self.isLoadingSuggestions = false
                return
            }

            guard let localResult = try? await SuggestionScoringWorker.result(
                for: normalizedQuery,
                history: queryContext.historyItems,
                bookmarks: queryContext.store.bookmarkItems,
                openTabs: queryContext.store.tabItems,
                apiSuggestions: [],
                intervalName: "Omnibox.localScore"
            ), !Task.isCancelled,
               generation == self.activeWebSuggestionGeneration else { return }
            let localSuggestions = self.makeSuggestions(
                from: localResult,
                query: normalizedQuery,
                context: queryContext
            )

            if !localSuggestions.isEmpty {
                self.updateSuggestionsIfNeeded(localSuggestions)
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

        return HistorySuggestionMatcher.merge(
            siteMatches: await siteMatches,
            visitMatches: await visitMatches
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
                    webSuggestionItems = try await SuggestionScoringWorker.decodeAPIResponse(data)
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
                self.webSuggestionCache.store(webSuggestionItems, for: query)
                guard let result = try? await SuggestionScoringWorker.result(
                    for: query,
                    history: context.historyItems,
                    bookmarks: context.store.bookmarkItems,
                    openTabs: context.store.tabItems,
                    apiSuggestions: webSuggestionItems,
                    intervalName: "Omnibox.combinedScore"
                ), !Task.isCancelled,
                   generation == self.activeWebSuggestionGeneration else { return }
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
            guard let suggestion = SuggestionContextBuilder.suggestion(
                from: item,
                historyByURL: context.historyByURL,
                bookmarksByURL: context.store.bookmarksByURL,
                tabsByID: context.store.tabsByID,
                tabsByURL: context.store.tabsByURL
            ) else { continue }

            let key = SuggestionDeduplicationPolicy.deduplicationKey(for: suggestion)
            guard seenKeys.insert(key).inserted else { continue }

            suggestions.append(suggestion)
            if suggestions.count >= maxVisibleSuggestions {
                break
            }
        }

        HistorySuggestionMatcher.appendURLMatchedSuggestions(
            from: context.historyEntries,
            query: query,
            maxVisibleSuggestions: maxVisibleSuggestions,
            suggestions: &suggestions,
            seenKeys: &seenKeys
        )

        if let directURLSuggestion = SuggestionDeduplicationPolicy.directURLSuggestion(for: query) {
            let directKey = SuggestionDeduplicationPolicy.deduplicationKey(for: directURLSuggestion)
            if !seenKeys.contains(directKey) {
                if suggestions.count >= maxVisibleSuggestions {
                    let removed = suggestions.removeLast()
                    seenKeys.remove(SuggestionDeduplicationPolicy.deduplicationKey(for: removed))
                }
                seenKeys.insert(directKey)
                suggestions.append(directURLSuggestion)
            }
        }

        return suggestions
    }

    private func currentSuggestionStoreContext() -> SuggestionStoreContext {
        SuggestionContextBuilder.storeContext(
            bookmarks: bookmarkManager?.allBookmarks() ?? [],
            tabs: tabMembership?.allTabsForCurrentProfile() ?? []
        )
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
