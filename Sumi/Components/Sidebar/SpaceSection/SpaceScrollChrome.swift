//
//  SpaceScrollChrome.swift
//  Sumi
//

import AppKit
import SwiftUI

extension SpaceView {
    var mainContentContainer: some View {
        SpaceScrollView(
            isInteractive: isInteractive,
            spaceId: space.id,
            scrollHoverCoordinator: scrollHoverCoordinator,
            outerWidth: outerWidth,
            onViewportChange: { viewport in
                onScrollViewportChange(space.id, viewport)
            }
        ) {
            VStack(spacing: 8) {
                pinnedTabsSection

                VStack(spacing: 8) {
                    regularTabsSection
                }
            }
        }
    }
}

private struct SidebarPassiveScrollIndicatorState: Equatable {
    let viewportHeight: CGFloat
    let contentHeight: CGFloat
    let contentOffset: CGFloat
}

/// A layout-stable wrapper that isolates scroll offsets and boundary state to prevent invalidating the parent SpaceView.
private struct SpaceScrollView<Content: View>: View {
    let isInteractive: Bool
    let spaceId: UUID
    @ObservedObject var scrollHoverCoordinator: NativeSurfaceScrollHoverCoordinator
    let outerWidth: CGFloat
    let onViewportChange: (SpaceSidebarSnapshotViewport) -> Void
    @ViewBuilder let content: () -> Content

    @State private var hasContentAbove = false
    @State private var hasContentBelow = false

    @Environment(\.resolvedThemeContext) var themeContext
    @Environment(\.sumiSettings) var sumiSettings
    @EnvironmentObject private var dragState: SidebarDragState

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var scrollIndicatorColor: NSColor {
        OverlayScrollIndicatorStyle.thumbColor
    }

    var body: some View {
        let contentWidth = SpaceViewLayout.contentWidth(for: outerWidth)
        let scrollIndicatorTrailingProjection = SpaceViewLayout.scrollIndicatorTrailingProjection

        ScrollView(.vertical, showsIndicators: false) {
            // The parent SpaceView owns the sidebar's horizontal inset; keep scroll content aligned with SpaceTitle.
            content()
                .frame(width: contentWidth, alignment: .leading)
                .background {
                    SidebarTabListScrollRegistrationViewRepresentable(
                        isEnabled: isInteractive,
                        indicatorColor: scrollIndicatorColor,
                        contentViewportWidth: contentWidth,
                        trailingProjection: scrollIndicatorTrailingProjection,
                        dragAutoscrollRegistry: dragState.dragAutoscrollRegistry
                    )
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                }
        }
        .frame(width: contentWidth, alignment: .leading)
        .environment(\.nativeSurfaceHoverUpdatesEnabled, scrollHoverCoordinator.hoverUpdatesEnabled)
        .suppressesNativeSurfaceHoverWhileScrolling(scrollHoverCoordinator, region: "sidebar-tabs-\(spaceId.uuidString)")
        .accessibilityIdentifier("space-view-scroll-\(spaceId.uuidString)")
        .scrollIndicators(.hidden, axes: .vertical)
        .onScrollGeometryChange(for: SidebarScrollBoundaryState.self) { geometry in
            SidebarScrollBoundaryState(
                contentOffsetY: geometry.contentOffset.y,
                visibleRect: geometry.visibleRect,
                contentHeight: geometry.contentSize.height
            )
        } action: { _, state in
            hasContentAbove = state.hasContentAbove
            hasContentBelow = state.hasContentBelow
            onViewportChange(state.scrollViewport)
        }
        .contentShape(Rectangle())
        .clipped() // Hardware-accelerated viewport-bound clipping
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(tokens.separator)
                .frame(width: contentWidth, height: 1)
                .opacity(hasContentAbove ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.15), value: hasContentAbove)
        }
        .overlay(alignment: .bottomLeading) {
            Rectangle()
                .fill(tokens.separator)
                .frame(width: contentWidth, height: 1)
                .opacity(hasContentBelow ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.15), value: hasContentBelow)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct SidebarTabListScrollRegistrationViewRepresentable: NSViewRepresentable {
    let isEnabled: Bool
    let indicatorColor: NSColor
    let contentViewportWidth: CGFloat
    let trailingProjection: CGFloat
    let dragAutoscrollRegistry: SidebarTabListDragAutoscrollRegistry

    func makeNSView(context: Context) -> SidebarTabListScrollRegistrationView {
        let view = SidebarTabListScrollRegistrationView()
        view.dragAutoscrollRegistry = dragAutoscrollRegistry
        return view
    }

    func updateNSView(_ nsView: SidebarTabListScrollRegistrationView, context: Context) {
        nsView.dragAutoscrollRegistry = dragAutoscrollRegistry
        nsView.indicatorColor = indicatorColor
        nsView.scrollIndicatorContentViewportWidth = contentViewportWidth
        nsView.scrollIndicatorTrailingProjection = trailingProjection
        if nsView.isRegistrationEnabled != isEnabled {
            nsView.isRegistrationEnabled = isEnabled
        }
        nsView.applyScrollChromeImmediatelyIfPossible()
        nsView.scheduleScrollViewSync()
    }

    static func dismantleNSView(_ nsView: SidebarTabListScrollRegistrationView, coordinator: ()) {
        nsView.detachScrollView()
    }
}

