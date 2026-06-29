import XCTest

@testable import Sumi

@MainActor
final class URLBarHubPageActionOwnerTests: XCTestCase {
    func testScreenshotFilenameSanitizesTitleAndScale() {
        let tab = Tab(url: URL(string: "https://example.com")!, name: "Example: One/Two")

        XCTAssertEqual(
            URLBarHubSnapshotActions.suggestedFilename(for: tab, quality: .fourX),
            "Example- One-Two@4x.png"
        )
    }
}
