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
            outerWidth: outerWidth
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

struct SidebarPassiveScrollIndicatorMetrics: Equatable {
    let thumbOffsetY: CGFloat
    let thumbHeight: CGFloat
}

struct SidebarScrollBoundaryState: Equatable {
    let hasContentAbove: Bool
    let hasContentBelow: Bool

    init(visibleRect: CGRect, contentHeight: CGFloat) {
        let tolerance: CGFloat = 0.5
        let hasOverflow = contentHeight > visibleRect.height + tolerance
        hasContentAbove = hasOverflow && visibleRect.minY > tolerance
        hasContentBelow = hasOverflow && visibleRect.maxY < contentHeight - tolerance
    }
}

enum SidebarPassiveScrollIndicatorLayout {
    static let width: CGFloat = 3
    static let trailingInset: CGFloat = 2
    static let minimumThumbHeight: CGFloat = 28
    static let visibleDuration: TimeInterval = 0.9
    static let fadeDuration: TimeInterval = 0.18

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

    static func frame(
        for metrics: SidebarPassiveScrollIndicatorMetrics,
        in viewportFrame: CGRect,
        isFlipped: Bool
    ) -> CGRect {
        let width = Self.width
        let x = max(
            viewportFrame.minX,
            viewportFrame.maxX - trailingInset - width
        )
        let y = isFlipped
            ? viewportFrame.minY + metrics.thumbOffsetY
            : viewportFrame.maxY - metrics.thumbOffsetY - metrics.thumbHeight

        return CGRect(
            x: x,
            y: y,
            width: width,
            height: metrics.thumbHeight
        )
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
    @ViewBuilder let content: () -> Content

    @State private var hasContentAbove = false
    @State private var hasContentBelow = false

    @Environment(\.resolvedThemeContext) var themeContext
    @Environment(\.sumiSettings) var sumiSettings

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            // The parent SpaceView owns the sidebar's horizontal inset; keep scroll content aligned with SpaceTitle.
            content()
                .frame(minWidth: 0, maxWidth: outerWidth, alignment: .leading)
                .background {
                    SidebarTabListScrollRegistrationViewRepresentable(
                        isEnabled: isInteractive,
                        indicatorColor: scrollIndicatorColor
                    )
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                }
        }
        .environment(\.nativeSurfaceHoverUpdatesEnabled, scrollHoverCoordinator.hoverUpdatesEnabled)
        .suppressesNativeSurfaceHoverWhileScrolling(scrollHoverCoordinator, region: "sidebar-tabs-\(spaceId.uuidString)")
        .accessibilityIdentifier("space-view-scroll-\(spaceId.uuidString)")
        .scrollIndicators(.hidden, axes: .vertical)
        .onScrollGeometryChange(for: SidebarScrollBoundaryState.self) { geometry in
            SidebarScrollBoundaryState(
                visibleRect: geometry.visibleRect,
                contentHeight: geometry.contentSize.height
            )
        } action: { _, state in
            hasContentAbove = state.hasContentAbove
            hasContentBelow = state.hasContentBelow
        }
        .contentShape(Rectangle())
        .clipped() // Hardware-accelerated viewport-bound clipping
        .overlay(alignment: .top) {
            Rectangle()
                .fill(tokens.separator)
                .frame(height: 1)
                .opacity(hasContentAbove ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.15), value: hasContentAbove)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(tokens.separator)
                .frame(height: 1)
                .opacity(hasContentBelow ? 1.0 : 0.0)
                .animation(.easeInOut(duration: 0.15), value: hasContentBelow)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var scrollIndicatorColor: NSColor {
        switch themeContext.nativeSurfaceColorScheme {
        case .light:
            return NSColor.black.withAlphaComponent(0.24)
        case .dark:
            return NSColor.white.withAlphaComponent(0.28)
        @unknown default:
            return NSColor.secondaryLabelColor.withAlphaComponent(0.35)
        }
    }
}

private struct SidebarTabListScrollRegistrationViewRepresentable: NSViewRepresentable {
    let isEnabled: Bool
    let indicatorColor: NSColor

    func makeNSView(context: Context) -> SidebarTabListScrollRegistrationView {
        SidebarTabListScrollRegistrationView()
    }

