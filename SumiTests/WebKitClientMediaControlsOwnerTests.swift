import AppKit
@testable import Sumi
import XCTest

@MainActor
final class WebKitClientMediaControlsOwnerTests: XCTestCase {
    func testCachesBuiltTouchBarUntilControlsViewChanges() {
        let firstTouchBar = NSTouchBar()
        let secondTouchBar = NSTouchBar()
        var builtViews: [NSView] = []
        var nextTouchBar = firstTouchBar
        let owner = WebKitClientMediaControlsOwner { controlsView in
            builtViews.append(controlsView)
            return WebKitClientMediaControlsOwner.ProviderMediaControls(
                provider: NSObject(),
                touchBar: nextTouchBar
            )
        }
        let firstControlsView = NSView()
        let secondControlsView = NSView()

        XCTAssertIdentical(owner.addMediaPlaybackControlsView(firstControlsView), firstTouchBar)
        XCTAssertIdentical(owner.makeTouchBar(), firstTouchBar)

        nextTouchBar = secondTouchBar
        XCTAssertIdentical(owner.addMediaPlaybackControlsView(secondControlsView), secondTouchBar)
        XCTAssertIdentical(owner.makeTouchBar(), secondTouchBar)
        XCTAssertEqual(builtViews, [firstControlsView, secondControlsView])
    }

    func testRemoveClearsHostedControlsState() {
        let touchBar = NSTouchBar()
        var buildCount = 0
        let owner = WebKitClientMediaControlsOwner { _ in
            buildCount += 1
            return WebKitClientMediaControlsOwner.ProviderMediaControls(
                provider: NSObject(),
                touchBar: touchBar
            )
        }

        XCTAssertIdentical(owner.addMediaPlaybackControlsView(NSView()), touchBar)
        owner.removeMediaPlaybackControlsView()

        XCTAssertNil(owner.makeTouchBar())
        XCTAssertEqual(buildCount, 1)
    }
}
