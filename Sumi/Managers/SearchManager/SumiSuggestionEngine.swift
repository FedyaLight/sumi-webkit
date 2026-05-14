import Foundation

struct SumiSuggestionEngine {
    enum Platform {
        case desktop
    }

    enum Item: Equatable {
        case phrase(String)
        case website(URL)
        case bookmark(title: String, url: URL, isFavorite: Bool, score: Int)
        case history(title: String?, url: URL, score: Int)
        case openTab(title: String, url: URL, tabId: UUID?, score: Int)

        var url: URL? {
            switch self {
            case .website(let url),
                 .bookmark(_, let url, _, _),
                 .history(_, let url, _),
                 .openTab(_, let url, _, _):
                return url
            case .phrase:
                return nil
            }
        }
    }

    struct Result: Equatable {
        static let empty = Result(topHits: [], remoteSuggestions: [], localSuggestions: [])

        let topHits: [Item]
        let remoteSuggestions: [Item]
        let localSuggestions: [Item]

        var all: [Item] {
            topHits + localSuggestions + remoteSuggestions
        }
    }

    struct HistoryItem {
        let url: URL
        let title: String?
        let visitCount: Int
        let failedToLoad: Bool
    }

    struct BookmarkItem {
        let url: URL
        let title: String
        let isFavorite: Bool
    }

    struct TabItem {
        let id: UUID?
        let url: URL
        let title: String
    }

    struct APISuggestion: Decodable {
        let phrase: String?
        let isNav: Bool?

        enum CodingKeys: String, CodingKey {
            case phrase
            case isNav = "is_nav"
        }
    }

    struct ScoredSuggestion {
        enum Kind: Hashable {
            case phrase
            case website
            case bookmark
            case favorite
            case history
            case tab
        }

        var kind: Kind
        var url: URL
        var title: String
        var visitCount: Int = 0
        var failedToLoad: Bool = false
        var score: Int = 0
        var tabId: UUID?
    }

    private static let maximumNumberOfSuggestions = 12
    private static let maximumNumberOfTopHits = 2
    private static let minimumNumberInSuggestionGroup = 5

    func result(
        for query: String,
        history: [HistoryItem],
        bookmarks: [BookmarkItem],
        openTabs: [TabItem],
        apiSuggestions: [APISuggestion],
        isUrlIgnored: @escaping (URL) -> Bool = { _ in false }
    ) -> Result {
        let searchQuery = SearchTextQuery(query)
        guard !searchQuery.isEmpty else { return .empty }

        let remoteSuggestions = duckDuckGoSuggestions(from: apiSuggestions, isUrlIgnored: isUrlIgnored)
        let remoteDomainSuggestions = remoteSuggestions.compactMap { item -> (suggestion: ScoredSuggestion, kinds: Set<ScoredSuggestion.Kind>)? in
            guard case .website(let url) = item else { return nil }
            return (
                ScoredSuggestion(kind: .website, url: url, title: url.absoluteString),
                [.website]
            )
        }

        let scoredLocal = [
            bookmarks.compactMap(scored(searchQuery: searchQuery, isUrlIgnored: isUrlIgnored)),
            openTabs.compactMap(scored(searchQuery: searchQuery, isUrlIgnored: isUrlIgnored)),
            history.compactMap(scored(searchQuery: searchQuery, isUrlIgnored: isUrlIgnored)),
        ]
            .joined()
            .sorted { $0.score > $1.score }
            .prefix(100)

        let dedupedLocal = removeDuplicates(scoredLocal)
        let navigationalSuggestions = dedupedLocal.sorted { $0.suggestion.score > $1.suggestion.score } + remoteDomainSuggestions

        let topHitsDeduped = navigationalSuggestions
            .filter { isTopHit($0.suggestion, $0.kinds) }
            .prefix(Self.maximumNumberOfTopHits)

        let topHits = handleTopHitsOpenTabCase(topHitsDeduped).compactMap(Item.init)
        let localCount = max(0, Self.maximumNumberOfSuggestions - topHits.count)

        let localSuggestions = navigationalSuggestions
            .filter {
                guard $0.kinds.intersects([.history, .bookmark, .favorite, .tab]),
                      let item = Item($0.suggestion),
                      !topHits.contains(item)
                else { return false }
                return true
            }
            .prefix(max(0, localCount))
            .compactMap { Item($0.suggestion) }

        let remainingRemoteSuggestions = remoteSuggestions
            .filter { !topHits.contains($0) }
            .prefix(max(0, Self.maximumNumberOfSuggestions - (topHits.count + localSuggestions.count)))

        return Result(
            topHits: topHits,
            remoteSuggestions: Array(remainingRemoteSuggestions),
            localSuggestions: localSuggestions
        )
    }

