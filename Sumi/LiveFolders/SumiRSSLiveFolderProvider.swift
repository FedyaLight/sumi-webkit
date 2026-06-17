import Foundation

struct SumiRSSLiveFolderProvider: Sendable {
    private let networkClient: SumiLiveFolderNetworkClient

    init(networkClient: SumiLiveFolderNetworkClient) {
        self.networkClient = networkClient
    }

    func fetch(source: SumiLiveFolderSource) async -> SumiLiveFolderProviderResponse {
        guard let url = URL(string: source.urlString),
              ["http", "https"].contains(url.scheme?.lowercased()) else {
            return failure(.invalidURL)
        }

        do {
            let response = try await networkClient.fetch(
                url: url,
                accept: "application/rss+xml,application/atom+xml,application/xml,text/xml,*/*;q=0.2",
                etag: source.etag,
                lastModified: source.lastModified
            )

            if response.statusCode == 304 {
                return SumiLiveFolderProviderResponse(
                    outcome: .notModified,
                    etag: response.etag,
                    lastModified: response.lastModified
                )
            }
            guard (200..<300).contains(response.statusCode) else {
                return failure(.network, retryAfter: response.retryAfter, response: response)
            }

            let parser = SumiRSSFeedParser(data: response.data, sourceId: source.id)
            guard let parsed = parser.parse() else {
                return failure(.parseFailed, response: response)
            }

            let now = Date()
            let cutoff = source.timeRangeSeconds.flatMap { seconds -> Date? in
                seconds > 0 ? now.addingTimeInterval(-seconds) : nil
            }
            let items = parsed.items
                .filter { item in
                    guard let url = item.url,
                          ["http", "https"].contains(url.scheme?.lowercased()) else {
                        return false
                    }
                    guard let itemDate = item.sortDate ?? item.updatedAt ?? item.publishedAt else {
                        return false
                    }
                    return cutoff.map { itemDate >= $0 } ?? true
                }
                .sorted { lhs, rhs in
                    lhs.sortKeyDate > rhs.sortKeyDate
                }
                .prefix(max(1, source.maxItems))

            return SumiLiveFolderProviderResponse(
                outcome: .success(
                    items: Array(items),
                    title: parsed.title,
                    activeRepositories: []
                ),
                etag: response.etag,
                lastModified: response.lastModified
            )
        } catch SumiLiveFolderNetworkClient.FetchError.oversizedResponse {
            return failure(.oversizedResponse)
        } catch {
            return failure(.network)
        }
    }

    private func failure(
        _ kind: SumiLiveFolderErrorKind,
        retryAfter: Date? = nil,
        response: SumiLiveFolderHTTPResponse? = nil
    ) -> SumiLiveFolderProviderResponse {
        SumiLiveFolderProviderResponse(
            outcome: .failure(kind, retryAfter: retryAfter),
            etag: response?.etag,
            lastModified: response?.lastModified
        )
    }
}

final class SumiRSSFeedParser: NSObject, XMLParserDelegate {
    struct ParsedFeed {
        var title: String?
        var items: [SumiLiveFolderItem]
    }

    private struct DraftItem {
        var title: String?
        var urlString: String?
        var stableId: String?
        var subtitle: String?
        var publishedAt: Date?
        var updatedAt: Date?
    }

    private let data: Data
    private let sourceId: UUID
    private var feedTitle: String?
    private var items: [SumiLiveFolderItem] = []
    private var elementStack: [String] = []
    private var textBuffer = ""
    private var currentItem: DraftItem?

    init(data: Data, sourceId: UUID) {
        self.data = data
        self.sourceId = sourceId
    }

    func parse() -> ParsedFeed? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            return nil
        }
        return ParsedFeed(title: feedTitle, items: items)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = normalized(elementName)
        elementStack.append(name)
        textBuffer = ""

        if name == "item" || name == "entry" {
            currentItem = DraftItem()
        } else if name == "link", var item = currentItem {
            let rel = attributeDict["rel"]?.lowercased()
            if rel == nil || rel == "alternate" {
                item.urlString = attributeDict["href"] ?? item.urlString
                currentItem = item
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = normalized(elementName)
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        if currentItem != nil {
            apply(text: text, toCurrentItemElement: name)
            if name == "item" || name == "entry" {
                finishCurrentItem()
            }
        } else if name == "title", feedTitle == nil, !text.isEmpty {
            feedTitle = text
        }

        if !elementStack.isEmpty {
            elementStack.removeLast()
        }
        textBuffer = ""
    }

    private func apply(text: String, toCurrentItemElement name: String) {
        guard !text.isEmpty, var item = currentItem else { return }
        switch name {
        case "title":
            item.title = text
        case "link":
            item.urlString = item.urlString ?? text
        case "guid", "id":
            item.stableId = text
        case "creator", "author", "name":
            item.subtitle = item.subtitle ?? text
        case "pubdate", "published":
            item.publishedAt = parseFeedDate(text)
        case "updated":
            item.updatedAt = parseFeedDate(text)
        default:
            break
        }
        currentItem = item
    }

    private func finishCurrentItem() {
        guard let draft = currentItem else { return }
        defer { currentItem = nil }

        let title = draft.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = draft.urlString?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let title, !title.isEmpty,
              let urlString, !urlString.isEmpty else {
            return
        }

        let stableId = draft.stableId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = stableId?.isEmpty == false ? stableId! : urlString
        let now = Date()
        let sortDate = draft.updatedAt ?? draft.publishedAt
        items.append(
            SumiLiveFolderItem(
                id: id,
                sourceId: sourceId,
                title: title,
                urlString: urlString,
                subtitle: draft.subtitle,
                publishedAt: draft.publishedAt,
                updatedAt: draft.updatedAt,
                sortDate: sortDate,
                stateBadge: nil,
                iconSystemName: "dot.radiowaves.left.and.right",
                firstSeenAt: now,
                lastSeenAt: now
            )
        )
    }

    private func normalized(_ name: String) -> String {
        name
            .split(separator: ":")
            .last
            .map(String.init)?
            .lowercased()
        ?? name.lowercased()
    }

    private func parseFeedDate(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string) ?? HTTPDateParser.parse(string)
    }
}