private final class SidebarPassiveScrollIndicatorView: NSView {
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

/// Owns the passive indicator's reveal → hold → fade lifecycle, kept separate
/// from the registration view so scroll-geometry observation and the timed
/// visibility state machine don't tangle. A monotonic `generation` token
/// discards a fade that outlives the view it was scheduled for.
@MainActor
private final class SidebarPassiveScrollIndicatorVisibilityController {
    private weak var indicatorView: SidebarPassiveScrollIndicatorView?
    private var state = SidebarPassiveScrollIndicatorVisibilityState()
    private var hideWorkItem: DispatchWorkItem?

    func attach(_ view: SidebarPassiveScrollIndicatorView?) {
        guard indicatorView !== view else { return }
        invalidate()
        indicatorView = view
    }

    func reveal(in window: NSWindow?) {
        guard let generation = present(in: window) else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.fadeOut(generation: generation)
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + SidebarPassiveScrollIndicatorLayout.visibleDuration,
            execute: workItem
        )
    }

    func hold(in window: NSWindow?) {
        _ = present(in: window)
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

    private func present(in window: NSWindow?) -> Int? {
        guard let view = indicatorView else { return nil }
        guard !SidebarChromePointerArbitration.isScrollIndicatorSuppressed(in: window) else {
            hideImmediately()
            return nil
        }
        cancelScheduledHide()
        let generation = state.beginPresentation()
        view.layer?.removeAllAnimations()
        view.isHidden = false
        view.alphaValue = 1
        view.setVisibleForResizeSuppression(true)
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
            context.duration = SidebarPassiveScrollIndicatorLayout.fadeDuration
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

@MainActor
private final class SidebarScrollBoundsObserver {
    var onBoundsChanged: (() -> Void)?

    private(set) weak var scrollView: NSScrollView?
    private weak var documentView: NSView?
    private var boundsObserver: NSObjectProtocol?
    private var documentFrameObserver: NSObjectProtocol?
    private var didEnableBoundsChangedNotifications = false
    private var didEnableDocumentFrameChangedNotifications = false

    deinit {
        MainActor.assumeIsolated {
            stop()
        }
    }

    @discardableResult
    func observe(_ scrollView: NSScrollView) -> Bool {
        guard self.scrollView !== scrollView else { return false }

        stop()
        self.scrollView = scrollView

        didEnableBoundsChangedNotifications = !scrollView.contentView.postsBoundsChangedNotifications
        if didEnableBoundsChangedNotifications {
            scrollView.contentView.postsBoundsChangedNotifications = true
        }
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onBoundsChanged?()
            }
        }

        if let documentView = scrollView.documentView {
            self.documentView = documentView
            didEnableDocumentFrameChangedNotifications = !documentView.postsFrameChangedNotifications
            if didEnableDocumentFrameChangedNotifications {
                documentView.postsFrameChangedNotifications = true
            }
            documentFrameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: documentView,
                queue: nil
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.onBoundsChanged?()
                }
            }
        }

        return true
    }

    func stop() {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
            self.boundsObserver = nil
        }
        if let documentFrameObserver {
            NotificationCenter.default.removeObserver(documentFrameObserver)
            self.documentFrameObserver = nil
        }
        if didEnableBoundsChangedNotifications {
            scrollView?.contentView.postsBoundsChangedNotifications = false
            didEnableBoundsChangedNotifications = false
        }
        if didEnableDocumentFrameChangedNotifications {
            documentView?.postsFrameChangedNotifications = false
            didEnableDocumentFrameChangedNotifications = false
        }
        scrollView = nil
        documentView = nil
    }
}

@MainActor
private final class SidebarPassiveScrollIndicatorPresenter {
    var indicatorColor: NSColor = .clear {
        didSet {
            indicatorView?.indicatorColor = indicatorColor
        }
    }
    var contentViewportWidth: CGFloat = 0
    var trailingProjection: CGFloat = 0
    var onScrollOffsetChanged: (() -> Void)?

    private weak var indicatorView: SidebarPassiveScrollIndicatorView?
    private let visibility = SidebarPassiveScrollIndicatorVisibilityController()
    private var lastState: SidebarPassiveScrollIndicatorState?

