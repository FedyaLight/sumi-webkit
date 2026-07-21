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
    @Environment(KeyboardShortcutManager.self) private var shortcutManager
    @Environment(\.controlSize) private var controlSize
    let browserContext: SidebarBrowserContext
    let spaceLifecycle: SidebarSpaceLifecycle
    let visualSelectedSpaceId: UUID?
    let onSelectSpace: (Space) -> Void
    @State private var availableWidth: CGFloat = 0
    @State private var deferredAvailableWidthMutation = SidebarDeferredStateMutation<CGFloat>()
    @State private var hoverLabel = SpaceHoverLabelSession()
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
        return spaceLifecycle.availableSpaces(isIncognito: false, ephemeralSpaces: [])
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
        .onChange(of: visualSelectedSpaceId) { _, _ in
            revealActiveSpace(animated: true)
        }
        .onChange(of: visibleSpaces.map(\.id)) { _, _ in
            if reorderState.isDragging {
                windowState.sidebarInteractionState.syncSidebarItemDrag(false)
            }
            reorderState.reset()
            hoverLabel.suppress()
            revealActiveSpace(animated: true)
        }
        .onDisappear {
            if reorderState.isDragging {
                windowState.sidebarInteractionState.syncSidebarItemDrag(false)
            }
            reorderState.reset()
            hoverLabel.suppress()
        }
        .animation(.easeInOut(duration: 0.3), value: visibleSpaces.count)
        .animation(.interactiveSpring(duration: 0.22, extraBounce: 0.05), value: displayedSpaces.map(\.id))
    }

    private var canReorderSpaces: Bool {
        !windowState.isIncognito && visibleSpaces.count > 1
    }

    private func spacesContent(spaces: [Space]) -> some View {
        SpaceStripLayout(geometry: stripGeometry, metrics: metrics) {
            ForEach(Array(spaces.enumerated()), id: \.element.id) { index, space in
                SpacesListItem(
                    space: space,
                    browserContext: browserContext,
                    spaceLifecycle: spaceLifecycle,
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
                .anchorPreference(
                    key: SpaceHoverLabelAnchorPreference.self,
                    value: .bounds
                ) { bounds in
                    guard hoverLabel.visibleSpaceID == space.id else { return nil }
                    return SpaceHoverLabelAnchor(
                        label: SpaceHoverLabelBuilder.label(
                            for: space,
                            at: index,
                            shortcuts: shortcutManager
                        ),
                        bounds: bounds
                    )
                }
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
            guard !hovering else { return }
            hoverLabel.suppress()
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
        let presentedSpaceID = hoverLabel.hoveredSpaceID ?? hoverLabel.visibleSpaceID
        if presentedSpaceID == space.id { return false }
        if visualSelectedSpaceId == space.id { return presentedSpaceID != nil }
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
            hoverLabel.hoverBegan(space.id)
            revealSpace(space.id, animated: true)
        } else {
            hoverLabel.hoverEnded(space.id)
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
                hoverLabel.suppress()
                windowState.sidebarInteractionState.syncSidebarItemDrag(true)
            },
            onEndDrag: {
                windowState.sidebarInteractionState.syncSidebarItemDrag(false)
            },
            onCommit: { move in
                _ = spaceLifecycle.reorderSpace(move.id, to: move.targetIndex)
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
                spaceLifecycle: spaceLifecycle,
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

}
