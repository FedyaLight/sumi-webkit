import AppKit
import QuartzCore
import XCTest

@testable import Sumi

@MainActor
final class CollapsedSidebarShadowChromeTests: XCTestCase {
    func testConfigureUsesNonClippingLayerShadow() throws {
        let view = makeCollapsedRootView()
        let layer = try XCTUnwrap(view.layer)

        XCTAssertTrue(view.wantsLayer)
        XCTAssertFalse(layer.masksToBounds)
        XCTAssertNotNil(layer.shadowColor)
        XCTAssertEqual(layer.shadowRadius, SidebarHoverOverlayMetrics.shadowRadius)
        XCTAssertEqual(layer.shadowOffset, SidebarHoverOverlayMetrics.shadowOffset)
        XCTAssertEqual(layer.shadowOpacity, 0)
    }

    func testShadowVisibilityControlsLayerOpacity() throws {
        let view = makeCollapsedRootView()
        let layer = try XCTUnwrap(view.layer)

        view.setCollapsedShadowVisible(false, animationDuration: 0)

        XCTAssertFalse(view.isCollapsedShadowVisible)
        XCTAssertEqual(layer.shadowOpacity, 0)

        view.setCollapsedShadowVisible(true, animationDuration: 0)

        XCTAssertTrue(view.isCollapsedShadowVisible)
        XCTAssertEqual(layer.shadowOpacity, SidebarHoverOverlayMetrics.shadowOpacity)
    }

    func testAnimatedShadowVisibilitySetsModelOpacityAndAddsOpacityAnimation() throws {
        let view = makeCollapsedRootView()
        let layer = try XCTUnwrap(view.layer)

        view.setCollapsedShadowVisible(true, animationDuration: 0.25)

        XCTAssertEqual(layer.shadowOpacity, SidebarHoverOverlayMetrics.shadowOpacity)
        let animation = try XCTUnwrap(
            layer.animation(forKey: CollapsedSidebarShadowChrome.shadowOpacityAnimationKey)
                as? CABasicAnimation
        )
        XCTAssertEqual(animation.keyPath, "shadowOpacity")
        XCTAssertEqual(animation.duration, 0.25)
    }

    func testShadowPathTracksCollapsedRootBounds() throws {
        let view = makeCollapsedRootView(
            frame: NSRect(x: 0, y: 0, width: 280, height: 640)
        )
        let layer = try XCTUnwrap(view.layer)

        XCTAssertEqual(layer.shadowPath?.boundingBox, view.bounds)

        view.frame = NSRect(x: 0, y: 0, width: 320, height: 720)
        view.layout()

        XCTAssertEqual(layer.shadowPath?.boundingBox, view.bounds)
    }

    func testNonClippingShadowDoesNotExpandHitTesting() throws {
        let view = makeCollapsedRootView()
        let layer = try XCTUnwrap(view.layer)
        view.isOverlayHitTestingEnabled = true
        view.setCollapsedShadowVisible(true, animationDuration: 0)

        XCTAssertFalse(layer.masksToBounds)
        XCTAssertNil(view.hitTest(NSPoint(
            x: view.bounds.maxX + SidebarHoverOverlayMetrics.shadowRadius,
            y: view.bounds.midY
        )))
    }

    private func makeCollapsedRootView(
        frame: NSRect = NSRect(x: 0, y: 0, width: 260, height: 600)
    ) -> CollapsedSidebarOverlayRootView {
        let view = CollapsedSidebarOverlayRootView(frame: frame)
        CollapsedSidebarShadowChrome.configure(view)
        CollapsedSidebarShadowChrome.updatePath(for: view)
        return view
    }
}
