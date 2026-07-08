//
//  WebSuggestionCache.swift
//  Sumi
//
//

import Foundation

/// Pure bounded LRU-ish cache of decoded web (DuckDuckGo) suggestions keyed
/// by normalized query text. Isolated so the eviction policy is directly
/// unit-testable without a SearchManager or network stack.
struct WebSuggestionCache {
    private let capacity: Int
    private var order: [String] = []
    private var suggestionsByQuery: [String: [SumiSuggestionEngine.APISuggestion]] = [:]

    init(capacity: Int = 24) {
        self.capacity = capacity
    }

    func suggestions(for query: String) -> [SumiSuggestionEngine.APISuggestion]? {
        suggestionsByQuery[query]
    }

    mutating func store(_ suggestions: [SumiSuggestionEngine.APISuggestion], for query: String) {
        suggestionsByQuery[query] = suggestions
        order.removeAll { $0 == query }
        order.append(query)

        while order.count > capacity {
            let evictedQuery = order.removeFirst()
            suggestionsByQuery.removeValue(forKey: evictedQuery)
        }
    }
}
