//
//  SidebarTabListScrollRegistrationView.swift
//  Sumi
//

import AppKit
import SwiftUI

final class SidebarTabListScrollRegistrationView: NSView {
    var isRegistrationEnabled = false {
        didSet {
            guard isRegistrationEnabled != oldValue else { return }
            syncScrollViewState()
        }
    }

    var dragAutoscrollRegistry: SidebarTabListDragAutoscrollRegistry?

    private var surfaceObservation = SidebarScrollSurfaceObservation.disabled

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
    private var pendingGeometry: SidebarSelectedItemSurfaceGeometry?
    private var lastDeliveredGeometry: SidebarSelectedItemSurfaceGeometry?
    private var isGeometryDeliveryScheduled = false

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

    func updateSurfaceObservation(
        _ observation: SidebarScrollSurfaceObservation
    ) {
        if surfaceObservation.surfaceID != observation.surfaceID {
            lastDeliveredGeometry = nil
        }
        surfaceObservation = observation
    }

    func detachScrollView() {
        surfaceObservation = .disabled
        pendingGeometry = nil
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
            reportAutoscrollBoundaries(
                hasContentAbove: false,
                hasContentBelow: false
            )
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
        let rawY = scrollView.contentView.bounds.origin.y
        let offset = documentView.isFlipped
            ? rawY
            : maximumOffset - rawY
        let geometry = SidebarSelectedItemSurfaceGeometry(
            contentOffsetY: offset,
            viewportHeight: visibleHeight,
            contentHeight: documentHeight
        )

        if surfaceObservation.capturesLiveViewport {
            surfaceObservation.onLiveViewportChange(geometry.scrollViewport)
        }
        scheduleGeometryDelivery(geometry)

        if maximumOffset > 0 {
            let hasContentAbove = offset > 0.5
            let hasContentBelow = offset < (maximumOffset - 0.5)
            indicatorPresenter.updateIndicator(
                scrollView: scrollView,
                visibleHeight: visibleHeight,
                documentHeight: documentHeight,
                offset: offset
            )
            reportAutoscrollBoundaries(
                hasContentAbove: hasContentAbove,
                hasContentBelow: hasContentBelow
            )
        } else {
            reportAutoscrollBoundaries(
                hasContentAbove: false,
                hasContentBelow: false
            )
            indicatorPresenter.hideImmediately(resetState: true)
        }
    }

    /// Geometry mutates observable reveal state, so it is coalesced outside
    /// AppKit's layout pass. Live viewport capture stays synchronous above so
    /// mouse and trackpad navigation see the latest offset in the same event.
    private func scheduleGeometryDelivery(
        _ geometry: SidebarSelectedItemSurfaceGeometry
    ) {
        pendingGeometry = geometry
        guard !isGeometryDeliveryScheduled else { return }
        isGeometryDeliveryScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isGeometryDeliveryScheduled = false
            guard let geometry = pendingGeometry else { return }
            pendingGeometry = nil
            guard lastDeliveredGeometry != geometry else { return }
            lastDeliveredGeometry = geometry
            surfaceObservation.onGeometryChange(geometry)
        }
    }

    private func reportAutoscrollBoundaries(
        hasContentAbove: Bool,
        hasContentBelow: Bool
    ) {
        guard let scrollView = scrollBoundsObserver.scrollView else { return }
        dragAutoscrollRegistry?.updateBoundaries(
            for: scrollView,
            hasContentAbove: hasContentAbove,
            hasContentBelow: hasContentBelow
        )
    }
}
