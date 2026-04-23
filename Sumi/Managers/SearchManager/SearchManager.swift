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
class SearchManager {
    var suggestions: [SearchSuggestion] = []
    var isLoading: Bool = false
    
    private let session = URLSession.shared
    private var searchTask: URLSessionDataTask?
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
    
    func setTabManager(_ tabManager: TabManager?) {
        self.tabManager = tabManager
        // Hop to MainActor to update profile context safely
        Task { @MainActor in
            self.updateProfileContext()
        }
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
        webSuggestionRequestGeneration &+= 1
        activeWebSuggestionGeneration = webSuggestionRequestGeneration

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
        
        // Search history
        let historySuggestions = searchHistory(for: normalizedQuery)
        
        // Combine suggestions: tabs first, then history, then web suggestions
        var allSuggestions: [SearchSuggestion] = []
        
        // Add tab suggestions (limit to 2 to leave room for history)
        let maxTabSuggestions = 2
        let limitedTabSuggestions = Array(tabSuggestions.prefix(maxTabSuggestions))
        allSuggestions.append(contentsOf: limitedTabSuggestions)
        
        // Add history suggestions (limit to leave room for web suggestions)
        let maxHistorySuggestions = 2
        let limitedHistorySuggestions = Array(historySuggestions.prefix(maxHistorySuggestions))
        allSuggestions.append(contentsOf: limitedHistorySuggestions)
        
        // Add URL suggestion if query looks like a URL
        if isLikelyURL(normalizedQuery) {
            allSuggestions.append(SearchSuggestion(text: normalizedQuery, type: .url))
        }
        
        // Update suggestions immediately with what we have
        if !allSuggestions.isEmpty {
            updateSuggestionsIfNeeded(allSuggestions)
        }

        if let cachedSuggestions = cachedWebSuggestions[normalizedQuery] {
            let combinedSuggestions = combineSuggestions(
                allSuggestions,
                withWebSuggestionTexts: cachedSuggestions
            )
            updateSuggestionsIfNeeded(combinedSuggestions)
            isLoading = false
            return
        }
        
        // Fetch web suggestions and combine them, but limit total to 5
        fetchWebSuggestions(
            for: normalizedQuery,
            prependTabSuggestions: allSuggestions,
            generation: activeWebSuggestionGeneration
        )
    }
    
    @MainActor private func searchTabs(for query: String) -> [SearchSuggestion] {
        guard let tabManager = tabManager else { return [] }
        
        let lowercaseQuery = query.lowercased()
        var matchingTabs: [SearchSuggestion] = []
        // Use TabManager's profile-aware access (handles fallback internally)
        let allTabs: [Tab] = tabManager.allTabsForCurrentProfile()
        
        for tab in allTabs {
            let nameMatch = tab.name.lowercased().contains(lowercaseQuery)
            let urlMatch = tab.url.absoluteString.lowercased().contains(lowercaseQuery)
            let hostMatch = tab.url.host?.lowercased().contains(lowercaseQuery) ?? false
            
            if nameMatch || urlMatch || hostMatch {
                let suggestion = SearchSuggestion(
                    text: tab.name,
                    type: .tab(tab)
                )
                matchingTabs.append(suggestion)
            }
        }
        
        // Sort by relevance (name matches first, then URL matches)
        let sortedTabs = matchingTabs.sorted { (lhs: SearchSuggestion, rhs: SearchSuggestion) -> Bool in
            if case .tab(let lhsTab) = lhs.type, case .tab(let rhsTab) = rhs.type {
                let lhsNameMatch = lhsTab.name.lowercased().contains(lowercaseQuery)
                let rhsNameMatch = rhsTab.name.lowercased().contains(lowercaseQuery)
                
                if lhsNameMatch && !rhsNameMatch {
                    return true
                } else if !lhsNameMatch && rhsNameMatch {
                    return false
                } else {
                    return lhsTab.name.count < rhsTab.name.count
                }
            }
            return false
        }
        
        return Array(sortedTabs.prefix(3)) // Limit to 3 tab suggestions
    }
    
    @MainActor private func searchHistory(for query: String) -> [SearchSuggestion] {
        guard let historyManager = historyManager else { return [] }
        
        let lowercaseQuery = query.lowercased()
        let historyEntries = historyManager.searchSuggestions(matching: query, limit: 20)
        
        var matchingHistory: [SearchSuggestion] = []
        
        for entry in historyEntries {
            let titleMatch = entry.title.lowercased().contains(lowercaseQuery)
            let urlMatch = entry.url.absoluteString.lowercased().contains(lowercaseQuery)
            let hostMatch = entry.url.host?.lowercased().contains(lowercaseQuery) ?? false
            
            if titleMatch || urlMatch || hostMatch {
                let suggestion = SearchSuggestion(
                    text: entry.displayTitle,
                    type: .history(entry)
                )
                matchingHistory.append(suggestion)
            }
        }
        
        // Sort by relevance (title matches first, then URL matches, then by visit count and recency)
        let sortedHistory = matchingHistory.sorted { (lhs: SearchSuggestion, rhs: SearchSuggestion) -> Bool in
            if case .history(let lhsHistory) = lhs.type, case .history(let rhsHistory) = rhs.type {
                let lhsTitleMatch = lhsHistory.title.lowercased().contains(lowercaseQuery)
                let rhsTitleMatch = rhsHistory.title.lowercased().contains(lowercaseQuery)
                
                // First prioritize title matches
                if lhsTitleMatch && !rhsTitleMatch {
                    return true
                } else if !lhsTitleMatch && rhsTitleMatch {
                    return false
                } else {
                    return (lhsHistory.visitedAt ?? .distantPast) > (rhsHistory.visitedAt ?? .distantPast)
                }
            }
            return false
        }
        
        return sortedHistory
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
        
        searchTask = session.dataTask(with: url) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard generation == self.activeWebSuggestionGeneration else { return }

                self.isLoading = false
                
                guard let data = data,
                      error == nil else {
                    RuntimeDiagnostics.emit("Search suggestions error: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                do {
                    guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [Any],
                          jsonArray.count >= 2,
                          let suggestionsArray = self.parseGoogleSuggestions(from: jsonArray[1]),
                          suggestionsArray.isEmpty == false else {
                        RuntimeDiagnostics.emit("Invalid JSON response format")
                        return
                    }

                    let limitedWebSuggestions = Array(suggestionsArray.prefix(5))
                    self.storeCachedWebSuggestions(limitedWebSuggestions, for: query)
                    let combinedSuggestions = self.combineSuggestions(
                        prependTabSuggestions,
                        withWebSuggestionTexts: limitedWebSuggestions
                    )
                    self.updateSuggestionsIfNeeded(combinedSuggestions)
                    
                } catch {
                    RuntimeDiagnostics.emit("JSON parsing error: \(error.localizedDescription)")
                }
            }
        }
        
        searchTask?.resume()
    }

    private func parseGoogleSuggestions(from payload: Any) -> [String]? {
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
