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

    func testBrowserChromeGeometryDefaultsExposeUniformInsetsAndCornerRadii() {
        let geometry = BrowserChromeGeometry()
        let separation = geometry.elementSeparation

        XCTAssertEqual(geometry.contentEdgeInsets, .uniform(separation))
        XCTAssertEqual(geometry.contentCornerRadii, .uniform(geometry.contentRadius))
        XCTAssertTrue(geometry.contentCornerRadii.isUniform)
    }

    func testBrowserChromeGeometrySettingsKeepUniformChromeWhenFramelessDisabled() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        settings.framelessChrome = false
        let geometry = BrowserChromeGeometry(settings: settings)

        let separation = geometry.elementSeparation
        XCTAssertEqual(geometry.contentEdgeInsets, .uniform(separation))
        XCTAssertEqual(geometry.contentCornerRadii, .uniform(geometry.contentRadius))
        XCTAssertTrue(geometry.contentCornerRadii.isUniform)
        XCTAssertEqual(geometry.contentCornerRadii.bottomLeading, geometry.contentRadius)
        XCTAssertEqual(geometry.contentCornerRadii.bottomTrailing, geometry.contentRadius)
    }

    func testBrowserChromeGeometrySettingsUseTopOnlyChromeWhenFramelessEnabled() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        settings.framelessChrome = true
        let geometry = BrowserChromeGeometry(settings: settings)

        let separation = geometry.elementSeparation
        // Only the top inset survives; sides and bottom are flush.
        XCTAssertEqual(geometry.contentEdgeInsets, .topOnly(separation))
        XCTAssertEqual(geometry.contentEdgeInsets.top, separation)
        XCTAssertEqual(geometry.contentEdgeInsets.bottom, 0)
        XCTAssertEqual(geometry.contentEdgeInsets.leading, 0)
        XCTAssertEqual(geometry.contentEdgeInsets.trailing, 0)
        // Only top corners are rounded; bottom corners are square.
        XCTAssertEqual(geometry.contentCornerRadii, .topOnly(geometry.contentRadius))
        XCTAssertEqual(geometry.contentCornerRadii.topLeading, geometry.contentRadius)
        XCTAssertEqual(geometry.contentCornerRadii.topTrailing, geometry.contentRadius)
        XCTAssertEqual(geometry.contentCornerRadii.bottomLeading, 0)
        XCTAssertEqual(geometry.contentCornerRadii.bottomTrailing, 0)
        // Legacy uniform `contentRadius` is preserved for existing consumers.
        XCTAssertEqual(geometry.contentRadius, geometry.contentCornerRadii.maxRadius)
    }

    func testChromeCornerRadiiMapsToTopOnlyAppKitCornerMask() {
        let radii = ChromeCornerRadii.topOnly(10)
        let mask = radii.caCornerMask

        XCTAssertTrue(mask.contains(.layerMinXMaxYCorner))
        XCTAssertTrue(mask.contains(.layerMaxXMaxYCorner))
        XCTAssertFalse(mask.contains(.layerMinXMinYCorner))
        XCTAssertFalse(mask.contains(.layerMaxXMinYCorner))
    }

    func testChromeCornerRadiiUniformMaskCoversAllCorners() {
        let mask = ChromeCornerRadii.uniform(10).caCornerMask

        XCTAssertTrue(mask.contains(.layerMinXMaxYCorner))
        XCTAssertTrue(mask.contains(.layerMaxXMaxYCorner))
        XCTAssertTrue(mask.contains(.layerMinXMinYCorner))
        XCTAssertTrue(mask.contains(.layerMaxXMinYCorner))
    }

    func testChromeCornerRadiiZeroRadiusProducesEmptyMask() {
        XCTAssertTrue(ChromeCornerRadii.uniform(0).caCornerMask.isEmpty)
        XCTAssertTrue(ChromeCornerRadii.topOnly(0).caCornerMask.isEmpty)
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
        XCTAssertIdentical(windowRegistry.appKitWindow(for: windowState), window)
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
        XCTAssertIdentical(windowRegistry.appKitWindow(for: windowState), window)

        coordinator.detach()

        XCTAssertNil(windowRegistry.appKitWindow(for: windowState))
    }

    func testBrowserWindowBridgeCoordinatorUnregistersWindowOnWillCloseNotification() {
        let window = WindowChromeTestSupport.makePlainWindow()
        let windowState = BrowserWindowState()
        let windowRegistry = WindowRegistry()
        var closedWindowIds: [UUID] = []
        let coordinator = BrowserWindowBridge.Coordinator(
            windowState: windowState,
            windowRegistry: windowRegistry
        )

        installWindowRegistryTestEventSink(
            on: windowRegistry,
            closeWindow: { closedWindowIds.append($0.id) }
        )
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        coordinator.attach(to: window)
        WindowChromeTestSupport.retain(window)

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)

        XCTAssertEqual(closedWindowIds, [windowState.id])
        XCTAssertNil(windowRegistry.windows[windowState.id])
        XCTAssertNil(windowRegistry.activeWindowId)
        XCTAssertNil(windowRegistry.appKitWindow(for: windowState))
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

    func testBrowserChromePerformCloseWorksWhileNativeControlsAreHidden() {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let willClose = expectation(description: "Browser chrome close posts will-close notification.")
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            willClose.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        assertNativeBrowserControlsHidden(window)
        window.performCloseFromBrowserChrome(nil)

        wait(for: [willClose], timeout: 0.2)
    }

    func testBrowserChromePerformCloseRespectsWindowShouldCloseWhileNativeControlsAreHidden() {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let delegate = WindowShouldCloseDelegate(shouldClose: false)
        let willClose = expectation(description: "Browser chrome close should not post will-close notification.")
        willClose.isInverted = true
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            willClose.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        window.delegate = delegate

        assertNativeBrowserControlsHidden(window)
        window.performCloseFromBrowserChrome(nil)

        XCTAssertEqual(delegate.windowShouldCloseCount, 1)
        wait(for: [willClose], timeout: 0.1)
    }

    func testContentViewCanBeConstructedWithWindowLifecycleHandlerProtocol() {
        let handler = FakeWindowLifecycleHandler()
        let lifecycleHandler: any BrowserWindowLifecycleHandling = handler
        let browserManager = BrowserManager()
        let updaterService = SumiUpdaterService(backendFactory: { _ in nil })

        let contentView = ContentView(
            windowLifecycleHandler: lifecycleHandler,
            webContentContext: .make(
                browserManager: browserManager,
                updaterService: updaterService,
                defaultBrowserService: SumiDefaultBrowserService()
            ),
            sidebarContext: .make(
                browserManager: browserManager,
                updaterService: updaterService
            ),
            floatingBarContext: browserManager.urlBarBundle.floatingBar.browserContext.context,
            nativeModalContext: .make(browserManager: browserManager),
            findContext: .make(browserManager: browserManager),
            splitContext: .make(browserManager: browserManager),
            themeChromeContext: .make(browserManager: browserManager),
            initialWorkspaceTheme: .default
        )

        withExtendedLifetime(browserManager) {
            XCTAssertTrue(type(of: contentView) == ContentView.self)
            XCTAssertTrue(handler.persistedWindowIds.isEmpty)
        }
    }

    func testWindowFeatureContextsReadLiveStateThroughExactRoleServices() {
        let browserManager = BrowserManager()
        let themeContext = WindowThemeChromeContext.make(browserManager: browserManager)
        let nativeModalContext = WindowNativeModalContext.make(browserManager: browserManager)

        XCTAssertFalse(themeContext.hasCurrentSpace)
        XCTAssertNil(nativeModalContext.presentation)

        let space = Space(name: "Live window context")
        browserManager.spaceStateOwner.replaceSpaces([space])
        browserManager.spaceStateOwner.replaceCurrentSpace(space)

        let presentation = BrowserNativeModalPresentation(
            windowID: UUID(),
            window: nil,
            kind: .browsingData,
            source: nil,
            transientSessionToken: nil
        )
        browserManager.nativeModalPresentationState.replace(with: presentation)

        XCTAssertTrue(themeContext.hasCurrentSpace)
        XCTAssertEqual(
            themeContext.workspaceTheme(for: space.id),
            space.workspaceTheme
        )
        XCTAssertIdentical(nativeModalContext.presentation, presentation)
        XCTAssertTrue(nativeModalContext.isPresented(in: presentation.windowID))

        browserManager.spaceStateOwner.replaceCurrentSpace(nil)
        browserManager.nativeModalPresentationState.replace(with: nil)

        XCTAssertFalse(themeContext.hasCurrentSpace)
        XCTAssertNil(nativeModalContext.presentation)
    }

    func testSplitPaneControlsOnlyHitTestWhenVisible() {
        let controls = SplitPaneControlsView(frame: NSRect(x: 0, y: 0, width: 64, height: 26))

        XCTAssertNil(controls.hitTest(NSPoint(x: 8, y: 8)))

        controls.setVisible(true, animated: false)
        XCTAssertNotNil(controls.hitTest(NSPoint(x: 8, y: 8)))

        controls.setVisible(false, animated: false)
        XCTAssertNil(controls.hitTest(NSPoint(x: 8, y: 8)))
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
            XCTAssertFalse(button.isTransparent, file: file, line: line)
            XCTAssertFalse(button.isEnabled, file: file, line: line)
            XCTAssertFalse(button.isAccessibilityElement(), file: file, line: line)
            XCTAssertTrue(button.isAccessibilityHidden(), file: file, line: line)
            XCTAssertTrue(button.identifier?.rawValue.isEmpty ?? true, file: file, line: line)
            XCTAssertTrue(button.accessibilityIdentifier().isEmpty, file: file, line: line)
        }
    }
}

@MainActor
private final class WindowShouldCloseDelegate: NSObject, NSWindowDelegate {
    private let shouldClose: Bool
    private(set) var windowShouldCloseCount = 0

    init(shouldClose: Bool) {
        self.shouldClose = shouldClose
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        windowShouldCloseCount += 1
        return shouldClose
    }
}

@MainActor
private final class FakeWindowLifecycleHandler: BrowserWindowLifecycleHandling {
    private(set) var persistedWindowIds: [UUID] = []

    func persistWindowSession(for windowState: BrowserWindowState) {
        persistedWindowIds.append(windowState.id)
    }
}
