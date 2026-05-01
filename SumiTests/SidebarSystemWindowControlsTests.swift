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

    func testNativeTrafficLightIdentifiersMapToSystemButtonTypes() {
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
            BrowserWindowControlsAccessibilityIdentifiers.allButtonIdentifiers,
            [
                BrowserWindowControlsAccessibilityIdentifiers.closeButton,
                BrowserWindowControlsAccessibilityIdentifiers.minimizeButton,
                BrowserWindowControlsAccessibilityIdentifiers.zoomButton,
            ]
        )
        XCTAssertEqual(
            BrowserWindowControlsAccessibilityIdentifiers.miniBrowserWindow,
            "mini-browser-window"
        )
    }

    func testNativeTrafficLightMetricsPreserveSidebarReservation() {
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
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.placeholderHorizontalOffset, -1)
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
        XCTAssertEqual(SidebarChromeMetrics.nativeTrafficLightHorizontalOffset, 9)
        XCTAssertEqual(SidebarChromeMetrics.nativeTrafficLightVerticalOffset, 5)
    }

    func testTrafficLightSourceUsesPlaceholderClusterAndNativeVisibilityBridgeWithoutReparenting() throws {
        let controlsSource = try Self.source(named: "Sumi/Components/Window/BrowserWindowTrafficLights.swift")
        let windowSource = try Self.source(named: "Sumi/Components/Window/SumiBrowserWindow.swift")
        let windowViewSource = try Self.source(named: "App/Window/WindowView.swift")
        let sidebarHeaderSource = try Self.source(named: "Navigation/Sidebar/SidebarHeader.swift")

        XCTAssertTrue(controlsSource.contains("final class BrowserWindowTrafficLightRenderState: ObservableObject"))
        XCTAssertTrue(controlsSource.contains("@Published var isNativeClusterVisible"))
        XCTAssertTrue(controlsSource.contains("enum BrowserWindowTrafficLightPlaceholderPalette"))
        XCTAssertTrue(controlsSource.contains("EC6A5E"))
        XCTAssertTrue(controlsSource.contains("F4BF4F"))
        XCTAssertTrue(controlsSource.contains("62C554"))
        XCTAssertTrue(controlsSource.contains("4E4F52"))
        XCTAssertTrue(controlsSource.contains("enum BrowserWindowTrafficLightProxyAction"))
        XCTAssertTrue(controlsSource.contains("struct BrowserWindowTrafficLightProxyCluster: View"))
        XCTAssertTrue(controlsSource.contains("parentWindow.performClose(nil)"))
        XCTAssertTrue(controlsSource.contains("parentWindow.miniaturize(nil)"))
        XCTAssertTrue(controlsSource.contains("parentWindow.performZoom(nil)"))
        XCTAssertTrue(controlsSource.contains("struct BrowserWindowTrafficLightPlaceholderCluster: View"))
        XCTAssertTrue(controlsSource.contains("struct BrowserWindowNativeTrafficLightVisibilityBridge: NSViewRepresentable"))
        XCTAssertTrue(controlsSource.contains("BrowserWindowTrafficLightMetrics"))
        XCTAssertTrue(controlsSource.contains("identifier(for buttonType: NSWindow.ButtonType)"))
        XCTAssertTrue(controlsSource.contains(".allowsHitTesting(false)"))
        XCTAssertTrue(controlsSource.contains(".accessibilityHidden(true)"))
        XCTAssertTrue(controlsSource.contains(".offset(x: BrowserWindowTrafficLightMetrics.placeholderHorizontalOffset)"))
        XCTAssertTrue(controlsSource.contains("renderState.isNativeClusterVisible == false"))
        XCTAssertTrue(controlsSource.contains("beginDelayedNativeReveal(delay:"))
        XCTAssertTrue(controlsSource.contains("showNativeButtonsIfRevealIsCurrent"))
        XCTAssertTrue(controlsSource.contains("isFinishingFullScreenExit"))
        XCTAssertTrue(controlsSource.contains("beginFullScreenExitPlaceholderGate()"))
        XCTAssertTrue(controlsSource.contains("fullScreenExitStabilizationDelay"))
        XCTAssertTrue(controlsSource.contains("fullScreenExitTransitionHideDuration"))
        XCTAssertTrue(controlsSource.contains("hiddenMaintenanceInterval"))
        XCTAssertTrue(controlsSource.contains("installFullScreenExitClickMonitor"))
        XCTAssertTrue(controlsSource.contains("NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown)"))
        XCTAssertTrue(controlsSource.contains("shouldConsumeFullScreenExitClick"))
        XCTAssertTrue(controlsSource.contains("window.toggleFullScreen(nil)"))
        XCTAssertTrue(controlsSource.contains("NSEvent.removeMonitor(fullScreenExitClickMonitor)"))
        XCTAssertTrue(controlsSource.contains("scheduleNativeButtonHiddenMaintenance"))
        XCTAssertTrue(controlsSource.contains("keepNativeButtonsHiddenIfTransitionIsCurrent"))
        XCTAssertTrue(controlsSource.contains("window.standardWindowButton(.zoomButton)"))
        XCTAssertTrue(controlsSource.contains("NSWindow.willEnterFullScreenNotification"))
        XCTAssertTrue(controlsSource.contains("NSWindow.willExitFullScreenNotification"))
        XCTAssertTrue(controlsSource.contains("NSWindow.didExitFullScreenNotification"))
        XCTAssertTrue(controlsSource.contains("hideNativeButtonsAndCancelReveal()"))
        XCTAssertTrue(controlsSource.contains("NSWindow.willStartLiveResizeNotification"))
        XCTAssertTrue(controlsSource.contains("NSWindow.didResizeNotification"))
        XCTAssertTrue(controlsSource.contains("NSWindow.didEndLiveResizeNotification"))
        XCTAssertTrue(controlsSource.contains("DispatchQueue.main.async"))
        XCTAssertTrue(controlsSource.contains("DispatchQueue.main.asyncAfter"))
        XCTAssertFalse(controlsSource.contains("struct BrowserWindowTrafficLights: View"))
        XCTAssertFalse(controlsSource.contains("BrowserWindowCustomTrafficLightsHost"))
        XCTAssertFalse(controlsSource.contains("BrowserWindowCustomTrafficLightsView"))
        XCTAssertFalse(controlsSource.contains("BrowserWindowTrafficLightButton"))
        XCTAssertFalse(controlsSource.contains("BrowserWindowTrafficLightVisualResolver"))
        XCTAssertFalse(controlsSource.contains("BrowserWindowTrafficLightActionRouter"))
        XCTAssertFalse(controlsSource.contains("BrowserWindowTrafficLightAvailability"))
        XCTAssertFalse(controlsSource.contains("NSTrackingArea"))
        XCTAssertFalse(controlsSource.contains("acceptsFirstMouse"))
        XCTAssertFalse(controlsSource.contains("mouseDownCanMoveWindow"))
        XCTAssertFalse(controlsSource.contains("hoverPollTimer"))
        XCTAssertFalse(controlsSource.contains("Timer(timeInterval"))
        XCTAssertFalse(controlsSource.contains("NSWindow.didMoveNotification"))
        XCTAssertFalse(controlsSource.contains("NSWindow.didChangeScreenNotification"))
        XCTAssertFalse(controlsSource.contains(".systemRed"))
        XCTAssertFalse(controlsSource.contains(".systemYellow"))
        XCTAssertFalse(controlsSource.contains(".systemGreen"))
        XCTAssertFalse(controlsSource.contains("traffic-light-zoom"))
        XCTAssertFalse(controlsSource.contains("NSPopover"))
        XCTAssertFalse(controlsSource.contains("NSHostingController"))

        XCTAssertTrue(windowSource.contains("guard let button = standardWindowButton(type)"))
        XCTAssertTrue(windowSource.contains("button.superview?.needsLayout = true"))
        XCTAssertTrue(windowViewSource.contains("BrowserWindowNativeTrafficLightVisibilityBridge("))
        XCTAssertTrue(windowViewSource.contains("collapsedLeftSidebarPanelVisible"))
        XCTAssertTrue(sidebarHeaderSource.contains("BrowserWindowTrafficLightPlaceholderCluster("))
        XCTAssertTrue(sidebarHeaderSource.contains("BrowserWindowTrafficLightProxyCluster("))
        XCTAssertTrue(sidebarHeaderSource.contains("sidebarPresentationContext.mode == .collapsedVisible"))
        XCTAssertFalse(windowSource.contains("SidebarSystemWindowControls"))
        XCTAssertFalse(windowViewSource.contains("SidebarSystemWindowControls"))
        XCTAssertFalse(sidebarHeaderSource.contains("SidebarSystemWindowControls"))
        Self.assertNoNativeTrafficLightReparenting(in: controlsSource, file: "BrowserWindowTrafficLights.swift")
        Self.assertNoNativeTrafficLightReparenting(in: windowSource, file: "SumiBrowserWindow.swift")
        Self.assertNoNativeTrafficLightReparenting(in: windowViewSource, file: "WindowView.swift")
        Self.assertNoNativeTrafficLightReparenting(in: sidebarHeaderSource, file: "SidebarHeader.swift")
    }

    func testPanelTrafficLightProxyActionsRouteToParentBrowserWindow() {
        let window = TrackingTrafficLightWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 320, height: 240)),
            styleMask: SumiBrowserChromeConfiguration.requiredStyleMask,
            backing: .buffered,
            defer: false
        )

        BrowserWindowTrafficLightProxyAction.close.perform(on: window)
        BrowserWindowTrafficLightProxyAction.minimize.perform(on: window)
        BrowserWindowTrafficLightProxyAction.zoom.perform(on: window)

        XCTAssertTrue(window.didPerformClose)
        XCTAssertTrue(window.didMiniaturize)
        XCTAssertTrue(window.didPerformZoom)
    }

    func testPanelTrafficLightProxyDoesNotReparentNativeButtonsIntoPanel() throws {
        let controlsSource = try Self.source(named: "Sumi/Components/Window/BrowserWindowTrafficLights.swift")
        let panelHostSource = try Self.source(named: "Sumi/Components/Sidebar/CollapsedSidebarPanelHost.swift")
        let sidebarHeaderSource = try Self.source(named: "Navigation/Sidebar/SidebarHeader.swift")

        XCTAssertTrue(controlsSource.contains("BrowserWindowTrafficLightProxyCluster"))
        XCTAssertTrue(sidebarHeaderSource.contains("BrowserWindowTrafficLightProxyCluster("))
        XCTAssertTrue(panelHostSource.contains("CollapsedSidebarPanelWindow"))
        XCTAssertFalse(panelHostSource.contains("standardWindowButton"))
        Self.assertNoNativeTrafficLightReparenting(in: controlsSource, file: "BrowserWindowTrafficLights.swift")
        Self.assertNoNativeTrafficLightReparenting(in: panelHostSource, file: "CollapsedSidebarPanelHost.swift")
        Self.assertNoNativeTrafficLightReparenting(in: sidebarHeaderSource, file: "SidebarHeader.swift")
    }

    func testWindowChromeUsesNativeButtonsWithoutCustomActionBridge() throws {
        let windowSource = try Self.source(named: "Sumi/Components/Window/SumiBrowserWindow.swift")
        let bridgeSource = try Self.source(named: "App/BrowserWindowBridge.swift")

        XCTAssertTrue(windowSource.contains("configureNativeStandardWindowButtonsForBrowserChrome()"))
        XCTAssertTrue(windowSource.contains("func configureNativeStandardWindowButtonsForBrowserChrome("))
        XCTAssertTrue(windowSource.contains("func syncNativeStandardWindowButtonsForBrowserChrome("))
        XCTAssertTrue(windowSource.contains("func setNativeStandardWindowButtonsForBrowserChromeVisible("))
        XCTAssertTrue(windowSource.contains("guard isVisible else"))
        XCTAssertTrue(windowSource.contains("captureNativeStandardWindowButtonBaseFramesIfNeeded"))
        XCTAssertTrue(windowSource.contains("applyNativeStandardWindowButtonState(button, isVisible: false)"))
        XCTAssertTrue(windowSource.contains("parkedNativeStandardWindowButtonFrame"))
        XCTAssertTrue(windowSource.contains("func alignNativeStandardWindowButtonsForBrowserChrome("))
        XCTAssertTrue(windowSource.contains("standardWindowButton(type)"))
        XCTAssertTrue(windowSource.contains("styleMask.contains(.fullScreen) || visibleOutsideFullScreen"))
        XCTAssertTrue(windowSource.contains("alignedFrame.origin.x += horizontalOffset"))
        XCTAssertTrue(windowSource.contains("button.superview?.isFlipped == true"))
        XCTAssertTrue(windowSource.contains("alignedFrame.origin.y += verticalOffset"))
        XCTAssertTrue(windowSource.contains("alignedFrame.origin.y -= verticalOffset"))
        XCTAssertTrue(windowSource.contains("button.isHidden = !isVisible"))
        XCTAssertTrue(windowSource.contains("button.alphaValue = isVisible ? 1 : 0"))
        XCTAssertTrue(windowSource.contains("button.isEnabled = isVisible"))
        XCTAssertTrue(windowSource.contains("button.wantsLayer = true"))
        XCTAssertTrue(windowSource.contains("button.layer?.opacity = isVisible ? 1 : 0"))
        XCTAssertTrue(windowSource.contains("button.isTransparent = !isVisible"))
        XCTAssertTrue(windowSource.contains("button.setAccessibilityElement(isVisible)"))
        XCTAssertTrue(windowSource.contains("button.setAccessibilityIdentifier(identifier)"))
        XCTAssertTrue(windowSource.contains("button.updateTrackingAreas()"))
        XCTAssertTrue(windowSource.contains("superview.updateTrackingAreas()"))
        XCTAssertTrue(windowSource.contains("invalidateCursorRects(for: superview)"))
        XCTAssertTrue(windowSource.contains("button.needsDisplay = true"))
        XCTAssertFalse(windowSource.contains("func performSumiTrafficLightAction("))
        XCTAssertFalse(windowSource.contains("hideStandardWindowButtonsForCustomChrome"))
        XCTAssertFalse(windowSource.contains("showStandardWindowButtonsForSystemFullScreenChrome"))
        XCTAssertFalse(windowSource.contains("updateStandardWindowButtonsForBrowserChromeState"))
        XCTAssertFalse(windowSource.contains("SumiBrowserChromeFullscreenObserverBag"))
        XCTAssertFalse(windowSource.contains("object_setClass(window, SumiBrowserWindow.self)"))
        XCTAssertFalse(windowSource.contains("SumiBrowserWindowToolbar"))
        XCTAssertTrue(bridgeSource.contains("window.setNativeStandardWindowButtonsForBrowserChromeVisible("))
        XCTAssertTrue(bridgeSource.contains("false,"))
        XCTAssertTrue(bridgeSource.contains("horizontalOffset: SidebarChromeMetrics.nativeTrafficLightHorizontalOffset"))
        XCTAssertTrue(bridgeSource.contains("verticalOffset: SidebarChromeMetrics.nativeTrafficLightVerticalOffset"))
    }

    func testBrowserWindowTrafficLightSpacerBelongsToSidebarHeader() throws {
        let windowSource = try Self.source(named: "App/Window/WindowView.swift")
        let sidebarHeaderSource = try Self.source(named: "Navigation/Sidebar/SidebarHeader.swift")
        let sidebarSource = try Self.source(named: "Navigation/Sidebar/SpacesSideBarView.swift")

        XCTAssertFalse(windowSource.contains("BrowserWindowTrafficLights("))
        XCTAssertTrue(windowSource.contains("BrowserWindowNativeTrafficLightVisibilityBridge("))
        XCTAssertTrue(windowSource.contains("@StateObject private var trafficLightRenderState"))
        XCTAssertTrue(windowSource.contains("renderState: trafficLightRenderState"))
        XCTAssertTrue(windowSource.contains("revealDelay: nativeTrafficLightsRevealDelay"))
        XCTAssertTrue(windowSource.contains("nativeTrafficLightsVisibleOutsideFullScreen"))
        XCTAssertTrue(windowSource.contains("horizontalOffset: SidebarChromeMetrics.nativeTrafficLightHorizontalOffset"))
        XCTAssertTrue(windowSource.contains("verticalOffset: SidebarChromeMetrics.nativeTrafficLightVerticalOffset"))
        XCTAssertTrue(windowSource.contains("SidebarHoverOverlayRevealPolicy.isOverlayRevealed"))
        XCTAssertTrue(sidebarHeaderSource.contains("BrowserWindowTrafficLightPlaceholderCluster("))
        XCTAssertTrue(sidebarHeaderSource.contains("@EnvironmentObject private var trafficLightRenderState"))
        XCTAssertTrue(sidebarHeaderSource.contains("sumiSettings.sidebarPosition.shellEdge.isLeft"))
        XCTAssertFalse(sidebarHeaderSource.contains("BrowserWindowTrafficLights("))
        XCTAssertFalse(sidebarHeaderSource.contains("standardWindowButton"))
        XCTAssertFalse(sidebarHeaderSource.contains("sidebarPresentationContext.mode != .collapsedHidden"))
        XCTAssertTrue(sidebarSource.contains(".padding(.top, SidebarChromeMetrics.topControlInset)"))
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
                "\(file) should not return with custom traffic lights."
            )
        }
    }

    func testMiniWindowUsesNativeButtonsWithSpacer() throws {
        let miniWindowToolbarSource = try Self.source(named: "Sumi/Components/MiniWindow/MiniWindowToolbar.swift")
        let miniWindowViewSource = try Self.source(
            named: "Sumi/Managers/ExternalMiniWindowManager/MiniBrowserWindowView.swift"
        )
        let miniWindowControllerSource = try Self.source(
            named: "Sumi/Managers/ExternalMiniWindowManager/ExternalMiniWindowManager.swift"
        )

        XCTAssertTrue(miniWindowToolbarSource.contains("BrowserWindowNativeTrafficLightSpacer()"))
        XCTAssertFalse(miniWindowToolbarSource.contains("BrowserWindowTrafficLights"))
        XCTAssertFalse(miniWindowToolbarSource.contains("standardWindowButton"))
        XCTAssertFalse(miniWindowViewSource.contains("window: window"))
        XCTAssertFalse(miniWindowControllerSource.contains("NSTitlebarAccessoryViewController"))
        XCTAssertTrue(
            miniWindowControllerSource.contains("BrowserWindowControlsAccessibilityIdentifiers.miniBrowserWindow")
        )
        XCTAssertTrue(miniWindowControllerSource.contains("configureNativeStandardWindowButtonsForBrowserChrome()"))
        XCTAssertFalse(miniWindowControllerSource.contains("hideStandardWindowButtonsForCustomChrome()"))
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
        var didPerformClose = false
        var didMiniaturize = false
        var didPerformZoom = false

        override func performClose(_ sender: Any?) {
            didPerformClose = true
        }

        override func miniaturize(_ sender: Any?) {
            didMiniaturize = true
        }

        override func performZoom(_ sender: Any?) {
            didPerformZoom = true
        }
    }
}
