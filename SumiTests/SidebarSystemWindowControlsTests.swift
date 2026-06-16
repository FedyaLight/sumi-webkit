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

    func testSidebarResizeSourceUsesCursorBridgeInsteadOfManualCursorSetting() throws {
        let resizeSource = try Self.source(named: "Sumi/Components/Sidebar/SidebarResizeView.swift")
        let windowViewSource = try Self.source(named: "App/Window/WindowView.swift")

        XCTAssertTrue(resizeSource.contains(".chromeCursor(.resizeLeftRight"))
        XCTAssertTrue(resizeSource.contains("transaction.disablesAnimations = true"))
        XCTAssertTrue(resizeSource.contains("persist: false"))
        XCTAssertTrue(resizeSource.contains("persistWindowSession(for: windowState)"))
        XCTAssertFalse(resizeSource.contains("NSCursor."))
        XCTAssertFalse(windowViewSource.contains(".alwaysArrowCursor()"))
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

    func testBrowserTrafficLightSourceUsesSidebarHostedStandardButtons() throws {
        let controlsSource = try Self.source(named: "Sumi/Components/Window/BrowserWindowTrafficLights.swift")
        let windowSource = try Self.source(named: "Sumi/Components/Window/SumiBrowserWindow.swift")
        let windowViewSource = try Self.source(named: "App/Window/WindowView.swift")
        let sidebarHeaderSource = try Self.source(named: "Navigation/Sidebar/SidebarHeader.swift")
        let collapsedOverlaySource = try Self.source(named: "Sumi/Components/Sidebar/CollapsedSidebarOverlayHost.swift")

        XCTAssertTrue(controlsSource.contains("struct BrowserWindowTrafficLights: View"))
        XCTAssertTrue(controlsSource.contains("NSViewRepresentable"))
        XCTAssertTrue(controlsSource.contains("NSWindow.standardWindowButton("))
        XCTAssertTrue(controlsSource.contains("addSubview(button)"))
        XCTAssertTrue(controlsSource.contains("width: BrowserWindowTrafficLightMetrics.sidebarReservedWidth(isVisible: isVisible)"))
        XCTAssertTrue(controlsSource.contains("struct BrowserWindowTrafficLightActionProvider"))
        XCTAssertTrue(controlsSource.contains("enum BrowserWindowTrafficLightAction"))
        XCTAssertTrue(controlsSource.contains("BrowserWindowTrafficLightRolloverGlyphOverlayView"))
        XCTAssertTrue(controlsSource.contains("button.target = targetWindow"))
        XCTAssertTrue(controlsSource.contains("button.action = action.selector"))
        XCTAssertTrue(controlsSource.contains("#selector(NSWindow.performCloseFromBrowserChrome(_:))"))
        XCTAssertTrue(controlsSource.contains("#selector(NSWindow.miniaturize(_:))"))
        XCTAssertTrue(controlsSource.contains("#selector(NSWindow.toggleFullScreen(_:))"))
        XCTAssertTrue(controlsSource.contains(".mouseMoved"))
        XCTAssertTrue(controlsSource.contains("enabledActions.remove(pressedAction)"))
        XCTAssertTrue(controlsSource.contains("glyphOverlayView.isHidden = !shouldShowGlyphs"))
        XCTAssertTrue(controlsSource.contains(BrowserWindowControlsAccessibilityIdentifiers.closeButton))
        XCTAssertTrue(controlsSource.contains(BrowserWindowControlsAccessibilityIdentifiers.minimizeButton))
        XCTAssertTrue(controlsSource.contains(BrowserWindowControlsAccessibilityIdentifiers.zoomButton))
        XCTAssertTrue(sidebarHeaderSource.contains("BrowserWindowTrafficLights("))
        XCTAssertTrue(sidebarHeaderSource.contains("isBrowserWindowFullScreen == false"))
        XCTAssertTrue(sidebarHeaderSource.contains("case .collapsedVisible:"))
        XCTAssertTrue(sidebarHeaderSource.contains("case .collapsedHidden:"))
        XCTAssertTrue(sidebarHeaderSource.contains(".onChange(of: browserWindowIdentity)"))
        XCTAssertTrue(sidebarHeaderSource.contains("windowState.window.map { ObjectIdentifier($0) }"))
        XCTAssertFalse(windowViewSource.contains("shouldRenderParentBrowserTrafficLights"))
        XCTAssertFalse(windowViewSource.contains("BrowserWindowTrafficLights("))
        XCTAssertTrue(windowSource.contains("hideNativeStandardWindowButtonsForBrowserChrome()"))
        XCTAssertTrue(collapsedOverlaySource.contains("CollapsedSidebarOverlayHost"))
        XCTAssertFalse(collapsedOverlaySource.contains("NSPanel"))

        XCTAssertFalse(controlsSource.contains("#selector(NSWindow.performZoom(_:))"))
        XCTAssertFalse(controlsSource.contains("targetWindow.performZoom"))
        XCTAssertFalse(controlsSource.contains("targetWindow.performClose"))
        XCTAssertFalse(controlsSource.contains("targetWindow.performMiniaturize"))
        XCTAssertFalse(controlsSource.contains("targetWindow.toggleFullScreen"))
        XCTAssertFalse(controlsSource.contains("button.sendAction("))
        XCTAssertFalse(controlsSource.contains("image.draw(in: frame"))
        XCTAssertFalse(sidebarHeaderSource.contains("standardWindowButton"))
        XCTAssertFalse(collapsedOverlaySource.contains("standardWindowButton"))

        Self.assertNoNativeTrafficLightReparenting(in: controlsSource, file: "BrowserWindowTrafficLights.swift")
        Self.assertNoNativeTrafficLightReparenting(in: windowSource, file: "SumiBrowserWindow.swift")
        Self.assertNoNativeTrafficLightReparenting(in: windowViewSource, file: "WindowView.swift")
        Self.assertNoNativeTrafficLightReparenting(in: sidebarHeaderSource, file: "SidebarHeader.swift")
        Self.assertNoNativeTrafficLightReparenting(in: collapsedOverlaySource, file: "CollapsedSidebarOverlayHost.swift")
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
        XCTAssertTrue(minimizeButton?.target as AnyObject === window)
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

    func testCollapsedOverlayUsesSameSidebarHostedTrafficLightsAndWindowLocalGeometry() throws {
        let headerSource = try Self.source(named: "Navigation/Sidebar/SidebarHeader.swift")
        let collapsedOverlaySource = try Self.source(named: "Sumi/Components/Sidebar/CollapsedSidebarOverlayHost.swift")
        let windowViewSource = try Self.source(named: "App/Window/WindowView.swift")

        XCTAssertTrue(headerSource.contains("BrowserWindowTrafficLights("))
        XCTAssertTrue(headerSource.contains(".browserWindow(windowState.window)"))
        XCTAssertTrue(headerSource.contains("isBrowserWindowFullScreen == false"))
        XCTAssertTrue(collapsedOverlaySource.contains("CollapsedSidebarOverlayHost"))
        XCTAssertTrue(collapsedOverlaySource.contains("presentationContext.sidebarWidth"))
        XCTAssertTrue(collapsedOverlaySource.contains("WebContentHoverShieldSensorView()"))
        XCTAssertFalse(windowViewSource.contains("collapsedLeftSidebarPanelVisible"))
        XCTAssertFalse(windowViewSource.contains("!dockedLeftSidebarVisible && !collapsedLeftSidebarPanelVisible"))
        XCTAssertFalse(windowViewSource.contains("BrowserWindowTrafficLights("))

        XCTAssertFalse(collapsedOverlaySource.contains("TrafficLightReserved"))
        XCTAssertFalse(collapsedOverlaySource.contains("trafficLightReserved"))
        XCTAssertFalse(collapsedOverlaySource.range(of: #"split.*panel"#, options: .regularExpression) != nil)
        XCTAssertFalse(collapsedOverlaySource.range(of: #"accessory.*panel"#, options: .regularExpression) != nil)
        XCTAssertFalse(collapsedOverlaySource.contains("standardWindowButton"))
        XCTAssertFalse(collapsedOverlaySource.contains("NSPanel"))
    }

    func testRightCollapsedSidebarUsesSameSidebarEmbeddedTrafficLights() throws {
        let headerSource = try Self.source(named: "Navigation/Sidebar/SidebarHeader.swift")
        let windowViewSource = try Self.source(named: "App/Window/WindowView.swift")

        XCTAssertTrue(headerSource.contains("BrowserWindowTrafficLights("))
        XCTAssertTrue(headerSource.contains("isBrowserWindowFullScreen == false"))
        XCTAssertFalse(headerSource.contains("sidebarPresentationContext.mode != .collapsedHidden"))
        XCTAssertFalse(headerSource.contains("sumiSettings.sidebarPosition.shellEdge.isLeft"))
        XCTAssertFalse(headerSource.contains("shellEdge.isRight"))
        XCTAssertFalse(windowViewSource.contains("shouldRenderParentBrowserTrafficLights"))
        XCTAssertFalse(windowViewSource.contains("BrowserWindowTrafficLights("))
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func source(named relativePath: String) throws -> String {
        try String(
            contentsOf: repoRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
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

    private static func assertNoNativeTrafficLightReparenting(
        in source: String,
        file: String,
        line: UInt = #line
    ) {
        let forbiddenPatterns = [
            #"(button|closeButton|minimizeButton|miniaturizeButton|zoomButton)\.removeFromSuperview\("#,
            #"standardWindowButton\([^)]+\)\?\.removeFromSuperview\("#,
            #"standardWindowButton\([^)]+\)\.removeFromSuperview\("#,
        ]

        for pattern in forbiddenPatterns {
            XCTAssertNil(
                source.range(of: pattern, options: .regularExpression),
                "\(file) must not reparent native traffic-light buttons with pattern: \(pattern)",
                line: line
            )
        }
    }

}
