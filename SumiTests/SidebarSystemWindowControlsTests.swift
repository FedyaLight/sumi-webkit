import AppKit
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

    func testBrowserWindowTrafficLightKindsExposeExpectedAccessibility() {
        XCTAssertEqual(
            BrowserWindowTrafficLightKind.close.accessibilityIdentifier,
            "browser-window-close-button"
        )
        XCTAssertEqual(
            BrowserWindowTrafficLightKind.minimize.accessibilityIdentifier,
            "browser-window-minimize-button"
        )
        XCTAssertEqual(
            BrowserWindowTrafficLightKind.zoom.accessibilityIdentifier,
            "browser-window-zoom-button"
        )

        XCTAssertEqual(BrowserWindowTrafficLightKind.close.accessibilityLabel, "Close window")
        XCTAssertEqual(BrowserWindowTrafficLightKind.minimize.accessibilityLabel, "Minimize window")
        XCTAssertEqual(BrowserWindowTrafficLightKind.zoom.accessibilityLabel, "Zoom window")
        XCTAssertEqual(BrowserWindowTrafficLightKind.close.symbolName, "xmark")
        XCTAssertEqual(BrowserWindowTrafficLightKind.minimize.symbolName, "minus")
        XCTAssertEqual(BrowserWindowTrafficLightKind.zoom.symbolName, "plus")
    }

    func testBrowserWindowTrafficLightMetricsPreserveNativeLikeSpacingAndSidebarReservation() {
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.buttonDiameter, 12)
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.buttonSpacing, 8)
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.clusterWidth, 52)
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.sidebarReservedWidth, 60)
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.windowLeadingInset, 16)
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.windowTopInset, 13)
    }

    func testBrowserWindowTrafficLightsUseWindowLevelTopLeftMetricsAcrossSidebarModes() {
        let contexts = [
            SidebarPresentationContext.docked(sidebarWidth: 250),
            SidebarPresentationContext.docked(sidebarWidth: 250, sidebarPosition: .right),
            SidebarPresentationContext.collapsedHidden(sidebarWidth: 250),
            SidebarPresentationContext.collapsedHidden(sidebarWidth: 250, sidebarPosition: .right),
            SidebarPresentationContext.collapsedVisible(sidebarWidth: 250),
            SidebarPresentationContext.collapsedVisible(sidebarWidth: 250, sidebarPosition: .right),
        ]

        let leadingInsets = contexts.map { _ in BrowserWindowTrafficLightMetrics.windowLeadingInset }
        let topInsets = contexts.map { _ in BrowserWindowTrafficLightMetrics.windowTopInset }

        XCTAssertEqual(Set(leadingInsets), [16])
        XCTAssertEqual(Set(topInsets), [13])
    }

    func testBrowserWindowTrafficLightAvailabilityFollowsWindowCapabilities() {
        let window = WindowChromeTestSupport.makePlainWindow()

        XCTAssertTrue(BrowserWindowTrafficLightAvailability.isEnabled(kind: .close, window: window))
        XCTAssertTrue(BrowserWindowTrafficLightAvailability.isEnabled(kind: .minimize, window: window))
        XCTAssertTrue(BrowserWindowTrafficLightAvailability.isEnabled(kind: .zoom, window: window))

        window.styleMask = window.styleMask.subtracting(.closable)
        XCTAssertFalse(BrowserWindowTrafficLightAvailability.isEnabled(kind: .close, window: window))

        window.styleMask = window.styleMask.subtracting(.miniaturizable)
        XCTAssertFalse(BrowserWindowTrafficLightAvailability.isEnabled(kind: .minimize, window: window))

        window.styleMask = window.styleMask.subtracting(.resizable)
        XCTAssertFalse(BrowserWindowTrafficLightAvailability.isEnabled(kind: .zoom, window: window))
    }

    func testBrowserWindowTrafficLightAvailabilityDisablesMinimizeInFullscreen() {
        let styleMask: NSWindow.StyleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
            .fullScreen,
        ]

        XCTAssertTrue(BrowserWindowTrafficLightAvailability.isEnabled(
            kind: .close,
            styleMask: styleMask,
            hasAttachedSheet: false
        ))
        XCTAssertFalse(BrowserWindowTrafficLightAvailability.isEnabled(
            kind: .minimize,
            styleMask: styleMask,
            hasAttachedSheet: false
        ))
        XCTAssertTrue(BrowserWindowTrafficLightAvailability.isEnabled(
            kind: .zoom,
            styleMask: styleMask,
            hasAttachedSheet: false
        ))
    }

    func testBrowserWindowTrafficLightAppearanceCoversIdleHoverPressedAndDisabledStates() {
        let idle = BrowserWindowTrafficLightAppearanceResolver.appearance(
            isEnabled: true,
            isWindowActive: true,
            interactionState: .idle
        )
        let hovered = BrowserWindowTrafficLightAppearanceResolver.appearance(
            isEnabled: true,
            isWindowActive: true,
            interactionState: .hovered
        )
        let pressed = BrowserWindowTrafficLightAppearanceResolver.appearance(
            isEnabled: true,
            isWindowActive: true,
            interactionState: .pressed
        )
        let inactive = BrowserWindowTrafficLightAppearanceResolver.appearance(
            isEnabled: true,
            isWindowActive: false,
            interactionState: .idle
        )
        let disabled = BrowserWindowTrafficLightAppearanceResolver.appearance(
            isEnabled: false,
            isWindowActive: true,
            interactionState: .hovered
        )

        XCTAssertEqual(idle.fillOpacity, 1)
        XCTAssertEqual(idle.symbolOpacity, 0)
        XCTAssertGreaterThan(hovered.symbolOpacity, 0)
        XCTAssertGreaterThan(hovered.fillOpacity, inactive.fillOpacity)
        XCTAssertLessThan(pressed.scale, hovered.scale)
        XCTAssertGreaterThan(pressed.overlayOpacity, hovered.overlayOpacity)
        XCTAssertLessThan(disabled.fillOpacity, inactive.fillOpacity)
        XCTAssertEqual(disabled.symbolOpacity, 0)
    }

    func testBrowserWindowTrafficLightActionRouterUsesWindowActions() {
        let window = TrackingWindow()

        BrowserWindowTrafficLightActionRouter.perform(.close, window: window)
        BrowserWindowTrafficLightActionRouter.perform(.minimize, window: window)
        BrowserWindowTrafficLightActionRouter.perform(.zoom, window: window)

        XCTAssertEqual(window.performedCloseCount, 1)
        XCTAssertEqual(window.miniaturizeCount, 1)
        XCTAssertEqual(window.performZoomCount, 1)
        XCTAssertEqual(window.closeCount, 0)
        XCTAssertEqual(window.toggleFullScreenCount, 0)
    }

    func testBrowserWindowTrafficLightActionRouterIgnoresUnavailableActions() {
        let window = TrackingWindow(styleMask: [.titled])

        BrowserWindowTrafficLightActionRouter.perform(.close, window: window)
        BrowserWindowTrafficLightActionRouter.perform(.minimize, window: window)
        BrowserWindowTrafficLightActionRouter.perform(.zoom, window: window)

        XCTAssertEqual(window.performedCloseCount, 0)
        XCTAssertEqual(window.miniaturizeCount, 0)
        XCTAssertEqual(window.performZoomCount, 0)
    }

    func testSidebarHeaderNoLongerReferencesNativeWindowControlsHosting() throws {
        let sidebarHeaderSource = try Self.source(named: "Navigation/Sidebar/SidebarHeader.swift")

        XCTAssertFalse(sidebarHeaderSource.contains("SidebarSystemWindowControlsHost"))
        XCTAssertFalse(sidebarHeaderSource.contains("standardWindowButton"))
        XCTAssertFalse(sidebarHeaderSource.contains("NativeWindowControls"))
        XCTAssertTrue(sidebarHeaderSource.contains("BrowserWindowTrafficLightMetrics.sidebarReservedWidth"))
        XCTAssertTrue(sidebarHeaderSource.contains("sumiSettings.sidebarPosition == .left"))
        XCTAssertTrue(sidebarHeaderSource.contains("sumiSettings.sidebarPosition.shellEdge.toggleSidebarSymbolName"))
    }

    private static func source(named relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repoRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}

@MainActor
private final class TrackingWindow: NSWindow {
    private(set) var performedCloseCount = 0
    private(set) var miniaturizeCount = 0
    private(set) var performZoomCount = 0
    private(set) var closeCount = 0
    private(set) var toggleFullScreenCount = 0

    init(
        styleMask: NSWindow.StyleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
        ]
    ) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
    }

    override func performClose(_ sender: Any?) {
        performedCloseCount += 1
    }

    override func miniaturize(_ sender: Any?) {
        miniaturizeCount += 1
    }

    override func performZoom(_ sender: Any?) {
        performZoomCount += 1
    }

    override func close() {
        closeCount += 1
    }

    override func toggleFullScreen(_ sender: Any?) {
        toggleFullScreenCount += 1
    }
}
