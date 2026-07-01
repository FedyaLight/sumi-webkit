import XCTest

@testable import Sumi

final class SumiSimpleCommonHelpersTests: XCTestCase {
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
}
