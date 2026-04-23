import XCTest

@testable import Sumi

final class SumiBookmarkURLVariantsTests: XCTestCase {
    func testHTTPURLIncludesSchemeAndTrailingSlashVariants() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com"))

        XCTAssertEqual(
            url.sumiBookmarkButtonURLVariants().map(\.absoluteString),
            [
                "https://example.com",
                "http://example.com",
                "http://example.com/",
                "https://example.com/",
            ]
        )
    }

    func testQueryURLDoesNotAddTrailingSlashVariants() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/path?query=1"))

        XCTAssertEqual(
            url.sumiBookmarkButtonURLVariants().map(\.absoluteString),
            [
                "https://example.com/path?query=1",
                "http://example.com/path?query=1",
            ]
        )
    }

    func testNonHTTPURLOnlyReturnsItself() throws {
        let url = URL(fileURLWithPath: "/tmp/example.html")

        XCTAssertEqual(url.sumiBookmarkButtonURLVariants(), [url])
    }
}