    private func duckDuckGoSuggestions(
        from suggestions: [APISuggestion],
        isUrlIgnored: (URL) -> Bool
    ) -> [Item] {
        suggestions.compactMap { suggestion in
            guard let phrase = suggestion.phrase else { return nil }
            let decodedPhrase = decodeSearchSuggestionEntities(phrase)
            if suggestion.isNav == true {
                guard let url = URL(string: "http://\(decodedPhrase)"),
                      !isUrlIgnored(url)
                else { return nil }
                return .website(url)
            }
            return .phrase(decodedPhrase)
        }
    }

    private func removeDuplicates(
        _ suggestions: some Sequence<ScoredSuggestion>
    ) -> [(suggestion: ScoredSuggestion, kinds: Set<ScoredSuggestion.Kind>)] {
        var orderedKeys: [String] = []
        var seenKeys = Set<String>()
        let groupedByURL = Dictionary(grouping: suggestions) { suggestion in
            let key = suggestion.url.sumiSuggestionNakedString
            if seenKeys.insert(key).inserted {
                orderedKeys.append(key)
            }
            return key
        }

        var result: [(ScoredSuggestion, Set<ScoredSuggestion.Kind>)] = []
        for key in orderedKeys {
            guard let group = groupedByURL[key],
                  var suggestion = group.max(by: { $0.quality < $1.quality })
            else { continue }

            let kinds = Set(group.map(\.kind))
            suggestion.visitCount = group.reduce(0) { $0 + ($1.kind == .history ? $1.visitCount : 0) }
            suggestion.tabId = group.first(where: { $0.kind == .tab })?.tabId
            suggestion.score = group.max(by: { $0.score < $1.score })?.score ?? 0
            result.append((suggestion, kinds))
        }

        return result
    }

    private func isTopHit(_ suggestion: ScoredSuggestion, _ kinds: Set<ScoredSuggestion.Kind>) -> Bool {
        guard kinds.intersects([.website, .favorite, .history]) else { return false }

        if kinds == [.history] {
            return !suggestion.failedToLoad && (suggestion.visitCount > 3 || suggestion.url.sumiSuggestionIsRoot)
        }

        if kinds == [.tab] {
            return false
        }

        return true
    }

    private func handleTopHitsOpenTabCase(
        _ topHits: some Collection<(suggestion: ScoredSuggestion, kinds: Set<ScoredSuggestion.Kind>)>
    ) -> [ScoredSuggestion] {
        var result = topHits.map(\.suggestion)

        guard let topHit = topHits.first,
              topHit.kinds.contains(.tab),
              topHit.kinds.intersects([.history, .bookmark, .favorite])
        else { return result }

        let newKind = if topHit.suggestion.kind == .tab {
            topHit.kinds.filter { $0 != .tab }.max(by: { $0.quality < $1.quality }) ?? .tab
        } else {
            ScoredSuggestion.Kind.tab
        }

        var newSuggestion = topHit.suggestion
        newSuggestion.kind = newKind
        result.insert(newSuggestion, at: newKind == .tab ? 1 : 0)

        if result.count > Self.maximumNumberOfTopHits {
            result.removeSubrange(Self.maximumNumberOfTopHits...)
        }

        return result
    }

    private func scored(searchQuery: SearchTextQuery, isUrlIgnored: @escaping (URL) -> Bool) -> (BookmarkItem) -> ScoredSuggestion? {
        { bookmark in
            guard !isUrlIgnored(bookmark.url) else { return nil }
            let score = score(title: bookmark.title, url: bookmark.url, visitCount: 0, searchQuery: searchQuery)
            guard score > 0 else { return nil }
            return ScoredSuggestion(
                kind: bookmark.isFavorite ? .favorite : .bookmark,
                url: bookmark.url,
                title: bookmark.title,
                score: score
            )
        }
    }

    private func scored(searchQuery: SearchTextQuery, isUrlIgnored: @escaping (URL) -> Bool) -> (HistoryItem) -> ScoredSuggestion? {
        { history in
            guard !isUrlIgnored(history.url) else { return nil }
            let score = score(title: history.title ?? "", url: history.url, visitCount: history.visitCount, searchQuery: searchQuery)
            guard score > 0 else { return nil }
            return ScoredSuggestion(
                kind: .history,
                url: history.url,
                title: history.title ?? "",
                visitCount: history.visitCount,
                failedToLoad: history.failedToLoad,
                score: score
            )
        }
    }

