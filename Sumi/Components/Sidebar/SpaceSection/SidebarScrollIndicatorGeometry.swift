//
//  SidebarScrollIndicatorGeometry.swift
//  Sumi
//
import AppKit

struct SidebarPassiveScrollIndicatorMetrics: Equatable {
    let thumbOffsetY: CGFloat
    let thumbHeight: CGFloat
}

struct SidebarPassiveScrollIndicatorVisibilityState: Equatable {
    private(set) var generation = 0
    private(set) var isVisible = false

    mutating func beginPresentation() -> Int {
        generation += 1
        isVisible = true
        return generation
    }

    mutating func hideImmediately() {
        generation += 1
        isVisible = false
    }

    mutating func invalidate() {
        generation += 1
        isVisible = false
    }

    func canFinishFade(generation: Int) -> Bool {
        self.generation == generation && isVisible
    }

    mutating func finishFade(generation: Int) -> Bool {
        guard canFinishFade(generation: generation) else { return false }
        isVisible = false
        return true
    }
}

struct SidebarScrollBoundaryState: Equatable {
    let hasContentAbove: Bool
    let hasContentBelow: Bool
    let scrollViewport: SpaceSidebarSnapshotViewport

    init(visibleRect: CGRect, contentHeight: CGFloat) {
        self.init(
            contentOffsetY: visibleRect.minY,
            visibleRect: visibleRect,
            contentHeight: contentHeight
        )
    }

    init(contentOffsetY: CGFloat, visibleRect: CGRect, contentHeight: CGFloat) {
        scrollViewport = SpaceSidebarSnapshotViewport(
            contentOffsetY: contentOffsetY,
            contentHeight: contentHeight,
            viewportHeight: visibleRect.height
        )

        let tolerance: CGFloat = 0.5
        let hasOverflow = scrollViewport.contentHeight > scrollViewport.viewportHeight + tolerance
        let maximumOffset = max(scrollViewport.contentHeight - scrollViewport.viewportHeight, 0)
        let clampedOffset = scrollViewport.clampedOffset()
        hasContentAbove = hasOverflow && clampedOffset > tolerance
        hasContentBelow = hasOverflow && clampedOffset < maximumOffset - tolerance
    }
}

enum SidebarPassiveScrollIndicatorLayout {
    static let thumbWidth: CGFloat = 3
    static let expandedThumbWidth: CGFloat = 7
    static let trackWidth: CGFloat = 12
    static let thumbOpacity: CGFloat = 0.40
    static let minimumThumbHeight: CGFloat = 28
    static let thumbLayoutAnimationDuration: TimeInterval = 0.12
    static let visibleDuration: TimeInterval = 2.0
    static let fadeDuration: TimeInterval = 0.18

    static func indicatorFrame(
        scrollViewFrameInOverlay: CGRect,
        viewportHeight: CGFloat,
        contentViewportWidth: CGFloat,
        trailingProjection: CGFloat
    ) -> CGRect {
        CGRect(
            x: scrollViewFrameInOverlay.minX + contentViewportWidth + trailingProjection - trackWidth,
            y: scrollViewFrameInOverlay.minY,
            width: trackWidth,
            height: viewportHeight
        )
    }

    static func thumbFrame(
        in bounds: CGRect,
        metrics: SidebarPassiveScrollIndicatorMetrics,
        width: CGFloat
    ) -> CGRect {
        CGRect(
            x: bounds.maxX - width,
            y: bounds.minY + metrics.thumbOffsetY,
            width: width,
            height: metrics.thumbHeight
        )
    }

    static func thumbInteractionFrame(
        in bounds: CGRect,
        metrics: SidebarPassiveScrollIndicatorMetrics
    ) -> CGRect {
        thumbFrame(in: bounds, metrics: metrics, width: expandedThumbWidth)
    }

    @MainActor
    static func overlayContainer(for scrollView: NSScrollView) -> NSView? {
        nearestSidebarColumnContainer(from: scrollView) ?? scrollView.superview
    }

    static func contentOffset(
        forThumbOffsetY thumbOffsetY: CGFloat,
        viewportHeight: CGFloat,
        thumbHeight: CGFloat,
        contentHeight: CGFloat
    ) -> CGFloat {
        guard viewportHeight > 0,
              contentHeight > viewportHeight,
              thumbHeight < viewportHeight
        else {
            return 0
        }

        let maximumContentOffset = max(contentHeight - viewportHeight, 0)
        let maximumThumbOffset = max(viewportHeight - thumbHeight, 0)
        guard maximumThumbOffset > 0 else { return 0 }

        let clampedThumbOffsetY = min(max(thumbOffsetY, 0), maximumThumbOffset)
        return maximumContentOffset * (clampedThumbOffsetY / maximumThumbOffset)
    }

    static func metrics(
        viewportHeight: CGFloat,
        contentHeight: CGFloat,
        contentOffset: CGFloat
    ) -> SidebarPassiveScrollIndicatorMetrics? {
        guard viewportHeight > 0,
              contentHeight > viewportHeight
        else {
            return nil
        }

        let maximumContentOffset = max(contentHeight - viewportHeight, 0)
        let clampedContentOffset = min(max(contentOffset, 0), maximumContentOffset)
        let unclampedThumbHeight = viewportHeight * (viewportHeight / contentHeight)
        let thumbHeight = min(max(unclampedThumbHeight, minimumThumbHeight), viewportHeight)
        let maximumThumbOffset = max(viewportHeight - thumbHeight, 0)
        let scrollProgress = maximumContentOffset > 0
            ? clampedContentOffset / maximumContentOffset
            : 0

        return SidebarPassiveScrollIndicatorMetrics(
            thumbOffsetY: maximumThumbOffset * scrollProgress,
            thumbHeight: thumbHeight
        )
    }

    @MainActor
    private static func nearestSidebarColumnContainer(from view: NSView) -> SidebarColumnBaseContainerView? {
        var current: NSView? = view
        while let candidate = current {
            if let container = candidate as? SidebarColumnBaseContainerView {
                return container
            }
            current = candidate.superview
        }
        return nil
    }
}

enum SidebarPassiveScrollIndicatorSuppressionPolicy {
    static func shouldSuppressResize(
        isIndicatorVisible: Bool,
        isThumbHovered: Bool,
        isThumbDragging: Bool
    ) -> Bool {
        isIndicatorVisible || isThumbHovered || isThumbDragging
    }
}

enum SidebarTabListScrollChromeConfiguration {
    @MainActor
    static func apply(to scrollView: NSScrollView) {
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets()
        scrollView.scrollerInsets = NSEdgeInsets()
        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScroller = nil
        scrollView.horizontalScroller = nil
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none

        for subview in scrollView.subviews where subview is NSScroller {
            subview.isHidden = true
            subview.alphaValue = 0
        }
    }
}
