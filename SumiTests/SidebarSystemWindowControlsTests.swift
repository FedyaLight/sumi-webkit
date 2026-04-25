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
        XCTAssertTrue(docked.showsResizeHandle)
        XCTAssertFalse(docked.isCollapsedOverlay)

        XCTAssertEqual(hidden.mode, .collapsedHidden)
        XCTAssertEqual(hidden.sidebarWidth, 280)
        XCTAssertFalse(hidden.showsResizeHandle)
        XCTAssertTrue(hidden.isCollapsedOverlay)

        XCTAssertEqual(visible.mode, .collapsedVisible)
        XCTAssertEqual(visible.sidebarWidth, 280)
        XCTAssertFalse(visible.showsResizeHandle)
        XCTAssertTrue(visible.isCollapsedOverlay)
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

    func testSidebarWindowControlsPlacementUsesSidebarHostAcrossWindowedSidebarModes() {
        XCTAssertEqual(
            SidebarWindowControlsPlacement.resolve(
                presentationMode: .docked,
                isFullScreen: false
            ),
            .sidebar
        )
        XCTAssertEqual(
            SidebarWindowControlsPlacement.resolve(
                presentationMode: .collapsedVisible,
                isFullScreen: false
            ),
            .sidebar
        )
        XCTAssertEqual(
            SidebarWindowControlsPlacement.resolve(
                presentationMode: .collapsedHidden,
                isFullScreen: false
            ),
            .sidebar
        )
        XCTAssertEqual(
            SidebarWindowControlsPlacement.resolve(
                presentationMode: .docked,
                isFullScreen: true
            ),
            .titlebar
        )
    }

    func testSidebarSystemWindowControlsContainerUsesFallbackEmbeddedWidthBeforeAttachingToWindow() {
        let host = SidebarSystemWindowControlsContainerView(frame: .zero)
        host.presentationMode = .docked

        XCTAssertEqual(
            host.intrinsicContentSize.width,
            ceil(NativeWindowControlsMetrics.fallbackHostedSize.width)
        )
        XCTAssertEqual(host.intrinsicContentSize.height, SidebarChromeMetrics.controlStripHeight)

        host.presentationMode = .collapsedHidden
        XCTAssertEqual(
            host.intrinsicContentSize.width,
            ceil(NativeWindowControlsMetrics.fallbackHostedSize.width)
        )
        XCTAssertEqual(host.intrinsicContentSize.height, SidebarChromeMetrics.controlStripHeight)
    }

    func testSidebarSystemWindowControlsContainerWaitsForBrowserChromeBeforeClaimingButtons() {
        let window = WindowChromeTestSupport.makePlainWindow()
        let host = makeHost()
        let nativeTitlebarView = window.standardWindowButton(.closeButton)?.superview

        host.presentationMode = .docked
        window.contentView?.addSubview(host)

        XCTAssertEqual(host.currentPlacement, .sidebar)
        XCTAssertTrue(host.subviews.isEmpty)
        XCTAssertEqual(
            host.intrinsicContentSize.width,
            ceil(NativeWindowControlsMetrics.fallbackHostedSize.width)
        )
        for type in WindowChromeTestSupport.standardButtonTypes {
            XCTAssertTrue(window.standardWindowButton(type)?.superview === nativeTitlebarView)
        }

        promoteToSumiBrowserWindowIfNeeded(window)
        WindowChromeTestSupport.retain(window)
        host.setPreferredWindowReference(window)
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(host.currentPlacement, .sidebar)
        XCTAssertEqual(host.intrinsicContentSize.width, expectedHostedWidth(for: window))
        XCTAssertEqual(host.intrinsicContentSize.height, SidebarChromeMetrics.controlStripHeight)
        assertButtonsHosted(in: host, window: window)
    }

    func testSidebarSystemWindowControlsContainerKeepsCompactHiddenSidebarInSameHostedPath() {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let host = makeHost()

        window.contentView?.addSubview(host)
        host.presentationMode = .collapsedHidden
        host.syncWindowReference(window)
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(host.currentPlacement, .sidebar)
        XCTAssertEqual(host.intrinsicContentSize.width, expectedHostedWidth(for: window))
        XCTAssertEqual(host.intrinsicContentSize.height, SidebarChromeMetrics.controlStripHeight)
        assertButtonsHosted(in: host, window: window)
    }

    func testSidebarSystemWindowControlsContainerUsesButtonGroupWidthAndLeadingInsetForEmbeddedAlignment() {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let host = makeHost()

        window.contentView?.addSubview(host)
        host.presentationMode = .docked
        host.syncWindowReference(window)
        host.layoutSubtreeIfNeeded()

        let metrics = window.nativeWindowControlsMetrics()

        XCTAssertEqual(host.currentPlacement, .sidebar)
        XCTAssertEqual(host.intrinsicContentSize.width, expectedHostedWidth(for: window))
        XCTAssertLessThan(
            host.intrinsicContentSize.width,
            ceil(metrics?.buttonGroupRect.maxX ?? 0)
        )
    }

    func testSidebarSystemWindowControlsContainerTeardownRestoresButtonsToTitlebar() {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let host = makeHost()
        let nativeTitlebarView = window.titlebarView

        window.contentView?.addSubview(host)
        host.presentationMode = .collapsedVisible
        host.syncWindowReference(window)
        host.layoutSubtreeIfNeeded()
        host.prepareForRemoval()

        XCTAssertEqual(host.currentPlacement, .titlebar)
        for type in WindowChromeTestSupport.standardButtonTypes {
            XCTAssertTrue(window.standardWindowButton(type)?.superview === nativeTitlebarView)
        }
    }

    func testSidebarSystemWindowControlsContainerTeardownDuringWindowCloseKeepsButtonsHosted() {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let host = makeHost()
        let nativeTitlebarView = window.titlebarView

        window.contentView?.addSubview(host)
        host.presentationMode = .collapsedVisible
        host.syncWindowReference(window)
        host.layoutSubtreeIfNeeded()
        window.prepareNativeWindowControlsForBrowserChromeWindowTeardown()
        host.prepareForRemoval()

        XCTAssertEqual(host.currentPlacement, .titlebar)
        XCTAssertTrue(window.isBrowserChromeNativeWindowControlsTeardownInProgress)
        for type in WindowChromeTestSupport.standardButtonTypes {
            XCTAssertTrue(window.standardWindowButton(type)?.superview === host)
            XCTAssertFalse(window.standardWindowButton(type)?.superview === nativeTitlebarView)
        }
    }

    func testSidebarSystemWindowControlsContainerWindowWillCloseSuppressesTitlebarRestore() {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let host = makeHost()

        window.contentView?.addSubview(host)
        host.presentationMode = .docked
        host.syncWindowReference(window)
        host.layoutSubtreeIfNeeded()

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        host.prepareForRemoval()

        XCTAssertTrue(window.isBrowserChromeNativeWindowControlsTeardownInProgress)
        assertButtonsHosted(in: host, window: window)
    }

    func testSidebarSystemWindowControlsContainerHandsOffButtonsBetweenHosts() {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let firstHost = makeHost()
        let secondHost = makeHost()

        window.contentView?.addSubview(firstHost)
        firstHost.presentationMode = .docked
        firstHost.syncWindowReference(window)
        firstHost.layoutSubtreeIfNeeded()
        assertButtonsHosted(in: firstHost, window: window)

        window.contentView?.addSubview(secondHost)
        secondHost.presentationMode = .docked
        secondHost.syncWindowReference(window)
        secondHost.layoutSubtreeIfNeeded()
        assertButtonsHosted(in: secondHost, window: window)

        firstHost.layoutSubtreeIfNeeded()
        assertButtonsHosted(in: secondHost, window: window)

        firstHost.prepareForRemoval()
        assertButtonsHosted(in: secondHost, window: window)

        secondHost.prepareForRemoval()
        for type in WindowChromeTestSupport.standardButtonTypes {
            XCTAssertTrue(window.standardWindowButton(type)?.superview === window.titlebarView)
        }
    }

    func testSidebarSystemWindowControlsContainerRefreshesHostedLayoutAfterResizeNotification() {
        assertHostedLayoutRefreshes(after: NSWindow.didResizeNotification)
    }

    func testSidebarSystemWindowControlsContainerRefreshesHostedLayoutAfterMiniaturizeNotification() {
        assertHostedLayoutRefreshes(after: NSWindow.didMiniaturizeNotification)
    }

    func testSidebarSystemWindowControlsContainerRefreshesHostedLayoutAfterDeminiaturizeNotification() {
        assertHostedLayoutRefreshes(after: NSWindow.didDeminiaturizeNotification)
    }

    func testSidebarSystemWindowControlsContainerRefreshesHostedLayoutAfterScreenChangeNotification() {
        assertHostedLayoutRefreshes(after: NSWindow.didChangeScreenNotification)
    }

    func testSidebarSystemWindowControlsContainerRefreshesHostedLayoutAfterWindowAppearanceNotification() {
        assertHostedLayoutRefreshes(after: .sumiWindowDidChangeEffectiveAppearance)
    }

    func testSidebarSystemWindowControlsContainerRefreshesHostedLayoutAfterApplicationAppearanceNotification() {
        assertHostedLayoutRefreshes(after: .sumiApplicationDidChangeEffectiveAppearance, postsWindowObject: false)
    }

    func testSidebarSystemWindowControlsContainerDoesNotOverwriteMetricsFromTransientTitlebarAppearanceShift() {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let host = makeHost()

        window.contentView?.addSubview(host)
        host.presentationMode = .docked
        host.syncWindowReference(window)
        host.layoutSubtreeIfNeeded()

        let controller = window.browserChromeNativeWindowControlsHostController()
        guard let initialMetrics = controller.cachedMetrics,
              let titlebarView = window.titlebarView
        else {
            XCTFail("Expected cached metrics and titlebar view.")
            return
        }

        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type),
                  let frame = initialMetrics.buttonFrames[type]
            else {
                XCTFail("Expected standard window button for \(type).")
                return
            }

            button.removeFromSuperview()
            titlebarView.addSubview(button)
            button.frame = frame.offsetBy(dx: -18, dy: 0)
        }

        NotificationCenter.default.post(
            name: .sumiWindowDidChangeEffectiveAppearance,
            object: window
        )

        XCTAssertEqual(controller.cachedMetrics, initialMetrics)
        assertButtonsHosted(in: host, window: window)
        assertHostedFramesMatchMetrics(in: host, window: window, metrics: initialMetrics)
    }

    func testSidebarSystemWindowControlsContainerReclaimsButtonsAfterLateAppearanceTitlebarPass() throws {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let host = makeHost()

        window.contentView?.addSubview(host)
        host.presentationMode = .docked
        host.syncWindowReference(window)
        host.layoutSubtreeIfNeeded()

        let controller = window.browserChromeNativeWindowControlsHostController()
        let initialMetrics = try XCTUnwrap(controller.cachedMetrics)
        let titlebarView = try XCTUnwrap(window.titlebarView)

        NotificationCenter.default.post(
            name: .sumiWindowDidChangeEffectiveAppearance,
            object: window
        )

        for type in WindowChromeTestSupport.standardButtonTypes {
            let button = try XCTUnwrap(window.standardWindowButton(type))
            let nativeFrame = try XCTUnwrap(initialMetrics.buttonFrames[type])

            button.removeFromSuperview()
            titlebarView.addSubview(button)
            button.frame = nativeFrame.offsetBy(dx: -18, dy: 0)
        }

        runMainLoopBriefly()

        XCTAssertEqual(controller.cachedMetrics, initialMetrics)
        assertButtonsHosted(in: host, window: window)
        assertHostedFramesMatchMetrics(in: host, window: window, metrics: initialMetrics)
    }

    func testSidebarSystemWindowControlsContainerRepairsHostedFrameDriftFromFrameNotificationSynchronously() throws {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let host = makeHost()

        window.contentView?.addSubview(host)
        host.presentationMode = .docked
        host.syncWindowReference(window)
        host.layoutSubtreeIfNeeded()

        let controller = window.browserChromeNativeWindowControlsHostController()
        let initialMetrics = try XCTUnwrap(controller.cachedMetrics)
        let closeButton = try XCTUnwrap(window.standardWindowButton(.closeButton))

        closeButton.frame = closeButton.frame.offsetBy(dx: -12, dy: 0)

        XCTAssertEqual(controller.cachedMetrics, initialMetrics)
        assertButtonsHosted(in: host, window: window)
        assertHostedFramesMatchMetrics(in: host, window: window, metrics: initialMetrics)
    }

    func testSidebarSystemWindowControlsContainerReclaimsReparentedButtonsOnWindowUpdate() throws {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let host = makeHost()

        window.contentView?.addSubview(host)
        host.presentationMode = .docked
        host.syncWindowReference(window)
        host.layoutSubtreeIfNeeded()

        let controller = window.browserChromeNativeWindowControlsHostController()
        let initialMetrics = try XCTUnwrap(controller.cachedMetrics)
        let titlebarView = try XCTUnwrap(window.titlebarView)

        for type in WindowChromeTestSupport.standardButtonTypes {
            let button = try XCTUnwrap(window.standardWindowButton(type))
            button.removeFromSuperview()
            titlebarView.addSubview(button)
        }

        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: window)

        XCTAssertEqual(controller.cachedMetrics, initialMetrics)
        assertButtonsHosted(in: host, window: window)
        assertHostedFramesMatchMetrics(in: host, window: window, metrics: initialMetrics)
    }

    func testSidebarSystemWindowControlsContainerRepairsHostedButtonStateChangedBySheetPass() throws {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let host = makeHost()

        window.contentView?.addSubview(host)
        host.presentationMode = .docked
        host.syncWindowReference(window)
        host.layoutSubtreeIfNeeded()

        let controller = window.browserChromeNativeWindowControlsHostController()
        let initialMetrics = try XCTUnwrap(controller.cachedMetrics)
        let zoomButton = try XCTUnwrap(window.standardWindowButton(.zoomButton))

        zoomButton.isHidden = true
        zoomButton.alphaValue = 0.2
        zoomButton.isEnabled = false
        zoomButton.isBordered = true
        zoomButton.translatesAutoresizingMaskIntoConstraints = false

        NotificationCenter.default.post(name: NSWindow.willBeginSheetNotification, object: window)

        XCTAssertEqual(controller.cachedMetrics, initialMetrics)
        assertButtonsHosted(in: host, window: window)
        assertHostedFramesMatchMetrics(in: host, window: window, metrics: initialMetrics)
        XCTAssertFalse(zoomButton.isHidden)
        XCTAssertEqual(zoomButton.alphaValue, 0)
        XCTAssertFalse(zoomButton.isBordered)
        XCTAssertTrue(zoomButton.translatesAutoresizingMaskIntoConstraints)

        NotificationCenter.default.post(name: NSWindow.didEndSheetNotification, object: window)
        runMainLoopForSheetTransition()

        XCTAssertEqual(zoomButton.alphaValue, 1)
        XCTAssertTrue(zoomButton.isEnabled)
    }

    func testSidebarSystemWindowControlsContainerShieldsHostedButtonsDuringSheetTransition() throws {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let host = makeHost()

        window.contentView?.addSubview(host)
        host.presentationMode = .docked
        host.syncWindowReference(window)
        host.layoutSubtreeIfNeeded()

        let initialSubviewCount = host.subviews.count
        window.beginHostedNativeWindowControlsVisualShieldForBrowserChrome()

        XCTAssertGreaterThan(host.subviews.count, initialSubviewCount)
        let shieldView = try XCTUnwrap(host.subviews.last)
        for type in WindowChromeTestSupport.standardButtonTypes {
            let button = try XCTUnwrap(window.standardWindowButton(type))
            XCTAssertFalse(button === shieldView)
        }
        assertButtonsHosted(in: host, window: window)

        window.endHostedNativeWindowControlsVisualShieldForBrowserChromeAfterAppKitPass()
        runMainLoopForSheetTransition()

        XCTAssertFalse(host.subviews.contains { $0 === shieldView })
        assertButtonsHosted(in: host, window: window)
    }

    func testSidebarSystemWindowControlsContainerRefreshesStaleStartupMetricsBeforeFirstHosting() throws {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let correctMetrics = try XCTUnwrap(window.nativeWindowControlsMetrics())
        let controller = window.browserChromeNativeWindowControlsHostController()

        for type in WindowChromeTestSupport.standardButtonTypes {
            let button = try XCTUnwrap(window.standardWindowButton(type))
            let frame = try XCTUnwrap(correctMetrics.buttonFrames[type])
            button.frame = frame.offsetBy(dx: -18, dy: 0)
        }
        controller.handleWindowGeometryChange()
        XCTAssertEqual(
            controller.cachedMetrics?.buttonGroupRect.minX,
            correctMetrics.buttonGroupRect.minX - 18
        )

        for type in WindowChromeTestSupport.standardButtonTypes {
            let button = try XCTUnwrap(window.standardWindowButton(type))
            let frame = try XCTUnwrap(correctMetrics.buttonFrames[type])
            button.frame = frame
        }

        let host = makeHost()
        window.contentView?.addSubview(host)
        host.presentationMode = .docked
        host.syncWindowReference(window)
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(controller.cachedMetrics, correctMetrics)
        assertButtonsHosted(in: host, window: window)
        assertHostedFramesMatchMetrics(in: host, window: window, metrics: correctMetrics)
    }

    func testSidebarSystemWindowControlsContainerUpdatesPlacementAcrossFullscreenLifecycle() {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let host = makeHost()

        window.contentView?.addSubview(host)
        host.presentationMode = .docked
        host.syncWindowReference(window)
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(host.currentPlacement, .sidebar)
        XCTAssertGreaterThan(host.intrinsicContentSize.width, 0)
        assertButtonsHosted(in: host, window: window)

        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: window)

        XCTAssertEqual(host.currentPlacement, .titlebar)
        XCTAssertEqual(host.intrinsicContentSize, .zero)
        for type in WindowChromeTestSupport.standardButtonTypes {
            XCTAssertTrue(window.standardWindowButton(type)?.superview === window.titlebarView)
        }

        NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: window)
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(host.currentPlacement, .sidebar)
        XCTAssertEqual(host.intrinsicContentSize.width, expectedHostedWidth(for: window))
        XCTAssertEqual(host.intrinsicContentSize.height, SidebarChromeMetrics.controlStripHeight)
        assertButtonsHosted(in: host, window: window)
    }

    private func assertHostedLayoutRefreshes(
        after notificationName: Notification.Name,
        postsWindowObject: Bool = true,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let host = makeHost()

        window.contentView?.addSubview(host)
        host.presentationMode = .collapsedVisible
        host.syncWindowReference(window)
        host.layoutSubtreeIfNeeded()

        let controller = window.browserChromeNativeWindowControlsHostController()
        let metrics = controller.cachedMetrics
        let expectedGroupHeight = metrics?.buttonGroupSize.height ?? 0
        let expectedYOffset = floor((host.bounds.height - expectedGroupHeight) / 2)
        guard let expectedCloseFrame = metrics?.normalizedButtonFrames[.closeButton]?.offsetBy(
            dx: SidebarChromeMetrics.windowControlsLeadingInset,
            dy: expectedYOffset
        ) else {
            XCTFail("Expected cached close-button metrics.", file: file, line: line)
            return
        }

        guard let closeButton = window.standardWindowButton(.closeButton) else {
            XCTFail("Expected close button.", file: file, line: line)
            return
        }

        closeButton.frame = closeButton.frame.offsetBy(dx: 17, dy: 5)
        NotificationCenter.default.post(
            name: notificationName,
            object: postsWindowObject ? window : nil
        )

        XCTAssertEqual(
            closeButton.frame,
            expectedCloseFrame,
            file: file,
            line: line
        )
        XCTAssertTrue(closeButton.superview === host, file: file, line: line)
    }

    private func assertButtonsHosted(
        in host: SidebarSystemWindowControlsContainerView,
        window: NSWindow,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type) else {
                XCTFail("Expected standard window button for \(type).", file: file, line: line)
                return
            }

            XCTAssertTrue(button.superview === host, file: file, line: line)
            XCTAssertEqual(
                button.accessibilityIdentifier(),
                BrowserWindowControlsAccessibilityIdentifiers.identifier(for: type),
                file: file,
                line: line
            )
        }
    }

    private func assertHostedFramesMatchMetrics(
        in host: SidebarSystemWindowControlsContainerView,
        window: NSWindow,
        metrics: NativeWindowControlsMetrics,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectedGroupHeight = metrics.buttonGroupSize.height
        let expectedYOffset = floor((host.bounds.height - expectedGroupHeight) / 2)

        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type),
                  let normalizedFrame = metrics.normalizedButtonFrames[type]
            else {
                XCTFail("Expected standard window button for \(type).", file: file, line: line)
                return
            }

            XCTAssertEqual(
                button.frame,
                normalizedFrame.offsetBy(
                    dx: SidebarChromeMetrics.windowControlsLeadingInset,
                    dy: expectedYOffset
                ),
                file: file,
                line: line
            )
        }
    }

    private func expectedHostedWidth(for window: NSWindow) -> CGFloat {
        ceil(
            (window.nativeWindowControlsMetrics()?.buttonGroupWidth ?? 0)
                + SidebarChromeMetrics.windowControlsLeadingInset
        )
    }

    private func runMainLoopBriefly() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    private func runMainLoopForSheetTransition() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }

    private func makeHost() -> SidebarSystemWindowControlsContainerView {
        SidebarSystemWindowControlsContainerView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: 80,
                height: SidebarChromeMetrics.controlStripHeight
            )
        )
    }
}
