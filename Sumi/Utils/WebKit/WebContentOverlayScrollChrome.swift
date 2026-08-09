import AppKit
import SumiWebRuntime
import WebKit

struct WebContentOverlayScrollMetrics: Equatable {
    let viewportHeight: CGFloat
    let contentHeight: CGFloat
    let contentOffset: CGFloat
}

/// AppKit chrome drawn above WKWebView. Page script messages supply geometry;
/// scrolling and ordinary input remain owned by WebKit.
@MainActor
final class WebContentOverlayScrollChrome {
    private weak var hostView: NSView?
    private weak var webView: WKWebView?
    private let indicatorView = WebContentOverlayScrollIndicatorView(frame: .zero)
    private let visibility = WebContentOverlayScrollIndicatorVisibilityController()
    private var isInstalled = false

    var indicatorHostingView: NSView { indicatorView }

    func install(in hostView: NSView, webView: WKWebView) {
        self.hostView = hostView
        self.webView = webView

        indicatorView.identifier = NSUserInterfaceItemIdentifier("SumiPageScrollbarOverlay")
        indicatorView.indicatorColor = OverlayScrollIndicatorStyle.thumbColor
        indicatorView.isHidden = true
        indicatorView.onInteractionBegan = { [weak self, weak hostView] in
            self?.visibility.hold(in: hostView?.window)
        }
        indicatorView.onInteractionEnded = { [weak self, weak hostView] in
            self?.visibility.reveal(in: hostView?.window)
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
        visibility.attach(nil)
        indicatorView.clearInteractionState()
        indicatorView.removeFromSuperview()
        hostView = nil
        webView = nil
    }

    func ensureIndicatorAboveContent() {
        guard isInstalled,
              let hostView,
              indicatorView.superview === hostView
        else { return }

        guard webView?.sumiIsInFullscreenElementPresentation != true else {
            hideImmediately()
            return
        }
        let contentView = webView?.sumiDisplayedContentView
        if contentView?.superview === hostView {
            hostView.addSubview(indicatorView, positioned: .above, relativeTo: contentView)
        } else {
            hostView.addSubview(indicatorView, positioned: .above, relativeTo: nil)
        }
        layoutIndicator()
    }

    func layoutIndicator() {
        guard let hostView else { return }
        guard webView?.sumiIsInFullscreenElementPresentation != true else {
            hideImmediately()
            return
        }
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

    func update(_ metrics: WebContentOverlayScrollMetrics, reveal: Bool) {
        guard isInstalled,
              let hostView,
              hostView.window != nil,
              !hostView.isHiddenOrHasHiddenAncestor,
              let webView,
              webView.window != nil,
              !webView.sumiIsInFullscreenElementPresentation
        else {
            hideImmediately()
            return
        }

        let maximumOffset = max(metrics.contentHeight - metrics.viewportHeight, 0)
        let clampedOffset = min(max(metrics.contentOffset, 0), maximumOffset)
        guard let thumbMetrics = SidebarPassiveScrollIndicatorLayout.metrics(
            viewportHeight: metrics.viewportHeight,
            contentHeight: metrics.contentHeight,
            contentOffset: clampedOffset
        ) else {
            hideImmediately()
            return
        }

        layoutIndicator()
        indicatorView.updateThumb(metrics: thumbMetrics)
        indicatorView.scrollableContentHeight = metrics.contentHeight
        indicatorView.viewportHeight = metrics.viewportHeight
        if reveal {
            visibility.reveal(in: indicatorView.window)
        }
    }

    func hideImmediately() {
        visibility.hideImmediately()
    }

    private func applyScrollOffset(_ contentOffset: CGFloat) {
        guard let webView else { return }
        let offset = Double(max(contentOffset, 0))
        webView.evaluateJavaScript(
            "window.scrollTo(0, \(offset));",
            completionHandler: nil
        )
    }
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

        let width = currentThumbWidth
        let frame = SidebarPassiveScrollIndicatorLayout.thumbFrame(
            in: bounds,
            metrics: metrics,
            width: width
        )
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = OverlayScrollIndicatorStyle.thumbLayoutAnimationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                thumbView.animator().frame = frame
                thumbView.animator().alphaValue = OverlayScrollIndicatorStyle.thumbOpacity
                thumbView.layer?.cornerRadius = width / 2
            }
        } else {
            thumbView.frame = frame
            thumbView.alphaValue = OverlayScrollIndicatorStyle.thumbOpacity
            thumbView.layer?.cornerRadius = width / 2
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self
        )
        trackingArea = area
        addTrackingArea(area)
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
        dragThumb(to: convert(event.locationInWindow, from: nil))
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
        return thumbInteractionFrame.contains(localPoint) ? self : nil
    }

    private var currentThumbWidth: CGFloat {
        isThumbHovered || isThumbDragging
            ? OverlayScrollIndicatorStyle.expandedThumbWidth
            : OverlayScrollIndicatorStyle.thumbWidth
    }

    private var thumbInteractionFrame: NSRect {
        guard let currentMetrics else { return .zero }
        return SidebarPassiveScrollIndicatorLayout.thumbInteractionFrame(
            in: bounds,
            metrics: currentMetrics
        )
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
        else { return }

        onScrollOffsetChanged?(
            SidebarPassiveScrollIndicatorLayout.contentOffset(
                forThumbOffsetY: point.y - dragGrabOffsetY,
                viewportHeight: viewportHeight,
                thumbHeight: metrics.thumbHeight,
                contentHeight: scrollableContentHeight
            )
        )
    }
}

