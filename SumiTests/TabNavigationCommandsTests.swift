import Foundation
import XCTest

@testable import Sumi

final class TabNavigationCommandsTests: XCTestCase {
    func testNavigationCommandURLRequestUsesReturnCacheDataElseLoadForRegularURL() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/path"))

        let request = Tab.navigationCommandURLRequest(for: url)

        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.cachePolicy, .returnCacheDataElseLoad)
        XCTAssertEqual(request.timeoutInterval, 30.0)
    }

    func testNavigationCommandURLRequestBypassesLocalCacheForExtensionSchemes() throws {
        let urls = [
            try XCTUnwrap(URL(string: "webkit-extension://extension-id/options.html")),
            try XCTUnwrap(URL(string: "safari-web-extension://extension-id/options.html")),
            try XCTUnwrap(URL(string: "WebKit-Extension://extension-id/options.html"))
        ]

        for url in urls {
            let request = Tab.navigationCommandURLRequest(for: url)

            XCTAssertEqual(request.url, url)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(request.timeoutInterval, 30.0)
        }
    }
}
