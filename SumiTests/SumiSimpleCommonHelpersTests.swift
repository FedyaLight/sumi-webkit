import XCTest

@testable import Sumi

final class SumiSimpleCommonHelpersTests: XCTestCase {
    func testSumiRootPreservesSchemeAndHostWhileDroppingPathCredentialsQueryAndFragment() throws {
        let url = try XCTUnwrap(URL(string: "http://user:pass@example.com:8080/path/to/page?q=1#section"))

        XCTAssertEqual(url.sumiRoot?.absoluteString, "http://example.com:8080/")
    }

    func testSumiRootReturnsRelativeRootForHostlessURLs() throws {
        let url = try XCTUnwrap(URL(string: "about:blank"))

        XCTAssertEqual(url.sumiRoot?.absoluteString, "about:/")
    }

    func testSumiToHttpsOnlyUpgradesLowercaseHTTP() throws {
        let httpURL = try XCTUnwrap(URL(string: "http://example.com/path?q=1#frag"))
        let httpsURL = try XCTUnwrap(URL(string: "https://example.com/path"))
        let mailtoURL = try XCTUnwrap(URL(string: "mailto:user@example.com"))

        XCTAssertEqual(httpURL.sumiToHttps()?.absoluteString, "https://example.com/path?q=1#frag")
        XCTAssertEqual(httpsURL.sumiToHttps(), httpsURL)
        XCTAssertEqual(mailtoURL.sumiToHttps(), mailtoURL)
    }

    func testSumiAppendingMatchesPathComponentBehavior() throws {
        let root = try XCTUnwrap(URL(string: "https://example.com/"))

        XCTAssertEqual(root.sumiAppending("favicon.ico"), root.appendingPathComponent("favicon.ico"))
        XCTAssertEqual(root.sumiAppending("icons/favicon.ico").absoluteString, "https://example.com/icons/favicon.ico")
    }

    func testSumiNavigationalSchemePreservesRawSchemeCase() throws {
        let url = try XCTUnwrap(URL(string: "HTTP://example.com"))

        XCTAssertEqual(url.sumiNavigationalScheme?.rawValue, "HTTP")
        XCTAssertNotEqual(url.sumiNavigationalScheme, .http)
    }

    func testSumiIsEmptyUsesAbsoluteString() {
        let emptyURL = (NSURL(string: "") ?? NSURL()) as URL

        XCTAssertTrue(emptyURL.sumiIsEmpty)
        XCTAssertFalse(URL(string: "about:blank")!.sumiIsEmpty)
    }

    func testSumiDecodableHelperDecodesValidJSONObjectAndReturnsNilForInvalidInputs() {
        struct Payload: Decodable, Equatable {
            let documentUrl: URL
            let favicons: [Favicon]

            struct Favicon: Decodable, Equatable {
                let href: URL
                let rel: String
                let type: String?
            }
        }

        let object: [String: Any] = [
            "documentUrl": "https://example.com/article",
            "favicons": [
                [
                    "href": "https://example.com/favicon.ico",
                    "rel": "icon",
                    "type": "image/x-icon",
                ],
            ],
        ]

        let payload: Payload? = SumiDecodableHelper.decode(from: object)
        XCTAssertEqual(payload?.documentUrl.absoluteString, "https://example.com/article")
        XCTAssertEqual(payload?.favicons.first?.href.absoluteString, "https://example.com/favicon.ico")
        XCTAssertEqual(payload?.favicons.first?.rel, "icon")
        XCTAssertEqual(payload?.favicons.first?.type, "image/x-icon")

        XCTAssertNil(SumiDecodableHelper.decode(from: ["documentUrl": Date()]) as Payload?)
        XCTAssertNil(SumiDecodableHelper.decode(from: ["favicons": []]) as Payload?)
    }

    func testSumiMonthAgoMatchesCalendarCurrentMonthOffset() {
        let before = Date()
        let value = Date.sumiMonthAgo
        let after = Date()

        let expectedLowerBound = Calendar.current.date(byAdding: .month, value: -1, to: before) ?? before
        let expectedUpperBound = Calendar.current.date(byAdding: .month, value: -1, to: after) ?? after
        XCTAssertGreaterThanOrEqual(value, expectedLowerBound)
        XCTAssertLessThanOrEqual(value, expectedUpperBound)
    }
}
