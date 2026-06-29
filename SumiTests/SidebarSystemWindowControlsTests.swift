import AppKit
import SwiftUI
import XCTest

@testable import Sumi

@MainActor
final class SidebarSystemWindowControlsTests: XCTestCase {
    func testSidebarPresentationContextKeepsSameVisibleWidthAcrossSidebarModes() {
        let docked = SidebarPresentationContext.docked(sidebarWidth: 280)
        let hidden = SidebarPresentationContext.collapsedHidden(sidebarWidth: 280)
        let visible = SidebarPresentationContext.collapsedVisible(sidebarWidth: 280)

        XCTAssertEqual(docked.mode, .docked)
        XCTAssertEqual(docked.sidebarWidth, 280)
        XCTAssertEqual(docked.sidebarPosition, .left)
        XCTAssertTrue(docked.showsResizeHandle)
        XCTAssertFalse(docked.isCollapsedOverlay)

        XCTAssertEqual(hidden.mode, .collapsedHidden)
        XCTAssertEqual(hidden.sidebarWidth, 280)
        XCTAssertEqual(hidden.sidebarPosition, .left)
        XCTAssertFalse(hidden.showsResizeHandle)
        XCTAssertTrue(hidden.isCollapsedOverlay)

        XCTAssertEqual(visible.mode, .collapsedVisible)
        XCTAssertEqual(visible.sidebarWidth, 280)
        XCTAssertEqual(visible.sidebarPosition, .left)
        XCTAssertFalse(visible.showsResizeHandle)
        XCTAssertTrue(visible.isCollapsedOverlay)
    }

    func testSidebarPresentationContextCarriesRightSidebarPosition() {
        let docked = SidebarPresentationContext.docked(
            sidebarWidth: 280,
            sidebarPosition: .right
        )
        let hidden = SidebarPresentationContext.collapsedHidden(
            sidebarWidth: 280,
            sidebarPosition: .right
        )
        let visible = SidebarPresentationContext.collapsedVisible(
            sidebarWidth: 280,
            sidebarPosition: .right
        )

        XCTAssertEqual(docked.sidebarPosition, .right)
        XCTAssertEqual(hidden.sidebarPosition, .right)
        XCTAssertEqual(visible.sidebarPosition, .right)
        XCTAssertTrue(docked.shellEdge.isRight)
        XCTAssertTrue(hidden.shellEdge.isRight)
        XCTAssertTrue(visible.shellEdge.isRight)
    }

    func testCollapsedSidebarWidthUsesSharedWidthSelection() {
        XCTAssertEqual(
            SidebarPresentationContext.collapsedSidebarWidth(
                sidebarWidth: 250,
                savedSidebarWidth: 280
            ),
            280
        )
        XCTAssertEqual(
            SidebarPresentationContext.collapsedSidebarWidth(
                sidebarWidth: 320,
                savedSidebarWidth: 280
            ),
            320
        )
    }

    func testSidebarResizeEdgeUsesSymmetricNativeHitTargetMetrics() {
        XCTAssertEqual(SidebarResizeMetrics.hitAreaWidth, 18)
        XCTAssertEqual(SidebarResizeMetrics.hitAreaEdgeOverlap, SidebarResizeMetrics.hitAreaWidth / 2)
        XCTAssertEqual(SidebarResizeMetrics.indicatorEdgeOverlap, SidebarResizeMetrics.indicatorWidth / 2)
        XCTAssertEqual(SidebarPosition.left.shellEdge.resizeHitAreaOffset, SidebarResizeMetrics.hitAreaEdgeOverlap)
        XCTAssertEqual(SidebarPosition.right.shellEdge.resizeHitAreaOffset, -SidebarResizeMetrics.hitAreaEdgeOverlap)
        XCTAssertEqual(SidebarPosition.left.shellEdge.resizeIndicatorOffset, SidebarResizeMetrics.indicatorEdgeOverlap)
        XCTAssertEqual(SidebarPosition.right.shellEdge.resizeIndicatorOffset, -SidebarResizeMetrics.indicatorEdgeOverlap)
    }

    func testSidebarResizeDeltaMirrorsLeftAndRightEdges() {
        XCTAssertEqual(
            SidebarPosition.left.shellEdge.resizeDelta(startingMouseX: 300, currentMouseX: 340),
            40
        )
        XCTAssertEqual(
            SidebarPosition.right.shellEdge.resizeDelta(startingMouseX: 300, currentMouseX: 260),
            40
        )
        XCTAssertEqual(
            SidebarPosition.left.shellEdge.resizeDelta(startingMouseX: 300, currentMouseX: 260),
            -40
        )
        XCTAssertEqual(
            SidebarPosition.right.shellEdge.resizeDelta(startingMouseX: 300, currentMouseX: 340),
            -40
        )
    }

    func testSidebarHoverOverlayRevealPolicyMatchesTrafficLightVisibilityInputs() {
        XCTAssertFalse(SidebarHoverOverlayRevealPolicy.isOverlayRevealed(
            isOverlayVisible: false,
            transientUIPinsHoverSidebar: false,
            sidebarDragPinsHoverSidebar: false
        ))
        XCTAssertTrue(SidebarHoverOverlayRevealPolicy.isOverlayRevealed(
            isOverlayVisible: true,
            transientUIPinsHoverSidebar: false,
            sidebarDragPinsHoverSidebar: false
        ))
        XCTAssertTrue(SidebarHoverOverlayRevealPolicy.isOverlayRevealed(
            isOverlayVisible: false,
            transientUIPinsHoverSidebar: true,
            sidebarDragPinsHoverSidebar: false
        ))
        XCTAssertTrue(SidebarHoverOverlayRevealPolicy.isOverlayRevealed(
            isOverlayVisible: false,
            transientUIPinsHoverSidebar: false,
            sidebarDragPinsHoverSidebar: true
        ))
    }

