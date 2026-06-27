import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionRequestedTabLifecycleOwnerTests: XCTestCase {
    func testRecentOpenRequestTrackerConsumesOnlyRecordedWebURLsOnce() {
        let owner = ExtensionRequestedTabLifecycleOwner()
        let url = URL(string: "https://example.com/login")!

        XCTAssertFalse(owner.consumeRecentlyOpenedTabRequest(for: url))

        owner.recordRecentlyOpenedTabRequest(for: url)

        XCTAssertTrue(owner.consumeRecentlyOpenedTabRequest(for: url))
        XCTAssertFalse(owner.consumeRecentlyOpenedTabRequest(for: url))
    }

    func testRecentOpenRequestTrackerIgnoresNonWebURLs() {
        let owner = ExtensionRequestedTabLifecycleOwner()
        let extensionURL = URL(string: "safari-web-extension://ext-id/popup.html")!

        owner.recordRecentlyOpenedTabRequest(for: extensionURL)

        XCTAssertFalse(owner.consumeRecentlyOpenedTabRequest(for: extensionURL))
    }
}
