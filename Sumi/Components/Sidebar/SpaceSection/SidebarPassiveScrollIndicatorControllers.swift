//
//  SidebarPassiveScrollIndicatorControllers.swift
//  Sumi
//

import AppKit
import SwiftUI

@MainActor
final class SidebarPassiveScrollIndicatorVisibilityController {
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
            MainActor.assumeIsolated {
                self?.fadeOut(generation: generation)
            }
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
final class SidebarScrollBoundsObserver {
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
final class SidebarPassiveScrollIndicatorPresenter {
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

