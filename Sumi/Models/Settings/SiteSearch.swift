//
//  SiteSearch.swift
//  Sumi
//
//  Site search (Tab-to-Search) data model and matching logic
//

import SwiftUI

// MARK: - Unified Search Engine

struct SumiSearchEngine: Codable, Identifiable, Equatable, Sendable {
    static let queryToken = "{query}"

    var id: String
    var name: String
    var domain: String
    var searchURLTemplate: String
    var colorHex: String
    var tabSearchEnabled: Bool

    var color: Color {
        Color(hex: colorHex)
    }

    var queryTemplate: String {
        normalizedSearchURLTemplate.replacingOccurrences(of: Self.queryToken, with: "%@")
    }

    private var normalizedSearchURLTemplate: String {
        var template = searchURLTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        template = template.replacingOccurrences(of: "%@", with: Self.queryToken)
        if !template.hasPrefix("http://") && !template.hasPrefix("https://") {
            template = "https://" + template
        }
        return template
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        domain: String,
        searchURLTemplate: String,
        colorHex: String = "#666666",
        tabSearchEnabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.domain = domain
        self.searchURLTemplate = Self.normalizedTemplate(searchURLTemplate)
        self.colorHex = Self.normalizedColorHex(colorHex)
        self.tabSearchEnabled = tabSearchEnabled
    }

    func searchURL(for query: String) -> URL? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }

        let urlString = normalizedSearchURLTemplate.replacingOccurrences(of: Self.queryToken, with: encoded)
        return URL(string: urlString)
    }

    func matches(prefix: String) -> Bool {
        let query = SearchTextQuery.normalized(prefix.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !query.isEmpty else { return false }

        return matchCandidates.contains {
            SearchTextQuery.normalized($0).hasPrefix(query)
        }
    }

    func matchesFilter(_ text: String) -> Bool {
        let query = SearchTextQuery(text)
        guard !query.isEmpty else { return true }

        return matchCandidates.contains {
            query.matches($0)
        } || query.matches(searchURLTemplate)
    }

    private var matchCandidates: [String] {
        [
            name,
            domain,
            domain.droppingWWWPrefix,
        ]
    }

    static func match(for text: String, in engines: [SumiSearchEngine]) -> SumiSearchEngine? {
        engines.first { engine in
            engine.tabSearchEnabled && engine.matches(prefix: text)
        }
    }

    static func normalized(_ engines: [SumiSearchEngine]) -> [SumiSearchEngine] {
        var seen = Set<String>()
        return engines.compactMap { engine in
            guard !engine.id.isEmpty, !seen.contains(engine.id) else { return nil }
            seen.insert(engine.id)
            return SumiSearchEngine(
                id: engine.id,
                name: engine.name,
                domain: engine.domain,
                searchURLTemplate: engine.searchURLTemplate,
                colorHex: engine.colorHex,
                tabSearchEnabled: engine.tabSearchEnabled
            )
        }
    }

    static func defaultSearchEngineID(in engines: [SumiSearchEngine]) -> String {
        if engines.contains(where: { $0.id == SearchProvider.google.rawValue }) {
            return SearchProvider.google.rawValue
        }
        return engines.first?.id ?? SearchProvider.google.rawValue
    }

    static func defaultEngines() -> [SumiSearchEngine] {
        var engines = SearchProvider.allCases.map { provider in
            let matchingSite = defaultSiteSearchEngines.first {
                SearchProvider.matchingSearchProvider(name: $0.name, domain: $0.domain) == provider
            }
            return provider.engine(
                tabSearchEnabled: matchingSite != nil,
                overridingSite: matchingSite
            )
        }
        for site in defaultSiteSearchEngines {
            guard SearchProvider.matchingSearchProvider(name: site.name, domain: site.domain) == nil else {
                continue
            }
            engines.append(site)
        }

        return normalized(engines)
    }

    static func normalizedTemplate(_ template: String) -> String {
        template
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%@", with: Self.queryToken)
    }

    static func normalizedColorHex(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
    }

    private static let defaultSiteSearchEngines: [SumiSearchEngine] = [
        SumiSearchEngine(
            id: "site.youtube",
            name: "YouTube", domain: "youtube.com",
            searchURLTemplate: "https://www.youtube.com/results?search_query={query}",
            colorHex: "#E62617",
            tabSearchEnabled: true
        ),
        SumiSearchEngine(
            id: "site.github",
            name: "GitHub", domain: "github.com",
            searchURLTemplate: "https://github.com/search?q={query}",
            colorHex: "#8B4DD9",
            tabSearchEnabled: true
        ),
        SumiSearchEngine(
            id: "site.reddit",
            name: "Reddit", domain: "reddit.com",
            searchURLTemplate: "https://www.reddit.com/search/?q={query}",
            colorHex: "#FF7300",
            tabSearchEnabled: true
        ),
        SumiSearchEngine(
            id: "site.x",
            name: "X", domain: "x.com",
            searchURLTemplate: "https://x.com/search?q={query}",
            colorHex: "#666666",
            tabSearchEnabled: true
        ),
        SumiSearchEngine(
            id: "site.wikipedia",
            name: "Wikipedia", domain: "wikipedia.org",
            searchURLTemplate: "https://en.wikipedia.org/w/index.php?search={query}",
            colorHex: "#737373",
            tabSearchEnabled: true
        ),
        SumiSearchEngine(
            id: "site.amazon",
            name: "Amazon", domain: "amazon.com",
            searchURLTemplate: "https://www.amazon.com/s?k={query}",
            colorHex: "#FF8C00",
            tabSearchEnabled: true
        ),
        SumiSearchEngine(
            id: "site.twitch",
            name: "Twitch", domain: "twitch.tv",
            searchURLTemplate: "https://www.twitch.tv/search?term={query}",
            colorHex: "#9146EB",
            tabSearchEnabled: true
        ),
        SumiSearchEngine(
            id: "site.spotify",
            name: "Spotify", domain: "open.spotify.com",
            searchURLTemplate: "https://open.spotify.com/search/{query}",
            colorHex: "#1DB954",
            tabSearchEnabled: true
        ),
        SumiSearchEngine(
            id: "site.stackoverflow",
            name: "Stack Overflow", domain: "stackoverflow.com",
            searchURLTemplate: "https://stackoverflow.com/search?q={query}",
            colorHex: "#F28C0D",
            tabSearchEnabled: true
        ),
        SumiSearchEngine(
            id: "site.perplexity",
            name: "Perplexity", domain: "perplexity.ai",
            searchURLTemplate: "https://www.perplexity.ai/search?q={query}",
            colorHex: "#20B8CD",
            tabSearchEnabled: true
        ),
        SumiSearchEngine(
            id: "site.chatgpt",
            name: "ChatGPT", domain: "chatgpt.com",
            searchURLTemplate: "https://chatgpt.com/?q={query}",
            colorHex: "#10A37F",
            tabSearchEnabled: true
        ),
        SumiSearchEngine(
            id: "site.claude",
            name: "Claude", domain: "claude.ai",
            searchURLTemplate: "https://claude.ai/new?q={query}",
            colorHex: "#D97757",
            tabSearchEnabled: true
        ),
        SumiSearchEngine(
            id: "site.gemini",
            name: "Gemini", domain: "gemini.google.com",
            searchURLTemplate: "https://gemini.google.com/app?q={query}",
            colorHex: "#8E75B2",
            tabSearchEnabled: true
        ),
        SumiSearchEngine(
            id: "site.grok",
            name: "Grok", domain: "grok.com",
            searchURLTemplate: "https://grok.com/?q={query}",
            colorHex: "#000000",
            tabSearchEnabled: true
        ),
    ]
}

