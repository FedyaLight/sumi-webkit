import AppKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserWindowChromeTests: XCTestCase {
    func testBrowserChromeGeometryDefaultsPreserveViewportCornerMetrics() {
        let geometry = BrowserChromeGeometry()
        let expectedMetrics = BrowserChromeGeometry.CornerMetrics.default

        XCTAssertEqual(BrowserChromeGeometry.defaultOuterRadius, expectedMetrics.defaultOuterRadius)
        XCTAssertEqual(BrowserChromeGeometry.elementSeparation, expectedMetrics.elementSeparation)
        XCTAssertEqual(BrowserChromeGeometry.minimumContentRadius, expectedMetrics.minimumContentRadius)
        XCTAssertEqual(geometry.outerRadius, expectedMetrics.defaultOuterRadius)
        XCTAssertEqual(geometry.elementSeparation, expectedMetrics.elementSeparation)
        XCTAssertEqual(
            geometry.contentRadius,
            expectedMetrics.contentRadius(
                outerRadius: expectedMetrics.defaultOuterRadius,
                elementSeparation: expectedMetrics.elementSeparation
            )
        )
    }

    func testBrowserChromeGeometrySequoiaFallbackPreservesViewportCornerMetrics() {
        let metrics = BrowserChromeGeometry.CornerMetrics.platformDefault(isMacOSTahoeOrNewer: false)
        let geometry = BrowserChromeGeometry(
            outerRadius: metrics.defaultOuterRadius,
            elementSeparation: metrics.elementSeparation,
            cornerMetrics: metrics
        )

        XCTAssertEqual(metrics.defaultOuterRadius, 7)
        XCTAssertEqual(metrics.elementSeparation, 8)
        XCTAssertEqual(metrics.minimumContentRadius, 5)
        XCTAssertEqual(geometry.outerRadius, 7)
        XCTAssertEqual(geometry.elementSeparation, 8)
        XCTAssertEqual(geometry.contentRadius, 5)
    }

    func testBrowserChromeGeometryTahoeFallbackUsesConservativeViewportCornerMetrics() {
        let metrics = BrowserChromeGeometry.CornerMetrics.platformDefault(isMacOSTahoeOrNewer: true)
        let geometry = BrowserChromeGeometry(
            outerRadius: metrics.defaultOuterRadius,
            elementSeparation: metrics.elementSeparation,
            cornerMetrics: metrics
        )

        XCTAssertEqual(metrics.defaultOuterRadius, 14)
        XCTAssertEqual(metrics.elementSeparation, 8)
        XCTAssertEqual(metrics.minimumContentRadius, 5)
        XCTAssertEqual(geometry.outerRadius, 14)
        XCTAssertEqual(geometry.elementSeparation, 8)
        XCTAssertEqual(geometry.contentRadius, 10)
    }

    func testBrowserChromeGeometryDerivesContentRadiusFromOuterRadiusAndSeparation() {
        let geometry = BrowserChromeGeometry(outerRadius: 14)

        XCTAssertEqual(geometry.outerRadius, 14)
        XCTAssertEqual(geometry.elementSeparation, 8)
        XCTAssertEqual(geometry.contentRadius, 10)
    }

    func testBrowserChromeGeometryClampsContentRadiusToMinimum() {
        let geometry = BrowserChromeGeometry(outerRadius: 2)

        XCTAssertEqual(geometry.outerRadius, 2)
        XCTAssertEqual(geometry.contentRadius, 5)
    }

    func testBrowserChromeGeometrySettingsUseDefaultOuterRadiusForSentinelBorderRadius() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        settings.themeBorderRadius = -1
        let geometry = BrowserChromeGeometry(settings: settings)
        let expectedMetrics = BrowserChromeGeometry.CornerMetrics.default

        XCTAssertEqual(geometry.outerRadius, expectedMetrics.defaultOuterRadius)
        XCTAssertEqual(
            geometry.contentRadius,
            expectedMetrics.contentRadius(
                outerRadius: expectedMetrics.defaultOuterRadius,
                elementSeparation: expectedMetrics.elementSeparation
            )
        )
    }

    func testBrowserChromeGeometrySettingsUseCustomBorderRadiusAsOuterRadius() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        settings.themeBorderRadius = 18
        let geometry = BrowserChromeGeometry(settings: settings)

        XCTAssertEqual(geometry.outerRadius, 18)
        XCTAssertEqual(geometry.contentRadius, 14)
    }

    func testBrowserChromeGeometryCustomBorderRadiusOverridesTahoePlatformDefault() {
        let metrics = BrowserChromeGeometry.CornerMetrics.platformDefault(isMacOSTahoeOrNewer: true)
        let customOuterRadius = metrics.outerRadius(themeBorderRadius: 18)
        let geometry = BrowserChromeGeometry(
            outerRadius: customOuterRadius,
            elementSeparation: metrics.elementSeparation,
            cornerMetrics: metrics
        )

        XCTAssertEqual(customOuterRadius, 18)
        XCTAssertEqual(geometry.outerRadius, 18)
        XCTAssertEqual(geometry.elementSeparation, 8)
        XCTAssertEqual(geometry.contentRadius, 14)
    }

    private func assertMinimumWindowConstraints(
        _ window: NSWindow,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(window.minSize, window.contentMinSize, file: file, line: line)
        XCTAssertEqual(
            window.minSize.width,
            SumiBrowserWindowShellConfiguration.minimumContentSize.width,
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            window.minSize.height,
            SumiBrowserWindowShellConfiguration.minimumContentSize.height,
            file: file,
            line: line
        )
    }

    func testSumiBrowserWindowInitAppliesBrowserChromeConfiguration() {
        let window = WindowChromeTestSupport.makeBrowserWindow()

        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        XCTAssertNil(window.toolbar)
        XCTAssertEqual(window.backgroundColor, SumiBrowserWindowShellConfiguration.backgroundColor)
        XCTAssertFalse(window.isOpaque)
        assertMinimumWindowConstraints(window)
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertTrue(window.isMovable)
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenPrimary))
        assertNativeBrowserControlsHidden(window)
    }

    func testBrowserWindowBridgeViewAttachPromotesWindowSynchronouslyOnAttach() {
        let window = WindowChromeTestSupport.makePlainWindow()
        let windowState = BrowserWindowState()
        let windowRegistry = WindowRegistry()
        let coordinator = BrowserWindowBridge.Coordinator(
            windowState: windowState,
            windowRegistry: windowRegistry
        )
        let bridgeView = BrowserWindowBridgeView(frame: .zero)

        bridgeView.coordinator = coordinator
        window.contentView?.addSubview(bridgeView)
        WindowChromeTestSupport.retain(window)

        XCTAssertFalse(window is SumiBrowserWindow)
        XCTAssertTrue(windowState.window === window)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        XCTAssertNil(window.toolbar)
        XCTAssertEqual(window.backgroundColor, SumiBrowserWindowShellConfiguration.backgroundColor)
        XCTAssertFalse(window.isOpaque)
        assertMinimumWindowConstraints(window)
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertTrue(window.isMovable)
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenPrimary))
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, SumiBrowserWindowShellConfiguration.defaultContentSize)
        assertNativeBrowserControlsHidden(window)
    }

    func testBrowserWindowBridgeCoordinatorDetachClearsWindowState() {
        let window = WindowChromeTestSupport.makePlainWindow()
        let windowState = BrowserWindowState()
        let windowRegistry = WindowRegistry()
        let coordinator = BrowserWindowBridge.Coordinator(
            windowState: windowState,
            windowRegistry: windowRegistry
        )

        coordinator.attach(to: window)
        WindowChromeTestSupport.retain(window)
        XCTAssertTrue(windowState.window === window)

        coordinator.detach()

        XCTAssertNil(windowState.window)
    }

    func testPromoteToSumiBrowserWindowIfNeededAppliesBrowserChromeConfiguration() {
        let window = WindowChromeTestSupport.makePlainWindow()

        promoteToSumiBrowserWindowIfNeeded(window)
        WindowChromeTestSupport.retain(window)

        XCTAssertFalse(window is SumiBrowserWindow)
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        XCTAssertNil(window.toolbar)
        XCTAssertEqual(window.backgroundColor, SumiBrowserWindowShellConfiguration.backgroundColor)
        XCTAssertFalse(window.isOpaque)
        assertMinimumWindowConstraints(window)
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenPrimary))
        assertNativeBrowserControlsHidden(window)
    }

    func testBrowserChromeHideNativeControlsClearsAccessibilityAcrossModeChanges() {
        let window = WindowChromeTestSupport.makeBrowserWindow()

        window.configureNativeStandardWindowButtonsForMiniWindowChrome()
        assertMiniWindowNativeControlsVisible(window)

        window.hideNativeStandardWindowButtonsForBrowserChrome()
        assertNativeBrowserControlsHidden(window)

        window.miniaturizeFromCustomBrowserChrome()
        assertNativeBrowserControlsHidden(window)
    }

    func testMiniWindowNativeControlConfigurationRemainsVisibleAndIdentified() {
        let window = WindowChromeTestSupport.makePlainWindow()

        window.configureNativeStandardWindowButtonsForMiniWindowChrome()

        assertMiniWindowNativeControlsVisible(window)
    }

    func testMainWindowSceneUsesHiddenTitlebarStyle() throws {
        let appSource = try Self.source(named: "App/SumiApp.swift")

        XCTAssertTrue(appSource.contains(".windowStyle(.hiddenTitleBar)"))
    }

    private func assertNativeBrowserControlsHidden(
        _ window: NSWindow,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type) else {
                XCTFail("Expected standard window button for \(type).", file: file, line: line)
                return
            }

            XCTAssertTrue(button.isHidden, file: file, line: line)
            XCTAssertEqual(button.alphaValue, 0, file: file, line: line)
            XCTAssertFalse(button.isEnabled, file: file, line: line)
            XCTAssertFalse(button.isAccessibilityElement(), file: file, line: line)
            XCTAssertTrue(button.identifier?.rawValue.isEmpty ?? true, file: file, line: line)
            XCTAssertTrue(button.accessibilityIdentifier().isEmpty, file: file, line: line)
        }
    }

    private func assertMiniWindowNativeControlsVisible(
        _ window: NSWindow,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type) else {
                XCTFail("Expected standard window button for \(type).", file: file, line: line)
                return
            }

            XCTAssertFalse(button.isHidden, file: file, line: line)
            XCTAssertEqual(button.alphaValue, 1, file: file, line: line)
            XCTAssertTrue(button.isEnabled, file: file, line: line)
            XCTAssertTrue(button.isAccessibilityElement(), file: file, line: line)
            XCTAssertEqual(
                button.identifier?.rawValue,
                BrowserWindowControlsAccessibilityIdentifiers.identifier(for: type),
                file: file,
                line: line
            )
            XCTAssertEqual(
                button.accessibilityIdentifier(),
                BrowserWindowControlsAccessibilityIdentifiers.identifier(for: type),
                file: file,
                line: line
            )
        }
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
}
