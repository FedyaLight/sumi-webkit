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
        XCTAssertEqual(
            BrowserWindowControlsAccessibilityIdentifiers.miniBrowserWindow,
            "mini-browser-window"
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
        XCTAssertEqual(SidebarChromeMetrics.topControlInset, 0)
        XCTAssertEqual(SidebarChromeMetrics.horizontalPadding, 18)
        XCTAssertEqual(SidebarChromeMetrics.controlStripHeight, 38)
        XCTAssertEqual(SidebarChromeMetrics.controlSpacing, 0)
        XCTAssertEqual(SidebarChromeMetrics.navigationButtonSize, 30)
        XCTAssertEqual(SidebarChromeMetrics.navigationIconSize, 14)
    }

    func testBrowserTrafficLightSourceUsesCanonicalCustomComponent() throws {
        let controlsSource = try Self.source(named: "Sumi/Components/Window/BrowserWindowTrafficLights.swift")
        let windowSource = try Self.source(named: "Sumi/Components/Window/SumiBrowserWindow.swift")
        let windowViewSource = try Self.source(named: "App/Window/WindowView.swift")
        let sidebarHeaderSource = try Self.source(named: "Navigation/Sidebar/SidebarHeader.swift")
        let panelHostSource = try Self.source(named: "Sumi/Components/Sidebar/CollapsedSidebarPanelHost.swift")

        XCTAssertTrue(controlsSource.contains("struct BrowserWindowTrafficLights: View"))
        XCTAssertTrue(controlsSource.contains("struct BrowserWindowTrafficLightActionProvider"))
        XCTAssertTrue(controlsSource.contains("enum BrowserWindowTrafficLightAction"))
        XCTAssertTrue(controlsSource.contains("parentWindow") == false)
        XCTAssertTrue(controlsSource.contains("targetWindow.close()") || controlsSource.contains("$0.close()"))
        XCTAssertTrue(
            controlsSource.contains("targetWindow.miniaturizeFromCustomBrowserChrome()")
                || controlsSource.contains("$0.miniaturizeFromCustomBrowserChrome()")
        )
        XCTAssertTrue(controlsSource.contains("targetWindow.toggleFullScreen(nil)") || controlsSource.contains("$0.toggleFullScreen(nil)"))
        XCTAssertTrue(controlsSource.contains("BrowserWindowTrafficLightMirroredZoomGlyph"))
        XCTAssertTrue(controlsSource.contains(BrowserWindowControlsAccessibilityIdentifiers.closeButton))
        XCTAssertTrue(controlsSource.contains(BrowserWindowControlsAccessibilityIdentifiers.minimizeButton))
        XCTAssertTrue(controlsSource.contains(BrowserWindowControlsAccessibilityIdentifiers.zoomButton))
        XCTAssertTrue(sidebarHeaderSource.contains("BrowserWindowTrafficLights("))
        XCTAssertTrue(sidebarHeaderSource.contains("sidebarPresentationContext.mode != .collapsedHidden"))
        XCTAssertFalse(sidebarHeaderSource.contains("sumiSettings.sidebarPosition.shellEdge.isLeft"))
        XCTAssertFalse(windowViewSource.contains("shouldRenderParentBrowserTrafficLights"))
        XCTAssertFalse(windowViewSource.contains("BrowserWindowTrafficLights("))
        XCTAssertTrue(windowSource.contains("hideNativeStandardWindowButtonsForBrowserChrome()"))
        XCTAssertTrue(panelHostSource.contains("CollapsedSidebarPanelWindow"))

        XCTAssertFalse(controlsSource.contains("BrowserWindowTrafficLightProxyCluster"))
        XCTAssertFalse(controlsSource.contains("BrowserWindowTrafficLightProxyAction"))
        XCTAssertFalse(controlsSource.contains("BrowserWindowTrafficLightPlaceholderCluster"))
        XCTAssertFalse(controlsSource.contains("BrowserWindowNativeTrafficLightVisibilityBridge"))
        XCTAssertFalse(controlsSource.contains("standardWindowButton"))
        XCTAssertFalse(windowViewSource.contains("BrowserWindowNativeTrafficLightVisibilityBridge"))
        XCTAssertFalse(windowViewSource.contains("trafficLightRenderState"))
        XCTAssertFalse(sidebarHeaderSource.contains("BrowserWindowTrafficLightProxyCluster"))
        XCTAssertFalse(sidebarHeaderSource.contains("BrowserWindowTrafficLightPlaceholderCluster"))
        XCTAssertFalse(sidebarHeaderSource.contains("standardWindowButton"))
        XCTAssertFalse(panelHostSource.contains("standardWindowButton"))

        Self.assertNoNativeTrafficLightReparenting(in: controlsSource, file: "BrowserWindowTrafficLights.swift")
        Self.assertNoNativeTrafficLightReparenting(in: windowSource, file: "SumiBrowserWindow.swift")
        Self.assertNoNativeTrafficLightReparenting(in: windowViewSource, file: "WindowView.swift")
        Self.assertNoNativeTrafficLightReparenting(in: sidebarHeaderSource, file: "SidebarHeader.swift")
        Self.assertNoNativeTrafficLightReparenting(in: panelHostSource, file: "CollapsedSidebarPanelHost.swift")
    }

    func testTrafficLightActionProviderRoutesToTargetBrowserWindow() {
        let window = TrackingTrafficLightWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 320, height: 240)),
            styleMask: SumiBrowserChromeConfiguration.requiredStyleMask,
            backing: .buffered,
            defer: false
        )
        let provider = BrowserWindowTrafficLightActionProvider.browserWindow(window)

        provider.perform(.close)
        provider.perform(.minimize)
        provider.perform(.zoom)

        XCTAssertTrue(window.didClose)
        XCTAssertTrue(window.didMiniaturize)
        XCTAssertTrue(window.didToggleFullScreen)
    }

    func testTrafficLightActionProviderUsesWindowStyleMaskAvailability() {
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

    func testTrafficLightActionProviderKeepsPaletteColoredWhenWindowIsNotKey() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 320, height: 240)),
            styleMask: SumiBrowserChromeConfiguration.requiredStyleMask,
            backing: .buffered,
            defer: false
        )
        let provider = BrowserWindowTrafficLightActionProvider.browserWindow(window)

        XCTAssertFalse(window.isKeyWindow)
        XCTAssertFalse(window.isMainWindow)
        XCTAssertTrue(provider.drawsActivePalette)
    }

    func testNativeBrowserButtonsAreHiddenWhileMiniWindowNativePathIsIsolated() throws {
        let windowSource = try Self.source(named: "Sumi/Components/Window/SumiBrowserWindow.swift")
        let bridgeSource = try Self.source(named: "App/BrowserWindowBridge.swift")
        let miniWindowToolbarSource = try Self.source(named: "Sumi/Components/MiniWindow/MiniWindowToolbar.swift")
        let miniWindowViewSource = try Self.source(
            named: "Sumi/Managers/ExternalMiniWindowManager/MiniBrowserWindowView.swift"
        )
        let miniWindowControllerSource = try Self.source(
            named: "Sumi/Managers/ExternalMiniWindowManager/ExternalMiniWindowManager.swift"
        )

        XCTAssertTrue(windowSource.contains("func hideNativeStandardWindowButtonsForBrowserChrome("))
        XCTAssertTrue(windowSource.contains("button.setAccessibilityElement(isVisible)"))
        XCTAssertTrue(windowSource.contains("button.setAccessibilityIdentifier(nil)"))
        XCTAssertTrue(windowSource.contains("button.identifier = nil"))
        XCTAssertFalse(windowSource.contains("parkedNativeStandardWindowButtonFrame"))
        XCTAssertFalse(windowSource.contains("prepareNativeStandardWindowButtonForSystemMiniaturize"))
        XCTAssertTrue(bridgeSource.contains("window.hideNativeStandardWindowButtonsForBrowserChrome()"))
        XCTAssertFalse(windowSource.contains("syncNativeStandardWindowButtonsForBrowserChrome"))
        XCTAssertFalse(windowSource.contains("setNativeStandardWindowButtonsForBrowserChromeVisible"))
        XCTAssertFalse(windowSource.contains("alignNativeStandardWindowButtonsForBrowserChrome"))
        XCTAssertFalse(bridgeSource.contains("setNativeStandardWindowButtonsForBrowserChromeVisible"))

        XCTAssertTrue(miniWindowToolbarSource.contains("BrowserWindowNativeTrafficLightSpacer()"))
        XCTAssertTrue(windowSource.contains("func configureNativeStandardWindowButtonsForMiniWindowChrome("))
        XCTAssertTrue(miniWindowControllerSource.contains("configureNativeStandardWindowButtonsForMiniWindowChrome()"))
        XCTAssertFalse(miniWindowToolbarSource.contains("BrowserWindowTrafficLights"))
        XCTAssertFalse(miniWindowToolbarSource.contains("standardWindowButton"))
        XCTAssertFalse(miniWindowViewSource.contains("window: window"))
    }

    func testNativeWindowControlsHostingFilesAndAssetsAreRemoved() {
        let removedFiles = [
            "Sumi/Components/Window/NativeWindowControlsSupport.swift",
            "Sumi/Components/Window/NativeWindowControlsVisualShield.swift",
            "Sumi/Components/MiniWindow/MiniWindowTrafficLights.swift",
            "SumiTests/MiniWindowTrafficLightsTests.swift",
            "Sumi/Assets.xcassets/WindowControls",
        ]

        for file in removedFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: Self.repoRoot.appendingPathComponent(file).path),
                "\(file) should not return with custom browser traffic lights."
            )
        }
    }

    func testCollapsedLeftPanelUsesSameCustomTrafficLightsAndSinglePanelGeometry() throws {
        let headerSource = try Self.source(named: "Navigation/Sidebar/SidebarHeader.swift")
        let panelHostSource = try Self.source(named: "Sumi/Components/Sidebar/CollapsedSidebarPanelHost.swift")
        let windowViewSource = try Self.source(named: "App/Window/WindowView.swift")

        XCTAssertTrue(headerSource.contains("BrowserWindowTrafficLights("))
        XCTAssertTrue(headerSource.contains(".browserWindow(windowState.window)"))
        XCTAssertTrue(panelHostSource.contains("CollapsedSidebarPanelFrameResolver.panelFrame("))
        XCTAssertTrue(panelHostSource.contains("width: width"))
        XCTAssertTrue(panelHostSource.contains("height: parentContentScreenFrame.height"))
        XCTAssertFalse(windowViewSource.contains("collapsedLeftSidebarPanelVisible"))
        XCTAssertFalse(windowViewSource.contains("!dockedLeftSidebarVisible && !collapsedLeftSidebarPanelVisible"))
        XCTAssertFalse(windowViewSource.contains("BrowserWindowTrafficLights("))

        XCTAssertFalse(panelHostSource.contains("TrafficLightReserved"))
        XCTAssertFalse(panelHostSource.contains("trafficLightReserved"))
        XCTAssertFalse(panelHostSource.range(of: #"split.*panel"#, options: .regularExpression) != nil)
        XCTAssertFalse(panelHostSource.range(of: #"accessory.*panel"#, options: .regularExpression) != nil)
        XCTAssertFalse(panelHostSource.contains("standardWindowButton"))
    }

    func testRightCollapsedSidebarUsesSameSidebarEmbeddedTrafficLights() throws {
        let headerSource = try Self.source(named: "Navigation/Sidebar/SidebarHeader.swift")
        let windowViewSource = try Self.source(named: "App/Window/WindowView.swift")

        XCTAssertTrue(headerSource.contains("BrowserWindowTrafficLights("))
        XCTAssertTrue(headerSource.contains("sidebarPresentationContext.mode != .collapsedHidden"))
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

    private static func assertNoNativeTrafficLightReparenting(
        in source: String,
        file: String,
        line: UInt = #line
    ) {
        let forbiddenPatterns = [
            #"\.addSubview\(\s*(button|closeButton|minimizeButton|miniaturizeButton|zoomButton)"#,
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

    private final class TrackingTrafficLightWindow: NSWindow {
        var didClose = false
        var didMiniaturize = false
        var didToggleFullScreen = false

        override func close() {
            didClose = true
        }

        override func miniaturize(_ sender: Any?) {
            didMiniaturize = true
        }

        override func toggleFullScreen(_ sender: Any?) {
            didToggleFullScreen = true
        }
    }
}
