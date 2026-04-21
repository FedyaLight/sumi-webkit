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
        XCTAssertEqual(docked.contentWidth, BrowserWindowState.sidebarContentWidth(for: 280))
        XCTAssertTrue(docked.showsResizeHandle)
        XCTAssertFalse(docked.isCollapsedOverlay)

        XCTAssertEqual(hidden.mode, .collapsedHidden)
        XCTAssertEqual(hidden.sidebarWidth, 280)
        XCTAssertEqual(hidden.contentWidth, BrowserWindowState.sidebarContentWidth(for: 280))
        XCTAssertFalse(hidden.showsResizeHandle)
        XCTAssertTrue(hidden.isCollapsedOverlay)

        XCTAssertEqual(visible.mode, .collapsedVisible)
        XCTAssertEqual(visible.sidebarWidth, 280)
        XCTAssertEqual(visible.contentWidth, BrowserWindowState.sidebarContentWidth(for: 280))
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

    func testSidebarSystemWindowControlsContainerUsesButtonGroupWidthForEmbeddedAlignment() {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let host = makeHost()

        window.contentView?.addSubview(host)
        host.presentationMode = .docked
        host.syncWindowReference(window)
        host.layoutSubtreeIfNeeded()

        let metrics = window.nativeWindowControlsMetrics()

        XCTAssertEqual(host.currentPlacement, .sidebar)
        XCTAssertEqual(host.intrinsicContentSize.width, ceil(metrics?.buttonGroupWidth ?? 0))
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
            dx: 0,
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
        NotificationCenter.default.post(name: notificationName, object: window)

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

    private func expectedHostedWidth(for window: NSWindow) -> CGFloat {
        ceil(window.nativeWindowControlsMetrics()?.buttonGroupWidth ?? 0)
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
