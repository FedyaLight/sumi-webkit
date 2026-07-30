import Foundation

extension SumiLiveFolderManager {
    func setRSSFeedURL(folderId: UUID, urlString: String) {
        guard let url = URL(string: urlString),
              ["http", "https"].contains(url.scheme?.lowercased()),
              var source = source(for: folderId),
              source.kind == .rss else {
            return
        }
        source.urlString = url.absoluteString
        source.etag = nil
        source.lastModified = nil
        source.nextRefreshAfter = nil
        replaceSourceAndRefresh(source)
    }

    func setRSSItemLimit(folderId: UUID, maxItems: Int) {
        guard [5, 10, 25, 50].contains(maxItems),
              var source = source(for: folderId),
              source.kind == .rss else {
            return
        }
        source.maxItems = maxItems
        source.nextRefreshAfter = nil
        replaceSourceAndRefresh(source)
    }

    func setRSSTimeRange(folderId: UUID, seconds: TimeInterval) {
        guard seconds >= 0,
              var source = source(for: folderId),
              source.kind == .rss else {
            return
        }
        source.timeRangeSeconds = seconds == 0 ? nil : seconds
        source.nextRefreshAfter = nil
        replaceSourceAndRefresh(source)
    }

    func setGitHubFilters(folderId: UUID, filters: SumiGitHubLiveFolderFilters) {
        guard var source = source(for: folderId),
              source.kind == .githubPullRequests || source.kind == .githubIssues else {
            return
        }
        source.githubFilters = filters
        source.nextRefreshAfter = nil
        replaceSourceAndRefresh(source)
    }

    func setGitHubRepositoryIncluded(
        folderId: UUID,
        repository: String,
        isIncluded: Bool
    ) {
        guard var source = source(for: folderId),
              source.kind == .githubPullRequests || source.kind == .githubIssues else {
            return
        }
        if isIncluded {
            source.excludedRepositories.remove(repository)
        } else {
            source.excludedRepositories.insert(repository)
        }
        source.nextRefreshAfter = nil
        replaceSourceAndRefresh(source)
    }
}
