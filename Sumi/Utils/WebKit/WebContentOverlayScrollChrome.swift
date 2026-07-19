//
//  WebContentOverlayScrollChrome.swift
//  Sumi
//

import AppKit
import WebKit
import SumiWebRuntime

/// AppKit overlay scroll indicator for WKWebView page scroll.
/// Hides WebKit's native scroller via a tiny CSS user script; geometry is
/// read from the page with `evaluateJavaScript` (macOS WKWebView has no scrollView).
@MainActor
final class WebContentOverlayScrollChrome {
    private weak var hostView: NSView?
    private weak var webView: WKWebView?
    private let indicatorView = WebContentOverlayScrollIndicatorView(frame: .zero)
    private let visibility = WebContentOverlayScrollIndicatorVisibilityController()
    private var lastState: WebContentOverlayScrollIndicatorState?
    private var geometryRequestGeneration = 0
    private var isGeometryRequestInFlight = false
    private var isInstalled = false

    /// Exposed so the host can preserve this subview across content reattachment.
    var indicatorHostingView: NSView { indicatorView }

    func install(in hostView: NSView, webView: WKWebView) {
        self.hostView = hostView
        self.webView = webView

        indicatorView.indicatorColor = OverlayScrollIndicatorStyle.thumbColor
        indicatorView.isHidden = true
        indicatorView.autoresizingMask = []
        indicatorView.onInteractionBegan = { [weak self] in
            self?.visibility.hold(in: hostView.window)
        }
        indicatorView.onInteractionEnded = { [weak self] in
            self?.visibility.reveal(in: hostView.window)
        }
        indicatorView.onScrollOffsetChanged = { [weak self] offset in
            self?.applyScrollOffset(offset)
        }

        if indicatorView.superview !== hostView {
            hostView.addSubview(indicatorView, positioned: .above, relativeTo: nil)
        }
        visibility.attach(indicatorView)
        isInstalled = true
        layoutIndicator()
    }

    func uninstall() {
        isInstalled = false
        lastState = nil
        visibility.attach(nil)
        indicatorView.clearInteractionState()
        indicatorView.removeFromSuperview()
        hostView = nil
        webView = nil
    }

    /// Keep the indicator above the web content after host reattachment.
    func ensureIndicatorAboveContent() {
        guard isInstalled,
              let hostView,
              indicatorView.superview === hostView
        else {
            return
        }
        hostView.addSubview(indicatorView, positioned: .above, relativeTo: nil)
        layoutIndicator()
    }

    func layoutIndicator() {
        guard let hostView else { return }
        let bounds = hostView.bounds
        indicatorView.frame = CGRect(
            x: bounds.maxX
                - OverlayScrollIndicatorStyle.edgeInset
                - OverlayScrollIndicatorStyle.trackWidth,
            y: bounds.minY,
            width: OverlayScrollIndicatorStyle.trackWidth,
            height: bounds.height
        )
    }

    func handleScrollWheel() {
        refreshGeometry(revealIfChanged: true)
    }

    func refreshGeometry(revealIfChanged: Bool) {
        guard isInstalled,
              let webView,
              webView.window != nil,
              !webView.sumiIsInFullscreenElementPresentation
        else {
            hideImmediately()
            return
        }

        geometryRequestGeneration += 1
        let generation = geometryRequestGeneration
        guard !isGeometryRequestInFlight else { return }
        isGeometryRequestInFlight = true

        webView.evaluateJavaScript(Self.geometryScript) { [weak self] result, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isGeometryRequestInFlight = false
                guard generation == self.geometryRequestGeneration else {
                    self.refreshGeometry(revealIfChanged: revealIfChanged)
                    return
                }
                self.applyGeometryResult(result, revealIfChanged: revealIfChanged)
            }
        }
    }

    func hideImmediately() {
        lastState = nil
        visibility.hideImmediately()
    }

    private func applyGeometryResult(_ result: Any?, revealIfChanged: Bool) {
        guard let dictionary = result as? [String: Any],
              let viewportHeight = cgFloat(dictionary["clientHeight"]),
              let contentHeight = cgFloat(dictionary["scrollHeight"]),
              let contentOffset = cgFloat(dictionary["scrollY"])
        else {
            hideImmediately()
            return
        }

        let maximumContentOffset = max(contentHeight - viewportHeight, 0)
        let clampedOffset = min(max(contentOffset, 0), maximumContentOffset)
        let state = WebContentOverlayScrollIndicatorState(
            viewportHeight: viewportHeight,
            contentHeight: contentHeight,
            contentOffset: clampedOffset
        )
        let shouldReveal = revealIfChanged && lastState != state
        lastState = state

        guard let metrics = SidebarPassiveScrollIndicatorLayout.metrics(
            viewportHeight: viewportHeight,
            contentHeight: contentHeight,
            contentOffset: clampedOffset
        ) else {
            hideImmediately()
            return
        }

        layoutIndicator()
        indicatorView.updateThumb(metrics: metrics)
        indicatorView.scrollableContentHeight = contentHeight
        indicatorView.viewportHeight = viewportHeight

        if shouldReveal {
            visibility.reveal(in: indicatorView.window)
        }
    }

    private func applyScrollOffset(_ contentOffset: CGFloat) {
        guard let webView else { return }
        let y = max(contentOffset, 0)
        webView.evaluateJavaScript("window.scrollTo(0, \(y));", completionHandler: nil)
        refreshGeometry(revealIfChanged: false)
    }

    private func cgFloat(_ value: Any?) -> CGFloat? {
        if let number = value as? NSNumber {
            return CGFloat(truncating: number)
        }
        if let double = value as? Double {
            return CGFloat(double)
        }
        if let int = value as? Int {
            return CGFloat(int)
        }
        return nil
    }

    private static let geometryScript = """
    (function() {
        var root = document.documentElement;
        var body = document.body;
        var scrollY = window.scrollY || root.scrollTop || (body && body.scrollTop) || 0;
        var scrollHeight = Math.max(
            root ? root.scrollHeight : 0,
            body ? body.scrollHeight : 0
        );
        var clientHeight = root
            ? root.clientHeight
            : (window.innerHeight || 0);
        return {
            scrollY: scrollY,
            scrollHeight: scrollHeight,
            clientHeight: clientHeight
        };
    })();
    """
}

