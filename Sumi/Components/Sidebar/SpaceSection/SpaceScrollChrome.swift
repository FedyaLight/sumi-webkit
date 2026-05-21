//
//  SpaceScrollChrome.swift
//  Sumi
//

import SwiftUI
import AppKit

extension SpaceView {
    var mainContentContainer: some View {
        let topFadeProgress = SidebarTabListVerticalFadeMask.topFadeProgress(
            for: tabListVerticalScrollOffset
        )

        return ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 8) {
                pinnedTabsSection

                VStack(spacing: 8) {
                    regularTabsSection
                }
            }
            .frame(minWidth: 0, maxWidth: innerWidth, alignment: .leading)
            .background {
                SidebarTabListScrollRegistrationViewRepresentable(
                    isEnabled: isInteractive,
                    onVerticalScrollOffsetChange: updateTabListVerticalScrollOffset
                )
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityIdentifier("space-view-scroll-\(space.id.uuidString)")
        .scrollIndicators(.visible, axes: .vertical)
        .contentShape(Rectangle())
        .mask(SidebarTabListVerticalFadeMask(topFadeProgress: topFadeProgress))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func updateTabListVerticalScrollOffset(_ offset: CGFloat) {
        let normalizedOffset = max(offset, 0)
        guard abs(tabListVerticalScrollOffset - normalizedOffset) > 0.25 else { return }
        tabListVerticalScrollOffset = normalizedOffset
    }
}

private struct SidebarTabListVerticalFadeMask: View {
    private static let fadeHeight: CGFloat = 14

    let topFadeProgress: CGFloat

    static func topFadeProgress(for verticalScrollOffset: CGFloat) -> CGFloat {
        guard verticalScrollOffset.isFinite, fadeHeight > 0 else { return 0 }
        return min(max(verticalScrollOffset / fadeHeight, 0), 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.white.opacity(1 - topFadeProgress), .white],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: Self.fadeHeight)

            Color.white

            LinearGradient(
                colors: [.white, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: Self.fadeHeight)
        }
    }
}

private struct SidebarTabListScrollRegistrationViewRepresentable: NSViewRepresentable {
    let isEnabled: Bool
    let onVerticalScrollOffsetChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> SidebarTabListScrollRegistrationView {
        SidebarTabListScrollRegistrationView()
    }

    func updateNSView(_ nsView: SidebarTabListScrollRegistrationView, context: Context) {
        nsView.onVerticalScrollOffsetChange = onVerticalScrollOffsetChange
        nsView.isRegistrationEnabled = isEnabled
        nsView.scheduleScrollViewSync()
    }

    static func dismantleNSView(_ nsView: SidebarTabListScrollRegistrationView, coordinator: ()) {
        nsView.onVerticalScrollOffsetChange = nil
        nsView.detachScrollView()
    }
}

private final class SidebarTabListScrollRegistrationView: NSView {
    var isRegistrationEnabled = true {
        didSet {
            guard isRegistrationEnabled != oldValue else { return }
            syncScrollViewState()
        }
    }

    var onVerticalScrollOffsetChange: ((CGFloat) -> Void)?

    private weak var registeredScrollView: NSScrollView?
    private weak var observedScrollView: NSScrollView?
    private var boundsObserver: NSObjectProtocol?
    private var lastReportedVerticalScrollOffset: CGFloat?

    override var isOpaque: Bool { false }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        scheduleScrollViewSync()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleScrollViewSync()
    }

    func scheduleScrollViewSync() {
        DispatchQueue.main.async { [weak self] in
            self?.syncScrollViewState()
        }
    }

    func detachScrollView() {
        unregisterScrollView()
        stopObservingScrollBounds()
        reportVerticalScrollOffset(0)
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
        guard let scrollView else {
            stopObservingScrollBounds()
            reportVerticalScrollOffset(0)
            return
        }

        guard observedScrollView !== scrollView else {
            reportCurrentVerticalScrollOffset()
            return
        }

        stopObservingScrollBounds()
        observedScrollView = scrollView
        scrollView.contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reportCurrentVerticalScrollOffset()
            }
        }
        reportCurrentVerticalScrollOffset()
    }

    private func stopObservingScrollBounds() {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
            self.boundsObserver = nil
        }
        observedScrollView = nil
    }

    private func reportCurrentVerticalScrollOffset() {
        guard let scrollView = observedScrollView else {
            reportVerticalScrollOffset(0)
            return
        }
        reportVerticalScrollOffset(normalizedVerticalScrollOffset(in: scrollView))
    }

    private func reportVerticalScrollOffset(_ offset: CGFloat) {
        let safeOffset = offset.isFinite ? max(offset, 0) : 0
        if let lastReportedVerticalScrollOffset,
           abs(lastReportedVerticalScrollOffset - safeOffset) <= 0.25 {
            return
        }
        lastReportedVerticalScrollOffset = safeOffset
        onVerticalScrollOffsetChange?(safeOffset)
    }

    private func normalizedVerticalScrollOffset(in scrollView: NSScrollView) -> CGFloat {
        guard let documentView = scrollView.documentView else { return 0 }

        let visibleHeight = scrollView.contentView.bounds.height
        let documentHeight = documentView.bounds.height
        let maximumOffset = max(documentHeight - visibleHeight, 0)
        guard maximumOffset > 0 else { return 0 }

        let rawY = scrollView.contentView.bounds.origin.y
        let offset = documentView.isFlipped
            ? rawY
            : maximumOffset - rawY

        return min(max(offset, 0), maximumOffset)
    }
}
