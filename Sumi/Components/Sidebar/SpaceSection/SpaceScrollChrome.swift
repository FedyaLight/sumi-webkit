//
//  SpaceScrollChrome.swift
//  Sumi
//

import AppKit
import SwiftUI

struct SidebarPassiveScrollIndicatorState: Equatable {
    let viewportHeight: CGFloat
    let contentHeight: CGFloat
    let contentOffset: CGFloat
}

struct SpaceSectionsView<Pinned: View, Regular: View>: View {
    let pinnedSection: Pinned
    let regularTabsSection: Regular
    /// The pinned↔regular gap is owned by the regular section itself (see
    /// `SpaceTabSeparatorLayout`) so it can collapse and animate with the
    /// separator; callers pass 0.
    var sectionSpacing: CGFloat = 8

    var body: some View {
        VStack(spacing: sectionSpacing) {
            pinnedSection
            regularTabsSection
        }
    }
}

/// A layout-stable wrapper that isolates scroll offsets and boundary state to prevent invalidating the parent SpaceView.
struct SpaceScrollChromeSurface<Content: View>: View {
    let isInteractive: Bool
    let spaceId: UUID
    let selectedItemRevealPath: SidebarSelectedItemRevealPath?
    let selection: SidebarWindowSelectionSnapshot
    let selectedItemRevealMode: SidebarMotionPolicy.Mode
    let restoredViewport: SpaceSidebarSnapshotViewport?
    @ObservedObject var scrollHoverCoordinator: NativeSurfaceScrollHoverCoordinator
    let outerWidth: CGFloat
    let onViewportChange: (SpaceSidebarSnapshotViewport) -> Void
    @ViewBuilder let content: () -> Content

    @State private var hasContentAbove = false
    @State private var hasContentBelow = false

    @Environment(\.resolvedThemeContext) var themeContext
    @Environment(\.chromeThemeTokens) var scopedChromeTokens
    @Environment(\.sumiSettings) var sumiSettings

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: sumiSettings)
    }

    private var scrollIndicatorColor: NSColor {
        OverlayScrollIndicatorStyle.thumbColor
    }

    var body: some View {
        let contentWidth = SpaceViewLayout.contentWidth(for: outerWidth)
        let scrollIndicatorTrailingProjection = SpaceViewLayout.scrollIndicatorTrailingProjection

        SidebarSelectedItemVisibilityScope(
            revealPath: selectedItemRevealPath,
            selection: selection,
            isEnabled: isInteractive,
            motionMode: selectedItemRevealMode,
            restoredViewport: isInteractive ? restoredViewport : nil,
            onCommittedViewportChange: onViewportChange
        ) {
            ScrollView(.vertical, showsIndicators: false) {
                // The parent SpaceView owns the sidebar's horizontal inset; keep scroll content aligned with SpaceTitle.
                content()
                    .frame(width: contentWidth, alignment: .leading)
                    .background {
                        SpaceScrollDragRegistration(
                            isEnabled: isInteractive,
                            indicatorColor: scrollIndicatorColor,
                            contentViewportWidth: contentWidth,
                            trailingProjection: scrollIndicatorTrailingProjection
                        )
                        .frame(width: 0, height: 0)
                        .allowsHitTesting(false)
                    }
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

/// Keeps high-frequency drag publications from invalidating the scroll surface.
private struct SpaceScrollDragRegistration: View {
    let isEnabled: Bool
    let indicatorColor: NSColor
    let contentViewportWidth: CGFloat
    let trailingProjection: CGFloat

    @EnvironmentObject private var dragState: SidebarDragState

    var body: some View {
        SidebarTabListScrollRegistrationViewRepresentable(
            isEnabled: isEnabled,
            indicatorColor: indicatorColor,
            contentViewportWidth: contentViewportWidth,
            trailingProjection: trailingProjection,
            dragAutoscrollRegistry: dragState.dragAutoscrollRegistry
        )
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
