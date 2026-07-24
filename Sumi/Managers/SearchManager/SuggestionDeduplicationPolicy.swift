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
    static func canonicalNavigationKey(for url: URL) -> String {
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
            return "url:\(canonicalNavigationKey(for: url).lowercased())"
        case .history(let entry):
            return "url:\(canonicalNavigationKey(for: entry.url).lowercased())"
        case .bookmark(let bookmark):
            return "url:\(canonicalNavigationKey(for: bookmark.url).lowercased())"
        case .tab(let tab):
            return "url:\(canonicalNavigationKey(for: tab.url).lowercased())"
        case .navigationTarget(let target):
            guard let url = target.primaryURL else {
                return "navigation:\(target.identity)"
            }
            return "url:\(canonicalNavigationKey(for: url).lowercased())"
        case .command(let command):
            return "command:\(command.rawValue)"
        case .space(let space):
            return "space:\(space.id.uuidString)"
        case .extensionAction(let action):
            return "extension:\(action.id)"
        }
    }

    static func isLocalNavigationSuggestion(_ suggestion: SearchManager.SearchSuggestion) -> Bool {
        switch suggestion.type {
        case .history, .bookmark, .tab, .navigationTarget:
            return true
        case .search, .url, .command, .space, .extensionAction:
            return false
        }
    }

    static func directURLSuggestion(for query: String) -> SearchManager.SearchSuggestion? {
        guard isLikelyURL(query) else { return nil }
        let normalizedURL = normalizeURL(query, queryTemplate: SearchProvider.duckDuckGo.queryTemplate)
        return SearchManager.SearchSuggestion(text: normalizedURL, type: .url)
    }
}
