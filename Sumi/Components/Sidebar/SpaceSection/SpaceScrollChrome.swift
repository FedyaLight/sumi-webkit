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

struct SidebarPassiveScrollIndicatorState: Equatable {
    let viewportHeight: CGFloat
    let contentHeight: CGFloat
    let contentOffset: CGFloat
}

/// A layout-stable wrapper that isolates scroll offsets and boundary state to prevent invalidating the parent SpaceView.
struct SpaceScrollView<Content: View>: View {
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

struct SidebarTabListScrollRegistrationViewRepresentable: NSViewRepresentable {
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