    func updateNSView(_ nsView: SidebarTabListScrollRegistrationView, context: Context) {
        nsView.indicatorColor = indicatorColor
        if nsView.isRegistrationEnabled != isEnabled {
            nsView.isRegistrationEnabled = isEnabled
        }
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

    private let thumbView = NSView()
    private var currentMetrics: SidebarPassiveScrollIndicatorMetrics?

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

    func updateThumb(metrics: SidebarPassiveScrollIndicatorMetrics) {
        currentMetrics = metrics
        updateThumbLayout(animated: false)
    }

    private func updateThumbLayout(animated: Bool) {
        guard let metrics = currentMetrics else { return }

        let targetWidth: CGFloat = SidebarPassiveScrollIndicatorLayout.width
        let targetOpacity: Float = 0.28
        let targetX = bounds.width - targetWidth // Align to the right
        let targetY = metrics.thumbOffsetY

        let targetFrame = NSRect(x: targetX, y: targetY, width: targetWidth, height: metrics.thumbHeight)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                thumbView.animator().frame = targetFrame
                thumbView.animator().alphaValue = CGFloat(targetOpacity)
                thumbView.layer?.cornerRadius = targetWidth / 2
            }
        } else {
            thumbView.frame = targetFrame
            thumbView.alphaValue = CGFloat(targetOpacity)
            thumbView.layer?.cornerRadius = targetWidth / 2
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private final class SidebarTabListScrollRegistrationView: NSView {
    var isRegistrationEnabled = false {
        didSet {
            guard isRegistrationEnabled != oldValue else { return }
            syncScrollViewState()
        }
    }

    var indicatorColor: NSColor = .clear {
        didSet {
            scrollIndicatorView?.indicatorColor = indicatorColor
        }
    }

    private weak var registeredScrollView: NSScrollView?
    private weak var observedScrollView: NSScrollView?
    private weak var observedDocumentView: NSView?
    private weak var scrollIndicatorView: SidebarPassiveScrollIndicatorView?
    private var lastScrollIndicatorState: SidebarPassiveScrollIndicatorState?
    private var hideScrollIndicatorWorkItem: DispatchWorkItem?
    private var scrollIndicatorVisibilityGeneration = 0

    private var boundsObserver: NSObjectProtocol?
    private var documentFrameObserver: NSObjectProtocol?
    private var didEnableBoundsChangedNotifications = false
    private var didEnableDocumentFrameChangedNotifications = false

    override var isOpaque: Bool { false }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        scheduleScrollViewSync()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleScrollViewSync()
    }

    deinit {
        MainActor.assumeIsolated {
            stopObservingScrollBounds()
            unregisterScrollView()
            removePassiveScrollIndicator()
        }
    }

    func scheduleScrollViewSync() {
        DispatchQueue.main.async { [weak self] in
            self?.syncScrollViewState()
        }
    }

    func detachScrollView() {
        unregisterScrollView()
        stopObservingScrollBounds()
        removePassiveScrollIndicator()
    }

    private func unregisterScrollView() {
        guard let registeredScrollView else { return }
        SidebarTabListDragAutoscrollRegistry.shared.unregister(registeredScrollView)
        self.registeredScrollView = nil
    }

    private func syncScrollViewState() {
        let scrollView = window == nil ? nil : enclosingScrollView
        syncRegistration(for: scrollView)
        syncScrollBoundsObservation(for: scrollView)
    }

    private func syncRegistration(for scrollView: NSScrollView?) {
        guard isRegistrationEnabled,
              let scrollView else {
            unregisterScrollView()
            return
        }

        guard registeredScrollView !== scrollView else { return }
        unregisterScrollView()
        SidebarTabListDragAutoscrollRegistry.shared.register(scrollView)
        registeredScrollView = scrollView
    }

    private func syncScrollBoundsObservation(for scrollView: NSScrollView?) {
        guard isRegistrationEnabled,
              let scrollView else {
            stopObservingScrollBounds()
            removePassiveScrollIndicator()
            reportAutoscrollBoundaries(hasContentAbove: false, hasContentBelow: false)
            return
        }

        configurePassiveScrollIndicator(for: scrollView)

        guard observedScrollView !== scrollView else {
            reportCurrentScrollBoundaries()
            return
        }

        stopObservingScrollBounds()
        observedScrollView = scrollView

        // 1. Observe Scroll/Viewport bounds changes synchronously
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
                self?.reportCurrentScrollBoundaries()
            }
        }

