import AppKit
@testable import Sumi
import XCTest

@MainActor
final class CollapsedSidebarInteractionParityTests: XCTestCase {
    func testCollapsedOverlayOwnsArrowCursorWithoutACompetingTrackingArea() {
        let root = CollapsedSidebarOverlayRootView(
            frame: NSRect(x: 0, y: 0, width: 280, height: 600)
        )

        root.isOverlayHitTestingEnabled = true

        XCTAssertTrue(root.ownsArrowCursorRegion)
        XCTAssertTrue(root.trackingAreas.isEmpty)

        root.isOverlayHitTestingEnabled = false
        XCTAssertFalse(root.ownsArrowCursorRegion)
        XCTAssertTrue(root.trackingAreas.isEmpty)
    }

    func testVisibleCollapsedSidebarPresentsMountedMiniPlayerCard() {
        XCTAssertTrue(
            SidebarMediaCardPresentationPolicy.shouldPresentCard(
                hasCardState: true,
                presentationContext: .collapsedVisible(sidebarWidth: 280)
            )
        )
    }

    func testHiddenCollapsedSidebarDoesNotPresentMountedMiniPlayerCard() {
        XCTAssertFalse(
            SidebarMediaCardPresentationPolicy.shouldPresentCard(
                hasCardState: true,
                presentationContext: .collapsedHidden(sidebarWidth: 280)
            )
        )
    }

    func testDockedSidebarStillPresentsMountedMiniPlayerCard() {
        XCTAssertTrue(
            SidebarMediaCardPresentationPolicy.shouldPresentCard(
                hasCardState: true,
                presentationContext: .docked(sidebarWidth: 280)
            )
        )
    }

    func testCollapsedOverlayPassesBareHostingHitsToSwiftUI() {
        let root = CollapsedSidebarOverlayRootView(
            frame: NSRect(x: 0, y: 0, width: 280, height: 600)
        )
        let hostedSidebar = NSView(frame: root.bounds)
        root.addSubview(hostedSidebar)
        root.hostedSidebarView = hostedSidebar
        root.isOverlayHitTestingEnabled = true

        XCTAssertTrue(root.hitTest(NSPoint(x: 140, y: 300)) === hostedSidebar)
    }

    func testCollapsedOverlayLeftClickRoutingKeepsSwiftUIGestureOwner() {
        let root = CollapsedSidebarOverlayRootView(
            frame: NSRect(x: 0, y: 0, width: 280, height: 600)
        )
        let hostedSidebar = NSView(frame: root.bounds)

        let routedHit = SidebarColumnHitTestRouting.routedHit(
            point: NSPoint(x: 140, y: 300),
            in: root,
            originalHit: hostedSidebar,
            hostedSidebarView: hostedSidebar,
            contextMenuController: nil,
            eventType: .leftMouseDown,
            capturesOverlayBackgroundPointerEvents: true
        )

        XCTAssertTrue(routedHit === hostedSidebar)
    }

    func testCollapsedOverlayRightClickStillRoutesToSidebarBackground() {
        let root = CollapsedSidebarOverlayRootView(
            frame: NSRect(x: 0, y: 0, width: 280, height: 600)
        )
        let hostedSidebar = NSView(frame: root.bounds)

        let routedHit = SidebarColumnHitTestRouting.routedHit(
            point: NSPoint(x: 140, y: 300),
            in: root,
            originalHit: hostedSidebar,
            hostedSidebarView: hostedSidebar,
            contextMenuController: nil,
            eventType: .rightMouseDown,
            capturesOverlayBackgroundPointerEvents: true
        )

        XCTAssertTrue(routedHit === root)
    }
}
