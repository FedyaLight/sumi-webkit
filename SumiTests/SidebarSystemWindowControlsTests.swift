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

    func testTrafficLightMetricsPreserveBrowserChromeClusterSize() {
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.clusterHeight, 30)
        XCTAssertEqual(
            BrowserWindowTrafficLightMetrics.clusterWidth,
            BrowserWindowTrafficLightGeometry.resolvedClusterWidth
        )
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.clusterTrailingInset, 14)
        XCTAssertEqual(BrowserWindowTrafficLightMetrics.clusterHorizontalOffset, -1)
        XCTAssertEqual(
            BrowserWindowTrafficLightMetrics.sidebarReservedWidth,
            BrowserWindowTrafficLightGeometry.resolvedClusterWidth
                + BrowserWindowTrafficLightMetrics.clusterTrailingInset
        )
        XCTAssertEqual(SidebarChromeMetrics.topControlInset, 0)
        XCTAssertEqual(SidebarChromeMetrics.controlLeadingPadding, 18)
        XCTAssertEqual(SidebarChromeMetrics.contentHorizontalPadding, 8)
        XCTAssertEqual(SidebarChromeMetrics.controlStripHeight, 38)
        XCTAssertEqual(SidebarChromeMetrics.controlSpacing, 0)
        XCTAssertEqual(SidebarChromeMetrics.navigationButtonSize, 30)
        XCTAssertEqual(SidebarChromeMetrics.navigationIconSize, 14)
    }

    func testTrafficLightHeaderReservesRoomOnlyWhereTheClusterIsTheSidebars() {
        for rendering in [BrowserWindowTrafficLightRendering.chrome, .travelling, .handoff] {
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

    func testTrafficLightFallbackGeometryMatchesSystemClusterForCurrentOS() {
        let fallback = BrowserWindowTrafficLightGeometry.fallback

        if #available(macOS 26.0, *) {
            XCTAssertEqual(fallback.diameter, 14)
            XCTAssertEqual(fallback.centerSpacing, 23)
        } else {
            XCTAssertEqual(fallback.diameter, 12)
            XCTAssertEqual(fallback.centerSpacing, 20)
        }
        XCTAssertEqual(
            fallback.clusterWidth,
            fallback.diameter + fallback.centerSpacing * 2
        )
    }

    // MARK: - Rendering

    func testPlaceholderExistsOnlyDuringTravelAndTheOneFrameHandoff() {
        XCTAssertTrue(BrowserWindowTrafficLightRendering.travelling.showsPlaceholder)
        XCTAssertTrue(BrowserWindowTrafficLightRendering.handoff.showsPlaceholder)
        for rendering in [BrowserWindowTrafficLightRendering.hidden, .system, .chrome] {
            XCTAssertFalse(rendering.showsPlaceholder, "\(rendering)")
        }
    }

    func testTrafficLightSlotDoesNotCollapseWhenNativeButtonsReplacePlaceholder() throws {
        let reservedWidth = BrowserWindowTrafficLightMetrics.sidebarReservedWidth

        for rendering in [
            BrowserWindowTrafficLightRendering.travelling,
            .handoff,
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

    func testChromePresentationUsesDisplayFramesForNativeHandoff() throws {
        let presentation = BrowserWindowChromePresentation()
        presentation.performSidebarMotion(
            surface: .docked,
            toward: .visible,
            animation: nil,
            updateLayout: noLayoutMutation
        )

        XCTAssertEqual(presentation.trafficLights.rendering, .travelling)
        XCTAssertEqual(presentation.trafficLights.travelProgress, 1)
        XCTAssertEqual(presentation.placement.displayFrameRequest?.frameCount, 2)

        let confirmationID = try XCTUnwrap(presentation.placement.displayFrameRequest?.id)
        presentation.displayFramesDidElapse(requestID: confirmationID)
        XCTAssertEqual(presentation.trafficLights.rendering, .handoff)
        XCTAssertEqual(presentation.placement.displayFrameRequest?.frameCount, 1)

        let retirementID = try XCTUnwrap(presentation.placement.displayFrameRequest?.id)
        presentation.displayFramesDidElapse(requestID: retirementID)
        XCTAssertEqual(presentation.trafficLights.rendering, .chrome)
        XCTAssertNil(presentation.placement.displayFrameRequest)
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
        XCTAssertNil(presentation.placement.displayFrameRequest)
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
        XCTAssertNil(presentation.placement.displayFrameRequest)
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
        XCTAssertEqual(presentation.placement.displayFrameRequest?.frameCount, 2)
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
        XCTAssertEqual(presentation.trafficLights.rendering, .travelling)
        XCTAssertEqual(presentation.trafficLights.travelProgress, 1)
        XCTAssertEqual(presentation.placement.displayFrameRequest?.frameCount, 2)
    }

    func testInterruptedDisplayFrameConfirmationCannotRevealNativeButtons() async throws {
        let presentation = BrowserWindowChromePresentation()
        presentation.performSidebarMotion(
            surface: .collapsed,
            toward: .visible,
            animation: nil,
            updateLayout: noLayoutMutation
        )
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
        try await Task.sleep(for: .milliseconds(20))
        let staleRequestID = try XCTUnwrap(presentation.placement.displayFrameRequest?.id)

        presentation.performSidebarMotion(
            surface: .collapsed,
            toward: .hidden,
            animation: nil,
            updateLayout: noLayoutMutation
        )
        presentation.displayFramesDidElapse(requestID: staleRequestID)

        XCTAssertEqual(presentation.trafficLights.rendering, .hidden)
        XCTAssertNil(presentation.placement.displayFrameRequest)
    }

    func testCollapsedSidebarOffsetCarriesPlaceholderPixelsWithItsContent() throws {
        BrowserWindowTrafficLightSnapshotStore.acquireDemand()
        defer {
            BrowserWindowTrafficLightSnapshotStore.releaseDemand()
        }
        _ = BrowserWindowTrafficLightSnapshotStore.snapshot(
            isKeyWindow: true,
            scale: 2
        )

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
                        rendering: .travelling,
                        travelProgress: 0,
                        carriesOwnTravel: false
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
                        rendering: rendering,
                        travelProgress: 1,
                        carriesOwnTravel: false
                    )
                )
                Color.black.frame(width: markerWidth, height: 2)
            }
            .fixedSize()
        )

        return try XCTUnwrap(renderer.nsImage).size.width - markerWidth
    }

    // MARK: - Placement

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

    func testChromePlacementMovesTheNativeClusterContainerAndPreservesButtonSizes() throws {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        WindowChromeTestSupport.retain(window)
        let closeButton = try XCTUnwrap(window.standardWindowButton(.closeButton))
        let titlebarView = try XCTUnwrap(closeButton.superview)
        let titlebarContainer = try XCTUnwrap(titlebarView.superview)
        let containerHost = try XCTUnwrap(titlebarContainer.superview)
        let nativeContainerFrame = titlebarContainer.frame
        let nativeSizes = BrowserWindowTrafficLightAction.allCases.map {
            window.standardWindowButton($0.buttonType)?.frame.size
        }

        window.browserTrafficLightPlacement.apply(
            rendering: .chrome
        )

        let closeFrameInHost = titlebarView.convert(closeButton.frame, to: containerHost)
        XCTAssertEqual(
            titlebarContainer.frame.height,
            SidebarChromeMetrics.controlStripHeight
        )
        XCTAssertEqual(titlebarContainer.frame.maxY, nativeContainerFrame.maxY)
        XCTAssertEqual(titlebarContainer.frame.width, containerHost.bounds.width)
        XCTAssertEqual(closeFrameInHost.minX, BrowserWindowTrafficLightMetrics.chromeLeading)
        XCTAssertEqual(
            closeFrameInHost.midY,
            containerHost.bounds.maxY
                - SidebarChromeMetrics.topControlInset
                - SidebarChromeMetrics.controlStripHeight / 2
        )
        for (index, action) in BrowserWindowTrafficLightAction.allCases.enumerated() {
            XCTAssertEqual(
                window.standardWindowButton(action.buttonType)?.frame.size,
                nativeSizes[index],
                "\(action)"
            )
        }
    }

    func testChromePlacementMovesAppKitsSharedTrackingAreaWithTheNativeButtons() throws {
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

            XCTAssertFalse(
                closeButton.isHidden,
                "Visibility has one owner: the native titlebar container"
            )
            XCTAssertTrue(
                titlebarView.isHidden,
                "The native tracking hierarchy must be inactive while the placeholder is visible"
            )
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

        placement.apply(
            rendering: .handoff
        )
        XCTAssertFalse(closeButton.isHidden)
        XCTAssertFalse(titlebarView.isHidden)
        XCTAssertFalse(titlebarContainer.isHidden)
        XCTAssertEqual(closeButton.frame, chromeFrame)
        placement.apply(rendering: .chrome)
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
        let titlebarView = try XCTUnwrap(closeButton.superview)
        let placement = window.browserTrafficLightPlacement

        placement.apply(rendering: .chrome)
        NotificationCenter.default.post(
            name: NSWindow.willBeginSheetNotification,
            object: window
        )

        // AppKit can finish mutating its titlebar after the lifecycle notification returns.
        titlebarView.isHidden = true
        await Task.yield()
        await Task.yield()

        XCTAssertFalse(titlebarView.isHidden)
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
        XCTAssertTrue(titlebarView.isHidden)
        XCTAssertFalse(titlebarContainer.isHidden)
        XCTAssertFalse(closeButton.isHidden)
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
        XCTAssertTrue(titlebarView.isHidden)
        XCTAssertFalse(titlebarContainer.isHidden)
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

        XCTAssertTrue(titlebarView.isHidden)
        XCTAssertFalse(titlebarContainer.isHidden)
    }

    func testSystemRenderingCannotExposeButtonsOutsideFullScreen() throws {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        WindowChromeTestSupport.retain(window)
        let closeButton = try XCTUnwrap(window.standardWindowButton(.closeButton))
        let titlebarView = try XCTUnwrap(closeButton.superview)

        window.browserTrafficLightPlacement.apply(rendering: .system)

        XCTAssertTrue(titlebarView.isHidden)
    }

    // MARK: - Snapshot cache

    func testSnapshotStorePreparesANativeColdStartPlaceholder() throws {
        BrowserWindowTrafficLightSnapshotStore.acquireDemand()
        defer {
            BrowserWindowTrafficLightSnapshotStore.releaseDemand()
        }

        let snapshot = try XCTUnwrap(
            BrowserWindowTrafficLightSnapshotStore.snapshot(isKeyWindow: true, scale: 2)
        )
        XCTAssertEqual(snapshot.size.height, BrowserWindowTrafficLightGeometry.fallback.diameter)
        XCTAssertEqual(snapshot.size.width, BrowserWindowTrafficLightGeometry.fallback.clusterWidth)
    }

    func testSnapshotCacheFallsBackToTheOtherKeyStateRatherThanToNothing() throws {
        let window = WindowChromeTestSupport.makeBrowserWindow()
        WindowChromeTestSupport.retain(window)
        BrowserWindowTrafficLightSnapshotStore.acquireDemand()
        defer {
            BrowserWindowTrafficLightSnapshotStore.releaseDemand()
        }
        let items = try BrowserWindowTrafficLightAction.allCases.enumerated().map { index, action in
            BrowserWindowTrafficLightSnapshotItem(
                button: try XCTUnwrap(window.standardWindowButton(action.buttonType)),
                frame: CGRect(x: CGFloat(index) * 20, y: 0, width: 14, height: 14)
            )
        }

        BrowserWindowTrafficLightSnapshotStore.warm(
            isKeyWindow: false,
            items: items,
            size: CGSize(width: 54, height: 14),
            scale: 2
        )

        // Over the ~200ms a placeholder is on screen, coloured-versus-grey beats no cluster at all.
        let oppositeKeySnapshot = try XCTUnwrap(
            BrowserWindowTrafficLightSnapshotStore.snapshot(isKeyWindow: true, scale: 2)
        )
        let liveSnapshot = try XCTUnwrap(
            BrowserWindowTrafficLightSnapshotStore.snapshot(isKeyWindow: false, scale: 2)
        )
        XCTAssertIdentical(oppositeKeySnapshot.image, liveSnapshot.image)
    }

    func testSnapshotCacheReusesAStoredKeyState() throws {
        BrowserWindowTrafficLightSnapshotStore.acquireDemand()
        defer {
            BrowserWindowTrafficLightSnapshotStore.releaseDemand()
        }

        let window = WindowChromeTestSupport.makeBrowserWindow()
        WindowChromeTestSupport.retain(window)
        let items = try BrowserWindowTrafficLightAction.allCases.enumerated().map { index, action in
            BrowserWindowTrafficLightSnapshotItem(
                button: try XCTUnwrap(window.standardWindowButton(action.buttonType)),
                frame: CGRect(x: CGFloat(index) * 20, y: 0, width: 14, height: 14)
            )
        }
        let size = CGSize(width: 54, height: 14)

        for _ in 0..<5 {
            for isKeyWindow in [true, false] {
                BrowserWindowTrafficLightSnapshotStore.warm(
                    isKeyWindow: isKeyWindow,
                    items: items,
                    size: size,
                    scale: 2
                )
            }
        }

        let first = BrowserWindowTrafficLightSnapshotStore.snapshot(isKeyWindow: true, scale: 2)
        BrowserWindowTrafficLightSnapshotStore.warm(
            isKeyWindow: true,
            items: items,
            size: size,
            scale: 2
        )
        // Repeated collapses must reuse the cached picture rather than re-render it.
        XCTAssertIdentical(
            BrowserWindowTrafficLightSnapshotStore.snapshot(isKeyWindow: true, scale: 2)?.image,
            first?.image
        )
    }

    func testSnapshotRenderingRefusesAClusterItCannotDraw() throws {
        BrowserWindowTrafficLightSnapshotStore.acquireDemand()
        defer {
            BrowserWindowTrafficLightSnapshotStore.releaseDemand()
        }

        let fallback = try XCTUnwrap(
            BrowserWindowTrafficLightSnapshotStore.snapshot(isKeyWindow: true, scale: 2)
        )
        BrowserWindowTrafficLightSnapshotStore.warm(
            isKeyWindow: true,
            items: [],
            size: CGSize(width: 54, height: 14),
            scale: 2
        )

        let window = WindowChromeTestSupport.makeBrowserWindow()
        WindowChromeTestSupport.retain(window)
        let item = BrowserWindowTrafficLightSnapshotItem(
            button: try XCTUnwrap(window.standardWindowButton(.closeButton)),
            frame: CGRect(x: 0, y: 0, width: 14, height: 14)
        )
        BrowserWindowTrafficLightSnapshotStore.warm(
            isKeyWindow: true,
            items: [item],
            size: .zero,
            scale: 2
        )
        XCTAssertIdentical(
            BrowserWindowTrafficLightSnapshotStore.snapshot(
                isKeyWindow: true,
                scale: 2
            )?.image,
            fallback.image
        )
    }

    func testSnapshotDemandReleaseDropsCachedPixels() throws {
        let first: BrowserWindowTrafficLightClusterSnapshot = try {
            BrowserWindowTrafficLightSnapshotStore.acquireDemand()
            defer {
                BrowserWindowTrafficLightSnapshotStore.releaseDemand()
            }
            return try XCTUnwrap(
                BrowserWindowTrafficLightSnapshotStore.snapshot(
                    isKeyWindow: true,
                    scale: 2
                )
            )
        }()

        BrowserWindowTrafficLightSnapshotStore.acquireDemand()
        defer {
            BrowserWindowTrafficLightSnapshotStore.releaseDemand()
        }
        let second = try XCTUnwrap(
            BrowserWindowTrafficLightSnapshotStore.snapshot(
                isKeyWindow: true,
                scale: 2
            )
        )
        XCTAssertNotIdentical(first.image, second.image)
    }

    func testSnapshotCacheNeverReusesPixelsFromAnotherBackingScale() throws {
        BrowserWindowTrafficLightSnapshotStore.acquireDemand()
        defer {
            BrowserWindowTrafficLightSnapshotStore.releaseDemand()
        }
        let scaleTwo = try XCTUnwrap(
            BrowserWindowTrafficLightSnapshotStore.snapshot(
                isKeyWindow: true,
                scale: 2
            )
        )
        let scaleOne = try XCTUnwrap(
            BrowserWindowTrafficLightSnapshotStore.snapshot(
                isKeyWindow: true,
                scale: 1
            )
        )
        XCTAssertNotIdentical(scaleTwo.image, scaleOne.image)
    }
}

private func noLayoutMutation() {
    // Presentation-only tests intentionally have no docked or collapsed view state to mutate.
}
