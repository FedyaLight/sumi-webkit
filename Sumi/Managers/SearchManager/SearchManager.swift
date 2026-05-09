//
//  SearchManager.swift
//  Alto
//
//  Created by Maciek Bagiński on 31/07/2025.
//

import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
class SearchManager {
    var suggestions: [SearchSuggestion] = []
    var isLoading: Bool = false
    
    private let session = URLSession.shared
    private var searchTask: URLSessionDataTask?
    private var historySuggestionTask: Task<Void, Never>?
    private weak var tabManager: TabManager?
    private weak var historyManager: HistoryManager?
    private var currentProfileId: UUID?
    private var webSuggestionRequestGeneration: UInt64 = 0
    private var activeWebSuggestionGeneration: UInt64 = 0
    private var cachedWebSuggestions: [String: [String]] = [:]
    private var cachedWebSuggestionOrder: [String] = []
    private let maxCachedWebSuggestionQueries = 24
    
    struct SearchSuggestion: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let type: SuggestionType
        
        enum SuggestionType {
            case search
            case url
            case tab(Tab)
            case history(HistoryListItem)
        }
        
        static func == (lhs: SearchSuggestion, rhs: SearchSuggestion) -> Bool {
            switch (lhs.type, rhs.type) {
            case (.search, .search), (.url, .url):
                return lhs.text == rhs.text
            case (.tab(let lhsTab), .tab(let rhsTab)):
                return lhs.text == rhs.text && lhsTab.id == rhsTab.id
            case (.history(let lhsHistory), .history(let rhsHistory)):
                return lhs.text == rhs.text && lhsHistory.id == rhsHistory.id
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

    @MainActor func updateProfileContext() {
        let pid = tabManager?.browserManager?.currentProfile?.id
        currentProfileId = pid
        #if DEBUG
        if let pid { RuntimeDiagnostics.emit("🔎 [SearchManager] Profile context updated: \(pid.uuidString)") }
        #endif
    }
    
    @MainActor func searchSuggestions(for query: String) {
        // Cancel previous request
        searchTask?.cancel()
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
        
        // Search tabs first
        let tabSuggestions = searchTabs(for: normalizedQuery)

        let immediateSuggestions = makeLocalSuggestions(
            tabSuggestions: tabSuggestions,
            historySuggestions: [],
            query: normalizedQuery
        )

        if !immediateSuggestions.isEmpty {
            updateSuggestionsIfNeeded(immediateSuggestions)
        }

        historySuggestionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let historySuggestions = await self.searchHistory(for: normalizedQuery)
            guard !Task.isCancelled,
                  generation == self.activeWebSuggestionGeneration
            else { return }

            let allSuggestions = self.makeLocalSuggestions(
                tabSuggestions: tabSuggestions,
                historySuggestions: historySuggestions,
                query: normalizedQuery
            )

            if !allSuggestions.isEmpty {
                self.updateSuggestionsIfNeeded(allSuggestions)
            }

            if let cachedSuggestions = self.cachedWebSuggestions[normalizedQuery] {
                let combinedSuggestions = self.combineSuggestions(
                    allSuggestions,
                    withWebSuggestionTexts: cachedSuggestions
                )
                self.updateSuggestionsIfNeeded(combinedSuggestions)
                self.isLoading = false
                return
            }

            self.fetchWebSuggestions(
                for: normalizedQuery,
                prependTabSuggestions: allSuggestions,
                generation: generation
            )
        }
    }
    
    @MainActor private func searchTabs(for query: String) -> [SearchSuggestion] {
        guard let tabManager else { return [] }

        let lowercaseQuery = query.lowercased()
        var matchingTabs: [RankedTabSuggestion] = []
        // Use TabManager's profile-aware access (handles fallback internally)
        let allTabs: [Tab] = tabManager.allTabsForCurrentProfile()

        for tab in allTabs {
            let nameMatches = tab.name.lowercased().contains(lowercaseQuery)
            let isMatch: Bool

            if nameMatches {
                isMatch = true
            } else {
                let urlMatches = tab.url.absoluteString.lowercased().contains(lowercaseQuery)
                let hostMatches = tab.url.host?.lowercased().contains(lowercaseQuery) ?? false
                isMatch = urlMatches || hostMatches
            }

            guard isMatch else { continue }

            matchingTabs.append(
                RankedTabSuggestion(
                    tab: tab,
                    text: tab.name,
                    nameMatches: nameMatches,
                    nameLength: tab.name.count
                )
            )
        }

        // Sort by relevance: name matches first, then shorter tab names.
        let sortedTabs = matchingTabs.sorted { lhs, rhs -> Bool in
            if lhs.nameMatches != rhs.nameMatches {
                return lhs.nameMatches
            }
            return lhs.nameLength < rhs.nameLength
        }

        return Array(
            sortedTabs.prefix(3).map { ranked in
                SearchSuggestion(
                    text: ranked.text,
                    type: .tab(ranked.tab)
                )
            }
        ) // Limit to 3 tab suggestions
    }

    @MainActor private func searchHistory(for query: String) async -> [SearchSuggestion] {
        guard let historyManager else { return [] }

        let lowercaseQuery = query.lowercased()
        let historyEntries = await historyManager.searchSuggestions(matching: query, limit: 20)

        var matchingHistory: [RankedHistorySuggestion] = []

        for entry in historyEntries {
            let titleMatches = entry.title.lowercased().contains(lowercaseQuery)
            let isMatch: Bool

            if titleMatches {
                isMatch = true
            } else {
                let urlMatches = entry.url.absoluteString.lowercased().contains(lowercaseQuery)
                let hostMatches = entry.url.host?.lowercased().contains(lowercaseQuery) ?? false
                isMatch = urlMatches || hostMatches
            }

            guard isMatch else { continue }

            matchingHistory.append(
                RankedHistorySuggestion(
                    entry: entry,
                    text: entry.displayTitle,
                    titleMatches: titleMatches,
                    visitedAt: entry.visitedAt
                )
            )
        }

        // Sort by relevance: title matches first, then by recency.
        let sortedHistory = matchingHistory.sorted { lhs, rhs -> Bool in
            if lhs.titleMatches != rhs.titleMatches {
                return lhs.titleMatches
            }
            return (lhs.visitedAt ?? .distantPast) > (rhs.visitedAt ?? .distantPast)
        }

        return sortedHistory.map { ranked in
            SearchSuggestion(
                text: ranked.text,
                type: .history(ranked.entry)
            )
        }
    }

    private func makeLocalSuggestions(
        tabSuggestions: [SearchSuggestion],
        historySuggestions: [SearchSuggestion],
        query: String
    ) -> [SearchSuggestion] {
        var allSuggestions: [SearchSuggestion] = []

        let maxTabSuggestions = 2
        allSuggestions.append(contentsOf: tabSuggestions.prefix(maxTabSuggestions))

        let maxHistorySuggestions = 2
        allSuggestions.append(contentsOf: historySuggestions.prefix(maxHistorySuggestions))

        if isLikelyURL(query) {
            allSuggestions.append(SearchSuggestion(text: query, type: .url))
        }

        return Array(allSuggestions.prefix(5))
    }
    
    private func fetchWebSuggestions(
        for query: String,
        prependTabSuggestions: [SearchSuggestion],
        generation: UInt64
    ) {
        isLoading = true
        
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://suggestqueries.google.com/complete/search?client=safari&q=\(encodedQuery)"
        
        guard let url = URL(string: urlString) else {
            isLoading = false
            return
        }
        
        searchTask = session.dataTask(with: url) { data, _, error in
            var webSuggestionTexts: [String]?
            if let data = data, error == nil {
                do {
                    let jsonArray = try JSONSerialization.jsonObject(with: data) as? [Any]
                    if let jsonArray,
                       jsonArray.count >= 2,
                       let suggestionsArray = Self.parseGoogleSuggestions(from: jsonArray[1]),
                       suggestionsArray.isEmpty == false {
                        webSuggestionTexts = Array(suggestionsArray.prefix(5))
                    } else {
                        RuntimeDiagnostics.emit("Invalid JSON response format")
                        webSuggestionTexts = nil
                    }
                } catch {
                    RuntimeDiagnostics.emit("JSON parsing error: \(error.localizedDescription)")
                    webSuggestionTexts = nil
                }
            } else {
                RuntimeDiagnostics.emit("Search suggestions error: \(error?.localizedDescription ?? "Unknown error")")
                webSuggestionTexts = nil
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                guard generation == self.activeWebSuggestionGeneration else { return }

                self.isLoading = false

                if let webSuggestionTexts {
                    self.storeCachedWebSuggestions(webSuggestionTexts, for: query)
                    let combinedSuggestions = self.combineSuggestions(
                        prependTabSuggestions,
                        withWebSuggestionTexts: webSuggestionTexts
                    )
                    self.updateSuggestionsIfNeeded(combinedSuggestions)
                }
            }
        }
        
        searchTask?.resume()
    }

    nonisolated private static func parseGoogleSuggestions(from payload: Any) -> [String]? {
        if let suggestions = payload as? [String] {
            return suggestions
        }

        guard let entries = payload as? [[Any]] else {
            return nil
        }

        let suggestions = entries.compactMap { entry in
            entry.first as? String
        }

        return suggestions.isEmpty ? nil : suggestions
    }

    private func combineSuggestions(
        _ baseSuggestions: [SearchSuggestion],
        withWebSuggestionTexts webSuggestionTexts: [String]
    ) -> [SearchSuggestion] {
        var combinedSuggestions = baseSuggestions

        for suggestionText in webSuggestionTexts {
            let suggestion = SearchSuggestion(
                text: suggestionText,
                type: isLikelyURL(suggestionText) == true ? .url : .search
            )
            if !combinedSuggestions.contains(suggestion) {
                combinedSuggestions.append(suggestion)
            }
            if combinedSuggestions.count >= 5 {
                break
            }
        }

        return Array(combinedSuggestions.prefix(5))
    }

    private func storeCachedWebSuggestions(_ suggestions: [String], for query: String) {
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
        searchTask?.cancel()
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
