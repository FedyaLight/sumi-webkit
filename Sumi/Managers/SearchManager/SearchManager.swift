//
//  SearchManager.swift
//  Sumi
//
//

import Foundation
import Observation
import SumiDomain

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

/// Orchestrates asynchronous browser suggestion work: task/generation
/// bookkeeping and merging local (history, bookmarks, navigation targets)
/// results with cached/remote DuckDuckGo results. Query debounce and rendered
/// row continuity belong to `CommandPaletteSearchSessionOwner`.
///
/// The actual policy logic (dedup identity, history matching/ranking,
/// contextual/active-tab ranking, web-suggestion caching, context mapping) is
/// delegated to standalone role-named types in this directory — see
/// `SuggestionDeduplicationPolicy`, `HistorySuggestionMatcher`,
/// `ContextualEmptyStateSuggestionOwner`, `ActiveTabSuggestionOwner`,
/// `WebSuggestionCache`,
/// and `SuggestionContextBuilder`. This class keeps only the parts that are
/// genuinely about asynchronous search: task cancellation/generation tracking
/// and composing those collaborators.
@Observable
@MainActor
class SearchManager {
    private(set) var suggestions: [SearchSuggestion] = []
    private(set) var isLoadingSuggestions = false {
        didSet {
            if !isLoadingSuggestions {
                suggestionPublicationIsSettled = true
            }
        }
    }
    /// The normalized query that produced `suggestions`; empty means the
    /// contextual empty state.
    private(set) var suggestionSourceQuery: String?
    private(set) var suggestionPublicationIsSettled = true

    private let suggestionDataProvider: SearchSuggestionDataProviding
    private var webSuggestionTask: Task<Void, Never>?
    private var historySuggestionTask: Task<Void, Never>?
    private weak var historyManager: HistoryManager?
    private weak var bookmarkManager: SumiBookmarkManager?
    private var navigationTargetCatalog: CommandPaletteNavigationTargetCatalog?
    private var webSuggestionRequestGeneration: UInt64 = 0
    private var activeWebSuggestionGeneration: UInt64 = 0
    private var webSuggestionCache = WebSuggestionCache()
    var onStateChange: (@MainActor () -> Void)?
    // Zen inherits Firefox's browser.urlbar.maxRichResults default.
    private let maxVisibleSuggestions = 10

    private typealias SuggestionStoreContext = SuggestionContextBuilder.StoreContext
    private typealias SuggestionQueryContext = SuggestionContextBuilder.QueryContext

    init(suggestionDataProvider: SearchSuggestionDataProviding = DuckDuckGoSearchSuggestionDataProvider()) {
        self.suggestionDataProvider = suggestionDataProvider
    }

    struct SearchSuggestion: Identifiable, Equatable {
        let text: String
        let type: SuggestionType

        enum ID: Hashable {
            case search(String)
            case url(String)
            case tab(UUID)
            case navigationTarget(CommandPaletteNavigationTargetPresentation.Identity)
            case history(String)
            case bookmark(String)
            case command(ShortcutAction)
            case space(UUID)
            case extensionAction(String)
        }

        enum SuggestionType {
            case search
            case url
            case tab(Tab)
            case navigationTarget(CommandPaletteNavigationTargetPresentation)
            case history(HistoryListItem)
            case bookmark(SumiBookmark)
            case command(ShortcutAction)
            case space(CommandPaletteSpacePresentation)
            case extensionAction(CommandPaletteExtensionPresentation)
        }

        var id: ID {
            switch type {
            case .search:
                .search(Self.normalizedIdentityText(text))
            case .url:
                .url(Self.normalizedIdentityText(text))
            case .tab(let tab):
                .tab(tab.id)
            case .navigationTarget(let target):
                .navigationTarget(target.identity)
            case .history(let history):
                .history(history.id)
            case .bookmark(let bookmark):
                .bookmark(bookmark.id)
            case .command(let action):
                .command(action)
            case .space(let space):
                .space(space.id)
            case .extensionAction(let action):
                .extensionAction(action.id)
            }
        }

        static func == (lhs: SearchSuggestion, rhs: SearchSuggestion) -> Bool {
            switch (lhs.type, rhs.type) {
            case (.search, .search), (.url, .url):
                return lhs.text == rhs.text
            case (.tab(let lhsTab), .tab(let rhsTab)):
                return lhs.text == rhs.text && lhsTab.id == rhsTab.id
            case (
                .navigationTarget(let lhsTarget),
                .navigationTarget(let rhsTarget)
            ):
                return lhs.text == rhs.text && lhsTarget == rhsTarget
            case (.history(let lhsHistory), .history(let rhsHistory)):
                return lhs.text == rhs.text && lhsHistory.id == rhsHistory.id
            case (.bookmark(let lhsBookmark), .bookmark(let rhsBookmark)):
                return lhs.text == rhs.text && lhsBookmark.id == rhsBookmark.id
            case (.command(let lhsCommand), .command(let rhsCommand)):
                return lhsCommand == rhsCommand
            case (.space(let lhsSpace), .space(let rhsSpace)):
                return lhsSpace == rhsSpace
            case (
                .extensionAction(let lhsAction),
                .extensionAction(let rhsAction)
            ):
                return lhsAction == rhsAction
            default:
                return false
            }
        }