@MainActor
private final class WebContentOverlayScrollIndicatorVisibilityController {
    private weak var indicatorView: WebContentOverlayScrollIndicatorView?
    private var state = SidebarPassiveScrollIndicatorVisibilityState()
    private var hideWorkItem: DispatchWorkItem?
    private var hideDeadline: DispatchTime?

    func attach(_ view: WebContentOverlayScrollIndicatorView?) {
        guard indicatorView !== view else { return }
        invalidate()
        indicatorView = view
    }

    func reveal(in window: NSWindow?) {
        _ = window
        guard present(cancelScheduledHide: false) != nil else { return }
        hideDeadline = .now() + OverlayScrollIndicatorStyle.visibleDuration
        scheduleHideIfNeeded()
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
        present(cancelScheduledHide: true)
    }

    private func present(cancelScheduledHide: Bool) -> Int? {
        guard let view = indicatorView else { return nil }
        if cancelScheduledHide {
            self.cancelScheduledHide()
        }
        let generation = state.beginPresentation()
        if view.isHidden || view.alphaValue < 1 {
            view.layer?.removeAllAnimations()
            view.isHidden = false
            view.alphaValue = 1
        }
        return generation
    }

    private func scheduleHideIfNeeded() {
        guard hideWorkItem == nil,
              let hideDeadline else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.finishScheduledHide()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: hideDeadline, execute: workItem)
    }

    private func finishScheduledHide() {
        hideWorkItem = nil
        guard let hideDeadline else { return }
        guard DispatchTime.now() >= hideDeadline else {
            scheduleHideIfNeeded()
            return
        }
        self.hideDeadline = nil
        fadeOut(generation: state.generation)
    }

    private func fadeOut(generation: Int) {
        guard state.canFinishFade(generation: generation),
              let view = indicatorView,
              !view.isHidden
        else { return }
        hideWorkItem = nil

        NSAnimationContext.runAnimationGroup { context in
            context.duration = OverlayScrollIndicatorStyle.fadeDuration
            view.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self,
                      self.state.finishFade(generation: generation),
                      let view = self.indicatorView
                else { return }
                view.isHidden = true
                view.alphaValue = 1
                view.clearInteractionState()
            }
        }
    }

    private func cancelScheduledHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        hideDeadline = nil
    }
}
