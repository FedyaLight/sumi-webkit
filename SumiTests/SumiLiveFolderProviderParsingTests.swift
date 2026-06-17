import XCTest
@testable import Sumi

final class SumiLiveFolderProviderParsingTests: XCTestCase {
    func testRSSParserExtractsFeedTitleAndDatedHTTPItems() throws {
        let sourceId = UUID()
        let xml = """
        <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
          <channel>
            <title>Example Feed</title>
            <item>
              <title>First Post</title>
              <link>https://example.com/posts/1</link>
              <guid>post-1</guid>
              <pubDate>Wed, 17 Jun 2026 08:00:00 GMT</pubDate>
              <dc:creator>Author A</dc:creator>
            </item>
          </channel>
        </rss>
        """

        let parsedFeed = SumiRSSFeedParser(data: Data(xml.utf8), sourceId: sourceId).parse()
        XCTAssertNotNil(parsedFeed)
        guard let feed = parsedFeed else { return }

        XCTAssertFalse(feed.items.isEmpty)
        guard let item = feed.items.first else { return }

        XCTAssertEqual(feed.title, "Example Feed")
        XCTAssertEqual(item.id, "post-1")
        XCTAssertEqual(item.sourceId, sourceId)
        XCTAssertEqual(item.title, "First Post")
        XCTAssertEqual(item.urlString, "https://example.com/posts/1")
        XCTAssertEqual(item.subtitle, "Author A")
        XCTAssertNotNil(item.publishedAt)
    }

    func testAtomParserUsesAlternateLinkHref() throws {
        let sourceId = UUID()
        let xml = """
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Atom Feed</title>
          <entry>
            <title>Atom Entry</title>
            <id>tag:example.com,2026:entry</id>
            <updated>2026-06-17T08:00:00Z</updated>
            <link rel="alternate" href="https://example.com/atom-entry" />
          </entry>
        </feed>
        """

        let parsedFeed = SumiRSSFeedParser(data: Data(xml.utf8), sourceId: sourceId).parse()
        XCTAssertNotNil(parsedFeed)
        guard let feed = parsedFeed else { return }

        XCTAssertFalse(feed.items.isEmpty)
        guard let item = feed.items.first else { return }

        XCTAssertEqual(feed.title, "Atom Feed")
        XCTAssertEqual(item.id, "tag:example.com,2026:entry")
        XCTAssertEqual(item.urlString, "https://example.com/atom-entry")
        XCTAssertNotNil(item.updatedAt)
    }

    func testGitHubIssuesHTMLParserMatchesZenIssueRows() throws {
        let source = SumiLiveFolderSource(
            folderId: UUID(),
            spaceId: UUID(),
            profileId: nil,
            kind: .githubIssues
        )
        let html = """
        <html>
          <body>
            <div>
              <div class="IssueItem-module__defaultRepoContainer"><span>mozilla/zen</span><span>#101</span></div>
              <a class="IssueItem-module__authorCreatedLink">UserA</a>
              <div class="Title-module__container">Fix the login bug</div>
              <a data-testid="issue-pr-title-link" href="/issues/101"></a>
            </div>
            <div>
              <div class="IssueItem-module__defaultRepoContainer"><span>mozilla/zen</span><span>#102</span></div>
              <a class="IssueItem-module__authorCreatedLink">UserB</a>
              <div class="Title-module__container">Add dark mode</div>
              <a data-testid="issue-pr-title-link" href="/pull/102"></a>
            </div>
          </body>
        </html>
        """

        let parsed = SumiGitHubLiveFolderProvider(networkClient: SumiLiveFolderNetworkClient())
            .parseGitHubHTML(
                html,
                source: source,
                baseURL: try XCTUnwrap(URL(string: "https://github.com/issues/assigned"))
            )

        XCTAssertEqual(parsed.activeRepositories, ["mozilla/zen"])
        XCTAssertEqual(parsed.items.map(\.id), ["mozilla/zen#101", "mozilla/zen#102"])
        XCTAssertEqual(parsed.items.map(\.title), ["Fix the login bug", "Add dark mode"])
        XCTAssertEqual(parsed.items.map(\.subtitle), ["UserA", "UserB"])
        XCTAssertEqual(parsed.items.map(\.urlString), ["https://github.com/issues/101", "https://github.com/pull/102"])
    }
}
