import AppKit
@testable import Sumi
import SumiDomain
import SwiftUI
import XCTest


@MainActor
final class SidebarScrollChromeTests: XCTestCase {
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
}