        private static func normalizedIdentityText(_ text: String) -> String {
            text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }
    }

    func setHistoryManager(_ historyManager: HistoryManager?) {
        self.historyManager = historyManager
    }

    func setBookmarkManager(_ bookmarkManager: SumiBookmarkManager?) {
        self.bookmarkManager = bookmarkManager
    }

    func setNavigationTargetCatalog(
        _ catalog: CommandPaletteNavigationTargetCatalog?
    ) {
        navigationTargetCatalog = catalog
    }

    func showContextualSuggestions(
        limit: Int = 5,
        windowState: BrowserWindowState? = nil
    ) {
        historySuggestionTask?.cancel()
        isLoadingSuggestions = true
        notifyStateChange()
        let navigationSuggestions = windowState.flatMap {
            navigationTargetCatalog?.snapshot(for: $0)
        }
        let contextualSuggestions =
            navigationSuggestions?.suggestions() ?? []
        let readsBrowserProfile = Self.readsBrowserProfile(in: windowState)
        let owner = ContextualEmptyStateSuggestionOwner(
            topVisitedSites: { [weak historyManager] limit in
                guard readsBrowserProfile else { return [] }
                return await historyManager?.topVisitedSites(limit: limit) ?? []
            },
            bookmarks: { [weak bookmarkManager] in
                guard readsBrowserProfile else { return [] }
                return bookmarkManager?.allBookmarks() ?? []
            },
            navigationSuggestions: {
                contextualSuggestions
            }
        )
        historySuggestionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let contextualRows = await owner.suggestions(limit: limit)
            guard !Task.isCancelled else { return }
            if contextualRows.isEmpty {
                self.clearSuggestions()
            } else {
                self.updateSuggestionsIfNeeded(
                    contextualRows,
                    sourceQuery: ""
                )
                self.isLoadingSuggestions = false
                self.notifyStateChange()
            }
        }
    }

    func showActiveTabSuggestions(for windowState: BrowserWindowState) {
        webSuggestionTask?.cancel()
        historySuggestionTask?.cancel()
        webSuggestionRequestGeneration &+= 1
        activeWebSuggestionGeneration = webSuggestionRequestGeneration
        isLoadingSuggestions = false
        notifyStateChange()

        guard let snapshot = navigationTargetCatalog?.snapshot(
            for: windowState
        ) else {
            clearSuggestions()
            return
        }

        let activeTabs = snapshot.suggestions()
        if activeTabs.isEmpty {
            clearSuggestions()
        } else {
            updateSuggestionsIfNeeded(activeTabs, sourceQuery: "")
        }
    }

    @MainActor func searchSuggestions(
        for query: String,
        windowState: BrowserWindowState? = nil
    ) {
        // Cancel previous request
        webSuggestionTask?.cancel()
        historySuggestionTask?.cancel()
        isLoadingSuggestions = true
        notifyStateChange()
        webSuggestionRequestGeneration &+= 1
        activeWebSuggestionGeneration = webSuggestionRequestGeneration
        let generation = activeWebSuggestionGeneration

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let readsBrowserProfile = Self.readsBrowserProfile(in: windowState)

        // Clear suggestions if query is empty
        guard !normalizedQuery.isEmpty else {
            isLoadingSuggestions = false
            clearSuggestionResults()
            notifyStateChange()
            return
        }

        if let directURLSuggestion = SuggestionDeduplicationPolicy.directURLSuggestion(for: normalizedQuery) {
            updateSuggestionsIfNeeded(
                [directURLSuggestion],
                sourceQuery: normalizedQuery,
                isSettled: false
            )
        }
        let navigationSnapshot = windowState.flatMap {
            navigationTargetCatalog?.snapshot(for: $0)
        }
        let navigationSuggestions =
            navigationSnapshot?.suggestions(matching: normalizedQuery) ?? []
        if !navigationSuggestions.isEmpty {
            updateSuggestionsIfNeeded(
                navigationSuggestions,
                sourceQuery: normalizedQuery,
                isSettled: false
            )
        }

        let storeContext = currentSuggestionStoreContext(
            navigationSnapshot: navigationSnapshot,
            readsBrowserProfile: readsBrowserProfile
        )

        historySuggestionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let queryInterval = PerformanceTrace.beginInterval("Omnibox.queryToPublish")
            defer { PerformanceTrace.endInterval("Omnibox.queryToPublish", queryInterval) }
            let historyEntries = await self.searchHistoryEntries(
                for: normalizedQuery,
                readsBrowserProfile: readsBrowserProfile
            )
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
                let combinedSuggestions = self.makeSuggestions(
                    from: combinedResult,
                    query: normalizedQuery,
                    context: queryContext,
                    leadingSuggestions: navigationSuggestions
                )
                self.updateSuggestionsIfNeeded(
                    combinedSuggestions,
                    sourceQuery: normalizedQuery
                )
                self.isLoadingSuggestions = false
                self.notifyStateChange()
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
                context: queryContext,
                leadingSuggestions: navigationSuggestions
            )

            if !localSuggestions.isEmpty {
                self.updateSuggestionsIfNeeded(
                    localSuggestions,
                    sourceQuery: normalizedQuery
                )
            }

            self.fetchWebSuggestions(
                for: normalizedQuery,
                context: queryContext,
                leadingSuggestions: navigationSuggestions,
                generation: generation
            )
        }
    }

    @MainActor private func searchHistoryEntries(
        for query: String,
        readsBrowserProfile: Bool
    ) async -> [HistoryListItem] {
        guard readsBrowserProfile, let historyManager else { return [] }

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
        leadingSuggestions: [SearchSuggestion],
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
                let combinedSuggestions = self.makeSuggestions(
                    from: result,
                    query: query,
                    context: context,
                    leadingSuggestions: leadingSuggestions
                )
                self.updateSuggestionsIfNeeded(
                    combinedSuggestions,
                    sourceQuery: query
                )
            }
            self.isLoadingSuggestions = false
            self.notifyStateChange()
        }
    }

    private func makeSuggestions(
        from result: SumiSuggestionEngine.Result,
        query: String,
        context: SuggestionQueryContext,
        leadingSuggestions: [SearchSuggestion] = []
    ) -> [SearchSuggestion] {
        var suggestions: [SearchSuggestion] = []
        var seenKeys = Set<String>()
        for suggestion in leadingSuggestions {
            let key = SuggestionDeduplicationPolicy.deduplicationKey(
                for: suggestion
            )
            guard seenKeys.insert(key).inserted else { continue }
            suggestions.append(suggestion)
            if suggestions.count >= maxVisibleSuggestions {
                return suggestions
            }
        }
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

    private func currentSuggestionStoreContext(
        navigationSnapshot:
            CommandPaletteNavigationTargetCatalog.Snapshot?,
        readsBrowserProfile: Bool
    ) -> SuggestionStoreContext {
        SuggestionContextBuilder.storeContext(
            bookmarks: readsBrowserProfile
                ? bookmarkManager?.allBookmarks() ?? []
                : [],
            tabs: navigationSnapshot?.eligibleRegularTabs ?? []
        )
    }

    private static func readsBrowserProfile(
        in windowState: BrowserWindowState?
    ) -> Bool {
        windowState?.isIncognito != true
    }

    private func updateSuggestionsIfNeeded(
        _ newSuggestions: [SearchSuggestion],
        sourceQuery: String,
        isSettled: Bool = true
    ) {
        suggestionSourceQuery = sourceQuery
        suggestionPublicationIsSettled = isSettled
        if suggestions != newSuggestions {
            suggestions = newSuggestions
        }
        notifyStateChange()
    }

    private func clearSuggestionResults() {
        suggestionSourceQuery = nil
        suggestionPublicationIsSettled = true
        if !suggestions.isEmpty {
            suggestions = []
        }
    }

    private func cancelSuggestionWork() {
        webSuggestionTask?.cancel()
        historySuggestionTask?.cancel()
        webSuggestionRequestGeneration &+= 1
        activeWebSuggestionGeneration = webSuggestionRequestGeneration
    }

    func cancelSuggestionRequests() {
        let stateChanged =
            isLoadingSuggestions || !suggestionPublicationIsSettled
        cancelSuggestionWork()
        isLoadingSuggestions = false
        if stateChanged {
            notifyStateChange()
        }
    }

    func clearSuggestions() {
        let stateChanged =
            isLoadingSuggestions
                || !suggestions.isEmpty
                || suggestionSourceQuery != nil
                || !suggestionPublicationIsSettled
        cancelSuggestionWork()
        isLoadingSuggestions = false
        clearSuggestionResults()
        if stateChanged {
            notifyStateChange()
        }
    }

    private func notifyStateChange() {
        onStateChange?()
    }
}
