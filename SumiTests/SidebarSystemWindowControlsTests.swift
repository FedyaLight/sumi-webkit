import AppKit
import XCTest

@testable import Sumi

@MainActor
final class SidebarSystemWindowControlsTests: XCTestCase {
    func testSidebarPresentationContextKeepsDockedAndHoverWidthsSeparate() {
        let docked = SidebarPresentationContext.docked(sidebarWidth: 280)
        let hidden = SidebarPresentationContext.collapsedHidden(
            sidebarWidth: 280,
            shellWidth: 298
        )
        let visible = SidebarPresentationContext.collapsedVisible(
            sidebarWidth: 280,
            shellWidth: 298
        )

        XCTAssertEqual(docked.mode, .docked)
        XCTAssertEqual(docked.sidebarWidth, 280)
        XCTAssertEqual(docked.shellWidth, 280)
        XCTAssertEqual(docked.contentWidth, BrowserWindowState.sidebarContentWidth(for: 280))
        XCTAssertTrue(docked.showsResizeHandle)
        XCTAssertFalse(docked.isCollapsedOverlay)

        XCTAssertEqual(hidden.mode, .collapsedHidden)
        XCTAssertEqual(hidden.sidebarWidth, 280)
        XCTAssertEqual(hidden.shellWidth, 298)
        XCTAssertEqual(hidden.contentWidth, BrowserWindowState.sidebarContentWidth(for: 280))
        XCTAssertFalse(hidden.showsResizeHandle)
        XCTAssertTrue(hidden.isCollapsedOverlay)

        XCTAssertEqual(visible.mode, .collapsedVisible)
        XCTAssertEqual(visible.sidebarWidth, 280)
        XCTAssertEqual(visible.shellWidth, 298)
        XCTAssertEqual(visible.contentWidth, BrowserWindowState.sidebarContentWidth(for: 280))
        XCTAssertFalse(visible.showsResizeHandle)
        XCTAssertTrue(visible.isCollapsedOverlay)
    }

    func testSidebarWindowControlsPlacementUsesSidebarOnlyWhenChromeIsVisibleAndWindowed() {
        XCTAssertEqual(
            SidebarWindowControlsPlacement.resolve(
                presentationMode: .docked,
                isFullScreen: false
            ),
            .titlebarReservedSpace
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
            .titlebar
        )
        XCTAssertEqual(
            SidebarWindowControlsPlacement.resolve(
                presentationMode: .docked,
                isFullScreen: true
            ),
            .titlebar
        )
    }

    func testSidebarSystemWindowControlsContainerReservesVisibleWidthBeforeAttachingToWindow() {
        let host = SidebarSystemWindowControlsContainerView(frame: .zero)
        host.presentationMode = .docked

        XCTAssertEqual(host.intrinsicContentSize.width, 66)
        XCTAssertEqual(host.intrinsicContentSize.height, SidebarChromeMetrics.controlStripHeight)

        host.presentationMode = .collapsedHidden
        XCTAssertEqual(host.intrinsicContentSize.width, 0)
        XCTAssertEqual(host.intrinsicContentSize.height, 0)
    }

    func testSidebarSystemWindowControlsContainerWaitsForBrowserChromeBeforeClaimingButtons() {
        let window = WindowChromeTestSupport.makePlainWindow()
        let host = SidebarSystemWindowControlsContainerView(frame: .zero)
        let nativeTitlebarView = window.standardWindowButton(.closeButton)?.superview

        host.presentationMode = .docked
        window.contentView?.addSubview(host)

        XCTAssertEqual(host.currentPlacement, .titlebarReservedSpace)
        XCTAssertTrue(host.subviews.isEmpty)
        for type in WindowChromeTestSupport.standardButtonTypes {
            XCTAssertTrue(window.standardWindowButton(type)?.superview === nativeTitlebarView)
        }

        promoteToSumiBrowserWindowIfNeeded(window)
        WindowChromeTestSupport.retain(window)
        host.setPreferredWindowReference(window)

        XCTAssertEqual(host.currentPlacement, .titlebarReservedSpace)
        for type in WindowChromeTestSupport.standardButtonTypes {
            XCTAssertTrue(window.standardWindowButton(type)?.superview === nativeTitlebarView)
        }
    }

