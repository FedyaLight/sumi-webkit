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
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.buttonSpacing, 9)
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.clusterHeight, 30)
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.clusterWidth, expectedDiameter * 3 + 18)
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.clusterTrailingInset, 8)
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
        XCTAssertLessThanOrEqual(BrowserWindowZoomPopoverPresenter.contentSize.width, 260)
        XCTAssertLessThanOrEqual(BrowserWindowZoomPopoverPresenter.contentSize.height, 220)
    }

    func testBrowserWindowTrafficLightAssetMappingMatchesOraReferenceModel() {
        XCTAssertEqual(
            BrowserWindowTrafficLightAsset.name(for: .close, showsGlyph: false, isActive: true),
            "traffic-light-close-normal"
        )
        XCTAssertEqual(
            BrowserWindowTrafficLightAsset.name(for: .close, showsGlyph: true, isActive: true),
            "traffic-light-close-hover"
        )
        XCTAssertEqual(
            BrowserWindowTrafficLightAsset.name(for: .minimize, showsGlyph: false, isActive: true),
            "traffic-light-minimize-normal"
        )
        XCTAssertEqual(
            BrowserWindowTrafficLightAsset.name(for: .minimize, showsGlyph: true, isActive: true),
            "traffic-light-minimize-hover"
        )
        XCTAssertEqual(
            BrowserWindowTrafficLightAsset.name(for: .zoom, showsGlyph: false, isActive: true),
            "traffic-light-zoom-normal"
        )
        XCTAssertEqual(
            BrowserWindowTrafficLightAsset.name(for: .zoom, showsGlyph: true, isActive: true),
            "traffic-light-zoom-hover"
        )
        XCTAssertEqual(
            BrowserWindowTrafficLightAsset.name(for: .zoom, showsGlyph: true, isActive: false),
            "traffic-light-no-focus"
        )
    }

    func testBrowserWindowTrafficLightPaletteMatchesOraReferenceAssets() {
        XCTAssertEqual(
            BrowserWindowTrafficLightPalette.colors(for: .close, isActive: true).outer,
            0xE24B41
        )
        XCTAssertEqual(
            BrowserWindowTrafficLightPalette.colors(for: .close, isActive: true).inner,
            0xED6A5F
        )
        XCTAssertEqual(
            BrowserWindowTrafficLightPalette.colors(for: .minimize, isActive: true).outer,
            0xE1A73E
        )
        XCTAssertEqual(
            BrowserWindowTrafficLightPalette.colors(for: .minimize, isActive: true).inner,
            0xF6BE50
        )
        XCTAssertEqual(
            BrowserWindowTrafficLightPalette.colors(for: .zoom, isActive: true).outer,
            0x2DAC2F
        )
        XCTAssertEqual(
            BrowserWindowTrafficLightPalette.colors(for: .zoom, isActive: true).inner,
            0x61C555
        )
        XCTAssertEqual(
            BrowserWindowTrafficLightPalette.colors(for: .close, isActive: false).outer,
            0xD1D0D2
        )
        XCTAssertEqual(
            BrowserWindowTrafficLightPalette.colors(for: .zoom, isActive: false).inner,
            0xC7C7C7
        )
    }

    func testBrowserWindowTrafficLightsUseOraLikeSwiftUICustomModel() throws {
        let controlsSource = try Self.source(named: "Sumi/Components/Window/BrowserWindowTrafficLights.swift")

        XCTAssertTrue(controlsSource.contains("struct BrowserWindowTrafficLights: View"))
        XCTAssertTrue(controlsSource.contains("BrowserWindowTrafficLightButton"))
        XCTAssertTrue(controlsSource.contains("BrowserWindowTrafficLightAsset"))
        XCTAssertTrue(controlsSource.contains("BrowserWindowTrafficLightClickTarget"))
        XCTAssertTrue(controlsSource.contains(".onHover"))
        XCTAssertTrue(controlsSource.contains("NSPopover"))
        XCTAssertTrue(controlsSource.contains("BrowserWindowZoomPopoverPresenter"))
        XCTAssertTrue(controlsSource.contains("BrowserWindowTrafficLightActionRouter.perform"))
        XCTAssertTrue(controlsSource.contains("Image(BrowserWindowTrafficLightAsset.name"))
        XCTAssertFalse(controlsSource.contains("BrowserWindowTrafficLightGlyph"))
        XCTAssertFalse(controlsSource.contains("Canvas"))
        XCTAssertFalse(controlsSource.contains(".drawingGroup"))
        XCTAssertFalse(controlsSource.contains("NSButton"))
        XCTAssertFalse(controlsSource.contains("NSBezierPath"))
        XCTAssertFalse(controlsSource.contains("NSEvent.addLocalMonitorForEvents"))
        XCTAssertFalse(controlsSource.contains("NSWindow.standardWindowButton(kind.buttonType, for: .titled)"))
        XCTAssertFalse(controlsSource.contains("window.standardWindowButton(kind.buttonType)"))
        XCTAssertFalse(controlsSource.contains("removeFromSuperview()"))
        XCTAssertFalse(controlsSource.contains("NSTitlebarAccessoryViewController"))
        XCTAssertFalse(controlsSource.contains("symbolName: \"plus\""))
    }

    func testBrowserWindowTrafficLightMenuFrameActionsUseVisibleFrame() {
        let visibleFrame = NSRect(x: 100, y: 50, width: 900, height: 600)
        let currentFrame = NSRect(x: 250, y: 160, width: 500, height: 340)

        XCTAssertEqual(
            BrowserWindowTrafficLightFrameCalculator.frame(
                for: .leftHalf,
                visibleFrame: visibleFrame,
                currentFrame: currentFrame
            ),
            NSRect(x: 100, y: 50, width: 450, height: 600)
        )
        XCTAssertEqual(
            BrowserWindowTrafficLightFrameCalculator.frame(
                for: .rightHalf,
                visibleFrame: visibleFrame,
                currentFrame: currentFrame
            ),
            NSRect(x: 550, y: 50, width: 450, height: 600)
        )
        XCTAssertEqual(
            BrowserWindowTrafficLightFrameCalculator.frame(
                for: .topHalf,
                visibleFrame: visibleFrame,
                currentFrame: currentFrame
            ),
            NSRect(x: 100, y: 350, width: 900, height: 300)
        )
        XCTAssertEqual(
            BrowserWindowTrafficLightFrameCalculator.frame(
                for: .bottomHalf,
                visibleFrame: visibleFrame,
                currentFrame: currentFrame
            ),
            NSRect(x: 100, y: 50, width: 900, height: 300)
        )
        XCTAssertEqual(
            BrowserWindowTrafficLightFrameCalculator.frame(
                for: .fill,
                visibleFrame: visibleFrame,
                currentFrame: currentFrame
            ),
            visibleFrame
        )
        XCTAssertEqual(
            BrowserWindowTrafficLightFrameCalculator.frame(
                for: .center,
                visibleFrame: visibleFrame,
                currentFrame: currentFrame
            ),
            NSRect(x: 300, y: 180, width: 500, height: 340)
        )
        XCTAssertEqual(
            BrowserWindowTrafficLightFrameCalculator.frame(
                for: .leftThird,
                visibleFrame: visibleFrame,
                currentFrame: currentFrame
            ),
            NSRect(x: 100, y: 50, width: 300, height: 600)
        )
        XCTAssertEqual(
            BrowserWindowTrafficLightFrameCalculator.frame(
                for: .rightThird,
                visibleFrame: visibleFrame,
                currentFrame: currentFrame
            ),
            NSRect(x: 700, y: 50, width: 300, height: 600)
        )
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
