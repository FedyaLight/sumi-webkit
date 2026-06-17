import Foundation

struct SumiGitHubLiveFolderProvider: Sendable {
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

        do {
            let queries = buildQueries(for: source)
            var combinedItems: [String: SumiLiveFolderItem] = [:]
            var activeRepositories = Set<String>()
            var latestETag: String?
            var latestLastModified: String?

            for query in queries {
                var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
                var items = components?.queryItems ?? []
                items.removeAll { $0.name == "q" }
                items.append(URLQueryItem(name: "q", value: query))
                components?.queryItems = items
                guard let url = components?.url else {
                    return failure(.invalidURL)
                }

                let response = try await networkClient.fetch(
                    url: url,
                    accept: "application/json,text/html;q=0.9,*/*;q=0.2",
                    etag: source.etag,
                    lastModified: source.lastModified,
                    cookies: cookies
                )
                latestETag = response.etag ?? latestETag
                latestLastModified = response.lastModified ?? latestLastModified

                if response.statusCode == 304 {
                    return SumiLiveFolderProviderResponse(
                        outcome: .notModified,
                        etag: latestETag,
                        lastModified: latestLastModified
                    )
                }
                if response.statusCode == 401 || response.statusCode == 403 || response.statusCode == 404 {
                    return failure(.notAuthenticated, response: response)
                }
                if response.statusCode == 429 {
                    return failure(.rateLimited, retryAfter: response.retryAfter, response: response)
                }
                guard (200..<300).contains(response.statusCode) else {
                    return failure(.network, retryAfter: response.retryAfter, response: response)
                }

                let parsed = parseGitHubResponse(
                    data: response.data,
                    source: source,
                    baseURL: baseURL
                )
                for item in parsed.items {
                    combinedItems[item.id] = item
                }
                activeRepositories.formUnion(parsed.activeRepositories)
            }

            let filteredItems = combinedItems.values
                .filter { item in
                    guard let repo = item.stateBadge else { return true }
                    return !source.excludedRepositories.contains(repo)
                }
                .sorted { lhs, rhs in
                    lhs.sortKeyDate > rhs.sortKeyDate
                }
                .prefix(max(1, source.maxItems))

            return SumiLiveFolderProviderResponse(
                outcome: .success(
                    items: Array(filteredItems),
                    title: nil,
                    activeRepositories: activeRepositories
                ),
                etag: latestETag,
                lastModified: latestLastModified
            )
        } catch SumiLiveFolderNetworkClient.FetchError.oversizedResponse {
            return failure(.oversizedResponse)
        } catch {
            return failure(.network)
        }
    }

    private func buildQueries(for source: SumiLiveFolderSource) -> [String] {
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
        return ["\(base.joined(separator: " ")) (\(filters.joined(separator: " OR ")))"]
    }

    private func parseGitHubResponse(
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
        guard source.kind == .githubPullRequests,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["payload"] as? [String: Any],
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
                iconSystemName: "chevron.left.forwardslash.chevron.right",
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
        let now = Date()
        var activeRepositories = Set<String>()
        var items: [SumiLiveFolderItem] = []

        if source.kind == .githubPullRequests {
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
                        iconSystemName: "chevron.left.forwardslash.chevron.right",
                        firstSeenAt: now,
                        lastSeenAt: now
                    )
                )
            }
            return (items, activeRepositories)
        }

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
                    iconSystemName: "exclamationmark.circle",
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
