import AppKit
@testable import Sumi
import XCTest

@available(macOS 15.5, *)
@MainActor
final class ExtensionOptionsWindowOwnerTests: XCTestCase {
    func testTrackingWindowExposesWindowAndExtensionIDs() {
        let owner = ExtensionOptionsWindowOwner()
        let window = NSWindow()

        owner.trackPresentedWindow(window, delegate: nil, for: "extension-a")

        XCTAssertIdentical(owner.windows["extension-a"], window)
        XCTAssertEqual(owner.extensionIDs, ["extension-a"])
    }

    func testCleanupWindowRemovesTrackedWindow() {
        let owner = ExtensionOptionsWindowOwner()
        let window = NSWindow()
        owner.trackPresentedWindow(window, delegate: nil, for: "extension-a")

        owner.cleanupWindow(for: "extension-a", shouldOrderOut: true)

        XCTAssertTrue(owner.windows.isEmpty)
        XCTAssertTrue(owner.extensionIDs.isEmpty)
    }

    func testCloseAllWindowsRemovesAllTrackedWindows() {
        let owner = ExtensionOptionsWindowOwner()
        owner.trackPresentedWindow(NSWindow(), delegate: nil, for: "extension-a")
        owner.trackPresentedWindow(NSWindow(), delegate: nil, for: "extension-b")

        owner.closeAllWindows()

        XCTAssertTrue(owner.windows.isEmpty)
        XCTAssertTrue(owner.extensionIDs.isEmpty)
    }
}
