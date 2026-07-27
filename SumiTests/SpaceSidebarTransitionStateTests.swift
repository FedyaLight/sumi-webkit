import AppKit
@testable import Sumi
import SumiDomain
import SwiftUI
import XCTest

@MainActor
final class SpaceSidebarTransitionStateTests: XCTestCase {
    func testSidebarSwipeCapturePrefersTabListForVerticalAndWheelScrolling() {
        XCTAssertTrue(
            SidebarSwipeScrollForwardingPolicy.shouldPreferTabListScroll(
                hasPreciseScrollingDeltas: false,
                scrollingDeltaX: 20,
                scrollingDeltaY: 0
            )
        )
        XCTAssertTrue(
            SidebarSwipeScrollForwardingPolicy.shouldPreferTabListScroll(
                hasPreciseScrollingDeltas: true,
                scrollingDeltaX: 2,
                scrollingDeltaY: 12
            )
        )
        XCTAssertFalse(
            SidebarSwipeScrollForwardingPolicy.shouldPreferTabListScroll(
                hasPreciseScrollingDeltas: true,
                scrollingDeltaX: 12,
                scrollingDeltaY: 2
            )
        )
    }

    func testSidebarSwipeCaptureKeepsTerminalHorizontalSampleInGesturePipeline() {
        var tracker = SpaceSwipeGestureTracker()

        _ = tracker.process(
            .init(phase: .began, scrollingDeltaX: -1, scrollingDeltaY: 0),
            width: 200,
            isEnabled: true
        )
        _ = tracker.process(
            .init(phase: .changed, scrollingDeltaX: -4, scrollingDeltaY: 0),
            width: 200,
            isEnabled: true
        )
        XCTAssertEqual(tracker.axisLock, .horizontal)

        XCTAssertFalse(
            SidebarSwipeScrollForwardingPolicy.shouldPreferTabListScroll(
                hasPreciseScrollingDeltas: true,
                scrollingDeltaX: 0,
                scrollingDeltaY: 0,
                isSpaceSwipeTracking: tracker.ownsScrollSequence
            )
        )
        XCTAssertFalse(
            SidebarSwipeScrollForwardingPolicy.shouldPreferTabListScroll(
                hasPreciseScrollingDeltas: true,
                scrollingDeltaX: 0.2,
                scrollingDeltaY: 1,
                isSpaceSwipeTracking: tracker.ownsScrollSequence
            )
        )

        let ended = tracker.process(
            .init(phase: .ended),
            width: 200,
            isEnabled: true
        )
        XCTAssertEqual(ended.emittedEvents.last?.phase, .ended)
        XCTAssertEqual(tracker.axisLock, .unresolved)
    }

    func testPassiveScrollIndicatorIsHiddenWhenContentFits() {
        XCTAssertNil(
            SidebarPassiveScrollIndicatorLayout.metrics(
                viewportHeight: 120,
                contentHeight: 120,
                contentOffset: 0
            )
        )
    }

    func testPassiveScrollIndicatorTracksScrollProgress() throws {
        let metrics = try XCTUnwrap(
            SidebarPassiveScrollIndicatorLayout.metrics(
                viewportHeight: 100,
                contentHeight: 200,
                contentOffset: 50
            )
        )

        XCTAssertEqual(metrics.thumbHeight, 50, accuracy: 0.001)
        XCTAssertEqual(metrics.thumbOffsetY, 25, accuracy: 0.001)
    }

    func testPassiveScrollIndicatorClampsElasticOffsets() throws {
        let topMetrics = try XCTUnwrap(
            SidebarPassiveScrollIndicatorLayout.metrics(
                viewportHeight: 100,
                contentHeight: 500,
                contentOffset: -40
            )
        )
        let bottomMetrics = try XCTUnwrap(
            SidebarPassiveScrollIndicatorLayout.metrics(
                viewportHeight: 100,
                contentHeight: 500,
                contentOffset: 999
            )
        )

        XCTAssertEqual(topMetrics.thumbOffsetY, 0, accuracy: 0.001)
        XCTAssertEqual(bottomMetrics.thumbOffsetY, 72, accuracy: 0.001)
    }

    func testPassiveScrollIndicatorFrameInsetsFromSidebarBoundaryFromContentViewport() {
        let outerWidth: CGFloat = 240
        let viewportHeight: CGFloat = 320
        let contentViewportWidth = SpaceViewLayout.contentWidth(for: outerWidth)
        let trailingProjection = SpaceViewLayout.scrollIndicatorTrailingProjection
        let scrollViewFrameInOverlay = CGRect(x: 8, y: 12, width: contentViewportWidth, height: viewportHeight)

        let frame = SidebarPassiveScrollIndicatorLayout.indicatorFrame(
            scrollViewFrameInOverlay: scrollViewFrameInOverlay,
            viewportHeight: viewportHeight,
            contentViewportWidth: contentViewportWidth,
            trailingProjection: trailingProjection
        )
        let sidebarBoundaryX = scrollViewFrameInOverlay.minX + contentViewportWidth + SpaceViewLayout.horizontalPadding

        XCTAssertEqual(contentViewportWidth, outerWidth - SpaceViewLayout.horizontalPaddingTotal, accuracy: 0.001)
        XCTAssertEqual(SpaceViewLayout.scrollIndicatorBoundaryInset, 3, accuracy: 0.001)
        XCTAssertEqual(frame.maxX, sidebarBoundaryX - SpaceViewLayout.scrollIndicatorBoundaryInset, accuracy: 0.001)
        XCTAssertLessThanOrEqual(frame.maxX, sidebarBoundaryX)
        XCTAssertEqual(frame.minY, scrollViewFrameInOverlay.minY, accuracy: 0.001)
        XCTAssertEqual(frame.width, SidebarPassiveScrollIndicatorLayout.trackWidth, accuracy: 0.001)
        XCTAssertEqual(frame.height, viewportHeight, accuracy: 0.001)
    }

    func testPassiveScrollIndicatorUsesFortyPercentThumbOpacityAndExpandedHoverWidth() {
        XCTAssertEqual(SidebarPassiveScrollIndicatorLayout.thumbWidth, 3, accuracy: 0.001)
        XCTAssertEqual(SidebarPassiveScrollIndicatorLayout.expandedThumbWidth, 7, accuracy: 0.001)
        XCTAssertEqual(SidebarPassiveScrollIndicatorLayout.thumbOpacity, 0.40, accuracy: 0.001)
        XCTAssertEqual(SidebarPassiveScrollIndicatorLayout.visibleDuration, 2.0, accuracy: 0.001)
    }

    func testPassiveScrollIndicatorInteractionFrameKeepsResizeBoundaryGap() {
        let outerWidth: CGFloat = 240
        let viewportHeight: CGFloat = 320
        let contentViewportWidth = SpaceViewLayout.contentWidth(for: outerWidth)
        let trailingProjection = SpaceViewLayout.scrollIndicatorTrailingProjection
        let scrollViewFrameInOverlay = CGRect(x: 8, y: 12, width: contentViewportWidth, height: viewportHeight)
        let indicatorFrame = SidebarPassiveScrollIndicatorLayout.indicatorFrame(
            scrollViewFrameInOverlay: scrollViewFrameInOverlay,
            viewportHeight: viewportHeight,
            contentViewportWidth: contentViewportWidth,
            trailingProjection: trailingProjection
        )
        let metrics = SidebarPassiveScrollIndicatorMetrics(thumbOffsetY: 24, thumbHeight: 60)

        let interactionFrame = SidebarPassiveScrollIndicatorLayout.thumbInteractionFrame(
            in: indicatorFrame,
            metrics: metrics
        )
        let sidebarBoundaryX = scrollViewFrameInOverlay.minX + contentViewportWidth + SpaceViewLayout.horizontalPadding

        XCTAssertEqual(interactionFrame.width, 7, accuracy: 0.001)
        XCTAssertEqual(interactionFrame.maxX, indicatorFrame.maxX, accuracy: 0.001)
        XCTAssertEqual(interactionFrame.minX, indicatorFrame.maxX - 7, accuracy: 0.001)
        XCTAssertEqual(interactionFrame.maxX, sidebarBoundaryX - SpaceViewLayout.scrollIndicatorBoundaryInset, accuracy: 0.001)
        XCTAssertLessThan(interactionFrame.width, SidebarPassiveScrollIndicatorLayout.trackWidth)
    }

