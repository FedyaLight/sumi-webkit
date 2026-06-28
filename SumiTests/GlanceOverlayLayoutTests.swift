import AppKit
import XCTest

@testable import Sumi

final class GlanceOverlayLayoutTests: XCTestCase {
    func testTargetContentFrameCentersPreviewInsideBrowserWebArea() {
        let layout = GlanceOverlayLayout()
        let configuration = makeConfiguration()

        let frame = layout.targetContentFrame(
            in: CGRect(x: 0, y: 0, width: 1000, height: 700),
            configuration: configuration
        )

        XCTAssertEqual(frame, CGRect(x: 106, y: 12, width: 787, height: 676))
    }

    func testTargetContentFrameUsesResolvedBrowserChromeInset() {
        let layout = GlanceOverlayLayout()
        let configuration = makeConfiguration(browserContentInset: 20)

        let frame = layout.targetContentFrame(
            in: CGRect(x: 0, y: 0, width: 1000, height: 700),
            configuration: configuration
        )

        XCTAssertEqual(frame, CGRect(x: 116, y: 12, width: 768, height: 676))
    }

    func testTargetContentFrameReservesDockedSidebarBeforeCenteringPreview() {
        let layout = GlanceOverlayLayout()
        let configuration = makeConfiguration(
            isSidebarVisible: true,
            sidebarWidth: 220,
            sidebarPosition: .left
        )

        let frame = layout.targetContentFrame(
            in: CGRect(x: 0, y: 0, width: 1000, height: 700),
            configuration: configuration
        )

        XCTAssertEqual(frame, CGRect(x: 304, y: 12, width: 611, height: 676))
    }

    func testActionChromeFramePreservesExistingLeftSidebarPlacement() {
        let layout = GlanceOverlayLayout()
        let frame = layout.actionChromeFrame(
            for: CGRect(x: 106, y: 12, width: 787, height: 676),
            in: CGRect(x: 0, y: 0, width: 1000, height: 700),
            buttonCount: 3,
            sidebarPosition: .left
        )

        XCTAssertEqual(frame, CGRect(x: 905, y: 553, width: 44, height: 120))
    }

    func testStartContentFrameUsesOwnerProvidedRootGeometry() {
        let layout = GlanceOverlayLayout()

        let frame = layout.startContentFrame(
            originFrameInRootBounds: CGRect(x: 40, y: 50, width: 120, height: 80),
            rootBounds: CGRect(x: 0, y: 0, width: 500, height: 400),
            targetFrame: CGRect(x: 100, y: 100, width: 200, height: 160)
        )

        XCTAssertEqual(frame, CGRect(x: 40, y: 50, width: 120, height: 80))
    }

    func testStartContentFrameClampsInvalidOriginUsingOwnerProvidedBounds() {
        let layout = GlanceOverlayLayout()

        let frame = layout.startContentFrame(
            originFrameInRootBounds: CGRect(x: 800, y: 700, width: 0, height: 0),
            rootBounds: CGRect(x: 0, y: 0, width: 500, height: 400),
            targetFrame: CGRect(x: 100, y: 100, width: 200, height: 160)
        )

        XCTAssertEqual(frame, CGRect(x: 456, y: 356, width: 44, height: 44))
    }

    func testSwiftUIContentFrameUsesOwnerProvidedRootOrientation() {
        let layout = GlanceOverlayLayout()
        let frame = CGRect(x: 20, y: 50, width: 120, height: 80)

        XCTAssertEqual(
            layout.swiftUIContentFrame(
                frame,
                rootBoundsHeight: 400,
                isRootViewFlipped: true
            ),
            frame
        )
        XCTAssertEqual(
            layout.swiftUIContentFrame(
                frame,
                rootBoundsHeight: 400,
                isRootViewFlipped: false
            ),
            CGRect(x: 20, y: 270, width: 120, height: 80)
        )
    }

    func testCursorRegionLayoutSubtractsWebContentChromeAndSidebarExclusions() {
        let rects = GlanceOverlayCursorRegionLayout.cursorRects(
            in: CGRect(x: 0, y: 0, width: 100, height: 100),
            excluding: [
                CGRect(x: 20, y: 20, width: 60, height: 60),
                CGRect(x: 80, y: 0, width: 20, height: 100),
            ]
        )

        XCTAssertEqual(
            Set(rects),
            Set([
                CGRect(x: 0, y: 0, width: 80, height: 20),
                CGRect(x: 0, y: 80, width: 80, height: 20),
                CGRect(x: 0, y: 20, width: 20, height: 60),
            ])
        )
    }

    private func makeConfiguration(
        isSidebarVisible: Bool = false,
        sidebarWidth: CGFloat = 0,
        sidebarPosition: SidebarPosition = .left,
        browserContentInset: CGFloat = 8
    ) -> GlanceOverlayConfiguration {
        GlanceOverlayConfiguration(
            isVisible: true,
            isSidebarVisible: isSidebarVisible,
            sidebarWidth: sidebarWidth,
            sidebarPosition: sidebarPosition,
            cornerRadius: 14,
            browserContentCornerRadius: 12,
            browserContentInset: browserContentInset,
            accentColor: .controlAccentColor,
            surfaceColor: .windowBackgroundColor,
            reduceMotion: false
        )
    }
}
