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

    func testTrafficLightMetricsPreserveBrowserChromeLayout() throws {
        let snapshot = try XCTUnwrap(
            BrowserWindowTrafficLightSnapshotStore.snapshot()
        )

        XCTAssertEqual(BrowserWindowTrafficLightMetrics.clusterHeight, 30)
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.clusterWidth, snapshot.size.width)
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.clusterTrailingInset, 14)
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.placeholderOpacity, 0.16)
        XCTAssertEqual(
            BrowserWindowTrafficLightMetrics.sidebarReservedWidth,
            snapshot.size.width + BrowserWindowTrafficLightMetrics.clusterTrailingInset
        )
        XCTAssertEqual(SidebarChromeMetrics.topControlInset, 0)
        XCTAssertEqual(SidebarChromeMetrics.controlLeadingPadding, 18)
        XCTAssertEqual(SidebarChromeMetrics.contentHorizontalPadding, 8)
        XCTAssertEqual(SidebarChromeMetrics.controlStripHeight, 40)
        XCTAssertEqual(SidebarChromeMetrics.controlToURLBarSpacing, 4)
        XCTAssertEqual(SidebarChromeMetrics.controlSpacing, 0)
        XCTAssertEqual(SidebarChromeMetrics.navigationButtonSize, 30)
        XCTAssertEqual(SidebarChromeMetrics.navigationIconSize, 14)
    }

    func testTrafficLightHeaderReservesRoomOnlyWhereTheClusterIsTheSidebars() {
        for rendering in [BrowserWindowTrafficLightRendering.chrome, .travelling] {
            XCTAssertEqual(
                BrowserWindowTrafficLightMetrics.sidebarReservedWidth(for: rendering),
                BrowserWindowTrafficLightMetrics.sidebarReservedWidth,
                "\(rendering)"
            )
        }
        // Fullscreen draws its own cluster in the titlebar, so the header reclaims the room.
        for rendering in [BrowserWindowTrafficLightRendering.hidden, .system] {
            XCTAssertEqual(
                BrowserWindowTrafficLightMetrics.sidebarReservedWidth(for: rendering),
                0,
                "\(rendering)"
            )
        }
    }

    // MARK: - Native geometry

    func testTrafficLightGeometryMeasuresNativeClusterWidth() {
        // Frames as macOS 26 lays the cluster out in NSTitlebarView.
        let clusterWidth = BrowserWindowTrafficLightGeometry.measuredClusterWidth(
            fromNativeFrames: [
            NSRect(x: 9, y: 9, width: 14, height: 14),
            NSRect(x: 32, y: 9, width: 14, height: 14),
            NSRect(x: 55, y: 9, width: 14, height: 14),
            ]
        )

        XCTAssertEqual(clusterWidth, 60)
    }

    func testTrafficLightGeometryToleratesAClusterAppKitLaysOutUnevenly() {
        // The zoom button carries a compact menu and is not always sized or pitched like its
        // neighbours. Nothing computes button positions from this measurement any more — it only
        // reserves room — so an uneven cluster has to measure rather than fall back.
        let clusterWidth = BrowserWindowTrafficLightGeometry.measuredClusterWidth(
            fromNativeFrames: [
                NSRect(x: 9, y: 9, width: 14, height: 14),
                NSRect(x: 32, y: 9, width: 14, height: 14),
                NSRect(x: 55, y: 8, width: 18, height: 16),
            ]
        )

        XCTAssertEqual(clusterWidth, 64)
    }

    func testTrafficLightGeometryRejectsFramesThatCannotDescribeACluster() {
        let square = NSRect(x: 0, y: 0, width: 14, height: 14)

        XCTAssertNil(BrowserWindowTrafficLightGeometry.measuredClusterWidth(fromNativeFrames: []))
        XCTAssertNil(BrowserWindowTrafficLightGeometry.measuredClusterWidth(fromNativeFrames: [square, square]))
        XCTAssertNil(BrowserWindowTrafficLightGeometry.measuredClusterWidth(fromNativeFrames: [
            .zero, .zero, .zero,
        ]))
        // Buttons still collapsed to a zero-height frame before their first layout.
        XCTAssertNil(BrowserWindowTrafficLightGeometry.measuredClusterWidth(fromNativeFrames: [
            NSRect(x: 9, y: 9, width: 14, height: 0),
            NSRect(x: 32, y: 9, width: 14, height: 0),
            NSRect(x: 55, y: 9, width: 14, height: 0),
        ]))
        // Buttons stacked rather than laid out left to right.
        XCTAssertNil(BrowserWindowTrafficLightGeometry.measuredClusterWidth(fromNativeFrames: [
            square, square, square,
        ]))
    }

    func testSystemPlaceholderGeometryComesFromAppKit() throws {
        let snapshot = try XCTUnwrap(
            BrowserWindowTrafficLightSnapshotStore.snapshot()
        )
        XCTAssertGreaterThan(snapshot.size.width, 0)
        XCTAssertGreaterThan(snapshot.size.height, 0)
        XCTAssertGreaterThanOrEqual(snapshot.leadingInset, 0)
        XCTAssertGreaterThanOrEqual(snapshot.topInset, 0)
        XCTAssertEqual(
            snapshot.buttonFrames.count,
            BrowserWindowTrafficLightAction.allCases.count
        )
        XCTAssertEqual(
            snapshot.topInset + snapshot.size.height / 2,
            SidebarChromeMetrics.controlStripHeight / 2,
            accuracy: 0.5
        )
    }

    // MARK: - Rendering

    func testPlaceholderRemainsMountedUnderSettledNativeButtons() {
        XCTAssertTrue(BrowserWindowTrafficLightRendering.travelling.showsPlaceholder)
        XCTAssertTrue(BrowserWindowTrafficLightRendering.chrome.showsPlaceholder)
        for rendering in [BrowserWindowTrafficLightRendering.hidden, .system] {
            XCTAssertFalse(rendering.showsPlaceholder, "\(rendering)")
        }
    }

    func testTrafficLightSlotDoesNotCollapseWhenNativeButtonsReplacePlaceholder() throws {
        let reservedWidth = BrowserWindowTrafficLightMetrics.sidebarReservedWidth

        for rendering in [
            BrowserWindowTrafficLightRendering.travelling,
            .chrome,
        ] {
            XCTAssertEqual(
                try renderedTrafficLightSlotWidth(rendering: rendering),
                reservedWidth,
                accuracy: 0.5,
                "\(rendering)"
            )
        }
    }

    func testSettledDockedSidebarRevealsNativeButtonsWithoutAFrameHandoff() {
        let presentation = BrowserWindowChromePresentation()
        presentation.performSidebarMotion(
            surface: .docked,
            toward: .visible,
            animation: nil,
            updateLayout: noLayoutMutation
        )

        XCTAssertEqual(presentation.trafficLights.rendering, .chrome)
        XCTAssertEqual(
            presentation.sidebarLayoutPhase,
            .settled(surface: .docked, visibility: .visible)
        )
    }

    func testFullScreenHandoverIsNotTreatedAsATrip() {
        let presentation = BrowserWindowChromePresentation()
        presentation.performSidebarMotion(
            surface: .docked,
            toward: .visible,
            animation: nil,
            updateLayout: noLayoutMutation
        )

        presentation.configure(
            shellEdge: SidebarPosition.left.shellEdge,
            isBrowserWindowFullScreen: true
        )

        XCTAssertEqual(presentation.trafficLights.rendering, .system)
    }

    func testTrailingSidebarKeepsNativeWindowControlsWithdrawn() {
        let presentation = BrowserWindowChromePresentation()
        presentation.configure(
            shellEdge: SidebarPosition.right.shellEdge,
            isBrowserWindowFullScreen: false
        )
        presentation.performSidebarMotion(
            surface: .docked,
            toward: .visible,
            animation: nil,
            updateLayout: noLayoutMutation
        )

        XCTAssertEqual(presentation.trafficLights.rendering, .hidden)
        XCTAssertFalse(presentation.placement.isLeadingSidebarChrome)
    }

    func testImmediateCollapsedHidePublishesOneSettledState() {
        let presentation = BrowserWindowChromePresentation()
        presentation.performSidebarMotion(
            surface: .collapsed,
            toward: .hidden,
            animation: nil,
            updateLayout: noLayoutMutation
        )

        XCTAssertEqual(presentation.trafficLights.rendering, .hidden)
        XCTAssertEqual(
            presentation.sidebarLayoutPhase,
            .settled(surface: .collapsed, visibility: .hidden)
        )
    }

    func testCollapsedSidebarIgnoresSettlementFromAnInterruptedTrip() async {
        let presentation = BrowserWindowChromePresentation()
        presentation.performSidebarMotion(
            surface: .collapsed,
            toward: .hidden,
            animation: .linear(duration: 0.01),
            updateLayout: noLayoutMutation
        )
        presentation.performSidebarMotion(
            surface: .collapsed,
            toward: .visible,
            animation: nil,
            updateLayout: noLayoutMutation
        )
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(
            presentation.sidebarLayoutPhase,
            .settled(surface: .collapsed, visibility: .visible)
        )
        XCTAssertEqual(presentation.trafficLights.rendering, .chrome)
    }

    func testCollapsedHostRetirementCannotOverrideDockedReveal() async {
        let presentation = BrowserWindowChromePresentation()
        presentation.performSidebarMotion(
            surface: .collapsed,
            toward: .visible,
            animation: nil,
            updateLayout: noLayoutMutation
        )
        await Task.yield()

        presentation.performSidebarMotion(
            surface: .docked,
            toward: .visible,
            animation: nil,
            updateLayout: noLayoutMutation
        )
        presentation.performSidebarMotion(
            surface: .collapsed,
            toward: .hidden,
            animation: nil,
            updateLayout: noLayoutMutation
        )

        XCTAssertEqual(
            presentation.sidebarLayoutPhase,
            .settled(surface: .docked, visibility: .visible)
        )
        XCTAssertEqual(presentation.trafficLights.rendering, .chrome)
    }

    func testInterruptedMotionCompletionCannotRevealNativeButtons() async {
        let presentation = BrowserWindowChromePresentation()
        presentation.performSidebarMotion(
            surface: .collapsed,
            toward: .visible,
            animation: .linear(duration: 0.02),
            updateLayout: noLayoutMutation
        )

        presentation.performSidebarMotion(
            surface: .collapsed,
            toward: .hidden,
            animation: nil,
            updateLayout: noLayoutMutation
        )
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(presentation.trafficLights.rendering, .hidden)
        XCTAssertEqual(
            presentation.sidebarLayoutPhase,
            .settled(surface: .collapsed, visibility: .hidden)
        )
    }

    func testCollapsedSidebarOffsetCarriesPlaceholderPixelsWithItsContent() throws {
        _ = BrowserWindowTrafficLightSnapshotStore.snapshot()

        let firstOffset: CGFloat = 12
        let secondOffset: CGFloat = 72
        let firstLeadingEdge = try placeholderLeadingEdge(renderedAt: firstOffset)
        let secondLeadingEdge = try placeholderLeadingEdge(renderedAt: secondOffset)

        XCTAssertEqual(
            secondLeadingEdge - firstLeadingEdge,
            secondOffset - firstOffset,
            accuracy: 0.5
        )
    }

    private func placeholderLeadingEdge(renderedAt parentOffset: CGFloat) throws -> CGFloat {
        let renderer = ImageRenderer(content:
            ZStack(alignment: .topLeading) {
                Color.clear
                BrowserWindowTrafficLights(
                    presentation: BrowserWindowTrafficLightPresentation(
                        rendering: .travelling
                    )
                )
                .offset(x: parentOffset)
            }
            .frame(width: 180, height: 40)
        )
        renderer.scale = 2

        let image = try XCTUnwrap(renderer.nsImage)
        let bitmap = try XCTUnwrap(
            image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
        )

        var firstOpaquePixelX: Int?
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y),
                      color.alphaComponent > 0.1
                else { continue }
                firstOpaquePixelX = min(firstOpaquePixelX ?? x, x)
            }
        }

        return CGFloat(try XCTUnwrap(firstOpaquePixelX)) / renderer.scale
    }

    private func renderedTrafficLightSlotWidth(
        rendering: BrowserWindowTrafficLightRendering
    ) throws -> CGFloat {
        let markerWidth: CGFloat = 2
        let renderer = ImageRenderer(content:
            HStack(spacing: 0) {
                BrowserWindowTrafficLights(
                    presentation: BrowserWindowTrafficLightPresentation(
                        rendering: rendering
                    )
                )
                Color.black.frame(width: markerWidth, height: 2)
            }
            .fixedSize()
        )

        return try XCTUnwrap(renderer.nsImage).size.width - markerWidth
    }

    // MARK: - Placement

    func testBrowserWindowUsesSystemTitlebarGeometryAlignedWithSidebarControls() throws {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        WindowChromeTestSupport.retain(window)
        let closeButton = try XCTUnwrap(window.standardWindowButton(.closeButton))
        let closeFrameInWindow = closeButton.convert(closeButton.bounds, to: nil)
        let closeCenterFromTop = window.frame.height - closeFrameInWindow.midY
        let toolbar = try XCTUnwrap(window.toolbar)

        XCTAssertEqual(window.toolbarStyle, .unifiedCompact)
        XCTAssertEqual(toolbar.displayMode, .iconOnly)
        XCTAssertTrue(toolbar.items.isEmpty)
        let snapshot = try XCTUnwrap(BrowserWindowTrafficLightSnapshotStore.snapshot())
        XCTAssertEqual(closeFrameInWindow.minX, snapshot.leadingInset, accuracy: 0.5)
        XCTAssertEqual(
            closeCenterFromTop,
            SidebarChromeMetrics.controlStripHeight / 2,
            accuracy: 0.5
        )
    }

    func testPlacementNeverMutatesAppKitsTitlebarHierarchyOrNativeButtonFrames() throws {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        WindowChromeTestSupport.retain(window)
        let buttons = try BrowserWindowTrafficLightAction.allCases.map { action in
            try XCTUnwrap(window.standardWindowButton(action.buttonType))
        }
        let titlebarView = try XCTUnwrap(buttons.first?.superview)
        let titlebarContainer = try XCTUnwrap(titlebarView.superview)
        let nativeButtonFrames = buttons.map(\.frame)
        let nativeContainerFrame = titlebarContainer.frame

        XCTAssertFalse(titlebarView.isHidden)
        XCTAssertFalse(titlebarContainer.isHidden)

        window.browserTrafficLightPlacement.apply(rendering: .chrome)

        XCTAssertEqual(buttons.map(\.frame), nativeButtonFrames)
        XCTAssertEqual(titlebarContainer.frame, nativeContainerFrame)
        XCTAssertFalse(titlebarView.isHidden)
        XCTAssertTrue(buttons.allSatisfy { !$0.isHidden })

        window.browserTrafficLightPlacement.apply(rendering: .travelling)

        XCTAssertEqual(buttons.map(\.frame), nativeButtonFrames)
        XCTAssertEqual(titlebarContainer.frame, nativeContainerFrame)
        XCTAssertFalse(titlebarView.isHidden)
        XCTAssertFalse(titlebarContainer.isHidden)
        XCTAssertTrue(buttons.allSatisfy(\.isHidden))
    }

    func testChromePlacementKeepsNativeButtonsInAppKitsTitlebar() throws {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        WindowChromeTestSupport.retain(window)
        let closeButton = try XCTUnwrap(window.standardWindowButton(.closeButton))
        let titlebarSuperview = try XCTUnwrap(closeButton.superview)
        let nativeSizes = BrowserWindowTrafficLightAction.allCases.map {
            window.standardWindowButton($0.buttonType)?.frame.size
        }

        window.browserTrafficLightPlacement.apply(
            rendering: .chrome
        )

        for (index, action) in BrowserWindowTrafficLightAction.allCases.enumerated() {
            let button = try XCTUnwrap(window.standardWindowButton(action.buttonType))
            XCTAssertIdentical(button.superview, titlebarSuperview, "\(action)")
            XCTAssertEqual(button.frame.size, nativeSizes[index], "\(action)")
        }
    }

    func testChromePlacementPreservesAppKitsNativeContainerAndButtonGeometry() throws {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        WindowChromeTestSupport.retain(window)
        let closeButton = try XCTUnwrap(window.standardWindowButton(.closeButton))
        let titlebarView = try XCTUnwrap(closeButton.superview)
        let titlebarContainer = try XCTUnwrap(titlebarView.superview)
        let nativeContainerFrame = titlebarContainer.frame
        let nativeFrames = BrowserWindowTrafficLightAction.allCases.map {
            window.standardWindowButton($0.buttonType)?.frame
        }

        window.browserTrafficLightPlacement.apply(
            rendering: .chrome
        )

        XCTAssertEqual(titlebarContainer.frame, nativeContainerFrame)
        for (index, action) in BrowserWindowTrafficLightAction.allCases.enumerated() {
            XCTAssertEqual(
                window.standardWindowButton(action.buttonType)?.frame,
                nativeFrames[index],
                "\(action)"
            )
        }
    }

    func testChromePlacementLeavesAppKitsSharedTrackingAreaWithTheNativeButtons() throws {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        WindowChromeTestSupport.retain(window)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        let closeButton = try XCTUnwrap(window.standardWindowButton(.closeButton))
        let titlebarView = try XCTUnwrap(closeButton.superview)

        window.browserTrafficLightPlacement.apply(rendering: .chrome)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let clusterFrame = BrowserWindowTrafficLightAction.allCases.compactMap {
            window.standardWindowButton($0.buttonType)?.frame
        }.reduce(CGRect.null) { $0.union($1) }
        let sharedTrackingArea = try XCTUnwrap(titlebarView.trackingAreas.first {
            ($0.owner as AnyObject?) === titlebarView
                && $0.options.contains(.mouseEnteredAndExited)
        })

        XCTAssertEqual(sharedTrackingArea.rect, clusterFrame)
    }

    func testVisibilityChangesKeepTheFixedChromeOrigins() throws {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        WindowChromeTestSupport.retain(window)
        let closeButton = try XCTUnwrap(window.standardWindowButton(.closeButton))
        let titlebarView = try XCTUnwrap(closeButton.superview)
        let titlebarContainer = try XCTUnwrap(titlebarView.superview)
        let placement = window.browserTrafficLightPlacement

        placement.apply(
            rendering: .chrome
        )
        let chromeFrame = closeButton.frame
        XCTAssertFalse(titlebarView.isHidden)
        XCTAssertFalse(titlebarContainer.isHidden)

        for rendering in [BrowserWindowTrafficLightRendering.travelling, .hidden] {
            placement.apply(
                rendering: rendering
            )

            XCTAssertTrue(closeButton.isHidden)
            XCTAssertFalse(titlebarView.isHidden)
            XCTAssertFalse(
                titlebarContainer.isHidden,
                "The AppKit-owned titlebar container must never be hidden"
            )
            XCTAssertEqual(closeButton.alphaValue, 1, "Visibility must not be implemented twice")
            XCTAssertEqual(closeButton.frame, chromeFrame, "\(rendering)")

            placement.apply(
                rendering: .chrome
            )
            XCTAssertFalse(closeButton.isHidden, "\(rendering)")
            XCTAssertFalse(titlebarView.isHidden, "\(rendering)")
            XCTAssertFalse(titlebarContainer.isHidden, "\(rendering)")
            XCTAssertEqual(closeButton.frame, chromeFrame, "\(rendering)")
        }
    }

    func testPlacementExposesAccessibilityIdentifiersOnlyWhileTheClusterIsVisible() throws {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        WindowChromeTestSupport.retain(window)
        let closeButton = try XCTUnwrap(window.standardWindowButton(.closeButton))
        let placement = window.browserTrafficLightPlacement

        placement.apply(
            rendering: .chrome
        )
        XCTAssertEqual(
            closeButton.accessibilityIdentifier(),
            BrowserWindowControlsAccessibilityIdentifiers.closeButton
        )

        placement.apply(
            rendering: .hidden
        )
        XCTAssertTrue(closeButton.accessibilityIdentifier().isEmpty)
        XCTAssertTrue(closeButton.isAccessibilityHidden())
    }

    func testPlacementPreservesNativeAppKitTargetsAndActions() throws {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        WindowChromeTestSupport.retain(window)
        let closeButton = try XCTUnwrap(window.standardWindowButton(.closeButton))
        let nativeTarget = closeButton.target
        let nativeAction = closeButton.action

        window.browserTrafficLightPlacement.apply(
            rendering: .chrome
        )

        XCTAssertIdentical(closeButton.target as AnyObject?, nativeTarget as AnyObject?)
        XCTAssertEqual(closeButton.action, nativeAction)
    }

    func testPlacementReassertsChromeAfterAppKitFinishesModalLifecycleWork() async throws {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        WindowChromeTestSupport.retain(window)
        let closeButton = try XCTUnwrap(window.standardWindowButton(.closeButton))
        let placement = window.browserTrafficLightPlacement

        placement.apply(rendering: .chrome)
        NotificationCenter.default.post(
            name: NSWindow.willBeginSheetNotification,
            object: window
        )

        // AppKit can finish replacing or mutating its buttons after the lifecycle notification.
        closeButton.isHidden = true
        await Task.yield()
        await Task.yield()

        XCTAssertFalse(closeButton.isHidden)
    }

    func testStableWindowPlacementResignsWithoutSidebarOwnership() throws {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        WindowChromeTestSupport.retain(window)
        let closeButton = try XCTUnwrap(window.standardWindowButton(.closeButton))
        let titlebarView = try XCTUnwrap(closeButton.superview)
        let titlebarContainer = try XCTUnwrap(titlebarView.superview)
        let placement = window.browserTrafficLightPlacement

        placement.apply(rendering: .chrome)
        placement.resign()
        XCTAssertFalse(titlebarView.isHidden)
        XCTAssertFalse(titlebarContainer.isHidden)
        XCTAssertTrue(closeButton.isHidden)
    }

    func testFullScreenTransitionKeepsTheChromeOutOfAppKitsWay() throws {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        WindowChromeTestSupport.retain(window)
        let closeButton = try XCTUnwrap(window.standardWindowButton(.closeButton))
        let titlebarView = try XCTUnwrap(closeButton.superview)
        let titlebarContainer = try XCTUnwrap(titlebarView.superview)
        let nativeFrame = closeButton.frame
        let placement = window.browserTrafficLightPlacement

        placement.apply(
            rendering: .chrome
        )

        placement.beginFullScreenTransition(isEntering: true)
        XCTAssertFalse(titlebarView.isHidden)
        XCTAssertFalse(titlebarContainer.isHidden)
        XCTAssertEqual(closeButton.frame, nativeFrame)

        placement.beginFullScreenTransition(isEntering: false)
        XCTAssertFalse(titlebarView.isHidden)
        XCTAssertFalse(titlebarContainer.isHidden)
        XCTAssertTrue(closeButton.isHidden)
        XCTAssertEqual(closeButton.frame, nativeFrame)

        placement.endFullScreenTransition()
        XCTAssertFalse(titlebarView.isHidden)
        XCTAssertFalse(titlebarContainer.isHidden)
    }

    func testTrailingSidebarKeepsTrafficLightsHiddenDuringFullScreenTransition() throws {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        WindowChromeTestSupport.retain(window)
        let closeButton = try XCTUnwrap(window.standardWindowButton(.closeButton))
        let titlebarView = try XCTUnwrap(closeButton.superview)
        let titlebarContainer = try XCTUnwrap(titlebarView.superview)
        let placement = window.browserTrafficLightPlacement

        placement.apply(
            rendering: .hidden,
            isLeadingSidebarChrome: false
        )
        placement.beginFullScreenTransition(isEntering: true)

        XCTAssertFalse(titlebarView.isHidden)
        XCTAssertFalse(titlebarContainer.isHidden)
        XCTAssertTrue(closeButton.isHidden)
    }

    func testSystemRenderingCannotExposeButtonsOutsideFullScreen() throws {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        WindowChromeTestSupport.retain(window)
        let closeButton = try XCTUnwrap(window.standardWindowButton(.closeButton))
        let titlebarView = try XCTUnwrap(closeButton.superview)

        window.browserTrafficLightPlacement.apply(rendering: .system)

        XCTAssertFalse(titlebarView.isHidden)
        XCTAssertTrue(closeButton.isHidden)
    }

    // MARK: - Placeholder geometry

    func testSnapshotStorePreparesNativeColdStartGeometry() throws {
        let snapshot = try XCTUnwrap(
            BrowserWindowTrafficLightSnapshotStore.snapshot()
        )
        XCTAssertGreaterThan(snapshot.size.width, 0)
        XCTAssertGreaterThan(snapshot.size.height, 0)
        XCTAssertGreaterThanOrEqual(snapshot.leadingInset, 0)
        XCTAssertGreaterThanOrEqual(snapshot.topInset, 0)
        XCTAssertEqual(snapshot.buttonFrames.count, 3)
    }

    func testSnapshotStoreReusesTheMeasuredSystemGeometry() {
        XCTAssertEqual(
            BrowserWindowTrafficLightSnapshotStore.snapshot(),
            BrowserWindowTrafficLightSnapshotStore.snapshot()
        )
    }

    func testPlaceholderShapeTurnsEveryNativeButtonFrameIntoACircle() {
        let nativeFrames = [
            CGRect(x: 0, y: 0, width: 18, height: 14),
            CGRect(x: 24, y: 0, width: 14, height: 14),
            CGRect(x: 47, y: 0, width: 14, height: 18),
        ]
        let path = BrowserWindowTrafficLightPlaceholderShape(
            nativeButtonFrames: nativeFrames
        ).path(in: CGRect(x: 0, y: 0, width: 61, height: 18))

        for frame in nativeFrames {
            XCTAssertTrue(path.contains(CGPoint(x: frame.midX, y: frame.midY)))
            XCTAssertFalse(path.contains(CGPoint(x: frame.minX, y: frame.minY)))
        }
        XCTAssertGreaterThan(BrowserWindowTrafficLightMetrics.placeholderOpacity, 0)
        XCTAssertLessThan(BrowserWindowTrafficLightMetrics.placeholderOpacity, 1)
    }
}

private func noLayoutMutation() {
    // Presentation-only tests intentionally have no docked or collapsed view state to mutate.
}