    func testSidebarResizeGrabberFlashesFullBorderButResizesCenteredZone() {
        let bounds = CGRect(x: 0, y: 0, width: 240, height: 400)

        let leftStrip = SidebarResizeGrabberLayout.borderStripFrame(in: bounds, sidebarPosition: .left)
        let rightStrip = SidebarResizeGrabberLayout.borderStripFrame(in: bounds, sidebarPosition: .right)
        // Interaction geometry is computed against the grabber view's own bounds.
        let stripBounds = CGRect(origin: .zero, size: leftStrip.size)

        XCTAssertEqual(SidebarResizeGrabberLayout.interactionWidth, 7, accuracy: 0.001)
        XCTAssertEqual(SidebarResizeGrabberLayout.interactionHeight, 64, accuracy: 0.001)
        XCTAssertEqual(SidebarResizeGrabberLayout.activationDelay, 0.5, accuracy: 0.001)
        XCTAssertEqual(SidebarResizeGrabberLayout.inactiveOpacity, 0.30, accuracy: 0.001)
        XCTAssertEqual(SidebarResizeGrabberLayout.activeOpacity, 0.60, accuracy: 0.001)

        // The hover/flash strip spans the full boundary height and is wider than
        // the resize target so fast crossings are still caught.
        XCTAssertEqual(leftStrip.width, SidebarResizeGrabberLayout.hoverStripWidth, accuracy: 0.001)
        XCTAssertGreaterThan(SidebarResizeGrabberLayout.hoverStripWidth, SidebarResizeGrabberLayout.interactionWidth)
        XCTAssertEqual(leftStrip.height, bounds.height, accuracy: 0.001)
        XCTAssertEqual(leftStrip.maxX, bounds.maxX, accuracy: 0.001)
        XCTAssertEqual(leftStrip.minY, bounds.minY, accuracy: 0.001)
        XCTAssertEqual(rightStrip.width, SidebarResizeGrabberLayout.hoverStripWidth, accuracy: 0.001)
        XCTAssertEqual(rightStrip.height, bounds.height, accuracy: 0.001)
        XCTAssertEqual(rightStrip.minX, bounds.minX, accuracy: 0.001)

        // The interactive resize zone is a fixed-height band anchored to the
        // boundary edge, keeping the narrow resize width regardless of the strip.
        let resizeZone = SidebarResizeGrabberLayout.resizeZoneFrame(in: stripBounds, sidebarPosition: .left)
        XCTAssertEqual(resizeZone.height, SidebarResizeGrabberLayout.interactionHeight, accuracy: 0.001)
        XCTAssertEqual(resizeZone.width, SidebarResizeGrabberLayout.interactionWidth, accuracy: 0.001)
        XCTAssertEqual(resizeZone.maxX, stripBounds.maxX, accuracy: 0.001)
        XCTAssertEqual(resizeZone.midY, stripBounds.midY, accuracy: 0.001)
        XCTAssertLessThan(resizeZone.height, stripBounds.height)

        let rightResizeZone = SidebarResizeGrabberLayout.resizeZoneFrame(
            in: CGRect(origin: .zero, size: rightStrip.size),
            sidebarPosition: .right
        )
        XCTAssertEqual(rightResizeZone.minX, 0, accuracy: 0.001)
        XCTAssertEqual(rightResizeZone.width, SidebarResizeGrabberLayout.interactionWidth, accuracy: 0.001)

        // The visible capsule is centered and thinner than the strip.
        let indicator = SidebarResizeGrabberLayout.indicatorFrame(in: stripBounds, sidebarPosition: .left)
        XCTAssertEqual(indicator.width, SidebarResizeMetrics.grabberWidth, accuracy: 0.001)
        XCTAssertEqual(indicator.height, SidebarResizeMetrics.grabberHeight, accuracy: 0.001)
        XCTAssertEqual(indicator.maxX, stripBounds.maxX, accuracy: 0.001)
        XCTAssertEqual(indicator.midY, stripBounds.midY, accuracy: 0.001)
    }

    func testSidebarResizeGrabberRequiresArmedStateAndNoScrollSuppression() {
        XCTAssertFalse(
            SidebarResizeGrabberLayout.canBeginResize(
                isEnabled: true,
                isArmed: false,
                isResizeSuppressed: false,
                isSidebarVisible: true
            )
        )
        XCTAssertFalse(
            SidebarResizeGrabberLayout.canBeginResize(
                isEnabled: true,
                isArmed: true,
                isResizeSuppressed: true,
                isSidebarVisible: true
            )
        )
        XCTAssertTrue(
            SidebarResizeGrabberLayout.canBeginResize(
                isEnabled: true,
                isArmed: true,
                isResizeSuppressed: false,
                isSidebarVisible: true
            )
        )
    }

    func testSidebarResizeGrabberCursorRequiresArmedStateAndNoSuppression() {
        // Unarmed, merely hovering: no resize cursor.
        XCTAssertFalse(
            SidebarResizeGrabberLayout.shouldUseResizeCursor(
                isEnabled: true,
                isResizeSuppressed: false,
                isArmed: false,
                isResizing: false
            )
        )
        // Armed: resize cursor.
        XCTAssertTrue(
            SidebarResizeGrabberLayout.shouldUseResizeCursor(
                isEnabled: true,
                isResizeSuppressed: false,
                isArmed: true,
                isResizing: false
            )
        )
        // Armed but yielding to the scroll thumb: no resize cursor.
        XCTAssertFalse(
            SidebarResizeGrabberLayout.shouldUseResizeCursor(
                isEnabled: true,
                isResizeSuppressed: true,
                isArmed: true,
                isResizing: false
            )
        )
    }

    func testSidebarResizeGrabberInteractionStateRejectsStaleHoverFlash() throws {
        var state = SidebarResizeGrabberInteractionState()

        let firstGeneration = try XCTUnwrap(state.beginHoverFlash())
        let secondGeneration = try XCTUnwrap(state.beginHoverFlash())

        XCTAssertFalse(state.finishHoverFlash(generation: firstGeneration))
        XCTAssertEqual(state.visualState, .hoverFlash)
        XCTAssertTrue(state.finishHoverFlash(generation: secondGeneration))
        XCTAssertEqual(state.visualState, .hidden)
        XCTAssertFalse(state.finishHoverFlash(generation: secondGeneration))
    }

    func testSidebarResizeGrabberInteractionStateActivationConsumesFlashOnlyWhenAllowed() throws {
        var blockedState = SidebarResizeGrabberInteractionState()
        _ = try XCTUnwrap(blockedState.beginHoverFlash())
        XCTAssertEqual(
            blockedState.setHovering(true, isEnabled: true, isResizeSuppressed: false),
            .schedule
        )

        XCTAssertFalse(blockedState.completeActivation(canBeginResize: false))

        XCTAssertFalse(blockedState.isArmed)
        XCTAssertEqual(blockedState.visualState, .hoverFlash)

        var allowedState = SidebarResizeGrabberInteractionState()
        _ = try XCTUnwrap(allowedState.beginHoverFlash())
        XCTAssertEqual(
            allowedState.setHovering(true, isEnabled: true, isResizeSuppressed: false),
            .schedule
        )

        XCTAssertTrue(allowedState.completeActivation(canBeginResize: true))

        XCTAssertTrue(allowedState.isArmed)
        XCTAssertFalse(allowedState.isHoverFlashVisible)
        XCTAssertEqual(allowedState.visualState, .persistent)
    }

    func testSidebarResizeGrabberInteractionStateResizeEndPreservesArmedUntilHoverLeaves() {
        var state = SidebarResizeGrabberInteractionState()

        XCTAssertEqual(
            state.setHovering(true, isEnabled: true, isResizeSuppressed: false),
            .schedule
        )
        XCTAssertTrue(state.completeActivation(canBeginResize: true))
        XCTAssertTrue(state.beginResize(canBeginResize: true))
        XCTAssertEqual(state.visualState, .persistent)

        state.endResize()

        XCTAssertFalse(state.isResizing)
        XCTAssertTrue(state.isArmed)
        XCTAssertEqual(state.visualState, .persistent)
        XCTAssertEqual(
            state.setHovering(false, isEnabled: true, isResizeSuppressed: false),
            .cancel
        )
        XCTAssertFalse(state.isArmed)
        XCTAssertEqual(state.visualState, .hidden)
    }

    func testSidebarResizeGrabberInteractionStateResetClearsInteraction() throws {
        var state = SidebarResizeGrabberInteractionState()

        _ = try XCTUnwrap(state.beginHoverFlash())
        XCTAssertEqual(
            state.setHovering(true, isEnabled: true, isResizeSuppressed: false),
            .schedule
        )
        XCTAssertTrue(state.completeActivation(canBeginResize: true))
        XCTAssertTrue(state.beginResize(canBeginResize: true))

        state.reset()

        XCTAssertFalse(state.isHovering)
        XCTAssertFalse(state.isArmed)
        XCTAssertFalse(state.isResizing)
        XCTAssertFalse(state.isHoverFlashVisible)
        XCTAssertEqual(state.visualState, .hidden)
    }

    func testPassiveScrollIndicatorVisibleStateSuppressesResizeUntilCleared() {
        XCTAssertFalse(
            SidebarPassiveScrollIndicatorSuppressionPolicy.shouldSuppressResize(
                isIndicatorVisible: false,
                isThumbHovered: false,
                isThumbDragging: false
            )
        )
        XCTAssertTrue(
            SidebarPassiveScrollIndicatorSuppressionPolicy.shouldSuppressResize(
                isIndicatorVisible: true,
                isThumbHovered: false,
                isThumbDragging: false
            )
        )
        XCTAssertTrue(
            SidebarPassiveScrollIndicatorSuppressionPolicy.shouldSuppressResize(
                isIndicatorVisible: false,
                isThumbHovered: true,
                isThumbDragging: false
            )
        )
        XCTAssertTrue(
            SidebarPassiveScrollIndicatorSuppressionPolicy.shouldSuppressResize(
                isIndicatorVisible: false,
                isThumbHovered: false,
                isThumbDragging: true
            )
        )
    }

    func testPassiveScrollIndicatorVisibilityStateRejectsStaleFadeAfterNewPresentation() {
        var state = SidebarPassiveScrollIndicatorVisibilityState()

        let firstGeneration = state.beginPresentation()
        let secondGeneration = state.beginPresentation()

        XCTAssertFalse(state.canFinishFade(generation: firstGeneration))
        XCTAssertTrue(state.canFinishFade(generation: secondGeneration))
        XCTAssertTrue(state.isVisible)
    }

    func testPassiveScrollIndicatorVisibilityStateInvalidatesPendingFadeWhenDetached() {
        var state = SidebarPassiveScrollIndicatorVisibilityState()

        let generation = state.beginPresentation()
        state.invalidate()

        XCTAssertFalse(state.canFinishFade(generation: generation))
        XCTAssertFalse(state.isVisible)
    }

    func testPassiveScrollIndicatorVisibilityStateFinishesMatchingFadeOnce() {
        var state = SidebarPassiveScrollIndicatorVisibilityState()

        let generation = state.beginPresentation()

        XCTAssertTrue(state.finishFade(generation: generation))
        XCTAssertFalse(state.isVisible)
        XCTAssertFalse(state.finishFade(generation: generation))
    }