    private func scored(searchQuery: SearchTextQuery, isUrlIgnored: @escaping (URL) -> Bool) -> (TabItem) -> ScoredSuggestion? {
        { tab in
            guard !isUrlIgnored(tab.url) else { return nil }
            let score = score(title: tab.title, url: tab.url, visitCount: 0, searchQuery: searchQuery)
            guard score > 0 else { return nil }
            return ScoredSuggestion(kind: .tab, url: tab.url, title: tab.title, score: score, tabId: tab.id)
        }
    }

    private func score(title: String?, url: URL, visitCount: Int, searchQuery: SearchTextQuery) -> Int {
        var score = 0
        let normalizedTitle = SearchTextQuery.normalized(title ?? "")
        let query = searchQuery.folded
        let queryTokens = query.tokenizedForSumiSuggestions()
        let queryCount = query.count
        let domain = SearchTextQuery.normalized(url.host?.droppingSumiSuggestionWwwPrefix() ?? "")
        let nakedURL = SearchTextQuery.normalized(url.sumiSuggestionNakedString)

        if nakedURL.hasPrefix(query) {
            score += 300
            if url.sumiSuggestionIsRoot { score += 2000 }
        } else if normalizedTitle.leadingSumiSuggestionBoundaryStarts(with: query) {
            score += 200
            if url.sumiSuggestionIsRoot { score += 2000 }
        } else if queryCount > 2 && domain.contains(query) {
            score += 150
        } else if queryCount > 2 && normalizedTitle.contains(" \(query)") {
            score += 100
        } else if queryTokens.count > 1 {
            var matchesAllTokens = true
            for token in queryTokens {
                guard normalizedTitle.leadingSumiSuggestionBoundaryStarts(with: token)
                    || normalizedTitle.contains(" \(token)")
                    || nakedURL.hasPrefix(token)
                else {
                    matchesAllTokens = false
                    break
                }
            }

            if matchesAllTokens {
                score += 10
                if nakedURL.hasPrefix(queryTokens[0]) {
                    score += 70
                } else if normalizedTitle.leadingSumiSuggestionBoundaryStarts(with: queryTokens[0]) {
                    score += 50
                }
            }
        }

        if score > 0 {
            score <<= 10
            score += visitCount
        }

        return score
    }
}

private extension SumiSuggestionEngine.Item {
    init?(_ suggestion: SumiSuggestionEngine.ScoredSuggestion) {
        switch suggestion.kind {
        case .phrase:
            self = .phrase(suggestion.title)
        case .website:
            self = .website(suggestion.url)
        case .bookmark:
            self = .bookmark(title: suggestion.title, url: suggestion.url, isFavorite: false, score: suggestion.score)
        case .favorite:
            self = .bookmark(title: suggestion.title, url: suggestion.url, isFavorite: true, score: suggestion.score)
        case .history:
            self = .history(title: suggestion.title, url: suggestion.url, score: suggestion.score)
        case .tab:
            self = .openTab(title: suggestion.title, url: suggestion.url, tabId: suggestion.tabId, score: suggestion.score)
        }
    }
}

private extension SumiSuggestionEngine.ScoredSuggestion.Kind {
    var quality: Int {
        switch self {
        case .phrase: return 1
        case .website: return 2
        case .history: return 3
        case .tab: return 4
        case .bookmark: return 5
        case .favorite: return 6
        }
    }
}

private extension SumiSuggestionEngine.ScoredSuggestion {
    var quality: Int { kind.quality }
}

private extension String {
    func tokenizedForSumiSuggestions() -> [String] {
        components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
    }

    func leadingSumiSuggestionBoundaryStarts(with string: String) -> Bool {
        hasPrefix(string) || trimmingCharacters(in: .alphanumerics.inverted).hasPrefix(string)
    }

    func droppingSumiSuggestionWwwPrefix() -> String {
        hasPrefix("www.") ? String(dropFirst(4)) : self
    }
}

private extension URL {
    var sumiSuggestionIsRoot: Bool {
        path.isEmpty || path == "/"
    }

    var sumiSuggestionNakedString: String {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return absoluteString
        }
        components.scheme = nil
        components.user = nil
        components.password = nil
        components.host = components.host?.droppingSumiSuggestionWwwPrefix()
        if components.path == "/" {
            components.path = ""
        }
        return components.string ?? absoluteString
    }
}

private extension Set {
    func intersects(_ values: [Element]) -> Bool {
        values.contains { contains($0) }
    }
}
