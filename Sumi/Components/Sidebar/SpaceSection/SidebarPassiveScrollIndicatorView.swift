//
//  SidebarPassiveScrollIndicatorView.swift
//  Sumi
//

import AppKit
import SwiftUI

final class SidebarPassiveScrollIndicatorView: NSView {
    var indicatorColor: NSColor = .clear {
        didSet {
            thumbView.layer?.backgroundColor = indicatorColor.cgColor
        }
    }
    weak var scrollView: NSScrollView?
    var onInteractionBegan: (() -> Void)?
    var onInteractionEnded: (() -> Void)?
    var onScrollOffsetChanged: (() -> Void)?

    private let thumbView = NSView()
    private var currentMetrics: SidebarPassiveScrollIndicatorMetrics?
    private var trackingArea: NSTrackingArea?
    private var dragGrabOffsetY: CGFloat?
    private var isThumbHovered = false
    private var isThumbDragging = false
    private var isVisibleForResizeSuppression = false
    private weak var resizeSuppressionWindow: NSWindow?

    override var isOpaque: Bool { false }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        thumbView.wantsLayer = true
        thumbView.layer?.masksToBounds = true
        addSubview(thumbView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        clearInteractionState()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncResizeGrabberSuppression()
    }

    func updateThumb(metrics: SidebarPassiveScrollIndicatorMetrics) {
        currentMetrics = metrics
        updateThumbLayout(animated: false)
        updateHoverStateFromMouseLocation(animated: false)
    }

    func clearInteractionState() {
        isThumbHovered = false
        isThumbDragging = false
        isVisibleForResizeSuppression = false
        dragGrabOffsetY = nil
        setResizeGrabberSuppressed(false)
    }

    func setVisibleForResizeSuppression(_ isVisible: Bool) {
        guard isVisibleForResizeSuppression != isVisible else { return }
        isVisibleForResizeSuppression = isVisible
        syncResizeGrabberSuppression()
    }

    private func updateThumbLayout(animated: Bool) {
        guard let metrics = currentMetrics else { return }

        let targetWidth = currentThumbWidth
        let targetOpacity = SidebarPassiveScrollIndicatorLayout.thumbOpacity
        let targetFrame = SidebarPassiveScrollIndicatorLayout.thumbFrame(
            in: bounds,
            metrics: metrics,
            width: targetWidth
        )

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = SidebarPassiveScrollIndicatorLayout.thumbLayoutAnimationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                thumbView.animator().frame = targetFrame
                thumbView.animator().alphaValue = targetOpacity
                thumbView.layer?.cornerRadius = targetWidth / 2
            }
        } else {
            thumbView.frame = targetFrame
            thumbView.alphaValue = targetOpacity
            thumbView.layer?.cornerRadius = targetWidth / 2
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self
        )
        self.trackingArea = trackingArea
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        updateHoverState(with: event, animated: true)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoverState(with: event, animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        guard !isThumbDragging else { return }
        setThumbHovered(false, animated: true)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard thumbInteractionFrame.contains(point) else { return }

        isThumbDragging = true
        dragGrabOffsetY = point.y - thumbView.frame.minY
        syncResizeGrabberSuppression()
        onInteractionBegan?()
        setThumbHovered(true, animated: true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isThumbDragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        dragThumb(to: point)
    }

    override func mouseUp(with event: NSEvent) {
        guard isThumbDragging else { return }
        isThumbDragging = false
        dragGrabOffsetY = nil
        updateHoverState(with: event, animated: true)
        syncResizeGrabberSuppression()
        onInteractionEnded?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden,
              alphaValue > 0.01
        else {
            return nil
        }
        // `point` arrives in the superview's coordinate space; the thumb frame is local.
        let localPoint = convert(point, from: superview)
        guard thumbInteractionFrame.contains(localPoint) else {
            return nil
        }
        return self
    }

    private var currentThumbWidth: CGFloat {
        isThumbHovered || isThumbDragging
            ? SidebarPassiveScrollIndicatorLayout.expandedThumbWidth
            : SidebarPassiveScrollIndicatorLayout.thumbWidth
    }

    private var thumbInteractionFrame: NSRect {
        guard let metrics = currentMetrics else { return .zero }
        return SidebarPassiveScrollIndicatorLayout.thumbInteractionFrame(in: bounds, metrics: metrics)
    }

    private func updateHoverState(with event: NSEvent, animated: Bool) {
        let point = convert(event.locationInWindow, from: nil)
        setThumbHovered(thumbInteractionFrame.contains(point), animated: animated)
    }

    private func updateHoverStateFromMouseLocation(animated: Bool) {
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setThumbHovered(thumbInteractionFrame.contains(point), animated: animated)
    }

    private func setThumbHovered(_ isHovered: Bool, animated: Bool) {
        guard isThumbHovered != isHovered else { return }
        isThumbHovered = isHovered
        updateThumbLayout(animated: animated)
        if isHovered {
            onInteractionBegan?()
        } else if !isThumbDragging {
            onInteractionEnded?()
        }
        syncResizeGrabberSuppression()
    }

    private func syncResizeGrabberSuppression() {
        setResizeGrabberSuppressed(
            SidebarPassiveScrollIndicatorSuppressionPolicy.shouldSuppressResize(
                isIndicatorVisible: isVisibleForResizeSuppression,
                isThumbHovered: isThumbHovered,
                isThumbDragging: isThumbDragging
            )
        )
    }

    private func setResizeGrabberSuppressed(_ isSuppressed: Bool) {
        // Suppression is registered against a specific window; retarget cleanly
        // whenever it changes (or clears) by releasing the previous window first.
        let targetWindow = isSuppressed ? window : nil
        if resizeSuppressionWindow !== targetWindow {
            SidebarChromePointerArbitration.setScrollIndicatorSuppressesResize(
                false,
                owner: self,
                window: resizeSuppressionWindow
            )
            resizeSuppressionWindow = targetWindow
        }
        SidebarChromePointerArbitration.setScrollIndicatorSuppressesResize(
            targetWindow != nil,
            owner: self,
            window: targetWindow
        )
    }

    private func dragThumb(to point: NSPoint) {
        guard let metrics = currentMetrics,
              let scrollView,
              let documentView = scrollView.documentView,
              let dragGrabOffsetY
        else {
            return
        }

        let visibleHeight = scrollView.contentView.bounds.height
        let documentHeight = documentView.bounds.height
        let contentOffset = SidebarPassiveScrollIndicatorLayout.contentOffset(
            forThumbOffsetY: point.y - dragGrabOffsetY,
            viewportHeight: visibleHeight,
            thumbHeight: metrics.thumbHeight,
            contentHeight: documentHeight
        )
        let maximumContentOffset = max(documentHeight - visibleHeight, 0)
        let targetBoundsY = documentView.isFlipped
            ? contentOffset
            : maximumContentOffset - contentOffset
        let targetOrigin = NSPoint(
            x: scrollView.contentView.bounds.origin.x,
            y: targetBoundsY
        )
        scrollView.contentView.scroll(to: targetOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        onScrollOffsetChanged?()
    }
}
