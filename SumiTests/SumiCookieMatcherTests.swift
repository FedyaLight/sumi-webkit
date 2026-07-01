@testable import Sumi
import XCTest

final class SumiCookieMatcherTests: XCTestCase {
    func testHostMatchingAllowsExactAndParentDomainSuffixesOnly() throws {
        let requestURL = try XCTUnwrap(URL(string: "https://static.example.com/favicon.ico"))
        let cookies = [
            Self.cookie(name: "parent", domain: ".example.com", path: "/"),
            Self.cookie(name: "exact", domain: "static.example.com", path: "/"),
            Self.cookie(name: "sibling", domain: "www.example.com", path: "/"),
            Self.cookie(name: "partial-suffix", domain: "ample.com", path: "/"),
        ]

        XCTAssertEqual(Self.matchedNames(cookies, matching: requestURL), ["parent", "exact"])

        let partialHostURL = try XCTUnwrap(URL(string: "https://badexample.com/favicon.ico"))
        XCTAssertTrue(SumiCookieMatcher.cookies([cookies[0]], matching: partialHostURL).isEmpty)
    }

    func testPathMatchingUsesBrowserCookiePathBoundaries() throws {
        let requestURL = try XCTUnwrap(URL(string: "https://example.com/account/settings"))
        let cookies = [
            Self.cookie(name: "root", domain: "example.com", path: "/"),
            Self.cookie(name: "directory", domain: "example.com", path: "/account"),
            Self.cookie(name: "directory-slash", domain: "example.com", path: "/account/"),
            Self.cookie(name: "sibling", domain: "example.com", path: "/accounts"),
            Self.cookie(name: "partial-prefix", domain: "example.com", path: "/accounting"),
        ]

        XCTAssertEqual(
            Self.matchedNames(cookies, matching: requestURL),
            ["root", "directory", "directory-slash"]
        )
    }

    func testSecureCookiesOnlyMatchHTTPSRequests() throws {
        let httpsURL = try XCTUnwrap(URL(string: "https://example.com/"))
        let httpURL = try XCTUnwrap(URL(string: "http://example.com/"))
        let cookies = [
            Self.cookie(name: "plain", domain: "example.com", path: "/"),
            Self.cookie(name: "secure", domain: "example.com", path: "/", isSecure: true),
        ]

        XCTAssertEqual(Self.matchedNames(cookies, matching: httpsURL), ["plain", "secure"])
        XCTAssertEqual(Self.matchedNames(cookies, matching: httpURL), ["plain"])
    }

    func testCookieMatchingNormalizesHostAndDomainEdges() throws {
        let requestURL = try XCTUnwrap(URL(string: "https://Example.COM./favicon.ico"))
        let cookies = [
            Self.cookie(name: "normalized", domain: ".example.com.", path: "/"),
        ]

        XCTAssertEqual(Self.matchedNames(cookies, matching: requestURL), ["normalized"])
        XCTAssertTrue(SumiCookieMatcher.cookies(cookies, matching: URL(fileURLWithPath: "/tmp/icon.png")).isEmpty)
    }

    func testSessionCookieAttachmentIsSchemefulSiteScoped() throws {
        let cookies = [
            Self.cookie(name: "same-site", domain: ".example.com", path: "/"),
        ]
        let sourceURL = try XCTUnwrap(URL(string: "https://www.example.com/page"))
        let sameSiteURL = try XCTUnwrap(URL(string: "https://cdn.example.com/favicon.ico"))
        let differentSchemeURL = try XCTUnwrap(URL(string: "http://cdn.example.com/favicon.ico"))
        let differentSiteURL = try XCTUnwrap(URL(string: "https://example.org/favicon.ico"))

        XCTAssertEqual(
            SumiCookieMatcher.cookies(cookies, matching: sameSiteURL, sourceDocumentURL: sourceURL).map(\.name),
            ["same-site"]
        )
        XCTAssertTrue(
            SumiCookieMatcher.cookies(cookies, matching: differentSchemeURL, sourceDocumentURL: sourceURL).isEmpty
        )
        XCTAssertTrue(
            SumiCookieMatcher.cookies(cookies, matching: differentSiteURL, sourceDocumentURL: sourceURL).isEmpty
        )
        XCTAssertTrue(
            SumiCookieMatcher.cookies(cookies, matching: sameSiteURL, sourceDocumentURL: nil).isEmpty
        )
    }

    private static func cookie(
        name: String,
        domain: String,
        path: String,
        isSecure: Bool = false
    ) -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .domain: domain,
            .path: path,
            .name: name,
            .value: "1",
        ]
        if isSecure {
            properties[.secure] = "TRUE"
        }
        return HTTPCookie(properties: properties)!
    }

    private static func matchedNames(_ cookies: [HTTPCookie], matching url: URL) -> [String] {
        SumiCookieMatcher.cookies(cookies, matching: url).map(\.name)
    }
}
