//
//  SuggestionDeduplicationPolicy.swift
//  Sumi
//
//

import Foundation
import SumiDomain

/// Pure dedup/identity policy for search suggestions: how a suggestion's
/// canonical URL is derived, whether two suggestions are "the same" result,
/// and whether a query looks like a direct URL navigation.
///
/// No dependencies beyond MainActor-isolated model types (`Tab`).
@MainActor
enum SuggestionDeduplicationPolicy {
    static func topLinkDeduplicationKey(for url: URL) -> String {
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

    static func deduplicationKey(for suggestion: SearchManager.SearchSuggestion) -> String {
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
        case .command(let command):
            return "command:\(command.rawValue)"
        }
    }

    static func isLocalNavigationSuggestion(_ suggestion: SearchManager.SearchSuggestion) -> Bool {
        switch suggestion.type {
        case .history, .bookmark, .tab:
            return true
        case .search, .url, .command:
            return false
        }
    }

    static func directURLSuggestion(for query: String) -> SearchManager.SearchSuggestion? {
        guard isLikelyURL(query) else { return nil }
        let normalizedURL = normalizeURL(query, queryTemplate: SearchProvider.duckDuckGo.queryTemplate)
        return SearchManager.SearchSuggestion(text: normalizedURL, type: .url)
    }
}
