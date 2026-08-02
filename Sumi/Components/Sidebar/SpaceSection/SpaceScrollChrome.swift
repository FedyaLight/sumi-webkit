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

private struct SidebarScrollBoundaryVisibility: Equatable {
    let hasContentAbove: Bool
    let hasContentBelow: Bool

    init(hasContentAbove: Bool = false, hasContentBelow: Bool = false) {
        self.hasContentAbove = hasContentAbove
        self.hasContentBelow = hasContentBelow
    }

    init(_ state: SidebarScrollBoundaryState) {
        hasContentAbove = state.hasContentAbove
        hasContentBelow = state.hasContentBelow
    }
}

/// A layout-stable wrapper that isolates scroll offsets and boundary state to prevent invalidating the parent SpaceView.
struct SpaceScrollChromeSurface<Content: View>: View {
    let isInteractive: Bool
    let spaceId: UUID
    let selectedItemRevealPath: SidebarSelectedItemRevealPath?
    let selectedItemRevealMode: SidebarMotionPolicy.Mode
    let restoredViewport: SpaceSidebarSnapshotViewport?
    let dragAutoscrollRegistry: SidebarTabListDragAutoscrollRegistry
    let scrollHoverCoordinator: NativeSurfaceScrollHoverCoordinator
    let outerWidth: CGFloat
    let onViewportChange: @MainActor (
        SpaceSidebarSnapshotViewport
    ) -> Void
    @ViewBuilder let content: () -> Content

    @State private var boundaryVisibility = SidebarScrollBoundaryVisibility()

    @Environment(\.resolvedThemeContext) var themeContext
    @Environment(\.chromeThemeTokens) var scopedChromeTokens
    @Environment(\.sumiSettings) var sumiSettings
    @Environment(BrowserWindowState.self) private var windowState

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
            isEnabled: isInteractive,
            motionMode: selectedItemRevealMode,
            targetResolution: .presentedLayout,
            restoredViewport: isInteractive ? restoredViewport : nil,
            onViewportChange: onViewportChange
        ) { surfaceObservation in
            ScrollView(.vertical, showsIndicators: false) {
                // The parent SpaceView owns the sidebar's horizontal inset; keep scroll content aligned with SpaceTitle.
                content()
                    .frame(width: contentWidth, alignment: .leading)
                    .background {
                        SpaceScrollDragRegistration(
                            isEnabled: isInteractive,
                            indicatorColor: scrollIndicatorColor,
                            contentViewportWidth: contentWidth,
                            trailingProjection: scrollIndicatorTrailingProjection,
                            dragAutoscrollRegistry: dragAutoscrollRegistry,
                            surfaceObservation: surfaceObservation
                        )
                        .frame(width: 0, height: 0)
                        .allowsHitTesting(false)
                    }
            }
        }
        .frame(width: contentWidth, alignment: .leading)
        .modifier(
            SidebarScrollHoverEnvironmentModifier(
                coordinator: scrollHoverCoordinator,
                hoverSession: windowState.sidebarInteractionState.hoverSession
            )
        )
        .suppressesNativeSurfaceHoverWhileScrolling(scrollHoverCoordinator, region: "sidebar-tabs-\(spaceId.uuidString)")
        .accessibilityIdentifier("space-view-scroll-\(spaceId.uuidString)")
        .scrollIndicators(.hidden, axes: .vertical)
        .onScrollGeometryChange(for: SidebarScrollBoundaryVisibility.self) { geometry in
            SidebarScrollBoundaryVisibility(
                SidebarScrollBoundaryState(
                    contentOffsetY: geometry.contentOffset.y,
                    visibleRect: geometry.visibleRect,
                    contentHeight: geometry.contentSize.height
                )
            )
        } action: { _, state in
            boundaryVisibility = state
        }
        .contentShape(Rectangle())
        .clipped() // Hardware-accelerated viewport-bound clipping
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(tokens.separator)
                .frame(width: contentWidth, height: 1)
                .opacity(boundaryVisibility.hasContentAbove ? 1.0 : 0.0)
                .animation(
                    .easeInOut(duration: 0.15),
                    value: boundaryVisibility.hasContentAbove
                )
        }
        .overlay(alignment: .bottomLeading) {
            Rectangle()
                .fill(tokens.separator)
                .frame(width: contentWidth, height: 1)
                .opacity(boundaryVisibility.hasContentBelow ? 1.0 : 0.0)
                .animation(
                    .easeInOut(duration: 0.15),
                    value: boundaryVisibility.hasContentBelow
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct SidebarScrollHoverEnvironmentModifier: ViewModifier {
    @ObservedObject var coordinator: NativeSurfaceScrollHoverCoordinator
    let hoverSession: SidebarHoverSession

    func body(content: Content) -> some View {
        content.environment(
            \.nativeSurfaceHoverUpdatesEnabled,
            coordinator.hoverUpdatesEnabled
        )
        .onAppear {
            synchronizeHoverSession()
        }
        .onChange(of: coordinator.hoverUpdatesEnabled) { _, _ in
            synchronizeHoverSession()
        }
    }

    private func synchronizeHoverSession() {
        hoverSession.setScrollSuppressed(!coordinator.hoverUpdatesEnabled)
    }
}

/// Keeps high-frequency drag publications from invalidating the scroll surface.
private struct SpaceScrollDragRegistration: View {
    let isEnabled: Bool
    let indicatorColor: NSColor
    let contentViewportWidth: CGFloat
    let trailingProjection: CGFloat
    let dragAutoscrollRegistry: SidebarTabListDragAutoscrollRegistry
    let surfaceObservation: SidebarScrollSurfaceObservation

    var body: some View {
        SidebarTabListScrollRegistrationViewRepresentable(
            isEnabled: isEnabled,
            indicatorColor: indicatorColor,
            contentViewportWidth: contentViewportWidth,
            trailingProjection: trailingProjection,
            dragAutoscrollRegistry: dragAutoscrollRegistry,
            surfaceObservation: surfaceObservation
        )
    }
}

struct SidebarTabListScrollRegistrationViewRepresentable: NSViewRepresentable {
    let isEnabled: Bool
    let indicatorColor: NSColor
    let contentViewportWidth: CGFloat
    let trailingProjection: CGFloat
    let dragAutoscrollRegistry: SidebarTabListDragAutoscrollRegistry
    let surfaceObservation: SidebarScrollSurfaceObservation

    func makeNSView(context: Context) -> SidebarTabListScrollRegistrationView {
        let view = SidebarTabListScrollRegistrationView()
        view.dragAutoscrollRegistry = dragAutoscrollRegistry
        return view
    }

    func updateNSView(_ nsView: SidebarTabListScrollRegistrationView, context: Context) {
        nsView.dragAutoscrollRegistry = dragAutoscrollRegistry
        nsView.updateSurfaceObservation(surfaceObservation)
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