    func testSidebarChromePointerArbitrationSuppressesResizePerWindow() {
        let owner = NSObject()
        let window = NSWindow()
        let otherWindow = NSWindow()

        XCTAssertFalse(SidebarChromePointerArbitration.isResizeSuppressed(in: window))
        XCTAssertFalse(SidebarChromePointerArbitration.isResizeSuppressed(in: otherWindow))

        SidebarChromePointerArbitration.setScrollIndicatorSuppressesResize(true, owner: owner, window: window)

        XCTAssertTrue(SidebarChromePointerArbitration.isResizeSuppressed(in: window))
        XCTAssertFalse(SidebarChromePointerArbitration.isResizeSuppressed(in: otherWindow))

        SidebarChromePointerArbitration.setScrollIndicatorSuppressesResize(false, owner: owner, window: window)

        XCTAssertFalse(SidebarChromePointerArbitration.isResizeSuppressed(in: window))
    }

    func testSidebarChromePointerArbitrationSuppressesScrollIndicatorPerWindow() {
        let owner = NSObject()
        let window = NSWindow()
        let otherWindow = NSWindow()

        XCTAssertFalse(SidebarChromePointerArbitration.isScrollIndicatorSuppressed(in: window))
        XCTAssertFalse(SidebarChromePointerArbitration.isScrollIndicatorSuppressed(in: otherWindow))

        SidebarChromePointerArbitration.setResizeSuppressesScrollIndicator(true, owner: owner, window: window)

        XCTAssertTrue(SidebarChromePointerArbitration.isScrollIndicatorSuppressed(in: window))
        XCTAssertFalse(SidebarChromePointerArbitration.isScrollIndicatorSuppressed(in: otherWindow))
        // The two suppression directions are independent.
        XCTAssertFalse(SidebarChromePointerArbitration.isResizeSuppressed(in: window))

        SidebarChromePointerArbitration.setResizeSuppressesScrollIndicator(false, owner: owner, window: window)

        XCTAssertFalse(SidebarChromePointerArbitration.isScrollIndicatorSuppressed(in: window))
    }

    func testPassiveScrollIndicatorDragMappingTracksThumbPosition() {
        let viewportHeight: CGFloat = 100
        let contentHeight: CGFloat = 500
        let thumbHeight: CGFloat = 28

        XCTAssertEqual(
            SidebarPassiveScrollIndicatorLayout.contentOffset(
                forThumbOffsetY: 0,
                viewportHeight: viewportHeight,
                thumbHeight: thumbHeight,
                contentHeight: contentHeight
            ),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SidebarPassiveScrollIndicatorLayout.contentOffset(
                forThumbOffsetY: 36,
                viewportHeight: viewportHeight,
                thumbHeight: thumbHeight,
                contentHeight: contentHeight
            ),
            200,
            accuracy: 0.001
        )
        XCTAssertEqual(
            SidebarPassiveScrollIndicatorLayout.contentOffset(
                forThumbOffsetY: 72,
                viewportHeight: viewportHeight,
                thumbHeight: thumbHeight,
                contentHeight: contentHeight
            ),
            400,
            accuracy: 0.001
        )
    }

    func testPassiveScrollIndicatorUsesSidebarContainerOutsideClippedContentHost() {
        let outerWidth: CGFloat = 240
        let contentViewportWidth = SpaceViewLayout.contentWidth(for: outerWidth)
        let sidebarContainer = SidebarColumnContainerView(frame: NSRect(x: 0, y: 0, width: outerWidth, height: 320))
        let clippedContentHost = NSView(frame: NSRect(x: 8, y: 0, width: contentViewportWidth, height: 320))
        let scrollView = NSScrollView(frame: clippedContentHost.bounds)
        clippedContentHost.clipsToBounds = true

        sidebarContainer.addSubview(clippedContentHost)
        clippedContentHost.addSubview(scrollView)

        let overlayContainer = SidebarPassiveScrollIndicatorLayout.overlayContainer(for: scrollView)

        XCTAssertTrue(overlayContainer === sidebarContainer)
    }

