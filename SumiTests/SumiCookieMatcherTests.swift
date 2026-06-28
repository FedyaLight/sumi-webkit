@testable import Sumi
import XCTest

final class SumiCookieMatcherTests: XCTestCase {
    func testCookieMatchingAppliesDomainPathAndSecureRules() throws {
        let requestURL = try XCTUnwrap(URL(string: "https://sub.example.com/account/settings"))
        let cookies = [
            Self.cookie(name: "root", domain: ".example.com", path: "/"),
            Self.cookie(name: "subpath", domain: "sub.example.com", path: "/account"),
            Self.cookie(name: "path-boundary", domain: ".example.com", path: "/accounts"),
            Self.cookie(name: "other-domain", domain: ".example.org", path: "/"),
            Self.cookie(name: "secure", domain: ".example.com", path: "/", isSecure: true),
        ]

        let matchedNames = Set(SumiCookieMatcher.cookies(cookies, matching: requestURL).map { $0.name })

        XCTAssertEqual(matchedNames, ["root", "subpath", "secure"])
    }

    func testSecureCookiesDoNotMatchPlainHTTPRequests() throws {
        let requestURL = try XCTUnwrap(URL(string: "http://example.com/"))
        let cookies = [
            Self.cookie(name: "plain", domain: "example.com", path: "/"),
            Self.cookie(name: "secure", domain: "example.com", path: "/", isSecure: true),
        ]

        let matchedNames = SumiCookieMatcher.cookies(cookies, matching: requestURL).map { $0.name }

        XCTAssertEqual(matchedNames, ["plain"])
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
            SumiCookieMatcher.cookies(cookies, matching: sameSiteURL, sourceDocumentURL: sourceURL).map { $0.name },
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
}