    func testSidebarSystemWindowControlsContainerMovesButtonsBetweenSidebarAndTitlebar() {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let host = SidebarSystemWindowControlsContainerView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: 80,
                height: SidebarChromeMetrics.controlStripHeight
            )
        )
        let cachedFrames = WindowChromeTestSupport.standardButtonTypes.reduce(into: [NSWindow.ButtonType: NSRect]()) { partialResult, type in
            partialResult[type] = window.cachedNativeWindowButtonFrame(for: type)
        }

        for type in WindowChromeTestSupport.standardButtonTypes {
            window.standardWindowButton(type)?.isHidden = true
            window.standardWindowButton(type)?.alphaValue = 0.2
            window.standardWindowButton(type)?.isEnabled = false
        }

        window.contentView?.addSubview(host)
        host.syncWindowReference(window)
        host.presentationMode = .collapsedVisible

        XCTAssertEqual(host.currentPlacement, .sidebar)
        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type) else {
                XCTFail("Expected standard window button for \(type).")
                return
            }

            XCTAssertTrue(button.superview === host)
            XCTAssertFalse(button.isHidden)
            XCTAssertEqual(button.alphaValue, 1)
            XCTAssertTrue(button.isEnabled)
            XCTAssertEqual(button.frame, cachedFrames[type])
        }

        let nativeTitlebarView = window.titlebarView
        host.presentationMode = .docked

        XCTAssertEqual(host.currentPlacement, .titlebarReservedSpace)
        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type) else {
                XCTFail("Expected standard window button for \(type).")
                return
            }

            XCTAssertTrue(button.superview === nativeTitlebarView)
            XCTAssertFalse(button.isHidden)
            XCTAssertEqual(button.alphaValue, 1)
            XCTAssertTrue(button.isEnabled)
            XCTAssertEqual(button.frame, cachedFrames[type])
        }
    }

    func testSidebarSystemWindowControlsContainerUsesNativeLeadingInsetAndHeight() {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let host = SidebarSystemWindowControlsContainerView(frame: .zero)

        window.contentView?.addSubview(host)
        host.syncWindowReference(window)
        host.presentationMode = .docked

        XCTAssertEqual(host.intrinsicContentSize.width, 66)
        XCTAssertEqual(host.intrinsicContentSize.height, SidebarChromeMetrics.controlStripHeight)

        let nativeTitlebarView = window.titlebarView
        for type in WindowChromeTestSupport.standardButtonTypes {
            guard let button = window.standardWindowButton(type),
                  let nativeFrame = window.cachedNativeWindowButtonFrame(for: type)
            else {
                XCTFail("Expected standard window button for \(type).")
                return
            }

            XCTAssertTrue(button.superview === nativeTitlebarView)
            XCTAssertEqual(button.frame, nativeFrame)
        }
    }

    func testSidebarSystemWindowControlsContainerTeardownRestoresButtonsWhenItStillOwnsThem() {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let host = SidebarSystemWindowControlsContainerView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: 80,
                height: SidebarChromeMetrics.controlStripHeight
            )
        )

        window.contentView?.addSubview(host)
        host.syncWindowReference(window)
        host.presentationMode = .collapsedVisible

        let nativeTitlebarView = window.titlebarView
        host.prepareForRemoval()

        XCTAssertEqual(host.currentPlacement, .titlebar)
        for type in WindowChromeTestSupport.standardButtonTypes {
            XCTAssertTrue(window.standardWindowButton(type)?.superview === nativeTitlebarView)
        }
    }

    func testSidebarSystemWindowControlsContainerTeardownDoesNotStealButtonsFromReplacementHost() {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let firstHost = SidebarSystemWindowControlsContainerView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: 80,
                height: SidebarChromeMetrics.controlStripHeight
            )
        )
        let secondHost = SidebarSystemWindowControlsContainerView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: 80,
                height: SidebarChromeMetrics.controlStripHeight
            )
        )

        window.contentView?.addSubview(firstHost)
        firstHost.syncWindowReference(window)
        firstHost.presentationMode = .collapsedVisible

        for type in WindowChromeTestSupport.standardButtonTypes {
            XCTAssertTrue(window.standardWindowButton(type)?.superview === firstHost)
        }

        window.contentView?.addSubview(secondHost)
        secondHost.syncWindowReference(window)
        secondHost.presentationMode = .collapsedVisible

        for type in WindowChromeTestSupport.standardButtonTypes {
            XCTAssertTrue(window.standardWindowButton(type)?.superview === secondHost)
        }

        firstHost.prepareForRemoval()

        for type in WindowChromeTestSupport.standardButtonTypes {
            XCTAssertTrue(window.standardWindowButton(type)?.superview === secondHost)
        }
    }
}