    func testSidebarTabListScrollChromeDoesNotReserveNativeScrollerGutter() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 240, height: 320))
        scrollView.drawsBackground = true
        scrollView.automaticallyAdjustsContentInsets = true
        scrollView.contentInsets = NSEdgeInsets(top: 1, left: 2, bottom: 3, right: 4)
        scrollView.scrollerInsets = NSEdgeInsets(top: 5, left: 6, bottom: 7, right: 8)
        scrollView.scrollerStyle = .legacy
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .allowed
        let strayScroller = NSScroller(frame: NSRect(x: 220, y: 0, width: 20, height: 320))
        scrollView.addSubview(strayScroller)

        SidebarTabListScrollChromeConfiguration.apply(to: scrollView)

        XCTAssertFalse(scrollView.drawsBackground)
        XCTAssertFalse(scrollView.automaticallyAdjustsContentInsets)
        XCTAssertEqual(scrollView.contentInsets.top, 0, accuracy: 0.001)
        XCTAssertEqual(scrollView.contentInsets.left, 0, accuracy: 0.001)
        XCTAssertEqual(scrollView.contentInsets.bottom, 0, accuracy: 0.001)
        XCTAssertEqual(scrollView.contentInsets.right, 0, accuracy: 0.001)
        XCTAssertEqual(scrollView.scrollerInsets.top, 0, accuracy: 0.001)
        XCTAssertEqual(scrollView.scrollerInsets.left, 0, accuracy: 0.001)
        XCTAssertEqual(scrollView.scrollerInsets.bottom, 0, accuracy: 0.001)
        XCTAssertEqual(scrollView.scrollerInsets.right, 0, accuracy: 0.001)
        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
        XCTAssertFalse(scrollView.hasVerticalScroller)
        XCTAssertFalse(scrollView.hasHorizontalScroller)
        XCTAssertNil(scrollView.verticalScroller)
        XCTAssertNil(scrollView.horizontalScroller)
        XCTAssertTrue(scrollView.autohidesScrollers)
        XCTAssertEqual(scrollView.verticalScrollElasticity, .none)
        XCTAssertEqual(scrollView.horizontalScrollElasticity, .none)
        XCTAssertTrue(strayScroller.isHidden)
        XCTAssertEqual(strayScroller.alphaValue, 0, accuracy: 0.001)
    }

    func testSnapshotViewportClampsOffsetToRenderedViewport() {
        let viewport = SpaceSidebarSnapshotViewport(
            contentOffsetY: 160,
            contentHeight: 240,
            viewportHeight: 100
        )

        XCTAssertEqual(viewport.clampedOffset(), 140, accuracy: 0.001)
        XCTAssertEqual(viewport.clampedOffset(for: 80), 160, accuracy: 0.001)
    }

    func testSnapshotViewportClampsElasticOffsets() {
        let topViewport = SpaceSidebarSnapshotViewport(
            contentOffsetY: -30,
            contentHeight: 500,
            viewportHeight: 100
        )
        let bottomViewport = SpaceSidebarSnapshotViewport(
            contentOffsetY: 999,
            contentHeight: 500,
            viewportHeight: 100
        )

        XCTAssertEqual(topViewport.clampedOffset(), 0, accuracy: 0.001)
        XCTAssertEqual(bottomViewport.clampedOffset(), 400, accuracy: 0.001)
    }

    func testNativeScrollBoundariesTrackVisibleRect() {
        let top = SidebarScrollBoundaryState(
            visibleRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            contentHeight: 300
        )
        let middle = SidebarScrollBoundaryState(
            visibleRect: CGRect(x: 0, y: 100, width: 100, height: 100),
            contentHeight: 300
        )
        let bottom = SidebarScrollBoundaryState(
            visibleRect: CGRect(x: 0, y: 200, width: 100, height: 100),
            contentHeight: 300
        )

        XCTAssertFalse(top.hasContentAbove)
        XCTAssertTrue(top.hasContentBelow)
        XCTAssertTrue(middle.hasContentAbove)
        XCTAssertTrue(middle.hasContentBelow)
        XCTAssertTrue(bottom.hasContentAbove)
        XCTAssertFalse(bottom.hasContentBelow)
    }

    func testNativeScrollBoundariesAreClearWhenContentFits() {
        let state = SidebarScrollBoundaryState(
            visibleRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            contentHeight: 100
        )

        XCTAssertFalse(state.hasContentAbove)
        XCTAssertFalse(state.hasContentBelow)
    }

    func testNativeScrollBoundariesExposeSnapshotViewport() {
        let state = SidebarScrollBoundaryState(
            contentOffsetY: 42,
            visibleRect: CGRect(x: 0, y: 42, width: 100, height: 120),
            contentHeight: 360
        )

        XCTAssertEqual(state.scrollViewport.contentOffsetY, 42, accuracy: 0.001)
        XCTAssertEqual(state.scrollViewport.viewportHeight, 120, accuracy: 0.001)
        XCTAssertEqual(state.scrollViewport.contentHeight, 360, accuracy: 0.001)
        XCTAssertEqual(state.scrollViewport.clampedOffset(), 42, accuracy: 0.001)
    }

    func testSameSpaceClickIsNoOp() {
        let ids = [UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertFalse(
            state.beginClick(
                from: ids[0],
                to: ids[0],
                orderedSpaceIds: ids
            )
        )
        XCTAssertFalse(state.hasDestination)
    }

    func testClickDirectionMatchesSpaceOrder() {
        let ids = [UUID(), UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertTrue(
            state.beginClick(
                from: ids[0],
                to: ids[2],
                orderedSpaceIds: ids
            )
        )
        XCTAssertEqual(state.direction, 1)

        state.reset()

        XCTAssertTrue(
            state.beginClick(
                from: ids[2],
                to: ids[0],
                orderedSpaceIds: ids
            )
        )
        XCTAssertEqual(state.direction, -1)
    }

    func testClickTransitionCommitsOnlyOnce() {
        let ids = [UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertTrue(
            state.beginClick(
                from: ids[0],
                to: ids[1],
                orderedSpaceIds: ids
            )
        )
        XCTAssertFalse(
            state.beginClick(
                from: ids[0],
                to: ids[1],
                orderedSpaceIds: ids
            )
        )
        XCTAssertEqual(state.finishTransition(commit: true), ids[1])
        XCTAssertNil(state.finishTransition(commit: true))
    }

    func testRenderPolicyKeepsCommittedInteractiveAndTransitionLayersSnapshot() {
        XCTAssertEqual(
            SpaceSidebarRenderPolicy.pageRenderMode(for: .committed),
            .interactive
        )
        XCTAssertEqual(
            SpaceSidebarRenderPolicy.pageRenderMode(for: .transitionLayer),
            .transitionSnapshot
        )
    }

    func testRenderPolicyCompletionDelayMatchesAnimationDuration() {
        XCTAssertEqual(
            SpaceSidebarRenderPolicy.completionDelay,
            SpaceSidebarTransitionConfig.spaceSwitchAnimationDuration,
            accuracy: 0.0001
        )
    }

    func testRenderPolicyKeepsUnresolvedSwipeOnCommittedInteractivePage() {
        let ids = [UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertTrue(
            state.beginSwipeGesture(
                from: ids[0],
                orderedSpaceIds: ids
            )
        )

        XCTAssertFalse(SpaceSidebarRenderPolicy.shouldUseTransitionLayers(for: state))

        state.updateSwipeGesture(
            progress: 0.2,
            latchedDirection: 1,
            orderedSpaceIds: ids
        )

        XCTAssertTrue(SpaceSidebarRenderPolicy.shouldUseTransitionLayers(for: state))
    }

    func testTransitionSnapshotMatchesOnlyActiveSourceDestination() {
        let sourceId = UUID()
        let destinationId = UUID()
        let unrelatedId = UUID()
        let orderedSpaceIds = [sourceId, destinationId, unrelatedId]
        let snapshot = SpaceSidebarTransitionSnapshot(
            source: makePageSnapshot(
                spaceId: sourceId,
                title: "Source",
                iconValue: SumiPersistentGlyph.spaceDefaultIconValue
            ),
            destination: makePageSnapshot(spaceId: destinationId, title: "Destination", iconValue: "star"),
            stationaryEssentials: nil
        )
        var activeState = SpaceSidebarTransitionState()
        var unresolvedState = SpaceSidebarTransitionState()
        var staleDestinationState = SpaceSidebarTransitionState()

        XCTAssertTrue(
            activeState.beginClick(
                from: sourceId,
                to: destinationId,
                orderedSpaceIds: orderedSpaceIds
            )
        )
        XCTAssertTrue(snapshot.matches(activeState))
        XCTAssertFalse(snapshot.matches(unresolvedState))

        XCTAssertTrue(
            staleDestinationState.beginClick(
                from: sourceId,
                to: unrelatedId,
                orderedSpaceIds: orderedSpaceIds
            )
        )
        XCTAssertFalse(snapshot.matches(staleDestinationState))

        unresolvedState = activeState
        _ = unresolvedState.finishTransition(commit: false)
        XCTAssertFalse(snapshot.matches(unresolvedState))
    }

    func testSwipeTransitionBeginsOnlyAfterHorizontalDirectionLatches() {
        XCTAssertFalse(
            SpaceSidebarRenderPolicy.shouldBeginSwipeTransition(
                for: .init(phase: .began, direction: nil, progress: 0)
            )
        )
        XCTAssertFalse(
            SpaceSidebarRenderPolicy.shouldBeginSwipeTransition(
                for: .init(phase: .changed, direction: nil, progress: 0.02)
            )
        )
        XCTAssertTrue(
            SpaceSidebarRenderPolicy.shouldBeginSwipeTransition(
                for: .init(phase: .changed, direction: 1, progress: 0.02)
            )
        )
    }

    func testChromePreviewPolicyAnimatesEssentialsOnlyForInteractiveCommittedPage() {
        XCTAssertTrue(
            SpaceSidebarChromePreviewPolicy.shouldAnimateEssentialsLayout(
                isActiveWindow: true,
                isTransitioningProfile: false,
                pageRenderMode: .interactive
            )
        )
        XCTAssertFalse(
            SpaceSidebarChromePreviewPolicy.shouldAnimateEssentialsLayout(
                isActiveWindow: true,
                isTransitioningProfile: false,
                pageRenderMode: .transitionSnapshot
            )
        )
        XCTAssertFalse(
            SpaceSidebarChromePreviewPolicy.shouldAnimateEssentialsLayout(
                isActiveWindow: true,
                isTransitioningProfile: true,
                pageRenderMode: .interactive
            )
        )
    }

    func testEssentialsPlacementUsesSharedPinnedGridForSameProfileTransition() {
        let profileId = UUID()

        XCTAssertTrue(
            SpaceSidebarEssentialsPlacementPolicy.usesSharedPinnedGrid(
                sourceProfileId: profileId,
                destinationProfileId: profileId
            )
        )
    }

    func testEssentialsPlacementKeepsEmbeddedPinnedGridForCrossProfileTransition() {
        XCTAssertFalse(
            SpaceSidebarEssentialsPlacementPolicy.usesSharedPinnedGrid(
                sourceProfileId: UUID(),
                destinationProfileId: UUID()
            )
        )
    }

    func testPinnedGridContextPrefersExplicitSpaceOverWindowSpace() {
        let explicitSpaceId = UUID()
        let windowSpaceId = UUID()

        XCTAssertEqual(
            PinnedGridContextResolver.contextMenuSpaceId(
                explicitSpaceId: explicitSpaceId,
                windowSpaceId: windowSpaceId
            ),
            explicitSpaceId
        )
        XCTAssertEqual(
            PinnedGridContextResolver.geometrySpaceId(
                explicitSpaceId: explicitSpaceId,
                windowSpaceId: windowSpaceId
            ),
            explicitSpaceId
        )
    }

    func testPinnedGridContextUsesWindowSpaceWithoutGlobalFallback() {
        let windowSpaceId = UUID()

        XCTAssertEqual(
            PinnedGridContextResolver.contextMenuSpaceId(
                explicitSpaceId: nil,
                windowSpaceId: windowSpaceId
            ),
            windowSpaceId
        )
        XCTAssertEqual(
            PinnedGridContextResolver.geometrySpaceId(
                explicitSpaceId: nil,
                windowSpaceId: windowSpaceId
            ),
            windowSpaceId
        )
    }

    func testPinnedGridContextWithoutSpaceKeepsStableGeometryAndNoMenuTarget() {
        XCTAssertNil(
            PinnedGridContextResolver.contextMenuSpaceId(
                explicitSpaceId: nil,
                windowSpaceId: nil
            )
        )
        XCTAssertEqual(
            PinnedGridContextResolver.geometrySpaceId(
                explicitSpaceId: nil,
                windowSpaceId: nil
            ),
            PinnedGridContextResolver.unresolvedGeometrySpaceId
        )
    }

    func testSnapshotBuilderKeepsSingleStationaryEssentialsForSameProfileTransition() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileId = UUID()
        let source = Space(name: "Source", profileId: profileId)
        let destination = Space(name: "Destination", profileId: profileId)
        let essential = makeEssentialPin(profileId: profileId, title: "Pinned")

        browserManager.spaceStateOwner.replaceSpaces([source, destination])
        browserManager.structuralCollectionMutationOwner.setPinnedTabs([essential], for: profileId)
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = source.id

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            settings: settings
        )

        XCTAssertNotNil(snapshot.stationaryEssentials)
        XCTAssertEqual(snapshot.stationaryEssentials?.items.map(\.id), [essential.id])
    }

    func testSnapshotBuilderPreservesActiveStationaryEssentialsAccentSource() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileId = UUID()
        let source = Space(name: "Source", profileId: profileId)
        let destination = Space(name: "Destination", profileId: profileId)
        let essential = makeEssentialPin(profileId: profileId, title: "Pinned")

        browserManager.spaceStateOwner.replaceSpaces([source, destination])
        browserManager.structuralCollectionMutationOwner.setPinnedTabs([essential], for: profileId)
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = source.id
        _ = browserManager.shortcutTabMaterializer.materialize(
            essential,
            in: windowState.id,
            currentSpaceId: source.id
        )!
        windowState.currentShortcutPinId = essential.id

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            settings: settings
        )
        let expectedPartition = browserManager.shortcutPinRuntimeResolutionOwner.resolvedFaviconPartition(
            for: essential,
            currentSpaceId: windowState.currentSpaceId
        )

        guard let item = snapshot.stationaryEssentials?.items.first else {
            return XCTFail("Expected stationary essentials snapshot item")
        }
        guard case .shortcut(let shortcut) = item else {
            return XCTFail("Expected stationary essential shortcut")
        }
        XCTAssertEqual(shortcut.presentationState, .visuallySelected)
        XCTAssertEqual(shortcut.accentSource.launchURL, essential.launchURL)
        XCTAssertEqual(shortcut.accentSource.partition, expectedPartition)
    }

    func testSnapshotBuilderCapturesSpaceTitleNameIconAndCornerRadius() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileId = UUID()
        let source = Space(name: "Source Space", icon: "sparkles", profileId: profileId)
        let destination = Space(name: "Destination Space", icon: "star.fill", profileId: profileId)

        browserManager.spaceStateOwner.replaceSpaces([source, destination])
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = source.id

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            settings: settings
        )

        XCTAssertEqual(snapshot.source.title, "Source Space")
        XCTAssertEqual(snapshot.source.iconValue, "sparkles")
        XCTAssertEqual(snapshot.destination.title, "Destination Space")
        XCTAssertEqual(snapshot.destination.iconValue, "star.fill")
        XCTAssertEqual(
            snapshot.source.rowCornerRadius,
            settings.resolvedCornerRadius(SpaceTitleRowLayout.defaultCornerRadius),
            accuracy: 0.0001
        )
    }

    func testSnapshotBuilderStoresSourceAndDestinationViewportOffsets() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileId = UUID()
        let source = Space(name: "Source", profileId: profileId)
        let destination = Space(name: "Destination", profileId: profileId)
        let sourceViewport = SpaceSidebarSnapshotViewport(
            contentOffsetY: 44,
            contentHeight: 480,
            viewportHeight: 160
        )
        let destinationViewport = SpaceSidebarSnapshotViewport(
            contentOffsetY: 88,
            contentHeight: 520,
            viewportHeight: 180
        )

        browserManager.spaceStateOwner.replaceSpaces([source, destination])
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = source.id

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            settings: settings,
            scrollViewportForSpace: { spaceId in
                switch spaceId {
                case source.id:
                    sourceViewport
                case destination.id:
                    destinationViewport
                default:
                    nil
                }
            }
        )

        XCTAssertEqual(snapshot.source.scrollViewport, sourceViewport)
        XCTAssertEqual(snapshot.destination.scrollViewport, destinationViewport)
    }

    func testSnapshotBuilderDefaultsMissingDestinationViewportToTop() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileId = UUID()
        let source = Space(name: "Source", profileId: profileId)
        let destination = Space(name: "Destination", profileId: profileId)
        let sourceViewport = SpaceSidebarSnapshotViewport(
            contentOffsetY: 72,
            contentHeight: 420,
            viewportHeight: 140
        )

        browserManager.spaceStateOwner.replaceSpaces([source, destination])
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = source.id

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            settings: settings,
            scrollViewportForSpace: { spaceId in
                spaceId == source.id ? sourceViewport : nil
            }
        )

        XCTAssertEqual(snapshot.source.scrollViewport, sourceViewport)
        XCTAssertEqual(snapshot.destination.scrollViewport, .zero)
        XCTAssertEqual(snapshot.destination.scrollViewport.clampedOffset(), 0, accuracy: 0.001)
    }

    func testSnapshotBuilderEmbedsEssentialsForCrossProfileTransition() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let sourceProfileId = UUID()
        let destinationProfileId = UUID()
        let source = Space(name: "Source", profileId: sourceProfileId)
        let destination = Space(name: "Destination", profileId: destinationProfileId)
        let sourceEssential = makeEssentialPin(profileId: sourceProfileId, title: "Source Pin")
        let destinationEssential = makeEssentialPin(profileId: destinationProfileId, title: "Destination Pin")

        browserManager.spaceStateOwner.replaceSpaces([source, destination])
        browserManager.structuralCollectionMutationOwner.setPinnedTabs([sourceEssential], for: sourceProfileId)
        browserManager.structuralCollectionMutationOwner.setPinnedTabs([destinationEssential], for: destinationProfileId)
        windowState.currentProfileId = sourceProfileId
        windowState.currentSpaceId = source.id

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            settings: settings
        )

        XCTAssertNil(snapshot.stationaryEssentials)
        XCTAssertEqual(snapshot.source.essentials?.items.map(\.id), [sourceEssential.id])
        XCTAssertEqual(snapshot.destination.essentials?.items.map(\.id), [destinationEssential.id])
    }

    func testSnapshotBuilderMarksSelectedRegularTabWithoutObservedTabRows() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileId = UUID()
        let source = Space(name: "Source", profileId: profileId)
        let destination = Space(name: "Destination", profileId: profileId)
        let first = browserManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/first")!,
            name: "First",
            spaceId: source.id,
            index: 0
        )
        let second = browserManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/second")!,
            name: "Second",
            spaceId: source.id,
            index: 1
        )
        first.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        second.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))

        browserManager.spaceStateOwner.replaceSpaces([source, destination])
        browserManager.regularTabLifecycleOwner.addTab(first)
        browserManager.regularTabLifecycleOwner.addTab(second)
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = source.id
        windowState.currentTabId = second.id

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            settings: settings
        )

        let regularTabs = regularTabRows(in: snapshot.source)
        XCTAssertEqual(regularTabs.map(\.id), [first.id, second.id])
        XCTAssertEqual(regularTabs.map(\.isSelected), [false, true])
    }

    func testSelectedSnapshotRowSurfaceKeepsFixedHeightInsideViewportProposal() throws {
        let viewportSize = CGSize(width: 213, height: 240)
        let settings = makeIsolatedSettings()
        let tokens = ResolvedThemeContext.default.tokens(settings: settings)
        let measurement = expectation(description: "Measure selected row surface")
        var measuredHeight: CGFloat?
        let root = VStack(spacing: 0) {
            Color.clear
                .frame(height: SidebarRowLayout.rowHeight)
                .frame(maxWidth: .infinity)
                .sidebarRowSurface(
                    background: .red,
                    cornerRadius: 0,
                    tokens: tokens,
                    isVisible: true,
                    drawsSelectionShadow: true
                )
                .overlay {
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear {
                                measuredHeight = geometry.size.height
                                measurement.fulfill()
                            }
                    }
                }
        }
        .frame(
            width: viewportSize.width,
            height: viewportSize.height,
            alignment: .top
        )
        let host = NSHostingView(rootView: root)
        host.wantsLayer = true
        host.frame = CGRect(origin: .zero, size: viewportSize)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        wait(for: [measurement], timeout: 1)

        XCTAssertEqual(
            try XCTUnwrap(measuredHeight),
            SidebarRowLayout.rowHeight,
            accuracy: 0.001,
            "The selected surface must not consume the snapshot viewport's spare height"
        )
    }

    func testSnapshotBuilderPreservesRegularTabUnloadedIndicator() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileId = UUID()
        let source = Space(name: "Source", profileId: profileId)
        let destination = Space(name: "Destination", profileId: profileId)
        let unloadedTab = browserManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/unloaded")!,
            name: "Unloaded",
            spaceId: source.id,
            index: 0
        )
        unloadedTab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))

        browserManager.spaceStateOwner.replaceSpaces([source, destination])
        browserManager.regularTabLifecycleOwner.addTab(unloadedTab)
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = source.id
        windowState.currentTabId = unloadedTab.id

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            settings: settings
        )

        XCTAssertTrue(unloadedTab.showsWebViewUnloadedIndicator)
        XCTAssertEqual(
            regularTabRows(in: snapshot.source).map(\.showsUnloadedIndicator),
            [true]
        )
    }

    func testSnapshotBuilderProjectsRegularSplitAsOneRowWithResolvedFavicons() throws {
        let browser = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileID = UUID()
        let source = Space(name: "Source", profileId: profileID)
        let destination = Space(name: "Destination", profileId: profileID)
        let tabs = (0..<3).map { index in
            browser.tabFactory.makeTab(
                url: URL(string: "https://split-\(index).example")!,
                name: "Split \(index)",
                favicon: index == 0 ? "star.fill" : "bolt.fill",
                spaceId: source.id,
                index: index,
                loadsCachedFaviconOnInit: false
            )
        }
        tabs.forEach {
            $0.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browser))
        }

        browser.spaceStateOwner.replaceSpaces([source, destination])
        tabs.forEach { browser.regularTabLifecycleOwner.addTab($0) }
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [
                    .regularTab(tabs[0].id),
                    .regularTab(tabs[1].id),
                ],
                layoutKind: .horizontal,
                container: .regularTabs(spaceId: source.id)
            )
        )
        XCTAssertTrue(browser.splitGroupMutations.insert(group, persist: false))
        windowState.currentProfileId = profileID
        windowState.currentSpaceId = source.id
        windowState.currentTabId = tabs[0].id

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browser,
            windowState: windowState,
            settings: settings
        )

        XCTAssertEqual(snapshot.source.regularRows.count, 2)
        guard case .splitGroup(let split) = snapshot.source.regularRows[0] else {
            return XCTFail("Expected one split-group row before the trailing tab")
        }
        XCTAssertEqual(split.id, group.id)
        XCTAssertEqual(split.members.map(\.id), group.memberIDs)
        XCTAssertTrue(split.members.allSatisfy { member in
            if case .system("globe") = member.icon {
                return false
            }
            return true
        })
        guard case .tab(let trailing) = snapshot.source.regularRows[1] else {
            return XCTFail("Expected the remaining regular tab")
        }
        XCTAssertEqual(trailing.id, tabs[2].id)
    }

    func testSnapshotSplitMemberContentMatchesLiveVerticalCenter() throws {
        let image = try renderedSnapshotSplitRow()
        var redPixelRows: [Int] = []

        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide {
                guard let color = image.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB) else {
                    continue
                }
                if color.redComponent > 0.8,
                   color.greenComponent < 0.4,
                   color.blueComponent < 0.4,
                   color.alphaComponent > 0.8 {
                    redPixelRows.append(y)
                }
            }
        }

        let minY = try XCTUnwrap(redPixelRows.min())
        let maxY = try XCTUnwrap(redPixelRows.max())
        let backingScale = CGFloat(image.pixelsHigh) / image.size.height
        XCTAssertEqual(
            CGFloat(minY + maxY) / 2,
            SidebarRowLayout.rowHeight * backingScale / 2,
            accuracy: backingScale / 2,
            "Snapshot split favicons and titles must not jump above live rows"
        )
    }

    func testSnapshotSplitFaviconMatchesLiveSize() throws {
        let image = try renderedSnapshotSplitRow(
            sourceIconSize: 32,
            memberCount: 1
        )
        var redPixelColumns: [Int] = []
        var redPixelRows: [Int] = []

        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide {
                guard let color = image.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB) else {
                    continue
                }
                if color.redComponent > 0.8,
                   color.greenComponent < 0.4,
                   color.blueComponent < 0.4,
                   color.alphaComponent > 0.8 {
                    redPixelColumns.append(x)
                    redPixelRows.append(y)
                }
            }
        }

        let minX = try XCTUnwrap(redPixelColumns.min())
        let maxX = try XCTUnwrap(redPixelColumns.max())
        let minY = try XCTUnwrap(redPixelRows.min())
        let maxY = try XCTUnwrap(redPixelRows.max())
        let backingScale = CGFloat(image.pixelsWide) / image.size.width
        XCTAssertEqual(
            maxX - minX + 1,
            Int(SplitGroupSidebarVisualLayout.iconWidth * backingScale),
            accuracy: Int(backingScale),
            "Snapshot bitmaps must scale down to the live split favicon width"
        )
        XCTAssertEqual(
            maxY - minY + 1,
            Int(SplitGroupSidebarVisualLayout.iconWidth * backingScale),
            accuracy: Int(backingScale),
            "Snapshot bitmaps must scale down to the live split favicon height"
        )
    }

    func testSnapshotLauncherFaviconKeepsLiveIntrinsicSize() throws {
        let sourceIconSize: CGFloat = 32
        let image = try renderedSnapshotLauncherIcon(
            sourceIconSize: sourceIconSize
        )
        var redPixelColumns: [Int] = []
        var redPixelRows: [Int] = []

        for y in 0..<image.pixelsHigh {
            for x in 0..<image.pixelsWide {
                guard let color = image.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB) else {
                    continue
                }
                if color.redComponent > 0.8,
                   color.greenComponent < 0.4,
                   color.blueComponent < 0.4,
                   color.alphaComponent > 0.8 {
                    redPixelColumns.append(x)
                    redPixelRows.append(y)
                }
            }
        }

        let minX = try XCTUnwrap(redPixelColumns.min())
        let maxX = try XCTUnwrap(redPixelColumns.max())
        let minY = try XCTUnwrap(redPixelRows.min())
        let maxY = try XCTUnwrap(redPixelRows.max())
        let backingScale = CGFloat(image.pixelsWide) / image.size.width
        XCTAssertEqual(
            maxX - minX + 1,
            Int(sourceIconSize * backingScale),
            accuracy: Int(backingScale),
            "Snapshot launchers must preserve the same intrinsic bitmap presentation as live rows"
        )
        XCTAssertEqual(
            maxY - minY + 1,
            Int(sourceIconSize * backingScale),
            accuracy: Int(backingScale),
            "Snapshot launchers must preserve the same intrinsic bitmap presentation as live rows"
        )
    }

    func testSnapshotBuilderKeepsPinnedSplitIconsDuringTransition() throws {
        let browser = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileID = UUID()
        let source = Space(name: "Source", profileId: profileID)
        let destination = Space(name: "Destination", profileId: profileID)
        let pins = [
            ShortcutPin(
                id: UUID(),
                role: .spacePinned,
                spaceId: source.id,
                index: 0,
                launchURL: URL(string: "https://first-split.example")!,
                title: "First",
                iconAsset: "star.fill"
            ),
            ShortcutPin(
                id: UUID(),
                role: .spacePinned,
                spaceId: source.id,
                index: 1,
                launchURL: URL(string: "https://second-split.example")!,
                title: "Second",
                iconAsset: "bolt.fill"
            ),
        ]
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: pins.map { .shortcutPin($0.id) },
                layoutKind: .horizontal,
                container: .shortcutSidebar(
                    spaceId: source.id,
                    profileId: profileID,
                    folderId: nil,
                    index: 0
                ),
                title: "Research",
                iconAsset: "rectangle.split.2x1"
            )
        )

        browser.spaceStateOwner.replaceSpaces([source, destination])
        browser.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts(pins, for: source.id)
        XCTAssertTrue(browser.splitGroupMutations.insert(group, persist: false))
        windowState.currentProfileId = profileID
        windowState.currentSpaceId = source.id

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browser,
            windowState: windowState,
            settings: settings
        )

        XCTAssertEqual(snapshot.source.pinnedItems.count, 1)
        guard case .splitGroup(let split) = snapshot.source.pinnedItems[0] else {
            return XCTFail("Expected one pinned split-group row")
        }
        XCTAssertEqual(split.members.map(\.id), group.memberIDs)
        XCTAssertEqual(split.displayTitle, "Research")
        guard case .system("rectangle.split.2x1") = split.customIcon else {
            return XCTFail("Expected the custom group icon in the snapshot")
        }
        XCTAssertTrue(split.members.allSatisfy(\.desaturatesIcon))
        XCTAssertEqual(
            split.members.compactMap { member -> String? in
                guard case .system(let name) = member.icon else { return nil }
                return name
            },
            ["star.fill", "bolt.fill"]
        )
    }

    func testSnapshotBuilderKeepsOnlyStickyPinnedRowsWhenSpaceIsCollapsed() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileID = UUID()
        let source = Space(name: "Source", profileId: profileID)
        let destination = Space(name: "Destination", profileId: profileID)
        let hiddenPin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: source.id,
            index: 0,
            launchURL: URL(string: "https://example.com/hidden")!,
            title: "Hidden"
        )
        let stickyPin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: source.id,
            index: 1,
            launchURL: URL(string: "https://example.com/sticky")!,
            title: "Sticky"
        )

        browserManager.spaceStateOwner.replaceSpaces([source, destination])
        browserManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([hiddenPin, stickyPin], for: source.id)
        let regularTab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/regular",
            in: source,
            activate: false
        )
        windowState.currentProfileId = profileID
        windowState.currentSpaceId = source.id
        _ = TransitionStateSidebarFixture(
            browser: browserManager,
            windowState: windowState
        )
        _ = browserManager.shortcutTabMaterializer.materialize(
            stickyPin,
            in: windowState.id,
            currentSpaceId: source.id
        )
        windowState.sidebarSpacePinnedCollapse.setCollapsed(true, for: source.id)
        windowState.sidebarSpacePinnedCollapse.scheduleMutation(
            for: source.id
        ) { _ in
            SidebarFolderProjectionState(
                stickyItemIDs: [stickyPin.id],
                hasActiveProjection: true
            )
        }

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            settings: settings
        )

        XCTAssertTrue(snapshot.source.hasPinnedContent)
        XCTAssertTrue(snapshot.source.isPinnedContentCollapsed)
        XCTAssertEqual(snapshot.source.pinnedItems.map(\.id), [stickyPin.id])
        XCTAssertEqual(
            regularTabRows(in: snapshot.source).map(\.id),
            [regularTab.id]
        )
    }

    func testSnapshotFolderBodyKeepsLiveFolderLayoutMetrics() {
        XCTAssertEqual(SpaceSidebarSnapshotFolderLayout.contentLeadingPadding, 14)
        XCTAssertEqual(SpaceSidebarSnapshotFolderLayout.contentVerticalPadding, 4)
    }

    func testSnapshotPageThemeContextUsesPageWorkspaceThemeWithoutInteractiveProgress() {
        let settings = makeIsolatedSettings()
        let sourceTheme = WorkspaceTheme(
            gradientTheme: WorkspaceGradientTheme(
                colors: [
                    WorkspaceThemeColor(
                        hex: "#0A84FF",
                        isPrimary: true,
                        position: .monochrome
                    ),
                ],
                opacity: 1,
                texture: 0
            )
        )
        let destinationTheme = WorkspaceTheme(
            gradientTheme: WorkspaceGradientTheme(
                colors: [
                    WorkspaceThemeColor(
                        hex: "#FF3B30",
                        isPrimary: true,
                        position: .monochrome
                    ),
                ],
                opacity: 1,
                texture: 0
            )
        )
        let destination = Space(name: "Destination", workspaceTheme: destinationTheme)
        var baseContext = ResolvedThemeContext.default
        baseContext.workspaceTheme = sourceTheme
        baseContext.sourceWorkspaceTheme = sourceTheme
        baseContext.targetWorkspaceTheme = destinationTheme
        baseContext.isInteractiveTransition = true
        baseContext.transitionProgress = 0.42

        let pageContext = SpaceSidebarSnapshotThemeResolver.pageThemeContext(
            for: destination,
            baseContext: baseContext,
            settings: settings,
            isIncognito: false
        )

        XCTAssertEqual(pageContext.workspaceTheme.gradient.primaryColorHex, "#FF3B30")
        XCTAssertEqual(pageContext.sourceWorkspaceTheme.gradient.primaryColorHex, "#FF3B30")
        XCTAssertEqual(pageContext.targetWorkspaceTheme.gradient.primaryColorHex, "#FF3B30")
        XCTAssertFalse(pageContext.isInteractiveTransition)
        XCTAssertEqual(pageContext.transitionProgress, 1.0, accuracy: 0.0001)
    }

    func testSnapshotBuilderKeepsClosedFolderProjectionRowsForLiveLaunchers() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileId = UUID()
        let source = Space(name: "Source", profileId: profileId)
        let destination = Space(name: "Destination", profileId: profileId)
        let folder = TabFolder(name: "Folder", spaceId: source.id)
        let firstPin = makeSpacePinnedPin(spaceId: source.id, folderId: folder.id, index: 0, title: "First")
        let secondPin = makeSpacePinnedPin(spaceId: source.id, folderId: folder.id, index: 1, title: "Second")

        browserManager.spaceStateOwner.replaceSpaces([source, destination])
        browserManager.structuralCollectionMutationOwner.setFolders([folder], for: source.id)
        browserManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([firstPin, secondPin], for: source.id)
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = source.id

        _ = browserManager.shortcutTabMaterializer.materialize(
            secondPin,
            in: windowState.id,
            currentSpaceId: source.id
        )!
        windowState.sidebarFolderProjections.scheduleUpdate(
            for: folder.id,
            stickyItemIDs: [secondPin.id],
            hasActiveProjection: true
        )

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            settings: settings
        )

        guard case .folder(let folderSnapshot) = snapshot.source.pinnedItems.first else {
            return XCTFail("Expected first pinned item to be a folder snapshot")
        }

        XCTAssertFalse(folderSnapshot.isOpen)
        XCTAssertEqual(folderSnapshot.bodyChildren.map(\.id), [secondPin.id])
        XCTAssertTrue(folderSnapshot.hasActiveSelection)
    }

    func testSnapshotBuilderPreservesOpenNestedFolderTreeForSpaceTransition() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileId = UUID()
        let source = Space(name: "Source", profileId: profileId)
        let destination = Space(name: "Destination", profileId: profileId)
        let parent = TabFolder(name: "Parent", spaceId: source.id, index: 0)
        let child = TabFolder(name: "Child", spaceId: source.id, parentFolderId: parent.id, index: 0)
        parent.isOpen = true
        child.isOpen = true
        let nestedPin = makeSpacePinnedPin(spaceId: source.id, folderId: child.id, index: 0, title: "Nested")

        browserManager.spaceStateOwner.replaceSpaces([source, destination])
        browserManager.structuralCollectionMutationOwner.setFolders([parent, child], for: source.id)
        browserManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([nestedPin], for: source.id)
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = source.id

        let snapshot = makeTransitionSnapshot(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            settings: settings
        )

        guard case .folder(let parentSnapshot) = snapshot.source.pinnedItems.first else {
            return XCTFail("Expected parent folder snapshot")
        }
        guard case .folder(let childSnapshot) = parentSnapshot.bodyChildren.first else {
            return XCTFail("Expected child folder snapshot")
        }

        XCTAssertTrue(parentSnapshot.isOpen)
        XCTAssertEqual(parentSnapshot.bodyChildren.map(\.id), [child.id])
        XCTAssertTrue(childSnapshot.isOpen)
        XCTAssertEqual(childSnapshot.bodyChildren.map(\.id), [nestedPin.id])
    }

    func testSwipeGestureBeginCreatesInteractiveSessionWithoutDestination() {
        let ids = [UUID(), UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertTrue(
            state.beginSwipeGesture(
                from: ids[0],
                orderedSpaceIds: ids
            )
        )

        XCTAssertEqual(state.sourceSpaceId, ids[0])
        XCTAssertNil(state.destinationSpaceId)
        XCTAssertEqual(state.phase, .interactive)
        XCTAssertEqual(state.trigger, .swipe)
        XCTAssertFalse(state.isCommitArmed)
        XCTAssertEqual(state.progress, 0, accuracy: 0.0001)
    }

    func testSwipeUpdateLatchesDestinationAndPreservesProgress() {
        let ids = [UUID(), UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertTrue(
            state.beginSwipeGesture(
                from: ids[0],
                orderedSpaceIds: ids
            )
        )

        state.updateSwipeGesture(
            progress: 0.24,
            latchedDirection: nil,
            orderedSpaceIds: ids
        )

        XCTAssertEqual(state.progress, 0.24, accuracy: 0.0001)
        XCTAssertNil(state.destinationSpaceId)
        XCTAssertEqual(state.direction, 0)

        state.updateSwipeGesture(
            progress: 0.32,
            latchedDirection: 1,
            orderedSpaceIds: ids
        )

        XCTAssertEqual(state.progress, 0.32, accuracy: 0.0001)
        XCTAssertEqual(state.direction, 1)
        XCTAssertEqual(state.destinationSpaceId, ids[1])
        XCTAssertTrue(state.isCommitArmed)
    }

    func testSwipeBelowThresholdCancelsCleanly() {
        let ids = [UUID(), UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertTrue(
            state.beginSwipeGesture(
                from: ids[0],
                orderedSpaceIds: ids
            )
        )

        state.updateSwipeGesture(
            progress: 0.24,
            latchedDirection: 1,
            orderedSpaceIds: ids
        )

        XCTAssertFalse(state.shouldCommitSwipeOnEnd)
        XCTAssertNil(state.finishTransition(commit: false))
        XCTAssertFalse(state.hasDestination)
    }

    func testSwipeAboveThresholdCommitsDestination() {
        let ids = [UUID(), UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertTrue(
            state.beginSwipeGesture(
                from: ids[0],
                orderedSpaceIds: ids
            )
        )

        state.updateSwipeGesture(
            progress: 0.74,
            latchedDirection: 1,
            orderedSpaceIds: ids
        )

        XCTAssertTrue(state.shouldCommitSwipeOnEnd)
        XCTAssertEqual(state.finishTransition(commit: true), ids[1])
        XCTAssertFalse(state.hasDestination)
    }

    func testSpaceListMutationResetsInvalidTransitionSafely() {
        let ids = [UUID(), UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertTrue(
            state.beginClick(
                from: ids[0],
                to: ids[2],
                orderedSpaceIds: ids
            )
        )

        state.syncSpaces(
            orderedSpaceIds: [ids[0], ids[1]],
            committedSpaceId: ids[0]
        )

        XCTAssertFalse(state.hasDestination)
        XCTAssertNil(state.visualSelectedSpaceId)
    }

    func testNormalizedProgressPreservesReleaseTailAtHighVelocity() {
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.normalizedProgress(distance: 0, width: 100),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.normalizedProgress(distance: 40, width: 100),
            0.4,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.normalizedProgress(distance: 82, width: 100),
            0.82,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.normalizedProgress(distance: 91, width: 100),
            0.87,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.normalizedProgress(distance: 100, width: 100),
            0.92,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.normalizedProgress(distance: 180, width: 100),
            0.92,
            accuracy: 0.0001
        )
    }

    func testDirectionLatchKeepsFirstDirection() {
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.latchedDirection(current: nil, rawDeltaX: -1.2),
            1
        )
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.latchedDirection(current: 1, rawDeltaX: 4),
            1
        )
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.latchedDirection(current: -1, rawDeltaX: -4),
            -1
        )
    }

    func testSwipeTrackerHorizontalLockConsumesAndEmitsExpectedEvents() {
        var tracker = SpaceSwipeGestureTracker()

        let began = tracker.process(
            .init(phase: .began, scrollingDeltaX: -0.4, scrollingDeltaY: 0.1),
            width: 200,
            isEnabled: true
        )
        XCTAssertEqual(began.handling, .consume)
        XCTAssertEqual(began.emittedEvents, [.init(phase: .began, direction: nil, progress: 0)])

        let changed = tracker.process(
            .init(phase: .changed, scrollingDeltaX: -3.0, scrollingDeltaY: 0.2),
            width: 200,
            isEnabled: true
        )
        XCTAssertEqual(changed.handling, .consume)
        XCTAssertEqual(changed.emittedEvents.count, 1)
        XCTAssertEqual(changed.emittedEvents[0].phase, .changed)
        XCTAssertEqual(changed.emittedEvents[0].direction, 1)
        XCTAssertGreaterThan(changed.emittedEvents[0].progress, 0.01)

        let ended = tracker.process(
            .init(phase: .ended),
            width: 200,
            isEnabled: true
        )
        XCTAssertEqual(ended.handling, .consume)
        XCTAssertEqual(ended.emittedEvents.count, 1)
        XCTAssertEqual(ended.emittedEvents[0].phase, .ended)
        XCTAssertEqual(ended.emittedEvents[0].direction, 1)
        XCTAssertGreaterThan(ended.emittedEvents[0].progress, 0.01)
    }

    func testSwipeTrackerPhaseLessInputTriggersOnceAndDrainsInertialTail() {
        var tracker = SpaceSwipeGestureTracker()

        let belowThreshold = tracker.process(
            .init(scrollingDeltaX: -4, scrollingDeltaY: 0, timestamp: 1),
            width: 200,
            isEnabled: true
        )
        XCTAssertTrue(belowThreshold.emittedEvents.isEmpty)

        let triggered = tracker.process(
            .init(scrollingDeltaX: -70, scrollingDeltaY: 0, timestamp: 1.01),
            width: 200,
            isEnabled: true
        )
        XCTAssertEqual(triggered.emittedEvents.last?.phase, .discrete)
        XCTAssertEqual(triggered.emittedEvents.last?.direction, 1)
        XCTAssertTrue(tracker.ownsScrollSequence)

        let inertialTail = tracker.process(
            .init(scrollingDeltaX: -100, scrollingDeltaY: 0, timestamp: 1.02),
            width: 200,
            isEnabled: false
        )
        XCTAssertEqual(inertialTail.handling, .consume)
        XCTAssertTrue(inertialTail.emittedEvents.isEmpty)

        _ = tracker.process(
            .init(scrollingDeltaX: 4, scrollingDeltaY: 0, timestamp: 1.30),
            width: 200,
            isEnabled: true
        )
        let nextGesture = tracker.process(
            .init(scrollingDeltaX: 70, scrollingDeltaY: 0, timestamp: 1.31),
            width: 200,
            isEnabled: true
        )
        XCTAssertEqual(nextGesture.emittedEvents.last?.phase, .discrete)
        XCTAssertEqual(nextGesture.emittedEvents.last?.direction, -1)
    }

    func testSwipeTrackerDoesNotOwnANewPhaseLessGestureWhenDisabled() {
        var tracker = SpaceSwipeGestureTracker()

        _ = tracker.process(
            .init(scrollingDeltaX: -4, timestamp: 1),
            width: 200,
            isEnabled: true
        )
        _ = tracker.process(
            .init(scrollingDeltaX: -70, timestamp: 1.01),
            width: 200,
            isEnabled: true
        )
        XCTAssertTrue(tracker.ownsScrollSequence)

        let newGesture = tracker.process(
            .init(scrollingDeltaX: 4, timestamp: 1.30),
            width: 200,
            isEnabled: false
        )

        XCTAssertEqual(newGesture.handling, .forwardToUnderlying)
        XCTAssertTrue(newGesture.emittedEvents.isEmpty)
        XCTAssertFalse(tracker.ownsScrollSequence)
    }

    func testSwipeTrackerVerticalLockCancelsAndForwardsToUnderlying() {
        var tracker = SpaceSwipeGestureTracker()

        _ = tracker.process(
            .init(phase: .began, scrollingDeltaX: 0.2, scrollingDeltaY: 0.2),
            width: 200,
            isEnabled: true
        )

        let changed = tracker.process(
            .init(phase: .changed, scrollingDeltaX: 0.4, scrollingDeltaY: 3.2),
            width: 200,
            isEnabled: true
        )
        XCTAssertEqual(changed.handling, .forwardToUnderlying)
        XCTAssertEqual(changed.emittedEvents, [.init(phase: .cancelled, direction: nil, progress: 0)])
        XCTAssertEqual(tracker.axisLock, .vertical)

        let ended = tracker.process(
            .init(phase: .ended),
            width: 200,
            isEnabled: true
        )
        XCTAssertEqual(ended.handling, .forwardToUnderlying)
        XCTAssertTrue(ended.emittedEvents.isEmpty)
        XCTAssertEqual(tracker.axisLock, .unresolved)
    }

    func testSwipeTrackerDisabledDoesNotStartGesture() {
        var tracker = SpaceSwipeGestureTracker()

        let result = tracker.process(
            .init(phase: .began, scrollingDeltaX: -4, scrollingDeltaY: 0),
            width: 200,
            isEnabled: false
        )

        XCTAssertEqual(result.handling, .forwardToUnderlying)
        XCTAssertTrue(result.emittedEvents.isEmpty)
        XCTAssertEqual(tracker.axisLock, .unresolved)
        XCTAssertFalse(tracker.didSendBeginEvent)
    }

    private func renderedSnapshotSplitRow(
        sourceIconSize: CGFloat = SidebarRowLayout.faviconSize,
        memberCount: Int = 2
    ) throws -> NSBitmapImageRep {
        let rowWidth: CGFloat = 213
        let redIcon = NSImage(
            size: CGSize(width: sourceIconSize, height: sourceIconSize)
        )
        redIcon.lockFocus()
        NSColor.red.setFill()
        NSBezierPath(
            rect: CGRect(
                x: 0,
                y: 0,
                width: sourceIconSize,
                height: sourceIconSize
            )
        ).fill()
        redIcon.unlockFocus()

        let members = (0..<memberCount).map { _ in
            SpaceSplitGroupMemberSnapshot(
                id: .regularTab(UUID()),
                title: "",
                icon: .image(Image(nsImage: redIcon)),
                desaturatesIcon: false,
                accentSource: nil,
                essentialBackdrop: nil,
                isSelected: false
            )
        }
        let snapshot = SpaceSplitGroupSnapshot(
            id: UUID(),
            displayTitle: "",
            customIcon: nil,
            members: members,
            isSelected: false,
            isLoaded: true
        )
        let settings = makeIsolatedSettings()
        let tokens = ResolvedThemeContext.default.tokens(settings: settings)
        let root = SpaceSnapshotSplitGroupView(
            splitGroup: snapshot,
            rowCornerRadius: SidebarRowLayout.defaultCornerRadius,
            tokens: tokens
        )
        .frame(width: rowWidth, height: SidebarRowLayout.rowHeight)
        let host = NSHostingView(rootView: root)
        host.wantsLayer = true
        host.frame = CGRect(
            x: 0,
            y: 0,
            width: rowWidth,
            height: SidebarRowLayout.rowHeight
        )
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let image = try XCTUnwrap(
            host.bitmapImageRepForCachingDisplay(in: host.bounds)
        )
        host.cacheDisplay(in: host.bounds, to: image)
        return image
    }

    private func renderedSnapshotLauncherIcon(
        sourceIconSize: CGFloat
    ) throws -> NSBitmapImageRep {
        let canvasSize: CGFloat = 64
        let redIcon = NSImage(
            size: CGSize(width: sourceIconSize, height: sourceIconSize)
        )
        redIcon.lockFocus()
        NSColor.red.setFill()
        NSBezierPath(
            rect: CGRect(
                x: 0,
                y: 0,
                width: sourceIconSize,
                height: sourceIconSize
            )
        ).fill()
        redIcon.unlockFocus()

        let root = SpaceSnapshotIconView(
            icon: .image(Image(nsImage: redIcon)),
            size: SidebarRowLayout.faviconSize,
            foregroundColor: .black
        )
        .frame(width: canvasSize, height: canvasSize)
        let host = NSHostingView(rootView: root)
        host.wantsLayer = true
        host.frame = CGRect(
            x: 0,
            y: 0,
            width: canvasSize,
            height: canvasSize
        )
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let image = try XCTUnwrap(
            host.bitmapImageRepForCachingDisplay(in: host.bounds)
        )
        host.cacheDisplay(in: host.bounds, to: image)
        return image
    }

    private func makeIsolatedSettings() -> SumiSettingsService {
        let suiteName = "SpaceSidebarTransitionStateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return SumiSettingsService(userDefaults: defaults)
    }

    private func makeTransitionSnapshot(
        sourceSpace: Space,
        destinationSpace: Space,
        browserManager: BrowserManager,
        windowState: BrowserWindowState,
        settings: SumiSettingsService,
        scrollViewportForSpace: (UUID) -> SpaceSidebarSnapshotViewport? = { _ in nil }
    ) -> SpaceSidebarTransitionSnapshot {
        let sidebar = TransitionStateSidebarFixture(
            browser: browserManager,
            windowState: windowState
        )
        return SpaceSidebarTransitionSnapshotBuilder.make(
            sourceSpace: sourceSpace,
            destinationSpace: destinationSpace,
            browserContext: browserManager.composeSidebarBrowserContext(
                spaceLifecycle: sidebar.lifecycle
            ),
            spaceCatalog: sidebar.spaceCatalog,
            inventory: sidebar.inventory,
            selection: sidebar.selection,
            pinProjection: sidebar.pinProjection,
            windowState: windowState,
            settings: settings,
            scrollViewportForSpace: scrollViewportForSpace
        )
    }

    private func makePageSnapshot(
        spaceId: UUID,
        title: String,
        iconValue: String
    ) -> SpaceSidebarPageSnapshot {
        SpaceSidebarPageSnapshot(
            spaceId: spaceId,
            title: title,
            iconValue: iconValue,
            extensionActions: nil,
            essentials: nil,
            hasPinnedContent: false,
            isPinnedContentCollapsed: false,
            pinnedItems: [],
            regularRows: [],
            showsNewTabButtonInList: true,
            showsTopNewTabButton: false,
            rowCornerRadius: SpaceTitleRowLayout.defaultCornerRadius,
            scrollViewport: .zero
        )
    }

    private func regularTabRows(
        in snapshot: SpaceSidebarPageSnapshot
    ) -> [SpaceTabRowSnapshot] {
        snapshot.regularRows.compactMap { row in
            guard case .tab(let tab) = row else { return nil }
            return tab
        }
    }

    private func makeEssentialPin(profileId: UUID, title: String) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileId,
            index: 0,
            launchURL: URL(string: "https://example.com/\(UUID().uuidString)")!,
            title: title
        )
    }

    private func makeSpacePinnedPin(
        spaceId: UUID,
        folderId: UUID,
        index: Int,
        title: String
    ) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: spaceId,
            index: index,
            folderId: folderId,
            launchURL: URL(string: "https://example.com/\(UUID().uuidString)")!,
            title: title
        )
    }
}