        // 2. Observe Document View frame changes synchronously
        if let documentView = scrollView.documentView {
            observedDocumentView = documentView
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
                    self?.reportCurrentScrollBoundaries()
                }
            }
        }

        reportCurrentScrollBoundaries()
    }

    private func configurePassiveScrollIndicator(for scrollView: NSScrollView) {
        if scrollView.scrollerStyle != .overlay {
            scrollView.scrollerStyle = .overlay
        }
        if scrollView.verticalScrollElasticity != .none {
            scrollView.verticalScrollElasticity = .none
        }
        if scrollView.hasVerticalScroller {
            scrollView.hasVerticalScroller = false
        }

        let indicatorView: SidebarPassiveScrollIndicatorView
        if let existing = scrollIndicatorView,
           existing.superview === scrollView {
            indicatorView = existing
        } else {
            scrollIndicatorView?.removeFromSuperview()
            let view = SidebarPassiveScrollIndicatorView(frame: .zero)
            view.indicatorColor = indicatorColor
            view.isHidden = true
            view.autoresizingMask = []
            scrollView.addSubview(view, positioned: .above, relativeTo: nil)
            scrollIndicatorView = view
            indicatorView = view
        }

        indicatorView.indicatorColor = indicatorColor
    }

    private func removePassiveScrollIndicator() {
        cancelScheduledPassiveScrollIndicatorHide()
        lastScrollIndicatorState = nil
        scrollIndicatorVisibilityGeneration += 1
        scrollIndicatorView?.removeFromSuperview()
        scrollIndicatorView = nil
    }

    private func stopObservingScrollBounds() {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
            self.boundsObserver = nil
        }
        if let documentFrameObserver {
            NotificationCenter.default.removeObserver(documentFrameObserver)
            self.documentFrameObserver = nil
        }
        if didEnableBoundsChangedNotifications {
            observedScrollView?.contentView.postsBoundsChangedNotifications = false
            didEnableBoundsChangedNotifications = false
        }
        if didEnableDocumentFrameChangedNotifications {
            observedDocumentView?.postsFrameChangedNotifications = false
            didEnableDocumentFrameChangedNotifications = false
        }
        observedScrollView = nil
        observedDocumentView = nil
    }

    private func reportCurrentScrollBoundaries() {
        guard let scrollView = observedScrollView,
              let documentView = scrollView.documentView else {
            reportAutoscrollBoundaries(hasContentAbove: false, hasContentBelow: false)
            hidePassiveScrollIndicatorImmediately(resetState: true)
            return
        }

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
            updatePassiveScrollIndicator(
                scrollView: scrollView,
                visibleHeight: visibleHeight,
                documentHeight: documentHeight,
                offset: offset
            )
            reportAutoscrollBoundaries(hasContentAbove: hasContentAbove, hasContentBelow: hasContentBelow)
        } else {
            reportAutoscrollBoundaries(hasContentAbove: false, hasContentBelow: false)
            hidePassiveScrollIndicatorImmediately(resetState: true)
        }
    }

    private func reportAutoscrollBoundaries(hasContentAbove: Bool, hasContentBelow: Bool) {
        guard let observedScrollView else { return }
        SidebarTabListDragAutoscrollRegistry.shared.updateBoundaries(
            for: observedScrollView,
            hasContentAbove: hasContentAbove,
            hasContentBelow: hasContentBelow
        )
    }

    private func updatePassiveScrollIndicator(
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
        let shouldReveal = lastScrollIndicatorState != state
        lastScrollIndicatorState = state

        guard let indicatorView = scrollIndicatorView,
              let metrics = SidebarPassiveScrollIndicatorLayout.metrics(
                viewportHeight: visibleHeight,
                contentHeight: documentHeight,
                contentOffset: clampedOffset
              )
        else {
            hidePassiveScrollIndicatorImmediately(resetState: true)
            return
        }

        let width: CGFloat = 12
        let inset: CGFloat = 2
        indicatorView.frame = CGRect(
            x: scrollView.contentView.frame.width - width - inset,
            y: 0,
            width: width,
            height: visibleHeight
        )

        indicatorView.updateThumb(metrics: metrics)

        if shouldReveal {
            showPassiveScrollIndicator(indicatorView)
        }
    }

    private func showPassiveScrollIndicator(_ indicatorView: SidebarPassiveScrollIndicatorView) {
        cancelScheduledPassiveScrollIndicatorHide()
        scrollIndicatorVisibilityGeneration += 1
        let generation = scrollIndicatorVisibilityGeneration

        indicatorView.layer?.removeAllAnimations()
        indicatorView.isHidden = false
        indicatorView.alphaValue = 1

        let workItem = DispatchWorkItem { [weak self] in
            self?.fadeOutPassiveScrollIndicator(generation: generation)
        }
        hideScrollIndicatorWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + SidebarPassiveScrollIndicatorLayout.visibleDuration,
            execute: workItem
        )
    }

    private func fadeOutPassiveScrollIndicator(generation: Int) {
        guard generation == scrollIndicatorVisibilityGeneration,
              let indicatorView = scrollIndicatorView,
              !indicatorView.isHidden
        else {
            return
        }
        hideScrollIndicatorWorkItem = nil

        NSAnimationContext.runAnimationGroup { context in
            context.duration = SidebarPassiveScrollIndicatorLayout.fadeDuration
            indicatorView.animator().alphaValue = 0
        } completionHandler: { [weak self, weak indicatorView] in
            MainActor.assumeIsolated {
                guard let self,
                      self.scrollIndicatorVisibilityGeneration == generation,
                      let indicatorView,
                      indicatorView === self.scrollIndicatorView
                else {
                    return
                }

                indicatorView.isHidden = true
                indicatorView.alphaValue = 1
            }
        }
    }

    private func hidePassiveScrollIndicatorImmediately(resetState: Bool) {
        cancelScheduledPassiveScrollIndicatorHide()
        scrollIndicatorVisibilityGeneration += 1
        if resetState {
            lastScrollIndicatorState = nil
        }

        scrollIndicatorView?.layer?.removeAllAnimations()
        scrollIndicatorView?.isHidden = true
        scrollIndicatorView?.alphaValue = 1
    }

    private func cancelScheduledPassiveScrollIndicatorHide() {
        hideScrollIndicatorWorkItem?.cancel()
        hideScrollIndicatorWorkItem = nil
    }
}
