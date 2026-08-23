import Foundation
import OSLog

struct SumiGitHubLiveFolderProvider: Sendable {
    private static let log = Logger.sumi(category: "LiveFolders")

    private let networkClient: SumiLiveFolderNetworkClient

    init(networkClient: SumiLiveFolderNetworkClient) {
        self.networkClient = networkClient
    }

    func fetch(
        source: SumiLiveFolderSource,
        cookies: [HTTPCookie]
    ) async -> SumiLiveFolderProviderResponse {
        guard source.githubFilters.authorMe
            || source.githubFilters.assignedMe
            || (source.kind == .githubPullRequests && source.githubFilters.reviewRequested)
        else {
            return failure(.noGitHubFilters)
        }

        guard let baseURL = URL(string: source.urlString),
              baseURL.scheme?.lowercased() == "https",
              baseURL.host?.lowercased().hasSuffix("github.com") == true else {
            return failure(.invalidURL)
        }

        var dashboardMode = source.githubDashboardMode
        do {
            dashboardMode = try await detectDashboardMode(
                for: source,
                baseURL: baseURL,
                cookies: cookies
            )
            return try await fetchResults(
                for: source,
                baseURL: baseURL,
                cookies: cookies,
                dashboardMode: dashboardMode
            )
        } catch let providerFailure as ProviderFailure {
            return failure(
                providerFailure.kind,
                response: providerFailure.response,
                githubDashboardMode: providerFailure.dashboardMode
            )
        } catch SumiLiveFolderNetworkClient.FetchError.oversizedResponse {
            return failure(.oversizedResponse, githubDashboardMode: dashboardMode)
        } catch SumiLiveFolderNetworkClient.FetchError.unsupportedResponse {
            return failure(.unsupportedResponse, githubDashboardMode: dashboardMode)
        } catch {
            return failure(.network, githubDashboardMode: dashboardMode)
        }
    }

    private func detectDashboardMode(
        for source: SumiLiveFolderSource,
        baseURL: URL,
        cookies: [HTTPCookie]
    ) async throws -> SumiGitHubDashboardMode? {
        guard source.kind == .githubPullRequests,
              source.githubDashboardMode == nil else {
            return source.githubDashboardMode
        }
        let response = try await networkClient.fetch(
            url: baseURL,
            accept: "application/json,text/html",
            etag: nil,
            lastModified: nil,
            cookies: cookies
        )
        try validate(response, dashboardMode: nil)
        return Self.isJSONPayload(response.data) ? .json : .html
    }

    private func fetchResults(
        for source: SumiLiveFolderSource,
        baseURL: URL,
        cookies: [HTTPCookie],
        dashboardMode initialDashboardMode: SumiGitHubDashboardMode?
    ) async throws -> SumiLiveFolderProviderResponse {
        let queries = buildQueries(for: source, dashboardMode: initialDashboardMode)
        var dashboardMode = initialDashboardMode
        var accumulator = FetchAccumulator()

        for query in queries {
            let url = try searchURL(baseURL: baseURL, query: query, dashboardMode: dashboardMode)
            let response = try await networkClient.fetch(
                url: url,
                accept: "application/json,text/html;q=0.9,*/*;q=0.2",
                etag: source.etag,
                lastModified: source.lastModified,
                cookies: cookies
            )
            accumulator.captureValidators(from: response)
            if response.statusCode == 304 {
                return accumulator.notModified(dashboardMode: dashboardMode)
            }
            try validate(response, dashboardMode: dashboardMode)

            if source.kind == .githubPullRequests {
                let responseIsJSON = Self.isJSONPayload(response.data)
                if dashboardMode == .json, responseIsJSON == false {
                    throw ProviderFailure(
                        kind: .network,
                        response: response,
                        dashboardMode: .html
                    )
                }
                if responseIsJSON {
                    dashboardMode = .json
                }
            }

            accumulator.merge(
                parseGitHubResponse(
                    data: response.data,
                    source: source,
                    baseURL: baseURL
                )
            )
        }

        return accumulator.success(
            excluding: source.excludedRepositories,
            dashboardMode: dashboardMode
        )
    }