    func testTrafficLightIdentifiersMapToSystemButtonTypes() {
        XCTAssertEqual(
            BrowserWindowControlsAccessibilityIdentifiers.identifier(for: .closeButton),
            BrowserWindowControlsAccessibilityIdentifiers.closeButton
        )
        XCTAssertEqual(
            BrowserWindowControlsAccessibilityIdentifiers.identifier(for: .miniaturizeButton),
            BrowserWindowControlsAccessibilityIdentifiers.minimizeButton
        )
        XCTAssertEqual(
            BrowserWindowControlsAccessibilityIdentifiers.identifier(for: .zoomButton),
            BrowserWindowControlsAccessibilityIdentifiers.zoomButton
        )
    }

    func testTrafficLightMetricsPreserveBrowserChromeClusterSize() {
        let expectedDiameter: CGFloat
        if #available(macOS 26.0, *) {
            expectedDiameter = 14
        } else {
            expectedDiameter = 12
        }

        XCTAssertEqual(BrowserWindowTrafficLightMetrics.buttonDiameter, expectedDiameter)
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.buttonCenterSpacing, 20)
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.buttonSpacing, 20 - expectedDiameter)
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.clusterHeight, 30)
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.clusterWidth, expectedDiameter * 3 + (20 - expectedDiameter) * 2)
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.clusterTrailingInset, 14)
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.clusterHorizontalOffset, -1)
        XCTAssertEqual(
            BrowserWindowTrafficLightMetrics.sidebarReservedWidth,
            BrowserWindowTrafficLightMetrics.clusterWidth + BrowserWindowTrafficLightMetrics.clusterTrailingInset
        )
        XCTAssertEqual(
            BrowserWindowTrafficLightMetrics.sidebarReservedWidth(isVisible: true),
            BrowserWindowTrafficLightMetrics.sidebarReservedWidth
        )
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.sidebarReservedWidth(isVisible: false), 0)
        XCTAssertEqual(SidebarChromeMetrics.topControlInset, 0)
        XCTAssertEqual(SidebarChromeMetrics.horizontalPadding, 18)
        XCTAssertEqual(SidebarChromeMetrics.controlStripHeight, 38)
        XCTAssertEqual(SidebarChromeMetrics.controlSpacing, 0)
        XCTAssertEqual(SidebarChromeMetrics.navigationButtonSize, 30)
        XCTAssertEqual(SidebarChromeMetrics.navigationIconSize, 14)
    }

    func testTrafficLightActionProviderEnablesAvailableWindowActions() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 320, height: 240)),
            styleMask: SumiBrowserChromeConfiguration.requiredStyleMask,
            backing: .buffered,
            defer: false
        )
        let provider = BrowserWindowTrafficLightActionProvider.browserWindow(window)

        XCTAssertTrue(provider.isEnabled(.close))
        XCTAssertTrue(provider.isEnabled(.minimize))
        XCTAssertTrue(provider.isEnabled(.zoom))
    }

    func testTrafficLightActionProviderDisablesUnavailableWindowActions() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 320, height: 240)),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let provider = BrowserWindowTrafficLightActionProvider.browserWindow(window)

        XCTAssertTrue(provider.isEnabled(.close))
        XCTAssertFalse(provider.isEnabled(.minimize))
        XCTAssertFalse(provider.isEnabled(.zoom))
    }

    func testBrowserTrafficLightsRetargetToHostingWindowAfterAttach() {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let host = NSHostingView(
            rootView: BrowserWindowTrafficLights(
                actionProvider: .browserWindow(nil),
                isVisible: true
            )
        )
        host.frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: BrowserWindowTrafficLightMetrics.sidebarReservedWidth,
                height: BrowserWindowTrafficLightMetrics.clusterHeight
            )
        )

        window.contentView = host
        host.layoutSubtreeIfNeeded()

        let minimizeButton = Self.button(
            in: host,
            accessibilityIdentifier: BrowserWindowControlsAccessibilityIdentifiers.minimizeButton
        )
        XCTAssertNotNil(minimizeButton)
        XCTAssertIdentical(minimizeButton?.target as AnyObject, window)
        XCTAssertEqual(minimizeButton?.action.map(NSStringFromSelector), "miniaturize:")
        XCTAssertTrue(minimizeButton?.isEnabled ?? false)

        window.hideNativeStandardWindowButtonsForBrowserChrome()
        host.layoutSubtreeIfNeeded()

        for identifier in [
            BrowserWindowControlsAccessibilityIdentifiers.closeButton,
            BrowserWindowControlsAccessibilityIdentifiers.minimizeButton,
            BrowserWindowControlsAccessibilityIdentifiers.zoomButton,
        ] {
            let button = Self.button(in: host, accessibilityIdentifier: identifier)
            XCTAssertNotNil(button, identifier)
            XCTAssertFalse(button?.isHidden ?? true, identifier)
            XCTAssertEqual(button?.alphaValue, 1, identifier)
            XCTAssertTrue(button?.isEnabled ?? false, identifier)
        }
    }

    private static func button(
        in view: NSView,
        accessibilityIdentifier: String
    ) -> NSButton? {
        if let button = view as? NSButton,
           button.accessibilityIdentifier() == accessibilityIdentifier {
            return button
        }

        for subview in view.subviews {
            if let button = button(in: subview, accessibilityIdentifier: accessibilityIdentifier) {
                return button
            }
        }

        return nil
    }

}
