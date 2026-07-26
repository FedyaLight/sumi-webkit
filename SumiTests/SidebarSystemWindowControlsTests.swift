import AppKit
import SwiftUI
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

    func testSidebarResizeEdgeUsesCenteredBoundaryHitTargetMetrics() {
        XCTAssertEqual(SidebarResizeMetrics.grabberWidth, 3)
        XCTAssertEqual(SidebarResizeMetrics.grabberHeight, 56)
    }

    func testSidebarBoundaryAnchorUsesDockedSplitBoundaryForLeftAndRightEdges() {
        let bounds = CGRect(x: 10, y: 0, width: 800, height: 600)

        XCTAssertEqual(
            SidebarPosition.left.shellEdge.sidebarBoundaryAnchorX(
                in: bounds,
                presentationWidth: 280
            ),
            290
        )
        XCTAssertEqual(
            SidebarPosition.right.shellEdge.sidebarBoundaryAnchorX(
                in: bounds,
                presentationWidth: 280
            ),
            530
        )
    }

    func testSidebarResizeDeltaMirrorsLeftAndRightEdges() {
        XCTAssertEqual(
            SidebarPosition.left.shellEdge.resizeDelta(startingMouseX: 300, currentMouseX: 340),
            40
        )
        XCTAssertEqual(
            SidebarPosition.right.shellEdge.resizeDelta(startingMouseX: 300, currentMouseX: 260),
            40
        )
        XCTAssertEqual(
            SidebarPosition.left.shellEdge.resizeDelta(startingMouseX: 300, currentMouseX: 260),
            -40
        )
        XCTAssertEqual(
            SidebarPosition.right.shellEdge.resizeDelta(startingMouseX: 300, currentMouseX: 340),
            -40
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

    func testCollapsedHostMountsFromOverlayLifecycleInputs() {
        XCTAssertFalse(SidebarHoverOverlayHostMountPolicy.shouldMountCollapsedHost(
            isSidebarVisible: false,
            isOverlayVisible: false,
            isOverlayHostPrewarmed: false,
            transientUIPinsHoverSidebar: false,
            sidebarDragPinsHoverSidebar: false
        ))
        XCTAssertTrue(SidebarHoverOverlayHostMountPolicy.shouldMountCollapsedHost(
            isSidebarVisible: false,
            isOverlayVisible: true,
            isOverlayHostPrewarmed: false,
            transientUIPinsHoverSidebar: false,
            sidebarDragPinsHoverSidebar: false
        ))
        XCTAssertTrue(SidebarHoverOverlayHostMountPolicy.shouldMountCollapsedHost(
            isSidebarVisible: false,
            isOverlayVisible: false,
            isOverlayHostPrewarmed: true,
            transientUIPinsHoverSidebar: false,
            sidebarDragPinsHoverSidebar: false
        ))
    }

    func testStartupPendingEmptyStateBootstrapProvidesOverlayInputs() {
        let shouldBootstrap = SidebarHoverOverlayStartupEmptyStatePolicy.shouldBootstrapVisible(
            isStartupEmptyStateSyncPending: true,
            isSidebarVisible: false,
            isShowingEmptyState: true
        )
        let effectiveVisible = SidebarHoverOverlayStartupEmptyStatePolicy.effectiveOverlayVisible(
            isStartupEmptyStateSyncPending: true,
            isOverlayVisible: false,
            startupEmptyStateBootstrapVisible: shouldBootstrap
        )
        let effectiveHostPrewarmed = SidebarHoverOverlayStartupEmptyStatePolicy.effectiveOverlayHostPrewarmed(
            isStartupEmptyStateSyncPending: true,
            isOverlayHostPrewarmed: false,
            startupEmptyStateBootstrapVisible: shouldBootstrap
        )

        XCTAssertTrue(shouldBootstrap)
        XCTAssertTrue(SidebarHoverOverlayRevealPolicy.isOverlayRevealed(
            isOverlayVisible: effectiveVisible,
            transientUIPinsHoverSidebar: false,
            sidebarDragPinsHoverSidebar: false
        ))
        XCTAssertTrue(SidebarHoverOverlayHostMountPolicy.shouldMountCollapsedHost(
            isSidebarVisible: false,
            isOverlayVisible: effectiveVisible,
            isOverlayHostPrewarmed: effectiveHostPrewarmed,
            transientUIPinsHoverSidebar: false,
            sidebarDragPinsHoverSidebar: false
        ))
    }

    func testStartupPendingSuppressesPrewarmedHiddenHostMount() {
        // Empty state has not resolved yet during launch, but the manager may have
        // prewarmed the collapsed host to a hidden state. It must NOT mount while
        // pending, otherwise it would reveal via an animated hidden→visible slide.
        let shouldBootstrap = SidebarHoverOverlayStartupEmptyStatePolicy.shouldBootstrapVisible(
            isStartupEmptyStateSyncPending: true,
            isSidebarVisible: false,
            isShowingEmptyState: false
        )
        let effectiveVisible = SidebarHoverOverlayStartupEmptyStatePolicy.effectiveOverlayVisible(
            isStartupEmptyStateSyncPending: true,
            isOverlayVisible: false,
            startupEmptyStateBootstrapVisible: shouldBootstrap
        )
        let effectiveHostPrewarmed = SidebarHoverOverlayStartupEmptyStatePolicy.effectiveOverlayHostPrewarmed(
            isStartupEmptyStateSyncPending: true,
            isOverlayHostPrewarmed: true,
            startupEmptyStateBootstrapVisible: shouldBootstrap
        )

        XCTAssertFalse(effectiveHostPrewarmed)
        XCTAssertFalse(SidebarHoverOverlayHostMountPolicy.shouldMountCollapsedHost(
            isSidebarVisible: false,
            isOverlayVisible: effectiveVisible,
            isOverlayHostPrewarmed: effectiveHostPrewarmed,
            transientUIPinsHoverSidebar: false,
            sidebarDragPinsHoverSidebar: false
        ))
    }

    func testResolvedStartupHonorsManagerPrewarmForHoverMount() {
        // Once startup resolves, the collapsed host should mount from the manager's
        // real prewarm state again so hover reveals stay responsive.
        let shouldBootstrap = SidebarHoverOverlayStartupEmptyStatePolicy.shouldBootstrapVisible(
            isStartupEmptyStateSyncPending: false,
            isSidebarVisible: false,
            isShowingEmptyState: false
        )
        let effectiveHostPrewarmed = SidebarHoverOverlayStartupEmptyStatePolicy.effectiveOverlayHostPrewarmed(
            isStartupEmptyStateSyncPending: false,
            isOverlayHostPrewarmed: true,
            startupEmptyStateBootstrapVisible: shouldBootstrap
        )

        XCTAssertTrue(effectiveHostPrewarmed)
        XCTAssertTrue(SidebarHoverOverlayHostMountPolicy.shouldMountCollapsedHost(
            isSidebarVisible: false,
            isOverlayVisible: false,
            isOverlayHostPrewarmed: effectiveHostPrewarmed,
            transientUIPinsHoverSidebar: false,
            sidebarDragPinsHoverSidebar: false
        ))
    }

    func testStartupPendingEmptyStateSyncUsesNonAnimatedBranch() {
        XCTAssertFalse(SidebarHoverOverlayStartupEmptyStatePolicy.shouldAnimateEmptyStateSync(
            isStartupEmptyStateSyncPending: true
        ))
        XCTAssertTrue(SidebarHoverOverlayStartupEmptyStatePolicy.shouldAnimateEmptyStateSync(
            isStartupEmptyStateSyncPending: false
        ))
    }

    func testEmptyStateBootstrapStopsAfterStartupSyncCompletes() {
        let shouldBootstrap = SidebarHoverOverlayStartupEmptyStatePolicy.shouldBootstrapVisible(
            isStartupEmptyStateSyncPending: false,
            isSidebarVisible: false,
            isShowingEmptyState: true
        )
        let effectiveVisible = SidebarHoverOverlayStartupEmptyStatePolicy.effectiveOverlayVisible(
            isStartupEmptyStateSyncPending: false,
            isOverlayVisible: false,
            startupEmptyStateBootstrapVisible: shouldBootstrap
        )
        let effectiveHostPrewarmed = SidebarHoverOverlayStartupEmptyStatePolicy.effectiveOverlayHostPrewarmed(
            isStartupEmptyStateSyncPending: false,
            isOverlayHostPrewarmed: false,
            startupEmptyStateBootstrapVisible: shouldBootstrap
        )

        XCTAssertFalse(shouldBootstrap)
        XCTAssertFalse(SidebarHoverOverlayRevealPolicy.isOverlayRevealed(
            isOverlayVisible: effectiveVisible,
            transientUIPinsHoverSidebar: false,
            sidebarDragPinsHoverSidebar: false
        ))
        XCTAssertFalse(SidebarHoverOverlayHostMountPolicy.shouldMountCollapsedHost(
            isSidebarVisible: false,
            isOverlayVisible: effectiveVisible,
            isOverlayHostPrewarmed: effectiveHostPrewarmed,
            transientUIPinsHoverSidebar: false,
            sidebarDragPinsHoverSidebar: false
        ))
    }

    func testCollapsedNormalWebContentKeepsHoverOnlyMountBehavior() {
        XCTAssertFalse(SidebarHoverOverlayStartupEmptyStatePolicy.shouldBootstrapVisible(
            isStartupEmptyStateSyncPending: true,
            isSidebarVisible: false,
            isShowingEmptyState: false
        ))
        XCTAssertFalse(SidebarHoverOverlayRevealPolicy.isOverlayRevealed(
            isOverlayVisible: false,
            transientUIPinsHoverSidebar: false,
            sidebarDragPinsHoverSidebar: false
        ))
        XCTAssertFalse(SidebarHoverOverlayHostMountPolicy.shouldMountCollapsedHost(
            isSidebarVisible: false,
            isOverlayVisible: false,
            isOverlayHostPrewarmed: false,
            transientUIPinsHoverSidebar: false,
            sidebarDragPinsHoverSidebar: false
        ))
    }

    func testDockedSidebarDoesNotMountCollapsedHost() {
        XCTAssertFalse(SidebarHoverOverlayStartupEmptyStatePolicy.shouldBootstrapVisible(
            isStartupEmptyStateSyncPending: true,
            isSidebarVisible: true,
            isShowingEmptyState: true
        ))
        XCTAssertFalse(SidebarHoverOverlayHostMountPolicy.shouldMountCollapsedHost(
            isSidebarVisible: true,
            isOverlayVisible: true,
            isOverlayHostPrewarmed: true,
            transientUIPinsHoverSidebar: false,
            sidebarDragPinsHoverSidebar: false
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
    }

    func testTrafficLightMetricsPreserveBrowserChromeClusterSize() {
        let geometry = BrowserWindowTrafficLightCustodian.resolvedGeometry

        XCTAssertEqual(BrowserWindowTrafficLightMetrics.buttonDiameter, geometry.diameter)
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.buttonCenterSpacing, geometry.centerSpacing)
        XCTAssertEqual(
            BrowserWindowTrafficLightMetrics.buttonSpacing,
            geometry.centerSpacing - geometry.diameter
        )
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.clusterHeight, 30)
        XCTAssertEqual(
            BrowserWindowTrafficLightMetrics.clusterWidth,
            geometry.diameter + geometry.centerSpacing * 2
        )
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.clusterTrailingInset, 14)
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.clusterHorizontalOffset, -1)
        XCTAssertEqual(
            BrowserWindowTrafficLightMetrics.sidebarReservedWidth,
            BrowserWindowTrafficLightMetrics.clusterWidth + BrowserWindowTrafficLightMetrics.clusterTrailingInset
        )
        for presentation in [BrowserWindowTrafficLightPresentation.interactive, .attached] {
            XCTAssertEqual(
                BrowserWindowTrafficLightMetrics.sidebarReservedWidth(for: presentation),
                BrowserWindowTrafficLightMetrics.sidebarReservedWidth
            )
        }
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.sidebarReservedWidth(for: .hidden), 0)
        XCTAssertEqual(SidebarChromeMetrics.topControlInset, 0)
        XCTAssertEqual(SidebarChromeMetrics.controlLeadingPadding, 18)
        XCTAssertEqual(SidebarChromeMetrics.contentHorizontalPadding, 8)
        XCTAssertEqual(SidebarChromeMetrics.controlStripHeight, 38)
        XCTAssertEqual(SidebarChromeMetrics.controlSpacing, 0)
        XCTAssertEqual(SidebarChromeMetrics.navigationButtonSize, 30)
        XCTAssertEqual(SidebarChromeMetrics.navigationIconSize, 14)
    }

    // MARK: - Native geometry

    func testTrafficLightGeometryDerivesNativeSpacingFromButtonFrames() {
        // Frames as macOS 26 lays the cluster out in NSTitlebarView.
        let geometry = BrowserWindowTrafficLightGeometry.measured(fromNativeFrames: [
            NSRect(x: 9, y: 9, width: 14, height: 14),
            NSRect(x: 32, y: 9, width: 14, height: 14),
            NSRect(x: 55, y: 9, width: 14, height: 14),
        ])

        XCTAssertEqual(geometry?.diameter, 14)
        XCTAssertEqual(geometry?.centerSpacing, 23)
    }

    func testTrafficLightGeometryRejectsFramesThatCannotDescribeACluster() {
        let square = NSRect(x: 0, y: 0, width: 14, height: 14)

        XCTAssertNil(BrowserWindowTrafficLightGeometry.measured(fromNativeFrames: []))
        XCTAssertNil(BrowserWindowTrafficLightGeometry.measured(fromNativeFrames: [square, square]))
        XCTAssertNil(BrowserWindowTrafficLightGeometry.measured(fromNativeFrames: [
            .zero, .zero, .zero,
        ]))
        // Uneven pitch: the middle button is not centred between its neighbours.
        XCTAssertNil(BrowserWindowTrafficLightGeometry.measured(fromNativeFrames: [
            NSRect(x: 9, y: 9, width: 14, height: 14),
            NSRect(x: 32, y: 9, width: 14, height: 14),
            NSRect(x: 70, y: 9, width: 14, height: 14),
        ]))
        // Buttons still collapsed to a zero-height frame before their first layout.
        XCTAssertNil(BrowserWindowTrafficLightGeometry.measured(fromNativeFrames: [
            NSRect(x: 9, y: 9, width: 14, height: 0),
            NSRect(x: 32, y: 9, width: 14, height: 0),
            NSRect(x: 55, y: 9, width: 14, height: 0),
        ]))
    }

    func testTrafficLightFallbackGeometryMatchesSystemClusterForCurrentOS() {
        let fallback = BrowserWindowTrafficLightGeometry.fallback

        if #available(macOS 26.0, *) {
            XCTAssertEqual(fallback.diameter, 14)
            XCTAssertEqual(fallback.centerSpacing, 23)
        } else {
            XCTAssertEqual(fallback.diameter, 12)
            XCTAssertEqual(fallback.centerSpacing, 20)
        }
    }

    func testTrafficLightCustodianLaysButtonsOutOnNativePitch() {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        WindowChromeTestSupport.retain(window)
        let host = Self.makeCustodyHost(in: window)
        let custodian = window.browserTrafficLightCustodian

        custodian.attach(
            host: host,
            presentation: .interactive,
            actionProvider: .browserWindow(window)
        )

        let spacing = BrowserWindowTrafficLightCustodian.resolvedGeometry.centerSpacing
        for (index, action) in BrowserWindowTrafficLightAction.allCases.enumerated() {
            let button = custodian.hostedButton(for: action)
            XCTAssertIdentical(button?.superview, host, "\(action)")
            XCTAssertEqual(button?.frame.origin.x, CGFloat(index) * spacing, "\(action)")
        }
    }

    // MARK: - Custody

    func testTrafficLightCustodianKeepsASingleHostWhenTwoClustersClaim() {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        WindowChromeTestSupport.retain(window)
        let firstHost = Self.makeCustodyHost(in: window)
        let secondHost = Self.makeCustodyHost(in: window)
        let custodian = window.browserTrafficLightCustodian
        let provider = BrowserWindowTrafficLightActionProvider.browserWindow(window)

        custodian.attach(host: firstHost, presentation: .interactive, actionProvider: provider)
        custodian.attach(host: secondHost, presentation: .interactive, actionProvider: provider)

        for action in BrowserWindowTrafficLightAction.allCases {
            XCTAssertIdentical(custodian.hostedButton(for: action)?.superview, secondHost, "\(action)")
        }

        // The cluster that lost the claim tears down later; that must not yank the buttons away
        // from the winner.
        custodian.detach(host: firstHost)

        for action in BrowserWindowTrafficLightAction.allCases {
            XCTAssertIdentical(custodian.hostedButton(for: action)?.superview, secondHost, "\(action)")
        }
    }

    func testTrafficLightCustodianRestoresButtonsMovedBehindItsBack() {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        WindowChromeTestSupport.retain(window)
        let host = Self.makeCustodyHost(in: window)
        let stray = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        window.contentView?.addSubview(stray)
        let custodian = window.browserTrafficLightCustodian

        custodian.attach(
            host: host,
            presentation: .interactive,
            actionProvider: .browserWindow(window)
        )

        guard let closeButton = custodian.hostedButton(for: .close) else {
            return XCTFail("close button was not captured")
        }
        let expectedFrame = closeButton.frame

        // AppKit relayout: the theme frame re-homes the button and drops it back at the window's
        // top-left corner.
        stray.addSubview(closeButton)
        closeButton.frame = NSRect(x: 9, y: 9, width: expectedFrame.width, height: expectedFrame.height)
        custodian.enforce(host: host)

        XCTAssertIdentical(closeButton.superview, host)
        XCTAssertEqual(closeButton.frame, expectedFrame)
    }

    func testTrafficLightCustodianReturnsButtonsToTheTitlebarOnRelease() {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        WindowChromeTestSupport.retain(window)
        let host = Self.makeCustodyHost(in: window)
        let custodian = window.browserTrafficLightCustodian
        let titlebarHomes = WindowChromeTestSupport.standardButtonTypes.map {
            window.standardWindowButton($0)?.superview
        }

        custodian.attach(
            host: host,
            presentation: .interactive,
            actionProvider: .browserWindow(window)
        )
        custodian.detach(host: host)

        for (index, type) in WindowChromeTestSupport.standardButtonTypes.enumerated() {
            XCTAssertIdentical(
                window.standardWindowButton(type)?.superview,
                titlebarHomes[index],
                "\(type.rawValue)"
            )
        }
    }

    // MARK: - Presentation policy

    func testTrafficLightsStayMountedWhileTheSidebarPanelIsStillOnScreen() {
        // Docked collapse: `isSidebarVisible` flips first, the column animates away afterwards.
        XCTAssertEqual(
            SidebarTrafficLightPresentationPolicy.presentation(
                isBrowserWindowFullScreen: false,
                mode: .docked,
                isSidebarVisible: false,
                overlayUsesTravel: true
            ),
            .attached
        )
        // Collapsed overlay closing: the panel translates out and carries the buttons with it.
        XCTAssertEqual(
            SidebarTrafficLightPresentationPolicy.presentation(
                isBrowserWindowFullScreen: false,
                mode: .collapsedHidden,
                isSidebarVisible: false,
                overlayUsesTravel: true
            ),
            .attached
        )
    }

    func testTrafficLightsAreInteractiveOnlyWhileTheSidebarIsSettled() {
        XCTAssertEqual(
            SidebarTrafficLightPresentationPolicy.presentation(
                isBrowserWindowFullScreen: false,
                mode: .docked,
                isSidebarVisible: true,
                overlayUsesTravel: true
            ),
            .interactive
        )
        XCTAssertEqual(
            SidebarTrafficLightPresentationPolicy.presentation(
                isBrowserWindowFullScreen: false,
                mode: .collapsedVisible,
                isSidebarVisible: false,
                overlayUsesTravel: true
            ),
            .interactive
        )
    }

    func testTrafficLightsWithdrawWhenThereIsNoPanelToRide() {
        // Reduced motion removes the overlay's travel, so a closed overlay has nothing to ride out.
        XCTAssertEqual(
            SidebarTrafficLightPresentationPolicy.presentation(
                isBrowserWindowFullScreen: false,
                mode: .collapsedHidden,
                isSidebarVisible: false,
                overlayUsesTravel: false
            ),
            .hidden
        )
        // Fullscreen hands the buttons back to the system titlebar in every sidebar mode.
        for mode in [SidebarPresentationMode.docked, .collapsedVisible, .collapsedHidden] {
            XCTAssertEqual(
                SidebarTrafficLightPresentationPolicy.presentation(
                    isBrowserWindowFullScreen: true,
                    mode: mode,
                    isSidebarVisible: true,
                    overlayUsesTravel: true
                ),
                .hidden,
                "\(mode)"
            )
        }
    }

    func testTrafficLightTravelIsCarriedOnlyByALeftDockedColumn() {
        XCTAssertEqual(
            SidebarTrafficLightPresentationPolicy.travelProgress(
                mode: .docked,
                shellEdge: SidebarPosition.left.shellEdge,
                isSidebarVisible: false
            ),
            0
        )
        XCTAssertEqual(
            SidebarTrafficLightPresentationPolicy.travelProgress(
                mode: .docked,
                shellEdge: SidebarPosition.left.shellEdge,
                isSidebarVisible: true
            ),
            1
        )
        // A right-docked column and the collapsed overlay are moved by their own containers.
        XCTAssertEqual(
            SidebarTrafficLightPresentationPolicy.travelProgress(
                mode: .docked,
                shellEdge: SidebarPosition.right.shellEdge,
                isSidebarVisible: false
            ),
            1
        )
        XCTAssertEqual(
            SidebarTrafficLightPresentationPolicy.travelProgress(
                mode: .collapsedHidden,
                shellEdge: SidebarPosition.left.shellEdge,
                isSidebarVisible: false
            ),
            1
        )
    }

    func testTrafficLightPresentationSeparatesTravelFromInteractivity() {
        XCTAssertFalse(BrowserWindowTrafficLightPresentation.hidden.isAttached)
        XCTAssertFalse(BrowserWindowTrafficLightPresentation.hidden.isInteractive)
        XCTAssertTrue(BrowserWindowTrafficLightPresentation.attached.isAttached)
        XCTAssertFalse(BrowserWindowTrafficLightPresentation.attached.isInteractive)
        XCTAssertTrue(BrowserWindowTrafficLightPresentation.interactive.isAttached)
        XCTAssertTrue(BrowserWindowTrafficLightPresentation.interactive.isInteractive)
    }

    private static func makeCustodyHost(in window: NSWindow) -> NSView {
        let host = NSView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: BrowserWindowTrafficLightMetrics.sidebarReservedWidth,
                height: BrowserWindowTrafficLightMetrics.clusterHeight
            )
        )
        window.contentView?.addSubview(host)
        return host
    }

    func testTrafficLightActionProviderEnablesAvailableWindowActions() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 320, height: 240)),
            styleMask: SumiBrowserChromeConfiguration.requiredStyleMask,
            backing: .buffered,
            defer: false
        )
        let provider = BrowserWindowTrafficLightActionProvider.browserWindow(window)

        XCTAssertTrue(provider.isEnabled(.close))
        XCTAssertTrue(provider.isEnabled(.minimize))
        XCTAssertTrue(provider.isEnabled(.zoom))
    }

    func testTrafficLightActionProviderDisablesUnavailableWindowActions() {
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

    func testBrowserTrafficLightsRetargetToHostingWindowAfterAttach() {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        let host = NSHostingView(
            rootView: BrowserWindowTrafficLights(
                actionProvider: .browserWindow(nil),
                presentation: .interactive
            )
        )
        host.frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: BrowserWindowTrafficLightMetrics.sidebarReservedWidth,
                height: BrowserWindowTrafficLightMetrics.clusterHeight
            )
        )

        window.contentView = host
        host.layoutSubtreeIfNeeded()

        let minimizeButton = Self.button(
            in: host,
            accessibilityIdentifier: BrowserWindowControlsAccessibilityIdentifiers.minimizeButton
        )
        XCTAssertNotNil(minimizeButton)
        XCTAssertIdentical(minimizeButton?.target as AnyObject, window)
        XCTAssertEqual(minimizeButton?.action.map(NSStringFromSelector), "miniaturize:")
        XCTAssertTrue(minimizeButton?.isEnabled ?? false)

        window.hideNativeStandardWindowButtonsForBrowserChrome()
        host.layoutSubtreeIfNeeded()

        for identifier in [
            BrowserWindowControlsAccessibilityIdentifiers.closeButton,
            BrowserWindowControlsAccessibilityIdentifiers.minimizeButton,
            BrowserWindowControlsAccessibilityIdentifiers.zoomButton,
        ] {
            let button = Self.button(in: host, accessibilityIdentifier: identifier)
            XCTAssertNotNil(button, identifier)
            XCTAssertFalse(button?.isHidden ?? true, identifier)
            XCTAssertEqual(button?.alphaValue, 1, identifier)
            XCTAssertTrue(button?.isEnabled ?? false, identifier)
        }
    }

    private static func button(
        in view: NSView,
        accessibilityIdentifier: String
    ) -> NSButton? {
        if let button = view as? NSButton,
           button.accessibilityIdentifier() == accessibilityIdentifier {
            return button
        }

        for subview in view.subviews {
            if let button = button(in: subview, accessibilityIdentifier: accessibilityIdentifier) {
                return button
            }
        }

        return nil
    }
}
