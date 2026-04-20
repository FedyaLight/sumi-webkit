import AppKit
import XCTest

@testable import Sumi

@MainActor
final class MiniWindowTrafficLightsTests: XCTestCase {
    func testMiniWindowTrafficLightsContainerUsesFallbackSizeBeforeAttachingToWindow() {
        let host = MiniWindowTrafficLightsContainerView(frame: .zero)

        XCTAssertEqual(host.intrinsicContentSize.width, 60)
        XCTAssertEqual(host.intrinsicContentSize.height, 18)
    }

    func testMiniWindowTrafficLightsContainerClaimsButtonsAndUsesMiniWindowSpacing() {
        let window = WindowChromeTestSupport.makePlainWindow()
        let host = MiniWindowTrafficLightsContainerView(
            frame: NSRect(x: 0, y: 0, width: 60, height: 20)
        )

        window.contentView?.addSubview(host)
        host.windowReference = window
        host.layoutSubtreeIfNeeded()

        let cachedFrames = WindowChromeTestSupport.standardButtonTypes.reduce(into: [NSWindow.ButtonType: NSRect]()) { partialResult, type in
            partialResult[type] = window.cachedNativeWindowButtonFrame(for: type)
        }

        var expectedMinX: CGFloat = 0
        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type),
                  let cachedFrame = cachedFrames[type]
            else {
                XCTFail("Expected standard window button for \(type).")
                return
            }

            XCTAssertTrue(button.superview === host)
            XCTAssertEqual(button.frame.minX, expectedMinX)
            XCTAssertEqual(button.frame.minY, floor((host.bounds.height - cachedFrame.height) / 2))
            XCTAssertEqual(button.frame.size, cachedFrame.size)
            expectedMinX += cachedFrame.width + 8
        }
    }

    func testMiniWindowTrafficLightsContainerPrepareForRemovalRestoresButtonsToTitlebar() {
        let window = WindowChromeTestSupport.makePlainWindow()
        let host = MiniWindowTrafficLightsContainerView(
            frame: NSRect(x: 0, y: 0, width: 60, height: 20)
        )

        window.contentView?.addSubview(host)
        host.windowReference = window
        host.layoutSubtreeIfNeeded()

        let nativeTitlebarView = window.titlebarView
        let cachedFrames = WindowChromeTestSupport.standardButtonTypes.reduce(into: [NSWindow.ButtonType: NSRect]()) { partialResult, type in
            partialResult[type] = window.cachedNativeWindowButtonFrame(for: type)
        }

        host.prepareForRemoval()

        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type) else {
                XCTFail("Expected standard window button for \(type).")
                return
            }

            XCTAssertTrue(button.superview === nativeTitlebarView)
            XCTAssertEqual(button.frame, cachedFrames[type])
        }
    }
}