    deinit {
        MainActor.assumeIsolated {
            removeIndicator()
        }
    }

    func configureIndicator(for scrollView: NSScrollView) {
        guard let overlayContainer = SidebarPassiveScrollIndicatorLayout.overlayContainer(for: scrollView) else {
            removeIndicator()
            return
        }

        let indicatorView: SidebarPassiveScrollIndicatorView
        if let existing = self.indicatorView,
           existing.superview === overlayContainer {
            indicatorView = existing
        } else {
            self.indicatorView?.clearInteractionState()
            self.indicatorView?.removeFromSuperview()
            let view = SidebarPassiveScrollIndicatorView(frame: .zero)
            view.indicatorColor = indicatorColor
            view.isHidden = true
            view.autoresizingMask = []
            overlayContainer.addSubview(view, positioned: .above, relativeTo: nil)
            self.indicatorView = view
            indicatorView = view
        }

        indicatorView.indicatorColor = indicatorColor
        indicatorView.scrollView = scrollView
        visibility.attach(indicatorView)
        indicatorView.onInteractionBegan = { [weak self, weak indicatorView] in
            guard let self else { return }
            visibility.hold(in: indicatorView?.window)
        }
        indicatorView.onInteractionEnded = { [weak self, weak indicatorView] in
            guard let self else { return }
            visibility.reveal(in: indicatorView?.window)
        }
        indicatorView.onScrollOffsetChanged = { [weak self] in
            self?.onScrollOffsetChanged?()
        }
    }

    func removeIndicator() {
        lastState = nil
        visibility.attach(nil)
        indicatorView?.clearInteractionState()
        indicatorView?.removeFromSuperview()
        indicatorView = nil
    }

    func updateIndicator(
        scrollView: NSScrollView,
        visibleHeight: CGFloat,
        documentHeight: CGFloat,
        offset: CGFloat
    ) {
        let maximumContentOffset = max(documentHeight - visibleHeight, 0)
        let clampedOffset = min(max(offset, 0), maximumContentOffset)
        let state = SidebarPassiveScrollIndicatorState(
            viewportHeight: visibleHeight,
            contentHeight: documentHeight,
            contentOffset: clampedOffset
        )
        let shouldReveal = lastState != state
        lastState = state

        guard let indicatorView,
              let metrics = SidebarPassiveScrollIndicatorLayout.metrics(
                viewportHeight: visibleHeight,
                contentHeight: documentHeight,
                contentOffset: clampedOffset
              )
        else {
            hideImmediately(resetState: true)
            return
        }

        guard let overlayContainer = indicatorView.superview else {
            hideImmediately(resetState: true)
            return
        }

        let scrollViewFrameInOverlay = overlayContainer.convert(scrollView.bounds, from: scrollView)
        indicatorView.frame = SidebarPassiveScrollIndicatorLayout.indicatorFrame(
            scrollViewFrameInOverlay: scrollViewFrameInOverlay,
            viewportHeight: visibleHeight,
            contentViewportWidth: max(contentViewportWidth, 0),
            trailingProjection: max(trailingProjection, 0)
        )

        indicatorView.updateThumb(metrics: metrics)

        if shouldReveal {
            visibility.reveal(in: indicatorView.window)
        }
    }

    func hideImmediately(resetState: Bool) {
        if resetState {
            lastState = nil
        }
        visibility.hideImmediately()
    }
}

private final class SidebarTabListScrollRegistrationView: NSView {
    var isRegistrationEnabled = false {
        didSet {
            guard isRegistrationEnabled != oldValue else { return }
            syncScrollViewState()
        }
    }

    var dragAutoscrollRegistry: SidebarTabListDragAutoscrollRegistry?

    var indicatorColor: NSColor = .clear {
        didSet {
            indicatorPresenter.indicatorColor = indicatorColor
        }
    }
    var scrollIndicatorContentViewportWidth: CGFloat = 0 {
        didSet {
            guard scrollIndicatorContentViewportWidth != oldValue else { return }
            indicatorPresenter.contentViewportWidth = scrollIndicatorContentViewportWidth
            scheduleScrollViewSync()
        }
    }
    var scrollIndicatorTrailingProjection: CGFloat = 0 {
        didSet {
            guard scrollIndicatorTrailingProjection != oldValue else { return }
            indicatorPresenter.trailingProjection = scrollIndicatorTrailingProjection
            scheduleScrollViewSync()
        }
    }

