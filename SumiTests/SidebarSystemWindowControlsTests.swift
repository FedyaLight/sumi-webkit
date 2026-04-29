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
        XCTAssertEqual(
            BrowserWindowControlsAccessibilityIdentifiers.miniBrowserWindow,
            "mini-browser-window"
        )

        XCTAssertEqual(BrowserWindowTrafficLightKind.close.accessibilityLabel, "Close window")
        XCTAssertEqual(BrowserWindowTrafficLightKind.minimize.accessibilityLabel, "Minimize window")
        XCTAssertEqual(BrowserWindowTrafficLightKind.zoom.accessibilityLabel, "Full Screen")
    }

    func testBrowserWindowTrafficLightMetricsPreserveOraLikeSpacingAndSidebarReservation() {
        let expectedDiameter: CGFloat
        if #available(macOS 26.0, *) {
            expectedDiameter = 14
        } else {
            expectedDiameter = 12
        }

        XCTAssertEqual(BrowserWindowTrafficLightMetrics.buttonDiameter, expectedDiameter)
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.buttonSpacing, 6)
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.clusterHeight, 30)
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.clusterWidth, expectedDiameter * 3 + 12)
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.clusterTrailingInset, 14)
        XCTAssertEqual(
            BrowserWindowTrafficLightMetrics.sidebarReservedWidth,
            BrowserWindowTrafficLightMetrics.clusterWidth + BrowserWindowTrafficLightMetrics.clusterTrailingInset
        )
        XCTAssertEqual(SidebarChromeMetrics.topControlInset, 0)
        XCTAssertEqual(SidebarChromeMetrics.horizontalPadding, 18)
        XCTAssertEqual(SidebarChromeMetrics.controlStripHeight, 38)
        XCTAssertEqual(SidebarChromeMetrics.controlSpacing, 0)
        XCTAssertEqual(SidebarChromeMetrics.navigationButtonSize, 30)
        XCTAssertEqual(SidebarChromeMetrics.navigationIconSize, 14)
        XCTAssertEqual(SidebarChromeMetrics.trafficLightLeadingOffset, 0)
    }

    func testBrowserWindowTrafficLightKindsMapToSystemButtonTypes() {
        XCTAssertEqual(BrowserWindowTrafficLightKind.close.buttonType, .closeButton)
        XCTAssertEqual(BrowserWindowTrafficLightKind.minimize.buttonType, .miniaturizeButton)
        XCTAssertEqual(BrowserWindowTrafficLightKind.zoom.buttonType, .zoomButton)
    }

    func testBrowserWindowTrafficLightsUseNativeSystemButtonHost() throws {
        let controlsSource = try Self.source(named: "Sumi/Components/Window/BrowserWindowTrafficLights.swift")

        XCTAssertTrue(controlsSource.contains("struct BrowserWindowTrafficLights: View"))
        XCTAssertTrue(controlsSource.contains("BrowserWindowStandardTrafficLightsHost"))
        XCTAssertTrue(controlsSource.contains("BrowserWindowStandardTrafficLightsView"))
        XCTAssertTrue(controlsSource.contains("window.standardWindowButton(kind.buttonType)"))
        XCTAssertTrue(controlsSource.contains("NSWindow.didResizeNotification"))
        XCTAssertTrue(controlsSource.contains("refreshLayoutAfterWindowChromePass"))
        XCTAssertTrue(controlsSource.contains("button.intrinsicContentSize"))
        XCTAssertTrue(controlsSource.contains("nativeButtonFrameSize(for: button)"))
        XCTAssertTrue(controlsSource.contains("button.alignmentRect("))
        XCTAssertTrue(controlsSource.contains("addSubview(button)"))
        XCTAssertTrue(controlsSource.contains("button.removeFromSuperview()"))
        XCTAssertTrue(controlsSource.contains("button.setAccessibilityIdentifier(kind.accessibilityIdentifier)"))
        XCTAssertTrue(controlsSource.contains("button.cell?.controlView = button"))
        XCTAssertTrue(controlsSource.contains("button.target = window"))
        XCTAssertTrue(controlsSource.contains("button.updateTrackingAreas()"))
        XCTAssertTrue(controlsSource.contains("drawTrafficLightImages()"))
        XCTAssertTrue(controlsSource.contains("traffic-light-zoom-\\(state)"))
        XCTAssertTrue(controlsSource.contains("NSTrackingArea"))
        XCTAssertTrue(controlsSource.contains("button.alphaValue = isTrafficLightVisible ? 0.01 : 0"))
        XCTAssertFalse(controlsSource.contains("BrowserWindowTrafficLightGlyph"))
        XCTAssertFalse(controlsSource.contains("BrowserWindowTrafficLightAsset"))
        XCTAssertFalse(controlsSource.contains("BrowserWindowTrafficLightClickTarget"))
        XCTAssertFalse(controlsSource.contains("BrowserWindowZoomMenuPresenter"))
        XCTAssertFalse(controlsSource.contains("BrowserWindowZoomMenuFactory"))
        XCTAssertFalse(controlsSource.contains("BrowserWindowTrafficLightMenuAction"))
        XCTAssertFalse(controlsSource.contains("Canvas"))
        XCTAssertFalse(controlsSource.contains(".drawingGroup"))
        XCTAssertFalse(controlsSource.contains("NSPopover"))
        XCTAssertFalse(controlsSource.contains("NSHostingController"))
        XCTAssertFalse(controlsSource.contains("NSBezierPath"))
        XCTAssertFalse(controlsSource.contains("NSEvent.addLocalMonitorForEvents"))
        XCTAssertFalse(controlsSource.contains("NSWindow.standardWindowButton(kind.buttonType, for: .titled)"))
        XCTAssertFalse(controlsSource.contains("NSTitlebarAccessoryViewController"))
        XCTAssertFalse(controlsSource.contains("symbolName: \"plus\""))
    }

    func testBrowserWindowTrafficLightActionRouterUsesStandardWindowActions() {
        let window = TrackingWindow()

        BrowserWindowTrafficLightActionRouter.perform(.close, window: window, sender: nil)
        BrowserWindowTrafficLightActionRouter.perform(.minimize, window: window, sender: nil)
        BrowserWindowTrafficLightActionRouter.perform(.zoom, window: window, sender: nil, modifierFlags: [])
        BrowserWindowTrafficLightActionRouter.perform(.zoom, window: window, sender: nil, modifierFlags: .option)

        XCTAssertEqual(window.performCloseCount, 1)
        XCTAssertEqual(window.miniaturizeCount, 1)
        XCTAssertEqual(window.toggleFullScreenCount, 1)
        XCTAssertEqual(window.performZoomCount, 1)
        XCTAssertEqual(window.closeCount, 0)
    }

    func testBrowserWindowTrafficLightsBelongToSidebarHeader() throws {
        let windowSource = try Self.source(named: "App/Window/WindowView.swift")
        let sidebarHeaderSource = try Self.source(named: "Navigation/Sidebar/SidebarHeader.swift")
        let sidebarSource = try Self.source(named: "Navigation/Sidebar/SpacesSideBarView.swift")

        XCTAssertFalse(windowSource.contains("BrowserWindowTrafficLights("))
        XCTAssertTrue(sidebarHeaderSource.contains("BrowserWindowTrafficLights("))
        XCTAssertFalse(sidebarHeaderSource.contains("sidebarPresentationContext.mode != .collapsedHidden"))
        XCTAssertFalse(sidebarHeaderSource.contains("Color.clear"))
        XCTAssertTrue(sidebarSource.contains(".padding(.top, SidebarChromeMetrics.topControlInset)"))
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

    func testNativeWindowControlsHostingFilesAreRemoved() {
        let removedFiles = [
            "Sumi/Components/Window/NativeWindowControlsSupport.swift",
            "Sumi/Components/Window/NativeWindowControlsVisualShield.swift",
            "Sumi/Components/MiniWindow/MiniWindowTrafficLights.swift",
            "SumiTests/MiniWindowTrafficLightsTests.swift",
        ]

        for file in removedFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: Self.repoRoot.appendingPathComponent(file).path),
                "\(file) should not return with custom traffic lights."
            )
        }
    }

    func testSidebarHeaderNoLongerReferencesNativeWindowControlsHosting() throws {
        let sidebarHeaderSource = try Self.source(named: "Navigation/Sidebar/SidebarHeader.swift")

        XCTAssertFalse(sidebarHeaderSource.contains("SidebarSystemWindowControlsHost"))
        XCTAssertFalse(sidebarHeaderSource.contains("standardWindowButton"))
        XCTAssertFalse(sidebarHeaderSource.contains("NativeWindowControls"))
        XCTAssertTrue(sidebarHeaderSource.contains("BrowserWindowTrafficLights("))
        XCTAssertFalse(sidebarHeaderSource.contains("sidebarPresentationContext.mode != .collapsedHidden"))
        XCTAssertTrue(sidebarHeaderSource.contains("sumiSettings.sidebarPosition.shellEdge.toggleSidebarSymbolName"))
    }

    func testMiniWindowUsesSharedCustomTrafficLights() throws {
        let miniWindowToolbarSource = try Self.source(named: "Sumi/Components/MiniWindow/MiniWindowToolbar.swift")
        let miniWindowControllerSource = try Self.source(
            named: "Sumi/Managers/ExternalMiniWindowManager/ExternalMiniWindowManager.swift"
        )

        XCTAssertFalse(miniWindowControllerSource.contains("NSTitlebarAccessoryViewController"))
        XCTAssertTrue(miniWindowToolbarSource.contains("BrowserWindowTrafficLights(window: window)"))
        XCTAssertFalse(miniWindowToolbarSource.contains("MiniWindowTrafficLights"))
        XCTAssertFalse(miniWindowToolbarSource.contains("standardWindowButton"))
        XCTAssertTrue(
            miniWindowControllerSource.contains("BrowserWindowControlsAccessibilityIdentifiers.miniBrowserWindow")
        )
        XCTAssertTrue(miniWindowControllerSource.contains("hideStandardWindowButtonsForCustomChrome()"))
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func source(named relativePath: String) throws -> String {
        return try String(
            contentsOf: repoRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}

@MainActor
private final class TrackingWindow: NSWindow {
    private(set) var performCloseCount = 0
    private(set) var miniaturizeCount = 0
    private(set) var performZoomCount = 0
    private(set) var toggleFullScreenCount = 0
    private(set) var closeCount = 0

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
    }

    override func performClose(_ sender: Any?) {
        performCloseCount += 1
    }

    override func miniaturize(_ sender: Any?) {
        miniaturizeCount += 1
    }

    override func performZoom(_ sender: Any?) {
        performZoomCount += 1
    }

    override func toggleFullScreen(_ sender: Any?) {
        toggleFullScreenCount += 1
    }

    override func close() {
        closeCount += 1
    }
}
