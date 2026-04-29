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
    private var showsScrollIndicator: Bool {
        isInteractive && totalContentHeight > viewportHeight + 1
    }

    var mainContentContainer: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
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
                        .coordinateSpace(name: "ScrollSpace")
                    }
                    .accessibilityIdentifier("space-view-scroll-\(space.id.uuidString)")
                    .scrollIndicators(.hidden)
                    .contentShape(Rectangle())
                    .onScrollGeometryChange(for: CGRect.self) { geometry in
                        geometry.bounds
                    } action: { oldBounds, newBounds in
                        guard isInteractive else { return }
                        deferredScrollStateMutation.schedule(newBounds) { bounds in
                            guard isInteractive else { return }
                            updateScrollState(bounds: bounds)
                        }
                    }
                    .overlay(alignment: .trailing) {
                        if showsScrollIndicator {
                            sidebarScrollIndicator
                                .padding(.trailing, 1)
                        }
                    }
                    VStack {
                        if showTopArrow {
                            HStack {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 1)
                                Spacer()
                                Button {
                                    scrollToTop(proxy: proxy)
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.gray)
                                        .frame(width: 24, height: 24)
                                        .background(Color.white.opacity(0.9))
                                        .clipShape(Circle())
                                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            .padding(.horizontal, 8)
                            .padding(.top, 4)
                        }
                        Spacer()
                    }
                    .zIndex(10)

                    VStack {
                        Spacer()
                        if showBottomArrow {
                            HStack {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(height: 1)
                                Spacer()
                                Button {
                                    scrollToActiveTab(proxy: proxy)
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.gray)
                                        .frame(width: 24, height: 24)
                                        .background(Color.white.opacity(0.9))
                                        .clipShape(Circle())
                                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                            .padding(.horizontal, 8)
                            .padding(.bottom, 4)
                        }
                    }
                }
                .onPreferenceChange(TabPositionPreferenceKey.self) { positions in
                    guard isInteractive else { return }
                    guard preferenceUpdateCoalescer.shouldApplyTabPositionUpdate() else { return }

                    let snapshot = positions
                    Task { @MainActor in
                        if tabPositions != snapshot {
                            tabPositions = snapshot
                        }
                        updateActiveTabPosition()
                    }
                }
                .onPreferenceChange(SpaceContentHeightPreferenceKey.self) { contentHeight in
                    guard isInteractive else { return }
                    deferredContentHeightMutation.schedule(contentHeight) { resolvedContentHeight in
                        guard isInteractive else { return }
                        guard abs(totalContentHeight - resolvedContentHeight) > 0.5 else { return }
                        totalContentHeight = resolvedContentHeight
                        updateArrowIndicators()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
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
        if abs(lastScrollOffset - newScrollOffset) > 0.5 {
            lastScrollOffset = newScrollOffset
        }

        let newCanScrollUp = minY < 0
        if canScrollUp != newCanScrollUp {
            canScrollUp = newCanScrollUp
        }

        let newCanScrollDown = totalContentHeight > viewportHeight && (-minY + viewportHeight) < totalContentHeight
        if canScrollDown != newCanScrollDown {
            canScrollDown = newCanScrollDown
        }

        let newIsAtTop = minY >= 0
        if isAtTop != newIsAtTop {
            isAtTop = newIsAtTop
        }

        updateContentHeight()
        updateArrowIndicators()
    }

    private func updateContentHeight() {
        totalContentHeight = max(totalContentHeight, 0)
    }

    private func updateActiveTabPosition() {
        guard isInteractive else {
            activeTabPosition = .zero
            showTopArrow = false
            showBottomArrow = false
            return
        }
        guard let activeTab = browserManager.currentTab(for: windowState),
              activeTab.spaceId == space.id else {
            activeTabPosition = .zero
            showTopArrow = false
            showBottomArrow = false
            return
        }

        if let tabFrame = tabPositions[activeTab.id] {
            activeTabPosition = tabFrame
        }

        DispatchQueue.main.async {
            self.updateArrowIndicators()
        }
    }

    private func updateArrowIndicators() {
        guard isInteractive else {
            showTopArrow = false
            showBottomArrow = false
            return
        }
        guard let activeTab = browserManager.currentTab(for: windowState),
              activeTab.spaceId == space.id else {
            // No active tab in this space, don't show arrows
            showTopArrow = false
            showBottomArrow = false
            return
        }

        guard !selectionScrollGuard.isLocked else {
            showTopArrow = false
            showBottomArrow = false
            return
        }

        let activeTabTop = activeTabPosition.minY
        let activeTabBottom = activeTabPosition.maxY

        let activeTabIsAbove = activeTabBottom < scrollOffset
        let activeTabIsBelow = activeTabTop > scrollOffset + viewportHeight
        showTopArrow = activeTabIsAbove && canScrollUp
        showBottomArrow = activeTabIsBelow && canScrollDown
    }

    private func scrollToActiveTab(proxy: ScrollViewProxy) {
        guard let activeTab = browserManager.currentTab(for: windowState),
              activeTab.spaceId == space.id else { return }

        guard !selectionScrollGuard.isLocked else { return }

        updateContentHeight()
        updateActiveTabPosition()

        let activeTabTop = activeTabPosition.minY
        if activeTabTop > scrollOffset + viewportHeight {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(activeTab.id, anchor: .bottom)
            }
            return
        }

        let activeTabBottom = activeTabPosition.maxY
        if activeTabBottom < scrollOffset {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(activeTab.id, anchor: .top)
            }
            return
        }
    }

    private func scrollToTop(proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo("space-separator-top", anchor: .top)
        }
    }
}
