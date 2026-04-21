import XCTest
@testable import Sumi

@MainActor
final class TabTitleDisplayPolicyTests: XCTestCase {
    func testManualTitleUpdateTrimsWhitespace() {
        let tab = Tab(
            url: URL(string: "https://example.com/watch?v=1")!,
            name: "Stable Title",
            spaceId: nil,
            index: 0
        )

        XCTAssertTrue(tab.acceptResolvedDisplayTitle("  Updated Title  "))
        XCTAssertEqual(tab.name, "Updated Title")
    }

    func testManualTitleUpdateRejectsWhitespaceOnlyTitle() {
        let tab = Tab(
            url: URL(string: "https://example.com/watch?v=1")!,
            name: "Stable Title",
            spaceId: nil,
            index: 0
        )

        XCTAssertFalse(tab.acceptResolvedDisplayTitle("   "))
        XCTAssertEqual(tab.name, "Stable Title")
    }

    func testManualTitleUpdateDoesNotRewriteSameTitle() {
        let tab = Tab(
            url: URL(string: "https://example.com/watch?v=1")!,
            name: "Stable Title",
            spaceId: nil,
            index: 0
        )

        XCTAssertFalse(tab.acceptResolvedDisplayTitle("Stable Title"))
        XCTAssertEqual(tab.name, "Stable Title")
    }
}