private extension SearchProvider {
    func engine(tabSearchEnabled: Bool, overridingSite site: SumiSearchEngine? = nil) -> SumiSearchEngine {
        SumiSearchEngine(
            id: rawValue,
            name: site?.name ?? displayName,
            domain: site?.domain ?? host,
            searchURLTemplate: site?.searchURLTemplate ?? queryTemplate,
            colorHex: site?.colorHex ?? defaultColorHex,
            tabSearchEnabled: tabSearchEnabled
        )
    }

    static func matchingSearchProvider(name: String, domain: String) -> SearchProvider? {
        let normalizedName = SearchTextQuery.normalized(name)
        let normalizedDomain = SearchTextQuery.normalized(domain.droppingWWWPrefix)
        return allCases.first { provider in
            SearchTextQuery.normalized(provider.displayName) == normalizedName
                || SearchTextQuery.normalized(provider.host.droppingWWWPrefix) == normalizedDomain
        }
    }

    var defaultColorHex: String {
        switch self {
        case .google: return "#4285F4"
        case .duckDuckGo: return "#DE5833"
        case .bing: return "#008373"
        case .brave: return "#FB542B"
        case .yahoo: return "#6001D2"
        case .perplexity: return "#20B8CD"
        case .unduck: return "#666666"
        case .ecosia: return "#008009"
        case .kagi: return "#FFB319"
        }
    }
}

private extension String {
    var droppingWWWPrefix: String {
        lowercased().hasPrefix("www.") ? String(dropFirst(4)) : self
    }
}
