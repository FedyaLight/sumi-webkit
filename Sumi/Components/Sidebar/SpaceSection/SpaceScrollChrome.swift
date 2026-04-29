//
//  SpaceScrollChrome.swift
//  Sumi
//

import SwiftUI

private struct SpaceContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension SpaceView {
    private var hasScrollableOverflow: Bool {
        totalContentHeight > viewportHeight + 1
    }

    private var showsScrollIndicator: Bool {
        isInteractive && isScrollIndicatorActive && hasScrollableOverflow
    }

    var mainContentContainer: some View {
        GeometryReader { _ in
            ZStack {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        pinnedTabsSection

                        VStack(spacing: 8) {
                            regularTabsSection
                        }
                    }
                    .frame(minWidth: 0, maxWidth: innerWidth, alignment: .leading)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: SpaceContentHeightPreferenceKey.self,
                                value: geometry.size.height
                            )
                        }
                    }
                }
                .accessibilityIdentifier("space-view-scroll-\(space.id.uuidString)")
                .scrollIndicators(.hidden)
                .contentShape(Rectangle())
                .onScrollGeometryChange(for: CGRect.self) { geometry in
                    geometry.bounds
                } action: { _, newBounds in
                    guard isInteractive else { return }
                    deferredScrollStateMutation.schedule(newBounds) { bounds in
                        guard isInteractive else { return }
                        updateScrollState(bounds: bounds)
                    }
                }
                .onScrollPhaseChange { _, newPhase in
                    updateScrollIndicatorActivity(isScrolling: newPhase.isScrolling)
                }
                .overlay(alignment: .trailing) {
                    if showsScrollIndicator {
                        sidebarScrollIndicator
                            .padding(.trailing, 1)
                            .transition(.opacity)
                    }
                }
            }
            .onPreferenceChange(SpaceContentHeightPreferenceKey.self) { contentHeight in
                guard isInteractive else { return }
                deferredContentHeightMutation.schedule(contentHeight) { resolvedContentHeight in
                    guard isInteractive else { return }
                    guard abs(totalContentHeight - resolvedContentHeight) > 0.5 else { return }
                    totalContentHeight = resolvedContentHeight
                    if !hasScrollableOverflow {
                        updateScrollIndicatorActivity(isScrolling: false)
                    }
                }
            }
            .onDisappear {
                cancelScrollIndicatorHideTask()
                isScrollIndicatorActive = false
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var sidebarScrollIndicator: some View {
        GeometryReader { geometry in
            let availableHeight = max(geometry.size.height - 8, 1)
            let thumbHeight = max(26, availableHeight * max(min(viewportHeight / max(totalContentHeight, 1), 1), 0))
            let maxTravel = max(availableHeight - thumbHeight, 0)
            let progress = max(
                0,
                min(
                    scrollOffset / max(totalContentHeight - viewportHeight, 1),
                    1
                )
            )

            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.28))
                .frame(width: 3, height: thumbHeight)
                .offset(y: 4 + maxTravel * progress)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(width: 6)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Scroll State

    private func updateScrollState(bounds: CGRect) {
        guard isInteractive else { return }
        let minY = bounds.minY
        let contentHeight = bounds.height

        if abs(viewportHeight - contentHeight) > 0.5 {
            viewportHeight = contentHeight
        }
        let newScrollOffset = -minY
        if abs(scrollOffset - newScrollOffset) > 0.5 {
            scrollOffset = newScrollOffset
        }

        updateContentHeight()
        if !hasScrollableOverflow {
            updateScrollIndicatorActivity(isScrolling: false)
        }
    }

    private func updateContentHeight() {
        totalContentHeight = max(totalContentHeight, 0)
    }

    private func updateScrollIndicatorActivity(isScrolling: Bool) {
        guard isInteractive && hasScrollableOverflow else {
            cancelScrollIndicatorHideTask()
            if isScrollIndicatorActive {
                withAnimation(.easeOut(duration: 0.18)) {
                    isScrollIndicatorActive = false
                }
            }
            return
        }

        cancelScrollIndicatorHideTask()

        if isScrolling {
            if !isScrollIndicatorActive {
                withAnimation(.easeInOut(duration: 0.12)) {
                    isScrollIndicatorActive = true
                }
            }
            return
        }

        scrollIndicatorHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                isScrollIndicatorActive = false
            }
            scrollIndicatorHideTask = nil
        }
    }

    private func cancelScrollIndicatorHideTask() {
        scrollIndicatorHideTask?.cancel()
        scrollIndicatorHideTask = nil
    }
}