@MainActor
private struct TransitionStateSidebarFixture {
    let spaceCatalog: SidebarSpaceCatalogProjection
    let inventory: SidebarSpaceInventoryProjection
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let lifecycle: SidebarSpaceLifecycle

    init(browser: BrowserManager, windowState: BrowserWindowState) {
        let registry = browser.windowRegistry
        registry.register(windowState)
        let windows = SidebarWindowIdentityQuery(registry: registry)
        spaceCatalog = SidebarSpaceCatalogProjection(
            runtime: browser.runtimePortConnection,
            spaces: browser.spaceStateOwner,
            pins: browser.shortcutPinCollectionStateOwner
        )
        inventory = SidebarSpaceInventoryProjection(
            runtime: browser.runtimePortConnection,
            spaces: browser.spaceStateOwner,
            regularTabs: browser.regularTabCollectionOwner,
            pinned: SidebarPinnedInventoryProjection(
                folders: browser.folderCollectionStateOwner,
                pins: browser.shortcutPinCollectionStateOwner,
                splitGroups: browser.splitGroupStore,
                splitOrdering: browser.splitGroupSidebarOrdering
            )
        )
        let splitQuery = browser.splitQuery
        selection = SidebarWindowSelectionQuery(
            runtimeIsAlive: { true },
            windows: windows,
            windowTabs: browser.windowTabContext,
            shortcutPresentation: browser.shortcutPresentationOwner,
            splitQuery: splitQuery
        )
        pinProjection = SidebarPinFolderProjection(
            runtimeIsAlive: { true },
            windows: windows,
            essentials: browser.essentialsShortcutPlacementOwner,
            resolution: browser.shortcutPinRuntimeResolutionOwner
        )
        lifecycle = browser.sidebarSpaceLifecycle
    }
}