private struct WebContentOverlayScrollIndicatorState: Equatable {
    let viewportHeight: CGFloat
    let contentHeight: CGFloat
    let contentOffset: CGFloat
}

private final class WebContentOverlayScrollIndicatorView: NSView {
    var indicatorColor: NSColor = OverlayScrollIndicatorStyle.thumbColor {
        didSet {
            thumbView.layer?.backgroundColor = indicatorColor.cgColor
        }
    }
    var viewportHeight: CGFloat = 0
    var scrollableContentHeight: CGFloat = 0
    var onInteractionBegan: (() -> Void)?
    var onInteractionEnded: (() -> Void)?
    var onScrollOffsetChanged: ((CGFloat) -> Void)?

    private let thumbView = NSView()
    private var currentMetrics: SidebarPassiveScrollIndicatorMetrics?
    private var trackingArea: NSTrackingArea?
    private var dragGrabOffsetY: CGFloat?
    private var isThumbHovered = false
    private var isThumbDragging = false

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        thumbView.wantsLayer = true
        thumbView.layer?.masksToBounds = true
        thumbView.layer?.backgroundColor = indicatorColor.cgColor
        addSubview(thumbView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateThumb(metrics: SidebarPassiveScrollIndicatorMetrics) {
        currentMetrics = metrics
        updateThumbLayout(animated: false)
        updateHoverStateFromMouseLocation(animated: false)
    }

    func clearInteractionState() {
        isThumbHovered = false
        isThumbDragging = false
        dragGrabOffsetY = nil
    }

    private func updateThumbLayout(animated: Bool) {
        guard let metrics = currentMetrics else { return }

        let targetWidth = currentThumbWidth
        let targetOpacity = OverlayScrollIndicatorStyle.thumbOpacity
        let targetFrame = SidebarPassiveScrollIndicatorLayout.thumbFrame(
            in: bounds,
            metrics: metrics,
            width: targetWidth
        )

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = OverlayScrollIndicatorStyle.thumbLayoutAnimationDuration
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
        onInteractionEnded?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01 else { return nil }
        let localPoint = convert(point, from: superview)
        guard thumbInteractionFrame.contains(localPoint) else { return nil }
        return self
    }

    private var currentThumbWidth: CGFloat {
        isThumbHovered || isThumbDragging
            ? OverlayScrollIndicatorStyle.expandedThumbWidth
            : OverlayScrollIndicatorStyle.thumbWidth
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
    }

    private func dragThumb(to point: NSPoint) {
        guard let metrics = currentMetrics,
              let dragGrabOffsetY,
              viewportHeight > 0,
              scrollableContentHeight > viewportHeight
        else {
            return
        }

        let contentOffset = SidebarPassiveScrollIndicatorLayout.contentOffset(
            forThumbOffsetY: point.y - dragGrabOffsetY,
            viewportHeight: viewportHeight,
            thumbHeight: metrics.thumbHeight,
            contentHeight: scrollableContentHeight
        )
        onScrollOffsetChanged?(contentOffset)
    }
}

@MainActor
private final class WebContentOverlayScrollIndicatorVisibilityController {
    private weak var indicatorView: WebContentOverlayScrollIndicatorView?
    private var state = SidebarPassiveScrollIndicatorVisibilityState()
    private var hideWorkItem: DispatchWorkItem?

    func attach(_ view: WebContentOverlayScrollIndicatorView?) {
        guard indicatorView !== view else { return }
        invalidate()
        indicatorView = view
    }

    func reveal(in window: NSWindow?) {
        _ = window
        guard let generation = present() else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.fadeOut(generation: generation)
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + OverlayScrollIndicatorStyle.visibleDuration,
            execute: workItem
        )
    }

    func hold(in window: NSWindow?) {
        _ = window
        _ = present()
    }

    func hideImmediately() {
        cancelScheduledHide()
        state.hideImmediately()
        guard let view = indicatorView else { return }
        view.layer?.removeAllAnimations()
        view.isHidden = true
        view.alphaValue = 1
        view.clearInteractionState()
    }

    func invalidate() {
        cancelScheduledHide()
        state.invalidate()
    }

    private func present() -> Int? {
        guard let view = indicatorView else { return nil }
        cancelScheduledHide()
        let generation = state.beginPresentation()
        view.layer?.removeAllAnimations()
        view.isHidden = false
        view.alphaValue = 1
        return generation
    }

    private func fadeOut(generation: Int) {
        guard state.canFinishFade(generation: generation),
              let view = indicatorView,
              !view.isHidden
        else {
            return
        }
        hideWorkItem = nil

        NSAnimationContext.runAnimationGroup { context in
            context.duration = OverlayScrollIndicatorStyle.fadeDuration
            view.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self,
                      self.state.finishFade(generation: generation),
                      let view = self.indicatorView
                else {
                    return
                }
                view.isHidden = true
                view.alphaValue = 1
                view.clearInteractionState()
            }
        }
    }

    private func cancelScheduledHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }
}