    private func searchURL(
        baseURL: URL,
        query: String,
        dashboardMode: SumiGitHubDashboardMode?
    ) throws -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        items.removeAll { $0.name == "q" }
        items.append(URLQueryItem(name: "q", value: query))
        components?.queryItems = items
        guard let url = components?.url else {
            throw ProviderFailure(kind: .invalidURL, dashboardMode: dashboardMode)
        }
        return url
    }

    private func validate(
        _ response: SumiLiveFolderHTTPResponse,
        dashboardMode: SumiGitHubDashboardMode?
    ) throws {
        if [401, 403, 404].contains(response.statusCode) {
            throw ProviderFailure(
                kind: .notAuthenticated,
                response: response,
                dashboardMode: dashboardMode
            )
        }
        if response.statusCode == 429 {
            throw ProviderFailure(
                kind: .rateLimited,
                response: response,
                dashboardMode: dashboardMode
            )
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ProviderFailure(
                kind: .network,
                response: response,
                dashboardMode: dashboardMode
            )
        }
    }

    private struct ProviderFailure: Error {
        let kind: SumiLiveFolderErrorKind
        let response: SumiLiveFolderHTTPResponse?
        let dashboardMode: SumiGitHubDashboardMode?

        init(
            kind: SumiLiveFolderErrorKind,
            response: SumiLiveFolderHTTPResponse? = nil,
            dashboardMode: SumiGitHubDashboardMode?
        ) {
            self.kind = kind
            self.response = response
            self.dashboardMode = dashboardMode
        }
    }

    private struct FetchAccumulator {
        private var itemsByID: [String: SumiLiveFolderItem]
        private var itemOrder: [String]
        private var activeRepositories: Set<String>
        private var latestETag: String?
        private var latestLastModified: String?

        init() {
            itemsByID = [:]
            itemOrder = []
            activeRepositories = []
            latestETag = nil
            latestLastModified = nil
        }

        mutating func captureValidators(from response: SumiLiveFolderHTTPResponse) {
            latestETag = response.etag ?? latestETag
            latestLastModified = response.lastModified ?? latestLastModified
        }

        mutating func merge(
            _ parsed: (items: [SumiLiveFolderItem], activeRepositories: Set<String>)
        ) {
            for item in parsed.items {
                if itemsByID[item.id] == nil {
                    itemOrder.append(item.id)
                }
                itemsByID[item.id] = item
            }
            activeRepositories.formUnion(parsed.activeRepositories)
        }

        func notModified(
            dashboardMode: SumiGitHubDashboardMode?
        ) -> SumiLiveFolderProviderResponse {
            SumiLiveFolderProviderResponse(
                outcome: .notModified,
                etag: latestETag,
                lastModified: latestLastModified,
                githubDashboardMode: dashboardMode
            )
        }

        func success(
            excluding excludedRepositories: Set<String>,
            dashboardMode: SumiGitHubDashboardMode?
        ) -> SumiLiveFolderProviderResponse {
            let items = itemOrder.compactMap { itemsByID[$0] }
                .filter { item in
                    guard let repo = item.stateBadge else { return true }
                    return !excludedRepositories.contains(repo)
                }
            return SumiLiveFolderProviderResponse(
                outcome: .success(
                    items: items,
                    title: nil,
                    activeRepositories: activeRepositories
                ),
                etag: latestETag,
                lastModified: latestLastModified,
                githubDashboardMode: dashboardMode
            )
        }
    }

    func buildQueries(
        for source: SumiLiveFolderSource,
        dashboardMode: SumiGitHubDashboardMode?
    ) -> [String] {
        var base = [
            source.kind == .githubPullRequests ? "is:pr" : "is:issue",
            "is:open",
            "sort:updated-desc",
        ]
        for repo in source.excludedRepositories.sorted() where !repo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            base.append("-repo:\(repo.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        var filters: [String] = []
        if source.githubFilters.authorMe {
            filters.append("author:@me")
        }
        if source.githubFilters.assignedMe {
            filters.append("assignee:@me")
        }
        if source.kind == .githubPullRequests && source.githubFilters.reviewRequested {
            filters.append("review-requested:@me")
        }

        guard filters.count > 1 else {
            return ["\(base.joined(separator: " ")) \(filters.first ?? "")"]
        }
        if source.kind == .githubPullRequests, dashboardMode == .html {
            return filters.map { "\(base.joined(separator: " ")) \($0)" }
        }
        return ["\(base.joined(separator: " ")) (\(filters.joined(separator: " OR ")))"]
    }

    private static func isJSONPayload(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    func parseGitHubResponse(
        data: Data,
        source: SumiLiveFolderSource,
        baseURL: URL
    ) -> (items: [SumiLiveFolderItem], activeRepositories: Set<String>) {
        if let items = parsePullRequestDashboardJSON(data: data, source: source), !items.isEmpty {
            return (items, Set(items.compactMap(\.stateBadge)))
        }

        guard let html = String(data: data, encoding: .utf8) else {
            return ([], [])
        }
        return parseGitHubHTML(html, source: source, baseURL: baseURL)
    }

    private func parsePullRequestDashboardJSON(
        data: Data,
        source: SumiLiveFolderSource
    ) -> [SumiLiveFolderItem]? {
        guard source.kind == .githubPullRequests else { return nil }
        let firstPayloadByte = data.first { byte in
            switch byte {
            case 0x09, 0x0A, 0x0D, 0x20:
                return false
            default:
                return true
            }
        }
        guard let firstPayloadByte else { return nil }
        guard firstPayloadByte == 0x7B || firstPayloadByte == 0x5B else { return nil }

        // Distinguish malformed JSON (unexpected, worth surfacing) from a valid
        // response that simply lacks the expected shape (can be an empty result).
        let root: [String: Any]
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            guard let object = jsonObject as? [String: Any] else {
                Self.log.error(
                    "GitHub PR dashboard payload is valid JSON but not an object; Live Folder will render empty."
                )
                return nil
            }
            root = object
        } catch {
            Self.log.error(
                "Failed to parse GitHub PR dashboard payload as JSON: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
        guard let payload = root["payload"] as? [String: Any],
              let route = payload["pullsDashboardSurfaceContentRoute"] as? [String: Any],
              let results = route["results"] as? [[String: Any]] else {
            return nil
        }

        let now = Date()
        return results.compactMap { pr in
            guard let repo = pr["repoNameWithOwner"] as? String,
                  let number = pr["number"],
                  let title = pr["title"] as? String,
                  let permalink = pr["permalink"] as? String else {
                return nil
            }
            let author = (pr["author"] as? [String: Any])?["displayLogin"] as? String
            let id = "\(repo)#\(number)"
            return SumiLiveFolderItem(
                id: id,
                sourceId: source.id,
                title: title,
                urlString: permalink,
                subtitle: author,
                publishedAt: nil,
                updatedAt: now,
                sortDate: now,
                stateBadge: repo,
                iconSystemName: "zen:logo-github",
                shortcutPinId: nil,
                firstSeenAt: now,
                lastSeenAt: now
            )
        }
    }

    func parseGitHubHTML(
        _ html: String,
        source: SumiLiveFolderSource,
        baseURL: URL
    ) -> (items: [SumiLiveFolderItem], activeRepositories: Set<String>) {
        if source.kind == .githubPullRequests {
            return parsePullRequestsHTML(html, source: source, baseURL: baseURL)
        }
        return parseIssuesHTML(html, source: source, baseURL: baseURL)
    }

    private func parsePullRequestsHTML(
        _ html: String,
        source: SumiLiveFolderSource,
        baseURL: URL
    ) -> (items: [SumiLiveFolderItem], activeRepositories: Set<String>) {
        let now = Date()
        var activeRepositories = Set<String>()
        var items: [SumiLiveFolderItem] = []
        let titleMatches = html.matches(
            #"(?s)<a[^>]+id=["']issue_[^"']+["'][^>]+href=["']([^"']+)["'][^>]*>(.*?)</a>"#
        )
        let authorMatches = html.matches(#"(?s)<span[^>]*class=["'][^"']*opened-by[^"']*["'][^>]*>(.*?)</span>"#)
        for (index, match) in titleMatches.enumerated() {
            guard match.count >= 3 else { continue }
            let href = match[1]
            let title = match[2].strippingHTML.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty,
                  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL else {
                continue
            }
            let repo = inferRepository(from: html, before: match[0]) ?? ""
            if !repo.isEmpty {
                activeRepositories.insert(repo)
            }
            let author = authorMatches.indices.contains(index)
                ? authorMatches[index].last?.strippingHTML.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil
            let number = href.split(separator: "/").last.map(String.init) ?? title
            items.append(
                SumiLiveFolderItem(
                    id: repo.isEmpty ? url.absoluteString : "\(repo)#\(number)",
                    sourceId: source.id,
                    title: title,
                    urlString: url.absoluteString,
                    subtitle: author,
                    publishedAt: nil,
                    updatedAt: now,
                    sortDate: now,
                    stateBadge: repo.isEmpty ? nil : repo,
                    iconSystemName: "zen:logo-github",
                    shortcutPinId: nil,
                    firstSeenAt: now,
                    lastSeenAt: now
                )
            )
        }
        return (items, activeRepositories)
    }

    private func parseIssuesHTML(
        _ html: String,
        source: SumiLiveFolderSource,
        baseURL: URL
    ) -> (items: [SumiLiveFolderItem], activeRepositories: Set<String>) {
        let now = Date()
        var activeRepositories = Set<String>()
        var items: [SumiLiveFolderItem] = []
        let repoMatches = html.matches(
            #"(?s)<div[^>]+class=["'][^"']*IssueItem-module__defaultRepoContainer[^"']*["'][^>]*>\s*<[^>]+>(.*?)</[^>]+>\s*<[^>]+>#?([0-9]+)</[^>]+>"#
        )
        let titleMatches = html.matches(
            #"(?s)<div[^>]+class=["'][^"']*Title-module__container[^"']*["'][^>]*>(.*?)</div>"#
        )
        let authorMatches = html.matches(
            #"(?s)<a[^>]+class=["'][^"']*IssueItem-module__authorCreatedLink[^"']*["'][^>]*>(.*?)</a>"#
        )
        let linkMatches = html.matches(
            #"(?s)<a[^>]+data-testid=["']issue-pr-title-link["'][^>]+href=["']([^"']+)["'][^>]*>"#
        )

        for index in repoMatches.indices {
            guard titleMatches.indices.contains(index),
                  linkMatches.indices.contains(index),
                  repoMatches[index].count >= 3,
                  titleMatches[index].count >= 2,
                  linkMatches[index].count >= 2 else {
                continue
            }
            let repo = repoMatches[index][1].strippingHTML.trimmingCharacters(in: .whitespacesAndNewlines)
            let number = repoMatches[index][2]
            let title = titleMatches[index][1].strippingHTML.trimmingCharacters(in: .whitespacesAndNewlines)
            let href = linkMatches[index][1]
            guard !repo.isEmpty,
                  !title.isEmpty,
                  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL else {
                continue
            }
            activeRepositories.insert(repo)
            let author = authorMatches.indices.contains(index)
                ? authorMatches[index][1].strippingHTML.trimmingCharacters(in: .whitespacesAndNewlines)
                : nil
            items.append(
                SumiLiveFolderItem(
                    id: "\(repo)#\(number)",
                    sourceId: source.id,
                    title: title,
                    urlString: url.absoluteString,
                    subtitle: author,
                    publishedAt: nil,
                    updatedAt: now,
                    sortDate: now,
                    stateBadge: repo,
                    iconSystemName: "zen:logo-github",
                    shortcutPinId: nil,
                    firstSeenAt: now,
                    lastSeenAt: now
                )
            )
        }

        return (items, activeRepositories)
    }

    private func inferRepository(from html: String, before marker: String) -> String? {
        guard let range = html.range(of: marker) else { return nil }
        let prefix = html[..<range.lowerBound].suffix(500)
        let candidates = String(prefix).matches(#"([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)"#)
        return candidates.last?.last
    }

    private func failure(
        _ kind: SumiLiveFolderErrorKind,
        response: SumiLiveFolderHTTPResponse? = nil,
        githubDashboardMode: SumiGitHubDashboardMode? = nil
    ) -> SumiLiveFolderProviderResponse {
        SumiLiveFolderProviderResponse(
            outcome: .failure(kind),
            etag: response?.etag,
            lastModified: response?.lastModified,
            githubDashboardMode: githubDashboardMode
        )
    }
}

private extension String {
    func matches(_ pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let nsRange = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: nsRange).map { result in
            (0..<result.numberOfRanges).compactMap { index in
                let range = result.range(at: index)
                guard range.location != NSNotFound,
                      let stringRange = Range(range, in: self) else {
                    return nil
                }
                return String(self[stringRange])
            }
        }
    }

    var strippingHTML: String {
        replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
