//
//  SpacesList.swift
//  Sumi
//
//  Horizontal strip of space icons in the sidebar bottom bar. Mirrors Zen's
//  workspace-icons strip: slots shrink as spaces are added, collapse to dots
//  past the minimum width, and the strip scrolls just enough to keep the
//  active (or hovered) space in view with a neighbour peeking in.
//

import SwiftUI

struct SpacesList: View {
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.controlSize) private var controlSize
    let browserContext: SidebarBrowserContext
    let visualSelectedSpaceId: UUID?
    let onSelectSpace: (Space) -> Void
    @State private var availableWidth: CGFloat = 0
    @State private var deferredAvailableWidthMutation = SidebarDeferredStateMutation<CGFloat>()
    @State private var hoveredSpaceId: UUID?
    @State private var showPreview: Bool = false
    @State private var isHoveringList: Bool = false
    @State private var reorderState = ReorderDragState<UUID>()
    @State private var stripScrollPosition = ScrollPosition(edge: .leading)
    @State private var stripScrollOffset: CGFloat = 0

    private var metrics: SpaceStripMetrics {
        SpaceStripMetrics.resolve(for: controlSize)
    }

    private var stripGeometry: SpaceStripGeometry {
        SpaceStripGeometry.make(
            itemCount: displayedSpaces.count,
            availableWidth: availableWidth,
            metrics: metrics
        )
    }

    private var reorderGeometry: ReorderGeometry {
        ReorderGeometry(axis: .horizontal, slotFrames: stripGeometry.slotFrames)
    }

    private var visibleSpaces: [Space] {
        if windowState.isIncognito {
            return windowState.ephemeralSpaces
        }
        return browserContext.tabManager.spaceStateOwner.spaces
    }

    private var displayedSpaces: [Space] {
        reorderState.displayOrder(visibleSpaces, id: \.id)
    }

    var body: some View {
        ScrollView(.horizontal) {
            spacesContent(spaces: displayedSpaces)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(!stripGeometry.isScrollable || reorderState.isDragging)
        .scrollPosition($stripScrollPosition)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.x
        } action: { _, newOffset in
            stripScrollOffset = newOffset
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            deferredAvailableWidthMutation.schedule(newWidth) { resolvedWidth in
                guard abs(availableWidth - resolvedWidth) > 0.5 else { return }
                availableWidth = resolvedWidth
                revealActiveSpace(animated: false)
            }
        }
        .overlay(alignment: .top) {
            spacePreviewOverlay(spaces: displayedSpaces)
        }
        .onChange(of: visualSelectedSpaceId) { _, _ in
            revealActiveSpace(animated: true)
        }
        .onChange(of: visibleSpaces.map(\.id)) { _, _ in
            if reorderState.isDragging {
                windowState.sidebarInteractionState.syncSidebarItemDrag(false)
            }
            reorderState.reset()
            revealActiveSpace(animated: true)
        }
        .onDisappear {
            if reorderState.isDragging {
                windowState.sidebarInteractionState.syncSidebarItemDrag(false)
            }
            reorderState.reset()
        }
        .animation(.easeInOut(duration: 0.3), value: visibleSpaces.count)
        .animation(.interactiveSpring(duration: 0.22, extraBounce: 0.05), value: displayedSpaces.map(\.id))
    }

    private var previewTextColor: Color {
        themeContext.tokens(settings: sumiSettings).secondaryText
    }

    private var canReorderSpaces: Bool {
        !windowState.isIncognito && visibleSpaces.count > 1
    }

    private func spacesContent(spaces: [Space]) -> some View {
        SpaceStripLayout(geometry: stripGeometry, metrics: metrics) {
            ForEach(spaces, id: \.id) { space in
                SpacesListItem(
                    space: space,
                    browserContext: browserContext,
                    isActive: visualSelectedSpaceId == space.id,
                    isFaded: false,
                    showsCompactDot: showsCompactDot(for: space),
                    slotWidth: stripGeometry.slotWidth,
                    metrics: metrics,
                    onSelect: {
                        guard !reorderState.isDragging else { return }
                        guard !reorderState.consumeSuppressedClick(for: space.id) else { return }
                        onSelectSpace(space)
                    },
                    onHoverChange: { isHovering in
                        handleHoverChange(isHovering, for: space)
                    }
                )
                .environment(windowState)
                .gesture(spaceInteractionGesture(for: space, spaces: spaces))
                .opacity(reorderState.hidesInlineItem(space.id) ? 0 : 1)
                .id(space.id)
                .transition(reorderState.isDragging ? .identity : .asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .scale.combined(with: .opacity)
                ))
            }
        }
        .coordinateSpace(name: SpaceReorderCoordinateSpace.name)
        .onHover { hovering in
            isHoveringList = hovering
            if !hovering {
                showPreview = false
                hoveredSpaceId = nil
            }
        }
        .overlay(alignment: .topLeading) {
            draggedSpaceOverlay(spaces: spaces)
        }
    }

    /// Zen's `icons-overflow` presentation: in compact mode every space shows
    /// a dot except the hovered one; the active space keeps its icon unless
    /// another space is being hovered.
    private func showsCompactDot(for space: Space) -> Bool {
        guard stripGeometry.displayMode == .compactDots else { return false }
        if hoveredSpaceId == space.id { return false }
        if visualSelectedSpaceId == space.id { return hoveredSpaceId != nil }
        return true
    }

    // MARK: - Scrolling

    private func revealActiveSpace(animated: Bool) {
        guard let visualSelectedSpaceId else { return }
        revealSpace(visualSelectedSpaceId, animated: animated)
    }

    /// Scroll the strip the minimal amount that brings the space into view
    /// (Zen scrolls on both activation and hover of edge-peeking icons).
    private func revealSpace(_ spaceId: UUID, animated: Bool) {
        guard !reorderState.isDragging,
              let index = displayedSpaces.firstIndex(where: { $0.id == spaceId }),
              let targetOffset = SpaceStripScrollPolicy.targetOffset(
                  toReveal: index,
                  geometry: stripGeometry,
                  currentOffset: stripScrollOffset,
                  viewportWidth: availableWidth,
                  margin: metrics.scrollMargin
              )
        else { return }

        if animated {
            withAnimation(.smooth(duration: 0.25)) {
                stripScrollPosition.scrollTo(x: targetOffset)
            }
        } else {
            stripScrollPosition.scrollTo(x: targetOffset)
        }
    }

    // MARK: - Hover

    private func handleHoverChange(_ isHovering: Bool, for space: Space) {
        guard !reorderState.isDragging else { return }

        if isHovering {
            hoveredSpaceId = space.id
            revealSpace(space.id, animated: true)
            if !showPreview {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    if hoveredSpaceId == space.id && isHoveringList && !reorderState.isDragging {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showPreview = true
                        }
                    }
                }
            }
        } else if hoveredSpaceId == space.id {
            hoveredSpaceId = nil
        }
    }

    private func spaceInteractionGesture(for space: Space, spaces: [Space]) -> some Gesture {
        makeReorderDragGesture(
            id: space.id,
            coordinateSpaceName: SpaceReorderCoordinateSpace.name,
            isEnabled: { canReorderSpaces },
            orderedIDs: { spaces.map(\.id) },
            geometry: { reorderGeometry },
            state: $reorderState,
            onBeginDrag: {
                showPreview = false
                hoveredSpaceId = nil
                windowState.sidebarInteractionState.syncSidebarItemDrag(true)
            },
            onEndDrag: {
                windowState.sidebarInteractionState.syncSidebarItemDrag(false)
            },
            onCommit: { move in
                browserContext.tabManager.spaceServices.catalog.reorderSpace(
                    spaceId: move.id,
                    to: move.targetIndex
                )
            },
            onTap: { onSelectSpace(space) }
        )
    }

    @ViewBuilder
    private func draggedSpaceOverlay(spaces: [Space]) -> some View {
        if let draggedSpaceId = reorderState.draggedID,
           let draggedSpace = spaces.first(where: { $0.id == draggedSpaceId }),
           let frame = reorderState.draggedOverlayFrame() {
            SpacesListItem(
                space: draggedSpace,
                browserContext: browserContext,
                isActive: visualSelectedSpaceId == draggedSpace.id,
                isFaded: false,
                showsCompactDot: false,
                slotWidth: frame.width,
                metrics: metrics,
                onSelect: { _ = () },
                onHoverChange: nil
            )
            .environment(windowState)
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .allowsHitTesting(false)
            .animation(nil, value: reorderState.currentLocation.x)
            .zIndex(2)
        }
    }

    @ViewBuilder
    private func spacePreviewOverlay(spaces: [Space]) -> some View {
        if showPreview,
           let hoveredId = hoveredSpaceId,
           hoveredId != visualSelectedSpaceId,
           let hoveredSpace = spaces.first(where: { $0.id == hoveredId }) {
            Text(hoveredSpace.name)
                .font(.caption)
                .foregroundStyle(previewTextColor)
                .opacity(0.7)
                .lineLimit(1)
                .id(hoveredSpace.id)
                .transition(
                    .scale(scale: 0.8)
                        .combined(with: .opacity)
                        .animation(.smooth(duration: 0.2))
                )
                .offset(y: -20)
        }
    }
}