    private weak var registeredScrollView: NSScrollView?
    private let scrollBoundsObserver = SidebarScrollBoundsObserver()
    private let indicatorPresenter = SidebarPassiveScrollIndicatorPresenter()
    private var isScrollViewSyncScheduled = false

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollBoundsObserver.onBoundsChanged = { [weak self] in
            self?.reportCurrentScrollBoundaries()
        }
        indicatorPresenter.onScrollOffsetChanged = { [weak self] in
            self?.reportCurrentScrollBoundaries()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        applyScrollChromeImmediatelyIfPossible()
        scheduleScrollViewSync()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyScrollChromeImmediatelyIfPossible()
        scheduleScrollViewSync()
    }

    /// Suppress the native overlay scroller synchronously, before the first
    /// paint of a freshly-mounted scroll view. Space switches rebuild the
    /// committed page (and its `NSScrollView`) from scratch; deferring the
    /// chrome config to the next runloop leaves a one-frame window where the
    /// native scroller flashes in.
    func applyScrollChromeImmediatelyIfPossible() {
        guard let scrollView = enclosingScrollView else { return }
        SidebarTabListScrollChromeConfiguration.apply(to: scrollView)
    }

    deinit {
        MainActor.assumeIsolated {
            scrollBoundsObserver.stop()
            unregisterScrollView()
            indicatorPresenter.removeIndicator()
        }
    }

    func scheduleScrollViewSync() {
        guard !isScrollViewSyncScheduled else { return }
        isScrollViewSyncScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isScrollViewSyncScheduled = false
            syncScrollViewState()
        }
    }

    func detachScrollView() {
        unregisterScrollView()
        scrollBoundsObserver.stop()
        indicatorPresenter.removeIndicator()
    }

    private func unregisterScrollView() {
        guard let registeredScrollView else { return }
        dragAutoscrollRegistry?.unregister(registeredScrollView)
        self.registeredScrollView = nil
    }

    private func syncScrollViewState() {
        let scrollView = window == nil ? nil : enclosingScrollView
        if let scrollView {
            SidebarTabListScrollChromeConfiguration.apply(to: scrollView)
        }
        syncRegistration(for: scrollView)
        syncScrollBoundsObservation(for: scrollView)
    }

    private func syncRegistration(for scrollView: NSScrollView?) {
        guard isRegistrationEnabled,
              let scrollView,
              let dragAutoscrollRegistry else {
            unregisterScrollView()
            return
        }

        guard registeredScrollView !== scrollView else { return }
        unregisterScrollView()
        dragAutoscrollRegistry.register(scrollView)
        registeredScrollView = scrollView
    }

    private func syncScrollBoundsObservation(for scrollView: NSScrollView?) {
        guard isRegistrationEnabled,
              let scrollView else {
            scrollBoundsObserver.stop()
            indicatorPresenter.removeIndicator()
            reportAutoscrollBoundaries(hasContentAbove: false, hasContentBelow: false)
            return
        }

        SidebarTabListScrollChromeConfiguration.apply(to: scrollView)
        indicatorPresenter.configureIndicator(for: scrollView)
        scrollBoundsObserver.observe(scrollView)
        reportCurrentScrollBoundaries()
    }

    private func reportCurrentScrollBoundaries() {
        guard let scrollView = scrollBoundsObserver.scrollView,
              let documentView = scrollView.documentView else {
            reportAutoscrollBoundaries(hasContentAbove: false, hasContentBelow: false)
            indicatorPresenter.hideImmediately(resetState: true)
            return
        }

        SidebarTabListScrollChromeConfiguration.apply(to: scrollView)

        let visibleHeight = scrollView.contentView.bounds.height
        let documentHeight = documentView.bounds.height
        let maximumOffset = max(documentHeight - visibleHeight, 0)

        if maximumOffset > 0 {
            let rawY = scrollView.contentView.bounds.origin.y
            let offset = documentView.isFlipped
                ? rawY
                : maximumOffset - rawY

            let hasContentAbove = offset > 0.5
            let hasContentBelow = offset < (maximumOffset - 0.5)
            indicatorPresenter.updateIndicator(
                scrollView: scrollView,
                visibleHeight: visibleHeight,
                documentHeight: documentHeight,
                offset: offset
            )
            reportAutoscrollBoundaries(hasContentAbove: hasContentAbove, hasContentBelow: hasContentBelow)
        } else {
            reportAutoscrollBoundaries(hasContentAbove: false, hasContentBelow: false)
            indicatorPresenter.hideImmediately(resetState: true)
        }
    }

    private func reportAutoscrollBoundaries(hasContentAbove: Bool, hasContentBelow: Bool) {
        guard let scrollView = scrollBoundsObserver.scrollView else { return }
        dragAutoscrollRegistry?.updateBoundaries(
            for: scrollView,
            hasContentAbove: hasContentAbove,
            hasContentBelow: hasContentBelow
        )
    }
}
