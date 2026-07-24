//
//  HistorySuggestionMatcher.swift
//  Sumi
//
//

import Foundation

/// Pure history-matching/ranking policy used by search suggestions:
/// merging duplicate history sources, matching entries against a query by
/// URL/domain, and splicing URL-matched history results into an existing
/// ranked suggestion list.
///
/// No dependencies — operates only on the data passed in, so it is directly
/// unit-testable without a running SearchManager, HistoryManager, etc.
@MainActor
enum HistorySuggestionMatcher {
    /// Merges site-aggregate and per-visit history matches, deduplicating by
    /// canonical URL and preferring the first occurrence (site matches take
    /// priority over individual visits).
    static func merge(
        siteMatches: [HistoryListItem],
        visitMatches: [HistoryListItem]
    ) -> [HistoryListItem] {
        var merged: [HistoryListItem] = []
        var seen = Set<String>()

        func append(_ item: HistoryListItem) {
            let key = SuggestionDeduplicationPolicy
                .canonicalNavigationKey(for: item.url)
            guard seen.insert(key).inserted else { return }
            merged.append(item)
        }

        siteMatches.forEach(append)
        visitMatches.forEach(append)
        return merged
    }

    static func matches(_ entry: HistoryListItem, query: SearchTextQuery) -> Bool {
        query.matches(entry.url.absoluteString)
            || query.matches(entry.domain)
            || (entry.siteDomain.map(query.matches) ?? false)
    }

    /// Splices history entries whose URL/domain matches `query` into
    /// `suggestions`, ranked ahead of remote/local-navigation suggestions
    /// once the list is at capacity. Mutates in place to preserve the
    /// existing dedup-key bookkeeping used by the caller.
    static func appendURLMatchedSuggestions(
        from historyEntries: [HistoryListItem],
        query: String,
        maxVisibleSuggestions: Int,
        suggestions: inout [SearchManager.SearchSuggestion],
        seenKeys: inout Set<String>
    ) {
        let searchQuery = SearchTextQuery(query)
        guard !searchQuery.isEmpty else { return }

        let urlMatches = historyEntries
            .filter { matches($0, query: searchQuery) }
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
            let suggestion = SearchManager.SearchSuggestion(text: entry.displayTitle, type: .history(entry))
            let key = SuggestionDeduplicationPolicy.deduplicationKey(for: suggestion)
            guard seenKeys.insert(key).inserted else { continue }

            if suggestions.count < maxVisibleSuggestions {
                suggestions.append(suggestion)
                continue
            }

            guard let replacementIndex = suggestions.lastIndex(where: {
                !SuggestionDeduplicationPolicy.isLocalNavigationSuggestion($0)
            }) else {
                seenKeys.remove(key)
                continue
            }

            let removed = suggestions[replacementIndex]
            seenKeys.remove(SuggestionDeduplicationPolicy.deduplicationKey(for: removed))
            suggestions[replacementIndex] = suggestion
        }
    }
}
